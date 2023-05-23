// ----------------------------------------------------------------------------
// This file is part of reDIP SID, a MOS 6581/8580 SID FPGA emulation platform.
// Copyright (C) 2023  Dag Lem <resid@nimrod.no>
//
// This source describes Open Hardware and is licensed under the CERN-OHL-S v2.
//
// You may redistribute and modify this source and make products using it under
// the terms of the CERN-OHL-S v2 (https://ohwr.org/cern_ohl_s_v2.txt).
//
// This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
// INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
// PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.
//
// Source location: https://github.com/daglem/reDIP-SID
// ----------------------------------------------------------------------------

`default_nettype none

// SID control registers for two chips.
// Fully pipelined operation, shifting out registers for one voice per cycle.
module sid_control #(
    localparam DBUS_VALUE_TTL_MOS6581 = 10'd7,
    localparam DBUS_VALUE_TTL_MOS8580 = 10'd664
)(
    input  logic               clk,
    input  logic               tick_ms,
    input  sid::cycle_t        voice_cycle,
    input  sid::cycle_t        filter_cycle,
    input  sid::bus_i_t        bus_i,
    input  logic [1:0]         cs,
    input  logic [1:0]         model,
    // Write-only registers.
    output sid::freq_pw_t      freq_pw_1,
    output logic [2:0]         test,
    output logic [2:0]         sync,
    output sid::control_t      control_4,
    output sid::envelope_reg_t ereg_5,
    output sid::filter_reg_t   freg_1,
    // Read-only registers.
    input  sid::misc_reg_t     mreg,
    output sid::reg8_t         data_o
);

    /* verilator lint_off LITENDIAN */
    typedef union packed {
        logic [0:6][7:0] bytes;
        sid::voice_reg_t regs;
    } voice_ctrl_t;

    typedef union packed {
        logic [0:3][7:0] bytes;
        sid::filter_reg_t regs;
    } filter_ctrl_t;

    typedef union packed {
        logic [0:3][7:0] bytes;
        sid::misc_reg_t  regs;
    } misc_ctrl_t;
    /* verilator lint_on LITENDIAN */

    // Register sets for two SID chips.
    // Handling of nowrshmsk for structs was added to Yosys to save 10% of the
    // LCs in this design.
    (* nowrshmsk *)
    voice_ctrl_t  v5 = '0, v4 = '0, v3 = '0, v2 = '0, v1 = '0, v0 = '0;
    (* nowrshmsk *)
    filter_ctrl_t f1 = '0, f0 = '0;
    misc_ctrl_t   m;

    // Value on data bus.
    // FIXME: Yosys doesn't support multidimensional packed arrays outside
    // of structs, nor arrays of structs.
    typedef struct packed {
        logic [1:0][7:0] value;
        logic [1:0][9:0] age;
    } dbus_t;

    (* nowrshmsk *)
    dbus_t dbus = '0;

    // Register offset.
    logic signed [4:0] vaddr_offset = 0;

    always_ff @(posedge clk) begin
        if (voice_cycle == 0 || voice_cycle == 3) begin
            vaddr_offset <= 0;
        end else if (voice_cycle >= 1 && voice_cycle <= 2 ||
                     voice_cycle >= 4 && voice_cycle <= 5)
        begin
            // Subtract a constant here so we can add instead of subtract the
            // variable later, saving LCs which would otherwise be used for
            // two's complement inversion.
            vaddr_offset <= vaddr_offset - 7;
        end
    end

    // Register read / write.
    logic cycle_cs;
    logic signed [5:0] vaddr;
    logic signed [5:0] faddr;
    logic signed [5:0] maddr;
    logic r;
    logic w;
    sid::reg8_t r_value;

    always_comb begin
        // Assign to / from ports.
        freq_pw_1 = v0.regs.waveform.freq_pw;
        control_4 = v3.regs.waveform.control;
        ereg_5    = v4.regs.envelope;
        test      = { v2.regs.waveform.control.test, v1.regs.waveform.control.test, v0.regs.waveform.control.test };
        sync      = { v2.regs.waveform.control.sync, v1.regs.waveform.control.sync, v0.regs.waveform.control.sync };
        freg_1    = f1.regs;  // Rotated before first use
        m.regs    = mreg;

        // cycle bit 2 is set for voice 4 - 6.
        cycle_cs = cs[voice_cycle[2]];
        // cycle_cs = cs[voice_cycle >= 4];

        // Address offsets.
        vaddr = signed'(6'(bus_i.addr)) + 6'(vaddr_offset);
        faddr = signed'(6'(bus_i.addr)) - 'sh15;
        maddr = signed'(6'(bus_i.addr)) - 'sh19;

        // Read / write.
        r =  bus_i.phi2 &  bus_i.r_w_n && maddr >= 0 && maddr <= 3;
        w = ~bus_i.phi2 & ~bus_i.r_w_n && voice_cycle >= 1 && voice_cycle <= 6;

        // FIXME: Verilator complains about m.bytes[maddr[1:0]].
        r_value  = m.bytes[maddr[2:0]];

        // Data output, default to SID 1 (for both SIDs at D400).
        // Read data could have been always output from dbus.value, however
        // this would delay the output by one cycle, possibly violating the
        // minimum MOS6510 TDSU of 100ns for SID 2 OSC3/ENV3.
        // data_o = dbus.value[cs == 2'b10];
        data_o = |cs && r ? r_value : dbus.value[cs == 2'b10];
    end

    // Value on data bus for each SID chip.
    // FIXME: Attempting to put the for loop inside always_ff makes Verilator fail with
    // %Error: Internal Error: sid_control.sv:147:55: ../V3LinkDot.cpp:2298: Bad package link
    // always_ff @(posedge clk) begin
    //     for (int i = 0; i < 2; i++) begin : sid
    for (genvar i = 0; i < 2; i++) begin : sid
        always_ff @(posedge clk) begin
            if (bus_i.res) begin
                dbus.value[i] <= '0;
                dbus.age[i]   <= '0;
            end else if (cs[i] && (r || w)) begin
                // Keep last register read/write on data bus.
                dbus.value[i] <= r ? r_value : bus_i.data;
                dbus.age[i]   <= 0;
            end else if (dbus.age[i] == ((model[i] == sid::MOS6581) ?
                                         DBUS_VALUE_TTL_MOS6581 :
                                         DBUS_VALUE_TTL_MOS8580))
            begin
                // Bus value has faded out.
                dbus.value[i] <= 0;
            end else if (voice_cycle == 1) begin
                // Count up to complete fade-out of bus value.
                dbus.age[i]   <= dbus.age[i] + 10'(tick_ms);
            end
        end
    end

    // Write-only registers.
    always_ff @(posedge clk) begin
        // Rotation on cycles 1 - 6 for writing.
        // Rotation on six additional cycles to keep in sync with
        // sid_waveform.sv and sid_envelope.sv
        if (voice_cycle >= 1 && voice_cycle <= 12) begin
            { v5, v4, v3, v2, v1, v0 } <= { v4, v3, v2, v1, v0, v5 };

            if (bus_i.res) begin
                v0.bytes <= '0;
            end else if (cycle_cs && w && vaddr >= 0 && vaddr <= 6) begin
                // Voice register write.
                v0.bytes[vaddr[2:0]] <= bus_i.data;
            end
        end

        if (voice_cycle == 1 || voice_cycle == 4 ||
            filter_cycle == 5 || filter_cycle == 10)
        begin
            { f1, f0 } <= { f0, f1 };

            if (bus_i.res) begin
                f0.bytes <= '0;
            end else if (cycle_cs && w && faddr >= 0 && faddr <= 3) begin
                // Filter register write.
                // FIXME: Verilator complains about f.bytes[faddr[1:0]].
                f0.bytes[faddr[2:0]] <= bus_i.data;
            end
        end
    end

`ifdef VM_TRACE
    // Latch voices for simulation.
    /* verilator lint_off UNUSED */
    voice_ctrl_t sim_voice[6];

    always_ff @(posedge clk) begin
        if (voice_cycle >= 2 && voice_cycle <= 7) begin
            sim_voice[voice_cycle - 2] <= v0;
        end
    end

    filter_ctrl_t sim_filter[2];

    always_ff @(posedge clk) begin
        if (voice_cycle == 2) begin
            sim_filter[0] <= f0;
        end else if (voice_cycle == 5) begin
            sim_filter[1] <= f0;
        end
    end
    /* verilator lint_on UNUSED */
`endif
endmodule

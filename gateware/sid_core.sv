// ----------------------------------------------------------------------------
// This file is part of reDIP SID, a MOS 6581/8580 SID FPGA emulation platform.
// Copyright (C) 2022  Dag Lem <resid@nimrod.no>
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

module sid_core #(
    localparam BUS_VALUE_TTL_MOS6581 = 20'h01D00,
    localparam BUS_VALUE_TTL_MOS8580 = 20'hA2000
)(
    input  logic         clk,
    input  sid::model_e  model,
    input  sid::bus_i_t  bus_i,
    input  sid::phase_t  phase,
    input  logic         cs,
    output sid::reg8_t   data_o = 0,
    input  sid::pot_i_t  pot_i,
    output sid::pot_o_t  pot_o,
    output sid::core_o_t out,
    input  sid::reg8_t   osc3
);

    // Write-only / read-only registers.
    sid::reg_i_t reg_i = '0;
    sid::reg_o_t reg_o;

    always_comb begin
        out.filter_regs = reg_i.regs.filter;
        reg_o.regs.osc3 = osc3;
        reg_o.regs.env3 = out.voice3.envelope;
    end
    
    // SID waveform generators.

    // We could have generated the waveform generators, however Yosys currently
    // doesn't support multidimensional packed arrays outside of structs.
    /* verilator lint_off UNOPTFLAT */
    sid::sync_t sync1, sync2, sync3;
    /* verilator lint_on UNOPTFLAT */

    sid_waveform waveform1 (
        .clk        (clk),
        .res        (bus_i.res),
        .model      (model),
        .phase      (phase),
        .reg_i      (reg_i.regs.voice1.waveform),
        .sync_i     (sync1),
        .sync_o     (sync2),
        .out        (out.voice1.waveform)
    );

    sid_waveform waveform2 (
        .clk        (clk),
        .res        (bus_i.res),
        .model      (model),
        .phase      (phase),
        .reg_i      (reg_i.regs.voice2.waveform),
        .sync_i     (sync2),
        .sync_o     (sync3),
        .out        (out.voice2.waveform)
    );

    sid_waveform waveform3 (
        .clk        (clk),
        .res        (bus_i.res),
        .model      (model),
        .phase      (phase),
        .reg_i      (reg_i.regs.voice3.waveform),
        .sync_i     (sync3),
        .sync_o     (sync1),
        .out        (out.voice3.waveform)
    );

    // SID envelope generators.
    
    sid_envelope envelope1 (
        .clk   (clk),
        .res   (bus_i.res),
        .phase (phase),
        .reg_i (reg_i.regs.voice1.envelope),
        .out   (out.voice1.envelope)
    );
    
    sid_envelope envelope2 (
        .clk   (clk),
        .res   (bus_i.res),
        .phase (phase),
        .reg_i (reg_i.regs.voice2.envelope),
        .out   (out.voice2.envelope)
    );
    
    sid_envelope envelope3 (
        .clk   (clk),
        .res   (bus_i.res),
        .phase (phase),
        .reg_i (reg_i.regs.voice3.envelope),
        .out   (out.voice3.envelope)
    );

    // SID POTX / POTY.
    sid_pot pot (
       .clk     (clk),
       .phase   (phase),
       .pot_reg (reg_o.regs.pot),
       .pot_i   (pot_i),
       .pot_o   (pot_o)
    );

    // Register read / write.
    logic r;
    logic w;

    // Fade-out of value on data bus.
    logic [19:0] bus_ttl;
    logic [19:0] bus_age   = 0;
    sid::reg8_t  bus_value = 0;

    always_comb begin
        // Read / write.
        r = cs && bus_i.oe && bus_i.addr >= 'h19 && bus_i.addr < 'h1D;
        w = cs && bus_i.we;

        // Time to live for value on data bus.
        bus_ttl = (model == sid::MOS6581) ? BUS_VALUE_TTL_MOS6581 : BUS_VALUE_TTL_MOS8580;
    end
        
    always_ff @(posedge clk) begin
        // Output from register or bus value.
        data_o <= r ? reg_o.bytes[bus_i.addr - 'h19] : bus_value;

        if (phase[sid::PHI2]) begin
            // Note that write-only registers must be updated at PHI2, before PHI2_PHI1.
            if (bus_i.res) begin
                // Reset write-only registers.
                reg_i <= '0;
            end else if (w) begin
                // Register write.
                reg_i.bytes[bus_i.addr] <= bus_i.data;
            end

            if (r) begin
                // Keep last register read on data bus.
                bus_value <= data_o;
                bus_age   <= 0;
            end else if (w) begin
                // Keep last register write on data bus.
                bus_value <= bus_i.data;
                bus_age   <= 0;
            end else begin
                if (bus_i.res || bus_age == bus_ttl) begin
                    // Bus value has faded out.
                    bus_value <= 0;
                end else begin
                    // Count up to complete fade-out of bus value.
                    bus_age   <= bus_age + 1;
                end
            end
        end
    end
endmodule

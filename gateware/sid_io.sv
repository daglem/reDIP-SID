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

/* verilator lint_off PINMISSING */

module sid_io (
    input  logic        clk,
    input  logic        rst,
    // I/O pads.
    inout  sid::reg5_t  pad_addr,
    inout  sid::reg8_t  pad_data,
    inout  logic        pad_r_w_n,
    inout  sid::reg4_t  pad_cs,
    inout  logic        pad_phi2,
    inout  logic        pad_res_n,
    inout  logic  [1:0] pad_pot,
    // Internal interfaces.
    output logic        phi2  = 0,
    output sid::bus_i_t bus_i,
    output sid::cs_t    cs,
    input  sid::reg8_t  data_o,
    output sid::pot_i_t pot_i = 0,
    input  sid::pot_o_t pot_o
);

    // Control signals.
    logic r_w_n;
    logic phi2_io;
    logic phi1_io;   // Inverted phi2
    logic res_n_x;

    // Delayed phi2 for write enable.
    logic phi2_prev = 0;

    // Output enable to be registered in the SB_IO OE register, separate from
    // bus_i.oe used in sid_core.sv
    logic oe_io = 0;

    logic we    = 0;
    logic oe    = 0;
    logic res   = 0;

    // POT signals.
    logic [1:0] charged_x;

    always_comb begin
        bus_i.we  = we;
        bus_i.oe  = oe;
        bus_i.res = res;
    end

    // The 6510 phi2 clock driver only weakly drives the clock line high.
    // This makes the clock signal susceptible to noise at the rising edge,
    // which could in theory cause a false detection of the falling edge.
    // Tests show that the iCE40UP5K has input hysteresis of approximately
    // 250mV, which should hopefully be sufficient to remedy this issue.
    // In an attempt to further aid in the avoidance of any glitches, we
    // configure the I/O with a 100k pullup.
    //
    // phi2 is configured as a simple input pin (not registered, i.e. without
    // any delay), so that the signal can be used to latch other signals,
    // which are stable until at least 10ns after the falling edge of phi2
    // (ref. 6510 datasheet).
    SB_IO #(
        .PIN_TYPE    (6'b0000_01),
        .PULLUP      (1'b1)
    ) io_phi2 (
        .PACKAGE_PIN (pad_phi2),
        .D_IN_0      (phi2_io)
    );

    // Registered input for res_n. Note that res_n may be applied at any time and
    // can thus be metastable. In a real SID, the reset value is held at phi2.
    SB_IO #(
        .PIN_TYPE     (6'b0000_00)
    ) io_res (
        .PACKAGE_PIN  (pad_res_n),
`ifdef VERILATOR
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (res_n_x)
    );
    
    // Hold other (registered) inputs at phi1, i.e. D-latch enable = phi2.
    // This allows us to read out the signals after the falling edge of phi2,
    // where the signals were stable.

    // R/W.
    SB_IO #(
        .PIN_TYPE          (6'b0000_10)
    ) io_r_w_n (
        .PACKAGE_PIN       (pad_r_w_n),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef VERILATOR
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (r_w_n)
    );

    // Chip select, including extra pins.
    SB_IO #(
        .PIN_TYPE          (6'b0000_10)
    ) io_cs[3:0] (
        .PACKAGE_PIN       (pad_cs),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef VERILATOR
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            ({ cs })
    );

    // Address pin inputs.
    SB_IO #(
        .PIN_TYPE          (6'b0000_10)
    ) io_addr[4:0] (
        .PACKAGE_PIN       (pad_addr),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef VERILATOR
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.addr)
    );

    // Bidirectional data pins. Registered output and output enable.
    SB_IO #(
        .PIN_TYPE          (6'b1110_10)
    ) io_data[7:0] (
        .PACKAGE_PIN       (pad_data),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef VERILATOR
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .OUTPUT_CLK        (clk),
        .OUTPUT_ENABLE     (oe_io),
        .D_IN_0            (bus_i.data),
        .D_OUT_0           (data_o)
    );

    always_comb begin
        // phi1 is used to hold signals after the falling edge of phi2.
        phi1_io = ~phi2_io;
    end

    always_ff @(posedge clk) begin
        // Bring phi2 into FPGA clock domain.
        // phi2 is metastable, but can be used by the calling module
        // for detection of the falling edge of phi2.
        phi2      <= phi2_io;
        phi2_prev <= phi2;

        // The reset signal is already registered on the I/O input,
        // so we only add one extra register stage wrt. metastability.
        // Also OR in the system reset for PLL sync / BRAM powerup.
        res       <= ~res_n_x | rst;

        // The data output must be held by the output enable for at least 10ns
        // after the falling edge of phi2 (ref. SID datasheet). This is ensured
        // since the SB_IO OE register is delayed by one FPGA clock.
        // NB! The pin output is enabled only for /CS, not for /IO1, in case of
        // address conflict with expansion port cartridges.
        // Delay the start of the pin OE by ANDing with phi2, in order to avoid
        // any output glitches.
        oe_io    <= phi2_io & phi2 & r_w_n & ~cs.cs_n;
        oe       <= phi2 & r_w_n;

        // Write enable must be held at the detected falling edge of phi2.
        we       <= phi2_prev & ~r_w_n;
    end

    // The POT pins are open drain I/O only, however the SB_IO primitive
    // can still be used instead of SB_IO_OD.
    // Tristate output with enable, registered input.
    SB_IO #(
        .PIN_TYPE      (6'b1010_00)
    ) io_pot[1:0] (
        .PACKAGE_PIN   (pad_pot),
`ifdef VERILATOR
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_ENABLE (pot_o.discharge),
        .D_IN_0        (charged_x),
        .D_OUT_0       (1'b0)
    );

    always_ff @(posedge clk) begin
        // Add one extra register stage for input wrt. metastability.
        pot_i.charged <= charged_x;
    end
endmodule

/* verilator lint_on PINMISSING */

// ----------------------------------------------------------------------------
// This file is part of reDIP SID, a MOS 6581/8580 SID FPGA emulation platform.
// Copyright (C) 2022 - 2023  Dag Lem <resid@nimrod.no>
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
    output sid::bus_i_t bus_i,
    output sid::cs_t    cs,
    input  sid::reg8_t  data_o,
    output sid::pot_i_t pot_i = 0,
    input  sid::pot_o_t pot_o
);

    // Control signals.
    logic phi2_io;
    logic phi2_x = 0;
    logic phi2 = 0;
    logic phi1_io;   // Inverted phi2
    logic res_n_x;
    logic res = 0;

    // Output enable to be registered in the SB_IO OE register, separate from
    // bus_i.oe used in sid_control.sv
    logic oe_io = 0;

    // POT signals.
    logic [1:0] charged_x;

    always_comb begin
        bus_i.phi2 = phi2;
        bus_i.res  = res;
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
    // (ref. MOS6510 datasheet).
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
        .D_IN_0            (bus_i.r_w_n)
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
        phi2_x <= phi2_io;
        phi2   <= phi2_x;

        // The reset signal is already registered on the I/O input,
        // so we only add one extra register stage wrt. metastability.
        // Also OR in the system reset for PLL sync / BRAM powerup.
        res   <= ~res_n_x | rst;

        // The data output must be held by the output enable for at least 10ns
        // after the falling edge of phi2 (ref. SID datasheet). This is ensured
        // since the SB_IO OE register is delayed by one FPGA clock.
        // NB! The pin output is enabled only for /CS, not for /IO1, in case of
        // address conflict with expansion port cartridges.
        // Delay the start of the pin OE by ANDing with phi2, in order to avoid
        // any output glitches.
        oe_io <= phi2_io & phi2 & bus_i.r_w_n & ~cs.cs_n;
    end

    // The MOS6581 datasheet specifies a minimum POT sink current of 500uA.
    // Use SB_RGBA_DRV to limit the current draw on the POT pins to 2mA.
    SB_RGBA_DRV #(
        .CURRENT_MODE ("0b1"),       // Half current mode
        .RGB0_CURRENT ("0b000001"),  // 2mA POTX
        .RGB1_CURRENT ("0b000001"),  // 2mA POTY
        .RGB2_CURRENT ("0b000000")   // 0mA /IO1, uses SB_IO only
    ) rgba_drv (
	.CURREN       (1'b1),
	.RGBLEDEN     (1'b1),
	.RGB0PWM      (pot_o.discharge),
	.RGB1PWM      (pot_o.discharge),
	.RGB0         (pad_pot[0]),
	.RGB1         (pad_pot[1])
    );

    // The POT pins are shared between the SB_RGBA_DRV primitive above
    // (sink current when pot_o.discharge = 1) and the SB_IO primitive below
    // (read input when pot_o.discharge = 0).
    // The POT pins are open drain I/O only, however the SB_IO primitive
    // can still be used instead of SB_IO_OD.
    // No output, registered input.
    SB_IO #(
        .PIN_TYPE     (6'b0000_00)
    ) io_pot[1:0] (
        .PACKAGE_PIN  (pad_pot),
`ifdef VERILATOR
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (charged_x)
    );

    always_ff @(posedge clk) begin
        // Add one extra register stage for input wrt. metastability.
        pot_i.charged <= charged_x;
    end
endmodule

/* verilator lint_on PINMISSING */

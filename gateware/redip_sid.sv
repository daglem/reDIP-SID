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

(* top *)
module redip_sid (
    // System clock
    input  logic sys_clk,
    // I2C + button / LED (shared signals)
    inout  logic i2c_scl_led_n,
    inout  logic i2c_sda_btn_n,
    // I2S
    output logic i2s_din,
    input  logic i2s_dout,
    input  logic i2s_sclk,
    input  logic i2s_lrclk,
    // SPI
    inout  logic spi_sio0,
    inout  logic spi_sio1,
    inout  logic spi_sio2,
    inout  logic spi_sio3,
    inout  logic spi_clk,
    inout  logic spi_flash_cs_n,
    output logic spi_ram_cs_n,
    // USB
    inout  logic usb_d_p,
    inout  logic usb_d_n,
    output logic usb_conn,
    // SID address bus
    inout  logic a0,
    inout  logic a1,
    inout  logic a2,
    inout  logic a3,
    inout  logic a4,
    // Extra address pins
    inout  logic a5,
    inout  logic a8,
    // SID data bus
    inout  logic d0,
    inout  logic d1,
    inout  logic d2,
    inout  logic d3,
    inout  logic d4,
    inout  logic d5,
    inout  logic d6,
    inout  logic d7,
    // SID read/write
    inout  logic r_w_n,
    // SID chip select
    inout  logic cs_n,
    // Extra chip select
    inout  logic cs_io1_n,
    // SID master clock
    inout  logic phi2,
    // SID reset
    inout  logic res_n,
    // SID POT inputs
    inout  logic pot_x,
    inout  logic pot_y
);

    // SID API parameters.
    logic        phi2_x;
    sid::bus_i_t bus_i;
    sid::cs_t    cs;
    sid::reg8_t  data_o;
    sid::pot_i_t pot_i;
    sid::pot_o_t pot_o;
    sid::audio_t audio_i;
    sid::audio_t audio_o;

    // Clocks and resets.
    logic clk_24;
    logic rst_24;
    logic clk_48;
    logic rst_48;

    // iCE40 FPGA initialization.
    logic bootloader;
    logic boot = 1'b0;

    ice40_init ice40_init (
        .boot    (boot),
        .image   ({ 1'b0, bootloader }),
        .sys_clk (sys_clk),
        .clk_24  (clk_24),
        .rst_24  (rst_24),
        .clk_48  (clk_48),
        .rst_48  (rst_48)
    );

    // SGTL5000 audio codec I2C initialization.
    /* verilator lint_off PINCONNECTEMPTY */
    sgtl5000_init sgtl5000_init (
        .scl_led (i2c_scl_led_n),
        .sda_btn (i2c_sda_btn_n),
        .btn     (),
        .led     (~cs.cs_n & bus_i.we),
        .done    (),
        .clk     (clk_24),
        .rst     (rst_24)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // SID I/O.
    sid_io sid_io (
        .clk       (clk_24),
        .rst       (rst_24),
        .pad_addr  ({ a4, a3, a2, a1, a0 }),
        .pad_data  ({ d7, d6, d5, d4, d3, d2, d1, d0 }),
        .pad_r_w_n (r_w_n),
        .pad_cs    ({ cs_n, cs_io1_n, a8, a5 }),
        .pad_phi2  (phi2),
        .pad_res_n (res_n),
        .pad_pot   ({ pot_y, pot_x }),
        .phi2      (phi2_x),
        .bus_i     (bus_i),
        .cs        (cs),
        .data_o    (data_o),
        .pot_i     (pot_i),
        .pot_o     (pot_o)
    );

    // SID API.
    sid_api sid_api (
        .clk     (clk_24),
        .phi2    (phi2_x),
        .bus_i   (bus_i),
        .cs      (cs),
        .data_o  (data_o),
        .pot_i   (pot_i),
        .pot_o   (pot_o),
        .audio_i (audio_i),
        .audio_o (audio_o)
    );

    // I2S SGTL5000 PCM Format A input / output.
    i2s_dsp_mode #(
        // FIXME: Yosys doesn't understand $bits(sid::audio_t)
        .BITS      ($bits(audio_o))
    ) i2s_io (
        .clk       (clk_24),
        .pad_lrclk (i2s_lrclk),
        .pad_sclk  (i2s_sclk),
        .pad_din   (i2s_din),
        .pad_dout  (i2s_dout),
        .audio_o   (audio_o),
        .audio_i   (audio_i)
    );

`ifdef MUACM
    /* verilator lint_off PINCONNECTEMPTY */
    muacm muacm (
        .usb_dp        (usb_d_p),
        .usb_dn        (usb_d_n),
        .usb_pu        (usb_conn),
        .in_data       (8'h00),
        .in_last       (),
        .in_valid      (1'b0),
        .in_ready      (),
        .in_flush_now  (1'b0),
        .in_flush_time (1'b1),
        .out_data      (),
        .out_last      (),
        .out_valid     (),
        .out_ready     (1'b1),
        .bootloader    (bootloader),
        .clk           (clk_48),
        .rst           (rst_48)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // Warmboot
    always_ff @(posedge clk_48) begin
        boot <= boot | bootloader;
    end
`else
    always_comb bootloader = 0;
`endif

endmodule

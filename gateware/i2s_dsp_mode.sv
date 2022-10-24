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

// I2S SGTL5000 PCM Format A input / output.
// Note that this implementation requires that I2S_LRCLK is driven high for
// exactly one cycle.
module i2s_dsp_mode #(
    parameter  BITS = 64,
    localparam COUNTBITS = $clog2(BITS)
)(
    input  logic clk,
    input  logic pad_lrclk,
    input  logic pad_sclk,
    output logic pad_din,
    input  logic pad_dout,
    input  logic [BITS-1:0] audio_o,
    output logic [BITS-1:0] audio_i = '0
);

    logic [BITS-1:0] dout = '0;
    logic [BITS-1:0] din  = '0;

    logic i2s_lrclk;
    logic i2s_sclk;
    logic i2s_din;
    logic i2s_dout;
    logic lrclk_prev = 0;
    logic sclk_prev  = 0;
    logic sclk_rise  = 0;
    logic sclk_fall  = 0;
    logic last_bit   = 0;
    logic [COUNTBITS-1:0] bitnum = 0;

    // Registered inputs. Sample on the falling edge of clk,
    // in order to detect edges as early as possible.
    SB_IO #(
        .PIN_TYPE    (6'b0000_00)
    ) i2s_in[2:0] (
        .PACKAGE_PIN ({ pad_lrclk, pad_sclk, pad_dout }),
        .INPUT_CLK   (clk),
        .D_IN_1      ({ i2s_lrclk, i2s_sclk, i2s_dout })
    );

    // Registered output.
    SB_IO #(
        .PIN_TYPE    (6'b0101_00)
    ) i2s_out (
        .PACKAGE_PIN (pad_din),
        .OUTPUT_CLK  (clk),
        .D_OUT_0     (i2s_din)
    );
    
    always @(posedge clk) begin
        lrclk_prev <= i2s_lrclk;
        sclk_prev  <= i2s_sclk;
        sclk_rise  <= ~sclk_prev &  i2s_sclk;
        sclk_fall  <=  sclk_prev & ~i2s_sclk;

        if (sclk_fall) begin
            if (lrclk_prev) begin
                // I2S_LRCLK pulse; prepare for data exchange.
                dout   <= audio_o;
                bitnum <= 0;
            end else begin
                bitnum <= bitnum + 1;
            end

            // Any last bit is processed even if I2S_LRCLK is high
            // (i.e. no padding, e.g. for 64 bits).
            last_bit <= (bitnum == BITS - 1);

            if (last_bit) begin
                audio_i <= din;
            end

            // Shift in input data bit.
            din <= { din[BITS-2:0], i2s_dout };
        end else if (sclk_rise) begin
            // Shift out output data bit.
            { i2s_din, dout } <= { dout, 1'b0 };
        end
    end
endmodule

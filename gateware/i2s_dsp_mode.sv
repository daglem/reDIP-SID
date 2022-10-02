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
    input  logic i2s_sclk,
    input  logic i2s_lrclk,
    input  logic i2s_dout,
    output logic i2s_din,
    input  logic signed [BITS-1:0] audio_o,
    output logic signed [BITS-1:0] audio_i = '0
);

    logic signed [BITS-1:0] dout = '0;
    logic signed [BITS-1:0] din  = '0;

    logic sclk_x    = 0;
    logic sclk_prev = 0;
    logic sclk_rise = 0;
    logic sclk_fall = 0;
    logic [COUNTBITS-1:0] bitnum = 0;
    
    always @(posedge clk) begin
        sclk_x    <= i2s_sclk;
        sclk_prev <= sclk_x;
        sclk_rise <= ~sclk_prev &  sclk_x;
        sclk_fall <=  sclk_prev & ~sclk_x;

        if (sclk_fall) begin
            // I2S_LRCLK is stable on the falling edge of I2S_SCLK.
            if (i2s_lrclk) begin
                // I2S_LRCLK pulse; prepare for data exchange.
                dout   <= audio_o;
                bitnum <= 0;
            end else begin
                bitnum <= bitnum + 1;
            end

            // Ensure that any last bit is processed even if I2S_LRCLK is high
            // (i.e. no padding, e.g. for 64 bits).
            if (bitnum == BITS - 1) begin
                // Shift in final input data bit, and store input data.
                audio_i <= { din[BITS-2:0], i2s_dout };
            end else begin
                // Shift in input data bit.
                din     <= { din[BITS-2:0], i2s_dout };
            end
        end else if (sclk_rise) begin
            // Shift out output data bit.
            { i2s_din, dout } <= { dout, 1'b0 };
        end
    end
endmodule

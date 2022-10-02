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
module i2s_dsp_mode #(
    parameter BITS
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
    // FIXME: Dynamic - check Verilator
    logic [5:0] bits = 0;
    
    always @(posedge clk) begin
        sclk_x    <= i2s_sclk;
        sclk_prev <= sclk_x;
        sclk_rise <= ~sclk_prev &  sclk_x;
        sclk_fall <=  sclk_prev & ~sclk_x;

        if (sclk_fall) begin
            // i2s_lrclk is stable on sclk_fall.
            if (i2s_lrclk) begin
                dout <= audio_o;
                bits <= 0;
            end

            // Ensure that any last bit is processed even if i2s_lrclk is high
            // (i.e. no padding, e.g. for 64 bits).
            if (bits < BITS) begin
                din  <= { din[BITS-2:0], i2s_dout };
                bits <= bits + 1;
            end else begin
                audio_i <= din;
            end
        end else if (sclk_rise) begin
            { i2s_din, dout } <= { dout[BITS-1:0], 1'b0 };
        end
    end
endmodule

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

// This module calculates o = c +- (a * b)
//
// a and b are signed 16 bit numbers, while c and o are
// signed 32 bit numbers.
//
// Addition or subtraction is selected by the input "s":
//
// * s = 0: Addition
// * s = 1: Subtraction
//
module muladd (
    input  logic signed [31:0] c,
    input  logic               s,
    input  logic signed [15:0] a,
    input  logic signed [15:0] b,
    output logic signed [31:0] o
);
    /* verilator lint_off PINMISSING */
    SB_MAC16 #(
        .TOPADDSUB_LOWERINPUT  (2'b10),  // Upper 16 bits from 16x16 multiplier
        .TOPADDSUB_UPPERINPUT  (1'b1),   // 16-bit C input
        .TOPADDSUB_CARRYSELECT (2'b10),  // Cascade carry/borrow from lower add/sub
        .BOTADDSUB_LOWERINPUT  (2'b10),  // Lower 16 bits from 16x16 multiplier
        .BOTADDSUB_UPPERINPUT  (1'b1),   // 16-bit D input
        .BOTADDSUB_CARRYSELECT (2'b00),  // Constant 0
        .A_SIGNED              (1'b1),
        .B_SIGNED              (1'b1)
    ) muladd_16x16_32 (
        .C         (c[31-:16]),
        .A         (a),
        .B         (b),
        .D         (c[15-:16]),
        .ADDSUBTOP (s),
        .ADDSUBBOT (s),
        .O         (o)
    );
    /* verilator lint_on PINMISSING */
endmodule

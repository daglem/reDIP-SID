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

/* verilator lint_off DECLFILENAME */
package sid;
/* verilator lint_on DECLFILENAME */

    // Constants may be defined by parameter declarations.

    typedef logic [23:0] reg24_t;  // Phase-accumulating oscillator
    typedef logic [22:0] reg23_t;  // Noise waveform LFSR
    typedef logic [14:0] reg15_t;  // Envelope rate counter LFSR
    typedef logic [11:0] reg12_t;  // Waveform output, pulse width
    typedef logic [10:0] reg11_t;  // Filter cutoff, filter 1/Q
    typedef logic  [9:0] reg10_t;  // Filter table lookup index
    typedef logic  [8:0] reg9_t;   // POT position counter, fc offset
    typedef logic  [7:0] reg8_t;   // Data bus, register bytes, envelope counter
    typedef logic  [6:0] reg7_t;   // Envelope exponential segment steps
    typedef logic  [4:0] reg5_t;   // Address bus, envelope exponential counter LFSR
    typedef logic  [3:0] reg4_t;   // Various register nibbles

    // Audio signals.
    typedef logic signed [31:0] s32_t;
    typedef logic signed [23:0] s24_t;
    typedef logic signed [21:0] s22_t;  // Output from voice DCA
    typedef logic signed [19:0] s20_t;  // Output from audio output stage
    typedef logic signed [16:0] s17_t;  // Before clamping to 16 bits
    typedef logic signed [15:0] s16_t;
    typedef logic signed [12:0] s13_t;  // tanh_x unclamped
    typedef logic signed [11:0] s12_t;  // tanh_x offset
    typedef logic signed [10:0] s11_t;  // tanh_x clamped

    typedef struct packed {
        s24_t left;
        s24_t right;
    } audio_t;

    // Pipeline cycles.
    typedef logic [4:0] cycle_t;

    typedef enum logic [0:0] {
        MOS6581,
        MOS8580
    } model_e;

    typedef enum {
        D420_BIT,
        D500_BIT,
        DE00_BIT
    } addr_bit_e;

    typedef enum logic [2:0] {
        D400 = 0,
        D420 = 1 << D420_BIT,
        D500 = 1 << D500_BIT,
        DE00 = 1 << DE00_BIT
    } addr_e;

    typedef logic [2:0] addr_t;

    typedef struct packed {
        model_e model;
        addr_t  addr;  // Only used for SID 2.
        reg9_t  fc_base;
        s11_t   fc_offset;
    } cfg_t;

    typedef struct packed {
        reg5_t addr;
        reg8_t data;
        logic  phi2;
        logic  r_w_n;
        logic  res;
    } bus_i_t;

    typedef struct packed {
        logic cs_n;
        logic cs_io1_n;
        logic a8;
        logic a5;
    } cs_t;

    typedef struct packed {
        logic [1:0] charged;
    } pot_i_t;

    typedef struct packed {
        logic       discharge;
    } pot_o_t;

    // Control registers.

    typedef struct packed {
        // FREQ Lo/Hi
        reg8_t freq_lo;
        reg8_t freq_hi;
        // PW Lo/Hi
        reg8_t pw_lo;
        reg8_t pw_hi;
    } freq_pw_t;

    // Control Reg (upper 7 bits).
    typedef struct packed {
        logic noise;
        logic pulse;
        logic sawtooth;
        logic triangle;
        logic test;
        logic ring_mod;
        logic sync;
    } control_t;

    typedef struct packed {
        freq_pw_t freq_pw;
        control_t control;
    } waveform_reg_t;

    typedef struct packed {
        // Control Reg (lower 1 bit).
        logic  gate;
        // Attack/Decay.
        reg4_t attack;
        reg4_t decay;
        // Sustain/Release.
        reg4_t sustain;
        reg4_t release_;  // release is a Verilog keyword.
    } envelope_reg_t;

    typedef struct packed {
        waveform_reg_t waveform;
        envelope_reg_t envelope;
    } voice_reg_t;

    typedef struct packed {
        // FC Lo/Hi
        reg8_t fc_lo;
        reg8_t fc_hi;
        // Res / Filt
        reg4_t res;
        reg4_t filt;
        // Mode / Vol
        reg4_t mode;
        reg4_t vol;
    } filter_reg_t;

    // FIXME: Currently the array must be encapsulated in a struct,
    // otherwise Yosys miscalculates its size.
    /* verilator lint_off LITENDIAN */
    typedef struct packed {
        logic [0:1][7:0] xy;
    } pot_reg_t;
    /* verilator lint_on LITENDIAN */

    typedef struct packed {
        pot_reg_t pot;
        reg8_t    osc3;
        reg8_t    env3;
    } misc_reg_t;
endpackage

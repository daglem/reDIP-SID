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

// Combinatorial circuits for combined waveforms sawtooth + triangle.
// Espresso has been used to simplify sums of products per bit, based on
// waveform samples from reSID.
function sid::reg8_t sid_waveform__ST(logic model, sid::reg12_t x);
    if (model == 0)
        // 6581 S + T
        sid_waveform__ST = {
            ((x & 'he00) == 'he00) | ((x & 'hd00) == 'hd00) | ((x & 'hcf0) == 'hcf0),
            ((x & 'he00) == 'he00) | ((x & 'h7fc) == 'h7fc),
            ((x & 'hf00) == 'hf00) | ((x & 'h7e0) == 'h7e0) | ((x & 'h3fe) == 'h3fe),
            ((x & 'hfc0) == 'hfc0) | ((x & 'hfa0) == 'hfa0) | ((x & 'hf90) == 'hf90) | ((x & 'hf88) == 'hf88) | ((x & 'hf84) == 'hf84) | ((x & 'hf82) == 'hf82) | ((x & 'hdfc) == 'hdfc) | ((x & 'h7e0) == 'h7e0) | ((x & 'h3f0) == 'h3f0) | ((x & 'h1ff) == 'h1ff),
            ((x & 'hfd0) == 'hfd0) | ((x & 'hfc8) == 'hfc8) | ((x & 'hfc4) == 'hfc4) | ((x & 'hfc2) == 'hfc2) | ((x & 'hfc1) == 'hfc1) | ((x & 'heff) == 'heff) | ((x & 'h7e0) == 'h7e0) | ((x & 'h3f0) == 'h3f0) | ((x & 'h1f8) == 'h1f8),
            ((x & 'hfe0) == 'hfe0) | ((x & 'h3f0) == 'h3f0) | ((x & 'h1f8) == 'h1f8) | ((x & 'h0fc) == 'h0fc),
            ((x & 'hff4) == 'hff4) | ((x & 'hff2) == 'hff2) | ((x & 'h1f8) == 'h1f8) | ((x & 'h0fc) == 'h0fc) | ((x & 'h07e) == 'h07e),
            ((x & 'hff8) == 'hff8) | ((x & 'hc3f) == 'hc3f) | ((x & 'ha3f) == 'ha3f) | ((x & 'h7fb) == 'h7fb) | ((x & 'h33f) == 'h33f) | ((x & 'h0fc) == 'h0fc) | ((x & 'h0bf) == 'h0bf) | ((x & 'h07e) == 'h07e)
        };
    else
        // 8580 S + T
        sid_waveform__ST = {
            ((x & 'hf00) == 'hf00) | ((x & 'he80) == 'he80) | ((x & 'he7e) == 'he7e) | ((x & 'he7d) == 'he7d),
            ((x & 'hf00) == 'hf00) | ((x & 'h7f8) == 'h7f8),
            ((x & 'hf80) == 'hf80) | ((x & 'hf40) == 'hf40) | ((x & 'hf30) == 'hf30) | ((x & 'hf29) == 'hf29) | ((x & 'hf27) == 'hf27) | ((x & 'hf26) == 'hf26) | ((x & 'hf1e) == 'hf1e) | ((x & 'hf1d) == 'hf1d) | ((x & 'hf0f) == 'hf0f) | ((x & 'hf0f) == 'hf0f) | ((x & 'hf0f) == 'hf0f) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7e0) == 'h7e0),
            ((x & 'hf80) == 'hf80) | ((x & 'hdfe) == 'hdfe) | ((x & 'h7e0) == 'h7e0) | ((x & 'h5ff) == 'h5ff) | ((x & 'h3f0) == 'h3f0),
            ((x & 'hfc0) == 'hfc0) | ((x & 'heff) == 'heff) | ((x & 'h7e0) == 'h7e0) | ((x & 'h3f0) == 'h3f0) | ((x & 'h1f8) == 'h1f8),
            ((x & 'hfe0) == 'hfe0) | ((x & 'h3f0) == 'h3f0) | ((x & 'h1f8) == 'h1f8) | ((x & 'h0fc) == 'h0fc),
            ((x & 'hff0) == 'hff0) | ((x & 'h7f7) == 'h7f7) | ((x & 'h1f8) == 'h1f8) | ((x & 'h0fc) == 'h0fc) | ((x & 'h07e) == 'h07e),
            ((x & 'hdbf) == 'hdbf) | ((x & 'h7f8) == 'h7f8) | ((x & 'h3fa) == 'h3fa) | ((x & 'h3bf) == 'h3bf) | ((x & 'h0fc) == 'h0fc) | ((x & 'h07e) == 'h07e)
        };
endfunction

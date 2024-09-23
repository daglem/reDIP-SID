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

// Combinatorial circuits for combined waveforms pulse + sawtooth + triangle.
// Espresso has been used to simplify sums of products per bit, based on
// waveform samples from reSID.
function sid::reg8_t sid_waveform_PST(logic model, sid::reg12_t x);
    if (model == 0)
        // 6581 P + S + T
        sid_waveform_PST = {
            ((x & 'hf00) == 'hf00) | ((x & 'hec0) == 'hec0) | ((x & 'heb0) == 'heb0) | ((x & 'heac) == 'heac) | ((x & 'heaa) == 'heaa) | ((x & 'hea9) == 'hea9) | ((x & 'hea6) == 'hea6) | ((x & 'hea5) == 'hea5) | ((x & 'he9c) == 'he9c) | ((x & 'he9a) == 'he9a) | ((x & 'he99) == 'he99) | ((x & 'he96) == 'he96) | ((x & 'he8e) == 'he8e) | ((x & 'he70) == 'he70) | ((x & 'he6c) == 'he6c) | ((x & 'he6a) == 'he6a) | ((x & 'he66) == 'he66) | ((x & 'he5c) == 'he5c) | ((x & 'he5b) == 'he5b) | ((x & 'he57) == 'he57) | ((x & 'he4f) == 'he4f) | ((x & 'he3c) == 'he3c) | ((x & 'he3b) == 'he3b) | ((x & 'he37) == 'he37) | ((x & 'he2f) == 'he2f) | ((x & 'he1f) == 'he1f) | ((x & 'hdf0) == 'hdf0) | ((x & 'hdec) == 'hdec) | ((x & 'hdeb) == 'hdeb) | ((x & 'hde7) == 'hde7) | ((x & 'hdde) == 'hdde) | ((x & 'hddd) == 'hddd) | ((x & 'hdcf) == 'hdcf) | ((x & 'hdbe) == 'hdbe) | ((x & 'hd7e) == 'hd7e) | ((x & 'hcfe) == 'hcfe),
            ((x & 'hfc0) == 'hfc0) | ((x & 'hfa0) == 'hfa0) | ((x & 'hf90) == 'hf90) | ((x & 'hf88) == 'hf88) | ((x & 'hf84) == 'hf84) | ((x & 'hf82) == 'hf82) | ((x & 'hf70) == 'hf70) | ((x & 'hf6c) == 'hf6c) | ((x & 'hf6a) == 'hf6a) | ((x & 'hf69) == 'hf69) | ((x & 'hf66) == 'hf66) | ((x & 'hf65) == 'hf65) | ((x & 'hf63) == 'hf63) | ((x & 'hf5c) == 'hf5c) | ((x & 'hf5b) == 'hf5b) | ((x & 'hf57) == 'hf57) | ((x & 'hf4f) == 'hf4f) | ((x & 'hf3c) == 'hf3c) | ((x & 'hf3b) == 'hf3b) | ((x & 'hf37) == 'hf37) | ((x & 'hf2f) == 'hf2f) | ((x & 'hf1f) == 'hf1f) | ((x & 'hefc) == 'hefc) | ((x & 'hefa) == 'hefa) | ((x & 'hef9) == 'hef9) | ((x & 'hef7) == 'hef7) | ((x & 'heef) == 'heef) | ((x & 'hedf) == 'hedf) | ((x & 'hebf) == 'hebf) | ((x & 'he7f) == 'he7f) | ((x & 'h7fc) == 'h7fc) | ((x & 'h7fb) == 'h7fb),
            ((x & 'hfe0) == 'hfe0) | ((x & 'hfd0) == 'hfd0) | ((x & 'hfc8) == 'hfc8) | ((x & 'hfc4) == 'hfc4) | ((x & 'hfc2) == 'hfc2) | ((x & 'hfc1) == 'hfc1) | ((x & 'hfb8) == 'hfb8) | ((x & 'hfb4) == 'hfb4) | ((x & 'hfb2) == 'hfb2) | ((x & 'hfae) == 'hfae) | ((x & 'hfad) == 'hfad) | ((x & 'hfa7) == 'hfa7) | ((x & 'hf9e) == 'hf9e) | ((x & 'hf9d) == 'hf9d) | ((x & 'hf8f) == 'hf8f) | ((x & 'hf7c) == 'hf7c) | ((x & 'hf7b) == 'hf7b) | ((x & 'hf77) == 'hf77) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7fc) == 'h7fc) | ((x & 'h7fb) == 'h7fb) | ((x & 'h7f7) == 'h7f7),
            ((x & 'hfe0) == 'hfe0) | ((x & 'hfd8) == 'hfd8) | ((x & 'hfd6) == 'hfd6) | ((x & 'hfd5) == 'hfd5) | ((x & 'hfd3) == 'hfd3) | ((x & 'hfce) == 'hfce) | ((x & 'hfbe) == 'hfbe) | ((x & 'hfbd) == 'hfbd) | ((x & 'hdfe) == 'hdfe) | ((x & 'hbfe) == 'hbfe) | ((x & 'hbfd) == 'hbfd) | ((x & 'h7fc) == 'h7fc) | ((x & 'h7fb) == 'h7fb) | ((x & 'h7f7) == 'h7f7) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hff0) == 'hff0) | ((x & 'hfec) == 'hfec) | ((x & 'hfea) == 'hfea) | ((x & 'hfe6) == 'hfe6) | ((x & 'hfde) == 'hfde) | ((x & 'heff) == 'heff) | ((x & 'hdfe) == 'hdfe) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7fe) == 'h7fe) | ((x & 'h7fd) == 'h7fd) | ((x & 'h7fb) == 'h7fb) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hff8) == 'hff8) | ((x & 'hff4) == 'hff4) | ((x & 'hff2) == 'hff2) | ((x & 'hfee) == 'hfee) | ((x & 'hf7f) == 'hf7f) | ((x & 'hefe) == 'hefe) | ((x & 'hdfe) == 'hdfe) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7fe) == 'h7fe) | ((x & 'h7fd) == 'h7fd) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hff8) == 'hff8) | ((x & 'hff6) == 'hff6) | ((x & 'hfbf) == 'hfbf) | ((x & 'hf7f) == 'hf7f) | ((x & 'heff) == 'heff) | ((x & 'hdfe) == 'hdfe) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7fe) == 'h7fe) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hffc) == 'hffc) | ((x & 'hffb) == 'hffb) | ((x & 'hfdf) == 'hfdf) | ((x & 'hfbf) == 'hfbf) | ((x & 'hf7f) == 'hf7f) | ((x & 'heff) == 'heff) | ((x & 'hdff) == 'hdff) | ((x & 'h7fe) == 'h7fe) | ((x & 'h3ff) == 'h3ff)
        };
    else
        // 8580 P + S + T
        sid_waveform_PST = {
            ((x & 'hf00) == 'hf00) | ((x & 'hec0) == 'hec0) | ((x & 'hea0) == 'hea0) | ((x & 'he90) == 'he90) | ((x & 'he8a) == 'he8a) | ((x & 'he89) == 'he89) | ((x & 'he85) == 'he85) | ((x & 'he83) == 'he83) | ((x & 'he70) == 'he70) | ((x & 'he6c) == 'he6c) | ((x & 'he6a) == 'he6a) | ((x & 'he67) == 'he67) | ((x & 'he5e) == 'he5e) | ((x & 'he3e) == 'he3e) | ((x & 'hdf8) == 'hdf8) | ((x & 'hdf7) == 'hdf7),
            ((x & 'hf00) == 'hf00) | ((x & 'hef0) == 'hef0) | ((x & 'heee) == 'heee) | ((x & 'h7f8) == 'h7f8) | ((x & 'h7f4) == 'h7f4) | ((x & 'h7f2) == 'h7f2) | ((x & 'h7f1) == 'h7f1) | ((x & 'h7ef) == 'h7ef),
            ((x & 'hf80) == 'hf80) | ((x & 'hf78) == 'hf78) | ((x & 'hf74) == 'hf74) | ((x & 'hf6f) == 'hf6f) | ((x & 'hbff) == 'hbff) | ((x & 'h7f0) == 'h7f0) | ((x & 'h7ee) == 'h7ee),
            ((x & 'hfc0) == 'hfc0) | ((x & 'hfb8) == 'hfb8) | ((x & 'hfb6) == 'hfb6) | ((x & 'hdff) == 'hdff) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7f8) == 'h7f8) | ((x & 'h7f4) == 'h7f4) | ((x & 'h7f2) == 'h7f2) | ((x & 'h7ef) == 'h7ef) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hfe0) == 'hfe0) | ((x & 'hfdc) == 'hfdc) | ((x & 'hfda) == 'hfda) | ((x & 'heff) == 'heff) | ((x & 'hdfe) == 'hdfe) | ((x & 'hbfe) == 'hbfe) | ((x & 'hbfd) == 'hbfd) | ((x & 'h7f8) == 'h7f8) | ((x & 'h7f7) == 'h7f7) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hff0) == 'hff0) | ((x & 'hfec) == 'hfec) | ((x & 'hfeb) == 'hfeb) | ((x & 'heff) == 'heff) | ((x & 'hdfe) == 'hdfe) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7fc) == 'h7fc) | ((x & 'h7fa) == 'h7fa) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hff8) == 'hff8) | ((x & 'hff6) == 'hff6) | ((x & 'hff5) == 'hff5) | ((x & 'hf7f) == 'hf7f) | ((x & 'heff) == 'heff) | ((x & 'hdff) == 'hdff) | ((x & 'hbfe) == 'hbfe) | ((x & 'h7fc) == 'h7fc) | ((x & 'h3ff) == 'h3ff),
            ((x & 'hffc) == 'hffc) | ((x & 'hffa) == 'hffa) | ((x & 'hff9) == 'hff9) | ((x & 'hf7f) == 'hf7f) | ((x & 'heff) == 'heff) | ((x & 'hdff) == 'hdff) | ((x & 'h7fe) == 'h7fe) | ((x & 'h3ff) == 'h3ff)
        };
endfunction

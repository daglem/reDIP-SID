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

// Run "make sim" to create simulation executables.
//
// The simulation reads lines from stdin on the following format, each line
// specifying a number of cycles to wait before writing to a SID register:
//
// cycles address value
//
// To test parts of real SID tunes, such SID register writes may be logged using
//
// vsid +saveres [-console] -sounddev dump -soundarg <filename.sidw> -tune <number> <filename.sid>
//
// To write a waveform dump for gtkwave to the file sid_api.fst:
//
// grep -v : <filename.sidw> | head -<numwrites> | sim_trace/Vsid_api
//
// To write raw audio to the file sid_api_audio.raw:
//
// grep -v : <filename.sidw> | head -<numwrites> | sim_audio/Vsid_api
//
// sid_api_audio.raw may be converted using e.g. either of:
//
// ffmpeg -loglevel error -y -f s24be -ar 96000 -ac 1 -i sid_api_audio.raw sid_api_audio.flac
// flac -s -f --endian=big --sign=signed --channels=1 --bps=24 --sample-rate=96000 sid_api_audio.raw

#include "Vsid_api.h"
#include "verilated.h"
#include <iostream>
#include <iomanip>
#include <fstream>

using namespace std;

// FIXME: Not used in newer versions of Verilator.
static double edges = 0;
double sc_time_stamp() {
    // 2.083ns for 2*24MHz edges.
    return 2.083*edges++;
}

void clk(Vsid_api* api) {
    api->clk = 1; api->eval();
    // api->timeInc();
    api->clk = 0; api->eval();
    // api->timeInc();
}

void clk12(Vsid_api* api) {
    for (int i = 0; i < 12; i++) {
        clk(api);
    }
}

void phi2(Vsid_api* api) {
    api->phi2 = 1;
    clk12(api);
}

void phi1(Vsid_api* api) {
    api->phi2 = 0;
    clk12(api);
}

void write(Vsid_api* api, int addr, int data) {
    api->bus_i = (addr << 11) | (data << 3) | (0b1 << 2) | (api->bus_i & 1);
}


int main(int argc, char** argv, char** env) {
#if VM_TRACE == 1
    Verilated::traceEverOn(true);
#endif
    Verilated::commandArgs(argc, argv);

    if (argc != 1) {
        return -1;
    }

    auto api = new Vsid_api;

    api->clk     = 0;
    api->phi2    = 0;
    api->bus_i   = 0;
    api->cs      = 0b0100;  // cs_n = 0, cs_io1_n = 1
    api->pot_i   = 0;
    api->audio_i = 0;

    // PAL phi2 = 0.985MHz
    // NTSC phi2 = 1.022725
    double cycle_T  = 1.0/0.985e6;
    double sample_T = 1.0/96e3;
    double sample_t  = 0;

#if VM_TRACE == 0
    ofstream fout("sid_api_audio.raw");
#endif

    // Convert input according to number prefixes (0x for hex, 0 for octal).
    cin.unsetf(ios::basefield);

    while (!cin.eof()) {
        int cycles, reg, val;
        cin >> cycles >> reg >> val >> ws;
        for (int i = 0; i < cycles; i++) {
            phi2(api);
            phi1(api);
#if VM_TRACE == 0
            sample_t += cycle_T;
            if (sample_t >= sample_T) {
                uint64_t o = api->audio_o;
                // Output left channel only.
                for (int j = 0; j < 3; j++) {
                    unsigned char c = o >> (8*(5 - j));
                    fout << c;
                }
                sample_t -= sample_T;
            }
#endif
        }
        write(api, reg, val);
    }

    api->final();
    delete api;
    return 0;
}

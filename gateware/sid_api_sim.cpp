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
// To test parts of real SID tunes, such SID register writes may be logged
// using either of:
//
// vsid +saveres [-console] -sounddev dump -soundarg <filename.sidw> -tune <number> <filename.sid>
// x64sc +saveres -sounddev dump -soundarg <filename.sidw> <filename.prg>
//
// To write a waveform dump for gtkwave to the file sid_api.fst:
//
// grep -v : <filename.sidw> | head -<numwrites> | sim_trace/Vsid_api
//
// To write raw audio to the file sid_api_audio.raw (see options!):
//
// grep -v : <filename.sidw> | head -<numwrites> | sim_audio/Vsid_api
//
// sid_api_audio.raw may be converted using e.g. either of:
//
// ffmpeg -loglevel error -y -f s24be -ar 96000 -ac 1 -i sid_api_audio.raw sid_api_audio.flac
// flac -s -f --endian=big --sign=signed --channels=1 --bps=24 --sample-rate=96000 sid_api_audio.raw

#include "Vsid_api.h"
#include <verilated.h>
#include <climits>
#include <fstream>
#include <getopt.h>
#include <stdio.h>
#include <unistd.h>
#include <iomanip>
#include <iostream>

using namespace std;

#if VM_TRACE == 0

// The frequency values below are copied from VICE.
constexpr int PHI2_HZ_PAL   =  985248;
constexpr int PHI2_HZ_NTSC  = 1022730;
constexpr int PHI2_HZ_PAL_N = 1023440;

static bool to_stdout = false;
static bool sid_filter = true;
static bool ext_filter = true;
static int f0hp = 10;
static int f0lp = 16000;
static int sample_hz = 96000;
static int sid_model = 0;  // MOS6581
static int phi2_hz = PHI2_HZ_PAL;

static struct option long_opts[] = {
    { "stdout",          no_argument,       0, 'c' },
    { "filter",          required_argument, 0, 'f' },
    { "bandpass",        required_argument, 0, 'p' },
    { "sample-rate",     required_argument, 0, 'r' },
    { "sid-model",       required_argument, 0, 's' },
    { "video-standard",  required_argument, 0, 'v' },
    { "help",            no_argument,       0, 'h' },
    { 0,                 0,                 0, 0   }
};

static void parse_args(int argc, char** argv) {
    int opt;
    int opt_ix = -1;
    while ((opt = getopt_long(argc, argv, "ce:f:p:r:s:v:h", long_opts, &opt_ix)) != -1) {
        string val = optarg ? optarg : "";
        switch (opt) {
        case 'c':
            to_stdout = true;
            break;
        case 'f':
            if      (val == "sid")  { sid_filter = true;  ext_filter = false; }
            else if (val == "ext")  { sid_filter = false; ext_filter = true;  }
            else if (val == "all")  { sid_filter = true;  ext_filter = true;  }
            else if (val == "none") { sid_filter = false; ext_filter = false; }
            else                    goto fail;
            break;
        case 'p':
            if (sscanf(optarg, "%d-%d", &f0hp, &f0lp) != 2 ||
                f0hp < 1 || f0lp > 20000)
            {
                goto fail;
            }
            break;
        case 'r':
            if ((sample_hz = strtol(optarg, 0, 10)) <= 0)
                goto fail;
            break;
        case 's':
            if      (val == "6581") sid_model = 0;
            else if (val == "8580") sid_model = 1;
            else                    goto fail;
            break;
        case 'v':
            if      (val == "pal")   phi2_hz = PHI2_HZ_PAL;
            else if (val == "ntsc")  phi2_hz = PHI2_HZ_NTSC;
            else if (val == "pal-n") phi2_hz = PHI2_HZ_PAL_N;
            else                     goto fail;
            break;
        case 'h':
            cout << "Usage: " << argv[0] << " [verilator-options] [options]" << R"(
Read lines of SID register writes (cycles address value) from standard input.
Write simulated raw audio to "sid_api_sim.raw" (default) or to standard output.

Options:
  -c, --stdout                           Write raw audio to standard output.
  -f, --filter {sid|ext|all|none}        Enable filters (default: all).
  -p, --bandpass <from-to>               Ext. filter band (default: 10-16000).
  -r, --sample-rate <frequency>          Set sample rate in Hz (default: 96000).
  -s, --sid-model {6581|8580}            Specify SID model (default: 6581).
  -v, --video-standard {pal|ntsc|pal-n}  Specify video standard (default: pal).
  -h, --help                             Display this information.
)";
            exit(EXIT_SUCCESS);
        default:
            goto help;
        }

        opt_ix = -1;
        continue;

    fail:
        cerr << argv[0]
             << ": option '"
             << (opt_ix != -1 ? "--" : "-")
             << (opt_ix != -1 ? string(long_opts[opt_ix].name) : string(1, (char)opt))
             << "' has invalid argument '" << val << "'"
             << endl;
    help:
        cerr << "Try '" << argv[0] << " --help' for more information." << endl;
        exit(EXIT_FAILURE);
    }
}


// The implementation of the external filter is adapted from reSID.
class ExternalFilterCoefficients
{
public:
    int shifthp, shiftlp;
    int mulhp, mullp;

    ExternalFilterCoefficients(double w0hp, double w0lp, double T, int coeff_bits) :
        // Fits cutoff frequencies in coeff_bits.
        shifthp( log2(((1 << coeff_bits) - 1.0)/(1.0 - exp(-w0hp*T))) ),
        shiftlp( log2(((1 << coeff_bits) - 1.0)/(1.0 - exp(-w0lp*T))) ),
        mulhp( (1.0 - exp(-w0hp*T))*(1 << shifthp) + 0.5 ),
        mullp( (1.0 - exp(-w0lp*T))*(1 << shiftlp) + 0.5 )
    {}
};

#endif


// FIXME: Not used in newer versions of Verilator.
static double edges = 0;
double sc_time_stamp() {
    // 2.083ns for 2*24MHz edges.
    return 2.083*edges++;
}

static void clk(Vsid_api* api) {
    api->clk = 1; api->eval();
    // api->timeInc();
    api->clk = 0; api->eval();
    // api->timeInc();
}

static void clk12(Vsid_api* api) {
    for (int i = 0; i < 12; i++) {
        clk(api);
    }
}

static void phi2(Vsid_api* api) {
    api->bus_i |= (0b1 << 2);
    clk12(api);
}

static void phi1(Vsid_api* api) {
    api->bus_i &= ~(0b1 << 2);
    clk12(api);
}

static void write(Vsid_api* api, int addr, int data) {
    api->bus_i = (addr << 11) | (data << 3) | (api->bus_i & 0b101);
}


int main(int argc, char** argv, char** env) {
    Verilated::commandArgs(argc, argv);
#if VM_TRACE == 1
    Verilated::traceEverOn(true);
    optind = 1;
#else
    parse_args(argc, argv);
#endif

    // Skip over "+verilator+" arguments.
    while (optind < argc && strncmp(argv[optind], "+verilator+", 11) == 0) {
        optind++;
    }

    if (optind < argc || isatty(fileno(stdin))) {
        if (!(optind < argc)) {
            cerr << argv[0] << ": standard input is a terminal." << endl;
        }
#if VM_TRACE == 1
        cerr << "Usage: " << argv[0] << R"( [verilator-options]
Read lines of SID register writes (cycles address value) from standard input.
Write waveform dump to "sid_api.fst".
)";
#else
        if (optind < argc) {
            cerr << argv[0]
                 << ": unrecognized argument '" << argv[optind] << "'" << endl;
        }
        cerr << "Try '" << argv[0] << " --help' for more information." << endl;
#endif
        return EXIT_FAILURE;
    }

    auto api = new Vsid_api;

    api->clk     = 0;
    api->bus_i   = 0;
    api->cs      = 0b0100;  // cs_n = 0, cs_io1_n = 1
    api->pot_i   = 0;
    api->audio_i = 0;

#if VM_TRACE == 0
    double cycle_T  = 1.0/phi2_hz;
    double sample_T = 1.0/sample_hz;
    double sample_t  = 0;

    // The implementation of the external filter is adapted from reSID.
    // Cutoff frequencies for C64 external bandpass filter:
    // w0hp = 1/(Rload*C77) = 1/(10e3*10e-6) =     10 (1.6Hz)
    // w0lp = 1/(R8*C74)    = 1/(10e3*1e-9)  = 100000 (16kHz)
    double w0hp = 2*M_PI*f0hp;
    double w0lp = 2*M_PI*f0lp;

    // Filter coefficients are fit into 4 bits, leaving 27 bits for filter
    // states (reserving one bit for summing). It is crucial to reserve a high
    // number of bits for filter states, since the highpass frequency can be
    // set very low (1Hz), and changes to vhp can thus be very small.
    constexpr int coeff_bits = 4;
    auto t1 = ExternalFilterCoefficients(w0hp, w0lp, cycle_T, coeff_bits);
    // Left shift of input, given 24 bit samples.
    constexpr int shifti = int(sizeof(int))*CHAR_BIT - coeff_bits - 1 - 24;

    // Filter states (27 bits):
    int vhp = 0;
    int vlp = 0;

    // With floating point:
    // double mulhp = 1.0 - exp(-w0hp*cycle_T);
    // double mullp = 1.0 - exp(-w0lp*cycle_T);
    // double vhp = 0;
    // double vlp = 0;

    ostream* out;
    ofstream fout;
    if (to_stdout) {
        out = &cout;
    } else {
        fout = ofstream("sid_api_audio.raw");
        out = &fout;
    }

    // TODO: Register writes to select SID model.
#endif

    // Convert input according to number prefixes (0x for hex, 0 for octal).
    cin.unsetf(ios::basefield);

    while (!cin.eof()) {
        int cycles, reg, val;
        cin >> cycles >> reg >> val >> ws;
#if VM_TRACE == 0
        if (!sid_filter) {
            if (reg == 0x17) {
                // Mask out Filt EX/Filt 3/Filt 2/Filt 1.
                val &= 0xF0;
            }
            else if (reg == 0x18) {
                // Mask out HP/BP/LP.
                val &= 0x8F;
            }
        }
#endif
        for (int i = 0; i < cycles; i++) {
            phi2(api);
            phi1(api);
#if VM_TRACE == 0
            // Output left channel only (24 bits).
            int o = int32_t(api->audio_o >> 16) >> 8;
            if (ext_filter) {
                // C64 audio output filter enabled.
                // The implementation of the external filter is adapted from reSID.
                vhp += t1.mulhp*(vlp - vhp) >> t1.shifthp;
                vlp += t1.mullp*((o << shifti) - vlp) >> t1.shiftlp;
                o = (vlp - vhp) >> shifti;
                // With floating point:
                // vhp += mulhp*(vlp - vhp);
                // vlp += mullp*(o - vlp);
                // o = round(vlp - vhp);
            }
            sample_t += cycle_T;
            if (sample_t >= sample_T) {
                for (int j = 0; j < 3; j++) {
                    unsigned char c = uint32_t(o) >> (8*(2 - j));
                    *out << c;
                }
                sample_t -= sample_T;
            }
#endif
        }
        write(api, reg, val);
    }

    api->final();
    delete api;

    return EXIT_SUCCESS;
}

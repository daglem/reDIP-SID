# ----------------------------------------------------------------------------
# This file is part of reDIP SID, a MOS 6581/8580 SID FPGA emulation platform.
# Copyright (C) 2022  Dag Lem <resid@nimrod.no>
#
# This source describes Open Hardware and is licensed under the CERN-OHL-S v2.
#
# You may redistribute and modify this source and make products using it under
# the terms of the CERN-OHL-S v2 (https:#ohwr.org/cern_ohl_s_v2.txt).
#
# This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
# INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
# PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.
#
# Source location: https:#github.com/daglem/reDIP-SID
# ----------------------------------------------------------------------------

# Simulation of MOS6581 filter cutoff curves.
#
# The simple approximation function which is used has the advantage that a
# software or hardware implementation only requires a single lookup table for
# the function y = 12000*tanh(x/350) to simulate any filter cutoff curve.
# Since tanh(-x) = -tanh(x), we only need to store table data for x >= 0.
#
# For comparison, the plot includes measurement data from
# https://bel.fi/alankila/c64-sw/fc-curves/

# Load filter cutoff DAC table data.
array fc_dac[2048]
stats "fc-curves-dac.dat" using (fc_dac[int($0) + 1] = int($1)) nooutput

# Define novel approximation function.
# b = base cutoff frequency
# d = FC register offset
# The center of the FC range is 1024, and the center of the average 6581 curve
# is additionaly offset by approximately 512. A further FC offset in the range
# [-1024, 1023] (11 bits) is more than sufficient to model any SID chip.
fc_curve(fc,b,d) = b + 12000*(1 + tanh((fc_dac[fc + 1] - (1024 + 512 + d))/350.0))

# Plot to PNG.
set terminal png truecolor linewidth 2 font "arial,14" size 1280,1024
set output "fc-curves.png"

# Plot measurement data and corresponding approximation curves.
set logscale y
set xrange [0:2047]
set yrange [170:24500]
set title "MOS6581 filter cutoff characteristics"
set key outside title "Measurement data:\nhttps://bel.fi/alankila/c64-sw/fc-curves\n\nApproximations:\nhttps://github.com/daglem/reDIP-SID\n" left
set xlabel "FC register value"
set ylabel "Cutoff frequency (Hz)"
set label "Follin-style" at 160,2000
set label "Galway-style" at 590,2000
set label "Average 6581" at 1050,2000
set label "Strong filter" at 1500,2000
set label "Extreme filter" at 1800,2000
set samples 2048
set style data lines
plot \
    "fc-curves/Trurl_Ext/6581R3_4885.txt" title "r3 4885 trurl", \
    fc_curve(x, 240, -785), \
    "fc-curves/Trurl_Ext/6581_3384.txt" title "r2 3384 trurl", \
    fc_curve(x, 280, -405), \
    "fc-curves/ZrX-oMs/6581R4AR_2286.txt" title "r4ar 2286 zrx", \
    fc_curve(x, 240, -20), \
    "fc-curves/Trurl_Ext/6581R4AR_3789.txt" title "r4ar 3789 trurl", \
    fc_curve(x, 300, +40), \
    "fc-curves/lord_nightmare/r3-6581r3-4485-redone.txt" title "r3 4485 lordn", \
    fc_curve(x, 260, +400), \
    "fc-curves/ZrX-oMs/6581R2_1984.txt" title "r3 4485 lordn", \
    fc_curve(x, 180, +430), \
    "fc-curves/ZrX-oMs/6581R2_3684.txt" title "r2 3684 zrx", \
    fc_curve(x, 200, +760)

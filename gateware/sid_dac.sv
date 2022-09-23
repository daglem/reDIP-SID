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

// ----------------------------------------------------------------------------
// This file is based on documentation and code from reSID, see
// https://github.com/daglem/reSID
//
// The SID DACs are built up as follows:
//
//          n  n-1      2   1   0    VGND
//          |   |       |   |   |      |   Termination
//         2R  2R      2R  2R  2R     2R   only for
//          |   |       |   |   |      |   MOS 8580
//      Vo  --R---R--...--R---R--    ---
//
//
// All MOS 6581 DACs are missing a termination resistor at bit 0. This causes
// pronounced errors for the lower 4 - 5 bits (e.g. the output for bit 0 is
// actually equal to the output for bit 1), resulting in DAC discontinuities
// for the lower bits.
// In addition to this, the 6581 DACs exhibit further severe discontinuities
// for higher bits, which may be explained by a less than perfect match between
// the R and 2R resistors, or by output impedance in the NMOS transistors
// providing the bit voltages. A good approximation of the actual DAC output is
// achieved for 2R/R ~ 2.20.
//
// The MOS 8580 DACs, on the other hand, do not exhibit any discontinuities.
// These DACs include the correct termination resistor, and also seem to have
// very accurately matched R and 2R resistors (2R/R = 2.00).
// ----------------------------------------------------------------------------

`default_nettype none

module sid_dac #(
    parameter BITS       = 12,
    parameter _2R_DIV_R  = 2.20,
    parameter TERM       = 0,
    localparam SCALEBITS = 4
)(
    input  logic [BITS-1:0] vin,
    output logic [BITS-1:0] vout
);
    logic [BITS-1+SCALEBITS:0] bitval[BITS];
    /* verilator lint_off UNUSED */
    logic [BITS-1+SCALEBITS:0] bitsum;
    /* verilator lint_on UNUSED */

`ifdef SV_ARRAY_MANIP
    // FIXME: Yosys, sv2v, Verilator, and Icarus Verilog all lack support for
    // SystemVerilog array reduction methods.
    always_comb begin
        // Sum values for all set bits, and add 0.5 for rounding by truncation.
        bitsum = bitval.sum with ( vin[item.index] ? item : 0 ) + (1 << (SCALEBITS - 1));
    end
`else
    if (BITS == 12) begin : dac12
        always_comb begin
            bitsum =
                (vin[11] ? bitval[11] : 0) +
                (vin[10] ? bitval[10] : 0) +
                (vin[ 9] ? bitval[ 9] : 0) +
                (vin[ 8] ? bitval[ 8] : 0) +
                (vin[ 7] ? bitval[ 7] : 0) +
                (vin[ 6] ? bitval[ 6] : 0) +
                (vin[ 5] ? bitval[ 5] : 0) +
                (vin[ 4] ? bitval[ 4] : 0) +
                (vin[ 3] ? bitval[ 3] : 0) +
                (vin[ 2] ? bitval[ 2] : 0) +
                (vin[ 1] ? bitval[ 1] : 0) +
                (vin[ 0] ? bitval[ 0] : 0) +
                (1 << (SCALEBITS - 1));
        end
    end else if (BITS == 11) begin : dac11
        always_comb begin
            bitsum =
                (vin[10] ? bitval[10] : 0) +
                (vin[ 9] ? bitval[ 9] : 0) +
                (vin[ 8] ? bitval[ 8] : 0) +
                (vin[ 7] ? bitval[ 7] : 0) +
                (vin[ 6] ? bitval[ 6] : 0) +
                (vin[ 5] ? bitval[ 5] : 0) +
                (vin[ 4] ? bitval[ 4] : 0) +
                (vin[ 3] ? bitval[ 3] : 0) +
                (vin[ 2] ? bitval[ 2] : 0) +
                (vin[ 1] ? bitval[ 1] : 0) +
                (vin[ 0] ? bitval[ 0] : 0) +
                (1 << (SCALEBITS - 1));
        end
    end else if (BITS == 8) begin : dac8
        always_comb begin
            bitsum =
                (vin[ 7] ? bitval[ 7] : 0) +
                (vin[ 6] ? bitval[ 6] : 0) +
                (vin[ 5] ? bitval[ 5] : 0) +
                (vin[ 4] ? bitval[ 4] : 0) +
                (vin[ 3] ? bitval[ 3] : 0) +
                (vin[ 2] ? bitval[ 2] : 0) +
                (vin[ 1] ? bitval[ 1] : 0) +
                (vin[ 0] ? bitval[ 0] : 0) +
                (1 << (SCALEBITS - 1));
        end
    end
`endif

    always_comb begin
        vout = bitsum[BITS-1+SCALEBITS:SCALEBITS];
    end

    initial begin
`ifdef YOSYS
        // FIXME: Currently the tables must be precalculated for Yosys,
        // which doesn't support variables of data type real.
        if (_2R_DIV_R == 2.20 && TERM == 0 && SCALEBITS == 4) begin
            case (BITS)
              12: $readmemh("dac_6581_waveform.txt", bitval);
              11: $readmemh("dac_6581_cutoff.txt",   bitval);
               8: $readmemh("dac_6581_envelope.txt", bitval);
            endcase
        end
`else
        real INFINITY = -1;  // This is only a flag, it just has to be different.

        // Calculate voltage contribution by each individual bit in the R-2R ladder.
        for (int set_bit = 0; set_bit < BITS; set_bit++) begin
            int n;  // Bit number.
            /* verilator lint_off UNUSED */
            int bitval_tmp;
            /* verilator lint_on UNUSED */

            real Vn = 1.0;          // Normalized bit voltage.
            real R = 1.0;           // Normalized R
            real _2R = _2R_DIV_R*R; // 2R
            real Rn = TERM ?        // Rn = 2R for correct termination,
                _2R : INFINITY;     // INFINITY for missing termination.

            // Calculate DAC "tail" resistance by repeated parallel substitution.
            for (n = 0; n < set_bit; n++) begin
                if (Rn == INFINITY) begin
                    Rn = R + _2R;
                end
                else begin
                    Rn = R + _2R*Rn/(_2R + Rn); // R + 2R || Rn
                end
            end

            // Source transformation for bit voltage.
            if (Rn == INFINITY) begin
                Rn = _2R;
            end
            else begin
                Rn = _2R*Rn/(_2R + Rn);  // 2R || Rn
                Vn = Vn*Rn/_2R;
            end

            // Calculate DAC output voltage by repeated source transformation from
            // the "tail".
            for (n = n + 1; n < BITS; n++) begin
                real I;
                Rn += R;
                I = Vn/Rn;
                Rn = _2R*Rn/(_2R + Rn);  // 2R || Rn
                Vn = Rn*I;
            end

            // Single bit values for superpositioning, scaled by 2^SCALEBITS.
            bitval_tmp = $rtoi(((1 << BITS) - 1)*Vn*(1 << SCALEBITS) + 0.5);
            bitval[set_bit] = bitval_tmp[BITS-1+SCALEBITS:0];
        end
`endif
    end
endmodule

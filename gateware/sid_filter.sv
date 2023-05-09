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

// Clamp to 16 bits.
function sid::s16_t clamp(sid::s17_t x);
    unique case (x[16:15])
      2'b10: clamp = -32768;
      2'b01: clamp =  32767;
      default:
             clamp =  x[15:0];
    endcase
endfunction

// Clamp index to [-1023, 1023].
// A simple bit check cannot be used since -1024 must not be included.
function sid::s11_t tanh_x_clamp(sid::s13_t x);
    tanh_x_clamp = (x < -1023) ? -1023 :
                   (x >  1023) ?  1023 :
                   11'(x);
endfunction

// We take advantage of the fact that tanh(-x) = -tanh(x) to access table data
// for x >= 0 only.
function sid::reg10_t tanh_x_mirror(sid::s11_t x);
    tanh_x_mirror = 10'(x < 0 ? -x : x);
endfunction

function sid::s16_t tanh_y_mirror(logic x_neg, sid::s16_t y);
    tanh_y_mirror = x_neg ? -y : y;
endfunction


module sid_filter #(
    // FC offset for average 6581 filter curve.
    localparam FC_OFFSET_6581 = 12'sh600,
    // The 6581 mixer DC offset is approximately -1/18 of the dynamic range of one voice.
    localparam MIXER_DC_6581 = 24'(-(1 << 20)/18),
    localparam MIXER_DC_8580 = 24'(0),
    localparam PI = $acos(-1)
)(
    input  logic             clk,
    input  sid::cycle_t      cycle,
    input  sid::filter_reg_t freg,
    input  sid::cfg_t        cfg,
    input  sid::s22_t        voice_i,
    output sid::s20_t        audio_o
);

    // MOS6581 filter cutoff: 200Hz - 24.2kHz (from cutoff curves below)
    // For reference, the datasheet specifies 30Hz - 12kHz.
    //
    // Max w0 = 2*pi*24200 = 152053.
    // In the filter, we must calculate w0*T for a ~1MHz clock.
    // 1.048576/(2^3)*w0 corresponds to 2^17*w0*T, since T =~ 1/1000000,
    // and 2^(3 + 17) = 1048576.
    // This scaled w0*T fits in a signed 16 bit register.
    //
    // As a first approximation, we use filter cutoff curves.
    // Several measurements of such curves can be found at
    // https://bel.fi/alankila/c64-sw/fc-curves/
    //
    // The curves can be approximated quite well by the following formula:
    //
    // fc_curve(fc,b,d) = b + 12000*(1 + tanh((fc_dac(fc) - (1024 + 512 + d))/350.0))
    //
    // - fc is the value of the FC register (x direction)
    // - b is the base cutoff frequency, shifting the curve in the y direction
    // - fc_dac(fc) is the output from the discontinuous filter cutoff DAC
    // - 1024 + 512 shifts the curve to match the average 6581 filter curve
    // - d further shifts the curve in the x direction, to model any chip
    //
    // Example filter curves:
    //
    // Follin-style: fc_curve(x, 240, -785)
    // Galway-style: fc_curve(x, 280, -405)
    // Average     : fc_curve(x, 250,    0)
    // Strong      : fc_curve(x, 260, +400)
    // Extreme     : fc_curve(x, 200, +760)
    //

    sid::s16_t w0_T_lsl17_8580;
    sid::s16_t w0_T_lsl17_6581;
    sid::s16_t w0_T_lsl17_6581_base = 0;

    // Since tanh(-x) = -tanh(x), we store table data for x >= 0 only, and use
    // the functions tanh_x_mirror and tanh_y_mirror for mirroring.
    sid::s16_t w0_T_lsl17_6581_tanh[1024];
    sid::s16_t w0_T_lsl17_6581_y0;
    initial begin
        for (int i = 0; i < 1024; i++) begin
            w0_T_lsl17_6581_tanh[i] = 16'($rtoi(1.048576/8*2*PI*12000*$tanh(i/350.0) + 0.5));
        end
        // NB! Can't lookup from table here, as this precludes the use of BRAM.
        // w0_T_lsl17_6581_y0 = w0_T_lsl17_6581_tanh[0];
        w0_T_lsl17_6581_y0 = 16'($rtoi(1.048576/8*2*PI*12000*1 + 0.5));
    end

    // MOS8580 filter cutoff: 0 - 12.5kHz.
    // Max w0 = 2*pi*12500 = 78540
    // We use the same scaling factor for w0*T as above.
    // The maximum value of the scaled w0*T is 1.048576/8*2*pi*12500 = 10294,
    // which is approximately 5 times the maximum fc (2^11 - 1 = 2047),
    // and may be calculated as 5*fc = 4*fc + fc (shift and add).

    // MOS6581 filter cutoff DAC output.
    sid::reg11_t fc_8580;
    sid::reg11_t fc_6581;

    always_comb begin
        // Filter cutoff register value.
        fc_8580 = { freg.fc_hi, freg.fc_lo[2:0] };
    end

    sid_dac #(
        .BITS(11)
    ) fc_dac (
        .vin  (fc_8580),
        .vout (fc_6581)
    );

    // Filter resonance.
    //
    // From die photographs, assuming ideal op-amps:
    //
    // MOS6581: 1/Q =~ ~res/8
    // MOS8580: 1/Q =~ 2^((4 - res)/8)
    //
    // The actual range of 1/Q in the MOS6581 is quite different, partly
    // because of low gain op-amps. For now, we use the formula from reSID 0.16.
    //
    // The values are multiplied by 1024 (1 << 10).
    // The coefficient 1024 is dispensed of later by right-shifting 10 times.
    sid::reg11_t _1_Q_lsl10;
    sid::reg11_t _1_Q_6581_lsl10[16];
    sid::reg11_t _1_Q_8580_lsl10[16];
    initial begin
        for (int res = 0; res < 16; res++) begin
            _1_Q_6581_lsl10[res] = 11'($rtoi(1024.0/(0.707 + res/15.0) + 0.5));
            _1_Q_8580_lsl10[res] = 11'($rtoi(1024.0*$pow(2, (4 - res)/8.0) + 0.5));
        end
    end

    // Hardware 16x16->32 multiply-add:
    // o = c +- (a * b)
    sid::s32_t o;
    sid::s32_t c;
    logic      s;
    sid::s16_t a;
    sid::s16_t b;

    muladd opamp (
        .c (c),
        .s (s),
        .a (a),
        .b (b),
        .o (o)
    );

    // Filter states for two SID chips, updated as follows:
    // vlp = vlp - w0*vbp
    // vbp = vbp - w0*vhp
    // vhp = 1/Q*vbp - vlp - vi
    //
    // (vlp, vbp, vhp) x 2
    sid::s16_t v5 = 0, v4 = 0, v3 = 0, v2 = 0, v1 = 0, v0 = 0;
    sid::s17_t dv;
    sid::s16_t v_next;

    // Simplify by converting cycle number to pipeline stage number.
    `define stage(cycle_1) (cycle == (cycle_1) || cycle == (cycle_1) + 5)
    `define cycle_between(cycle_1, cycle_2) (cycle >= (cycle_1) && cycle <= (cycle_2))
    `define stage_between(cycle_1, cycle_2) (`cycle_between((cycle_1), (cycle_2)) || `cycle_between((cycle_1) + 5, (cycle_2) + 5))

    // Mux and sum for direct audio path and filter input path.
    // Each voice is 22 bits, i.e. the sum of four voices is 24 bits.
    sid::s24_t  vd   = 0;
    sid::s24_t  vi   = 0;
    sid::reg4_t filt = 0;
    sid::s24_t  vd1  = 0;

    always_ff @(posedge clk) begin
        if (`stage(1)) begin
            vd   <= 0;
            vi   <= 0;
            filt <= freg.filt;
        end else if (`stage_between(2, 5)) begin
            // Direct audio path.
            // 3 OFF (mode[3]) disconnects voice 3 from the direct audio path.
            if (~(filt[0] || (freg.mode[3] && `stage(4)))) begin
                vd <= vd + 24'(voice_i);
            end

            // Filter path.
            if (filt[0]) begin
                vi <= vi + 24'(voice_i);
            end

            filt <= filt >> 1;
        end

        if (`stage(6)) begin
            // Buffer input to master volume, adding in mixer DC at the same
            // time.
            vd1 <= vd + ((model == sid::MOS6581) ?
                         MIXER_DC_6581 :
                         MIXER_DC_8580);
        end
    end

    // Mux and sum for filter outputs.
    // Each filter output is 16 bits, i.e. the sum of three outputs is 17.5
    // bits. We assume that filter outputs are out of phase, so that we don't
    // need more than 17 bits.
    sid::s17_t  vf   = 0;
    sid::reg4_t mode = 0;

    // Audio mixers.
    always_ff @(posedge clk) begin
        if (`stage(4)) begin
            vf   <= 0;
            mode <= freg.mode;
        end else if (`stage_between(5, 7)) begin
            if (mode[0]) begin
                vf <= vf + v_next;
            end

            mode <= mode >> 1;
        end
    end

    sid::reg4_t  vol   = 0;
    sid::model_e model = sid::MOS6581;
    sid::s12_t   fc_offset;
    sid::reg11_t fc_x  = 0;

    always_comb begin
        // Filter cutoff offset.
        fc_offset = cfg.fc_offset + FC_OFFSET_6581;

        // Intermediate results for filter.
        // Shifts -w0*vbp and -w0*vlp right by 17.
        dv = 17'(o >>> 17);

        // Next hp or lp/bp.
        v_next = clamp(`stage(7) ? o[10+:17] : 17'(v5) + dv);

        // Final result for audio output, at cycle 9 and 14.
        // The effective width is 20 bits (4 bit volume * 16 bit audio).
        audio_o = o[19:0];
    end

    // Calculation of filter outputs. TDM to use only one multiplier.
    always_ff @(posedge clk) begin
        if (`stage_between(5, 7)) begin
            // (vlp, vbp, vhp) x 2
            { v5, v4, v3, v2, v1, v0 } <= { v4, v3, v2, v1, v0, v_next };
        end

        if (`stage(2)) begin
            // MOS6581: w0 = filter curve
            // 1.048576/8*fc_base is approximated by fc_base >> 3.
            w0_T_lsl17_6581_base <= { 10'b0, cfg.fc_base[8:3] };
            // We have to register fc_x in order to meet timing.
            fc_x <= tanh_x_clamp(signed'(13'(fc_6581)) - fc_offset);

            // MOS8580: w0 = 5*fc = 4*fc + fc
            w0_T_lsl17_8580 <= { 3'b0, fc_8580, 2'b0 } + { 5'b0, fc_8580 };

            // MOS6581: 1/Q =~ ~res/8 (not used - op-amps are not ideal)
            // MOS8580: 1/Q =~ 2^((4 - res)/8)
            _1_Q_lsl10 <= (cfg.model == sid::MOS6581) ?
                          _1_Q_6581_lsl10[freg.res] :
                          _1_Q_8580_lsl10[freg.res];
        end

        if (`stage(3)) begin
            // Read from BRAM.
            w0_T_lsl17_6581 <= w0_T_lsl17_6581_tanh[tanh_x_mirror(fc_x)];

            // Save model and volume for later stages.
            model <= cfg.model;
            vol   <= freg.vol;
        end

        unique0 case (cycle)
          4, 9: begin
              // vlp = vlp - w0*vbp
              // We first calculate -w0*vbp
              c <= 0;
              s <= 1'b1;
              a <= (model == sid::MOS6581) ?
                   w0_T_lsl17_6581_base + w0_T_lsl17_6581_y0 + tanh_y_mirror(fc_x[10], w0_T_lsl17_6581) :
                   w0_T_lsl17_8580;  // w0*T << 17
              b <= v4;               // vbp
          end
          5, 10: begin
              // Result for vlp ready.

              // vbp = vbp - w0*vhp
              // We first calculate -w0*vhp
              // c <= 0;
              // s <= 1'b1;
              // a <= ...
              b <= v3;               // vhp
          end
          6, 11: begin
              // Result for vbp ready.

              // vhp = 1/Q*vbp - vlp - vi
              // c <= -(32'(v0) + (32'(vi) >>> 7)) << 10;
              c <= -(((32'(v0) << 7) + 32'(vi)) << 3);
              s <= 1'b0;
              a <= 16'(_1_Q_lsl10);  // 1/Q << 10
              b <= v_next;           // vbp
          end
          // 7, 12: Result for vhp ready
          8, 13: begin
              // Audio output: aout = vol*amix
              // In the real SID, the signal is inverted first in the mixer
              // op-amp, and then again in the volume control op-amp.
              c <= 0;
              // s <= 1'b0;
              a <= { 12'b0, vol };         // Master volume
              b <= clamp(17'(vd1 >>> 7) +  // Audio mixer / master volume input
                         vf);
          end
        endcase
    end

`ifdef VM_TRACE
    // Latch states for simulation.
    /* verilator lint_off UNUSED */
    typedef struct packed {
        sid::s24_t   vd;
        sid::s24_t   vi;
        sid::s16_t   w0_T;
        sid::reg11_t _1_Q;
        sid::s16_t   vhp;
        sid::s16_t   vbp;
        sid::s16_t   vlp;
        sid::s17_t   vf;
        sid::s20_t   vo;
    } sim_t;

    sim_t sim[2];

    always_ff @(posedge clk) begin
        if (`stage(6)) begin
            sim[cycle > 6].vd   <= vd;
            sim[cycle > 6].vi   <= vi;
            sim[cycle > 6].w0_T <= a;
            sim[cycle > 6]._1_Q <= _1_Q_lsl10;
        end

        if (`stage(8)) begin
            sim[cycle > 8].vf  <= vf;
            sim[cycle > 8].vhp <= v0;
            sim[cycle > 8].vbp <= v1;
            sim[cycle > 8].vlp <= v2;
        end

        if (`stage(9)) begin
            sim[cycle > 9].vo <= audio_o;
        end
    end
    /* verilator lint_on UNUSED */
`endif
endmodule

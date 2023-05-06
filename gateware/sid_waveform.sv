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

`include "sid_waveform_PST.svh"
`include "sid_waveform__ST.svh"

module sid_waveform #(
    // Even bits are high on powerup, and there is no reset.
    localparam OSC_INIT       = { 12{2'b01} },
    // Time for noise LFSR to be filled with 1 bits when reset or test is held.
    localparam NOISE_TTL_6581 = 14'd33,   // ~30ms
    localparam NOISE_TTL_8580 = 14'd9765, // ~10s
    // Time for waveform 0 to fade out.
    localparam WF_0_TTL_6581  = 13'd200,  // ~200ms
    localparam WF_0_TTL_8580  = 13'd5000  // ~5s
)(
    input  logic          clk,
    input  logic          tick_ms,
    input  sid::cycle_t   cycle,
    input  logic          res,
    input  logic[1:0]     model,
    input  sid::freq_pw_t freq_pw_1,
    input  sid::control_t control_3,
    input  sid::control_t control_4,
    input  sid::control_t control_5,
    input logic [2:0]     test,
    input logic [2:0]     sync,
    output sid::reg12_t   wav
);

    // Initialization flag.
    logic primed = 0;

    // ------------------------------------------------------------------------
    // Oscillators
    // ------------------------------------------------------------------------
    // Phase-accumulating oscillators. Two extra pipeline stages for synchronization.
    sid::reg24_t o7 = 0, o6 = 0, o5 = 0, o4 = 0, o3 = 0, o2 = 0, o1 = 0, o0 = 0;
    sid::reg24_t osc_next;
    // Inter-oscillator synchronization.
    logic        o7_msb_up;
    logic        o0_msb_up = 0, o1_msb_up = 0;
    logic        o7_synced, o0_synced, o1_synced;
    logic        o7_reset,  o0_reset,  o1_reset;
    // Latched signals for noise and pulse.
    logic [7:0]  osc19_prev    = '0;
    logic [7:0]  osc19_prev_up = '0;
    logic [7:0]  pulse         = '0;
    logic        pulse_next;

    always_comb begin
        // Constant value / ripple carry add can in theory be combined in single iCE40 LCs.
        osc_next  = primed ? o7 + { 8'b0, freq_pw_1.freq_hi, freq_pw_1.freq_lo } : OSC_INIT;
        o7_msb_up = ~o7[23] & osc_next[23];

        // A sync source will normally sync its destination when the MSB of the
        // sync source rises. However if the sync source is itself synced on the
        // same cycle, its MSB is zeroed, and the destination will not be synced.
        // In the real SID, the sync dependencies form a circular combinational
        // circuit, which takes the form of a ring oscillator when all three
        // oscillators are synced on the same cycle. Here, like in reSID, no
        // oscillator will be synced in this special case of the special case.
        //
        // We sync all oscillators as soon as possible, in order to get
        // correct msbs for ring modulation.
        //
        // At cycle 4 and 7 (SID 1 / SID 2):
        // voice 1 osc = o1
        // voice 2 osc = o0
        // voice 3 osc = o7
        //
        //  ---------<----------      ---------<----------
        // |                    | =  |                    |
        //  -> v1 -> v2 -> v3 ->      -> o1 -> o0 -> o7 ->
        //
        o7_synced = test[0] || (sync[0] && o0_msb_up);
        o0_synced = test[1] || (sync[1] && o1_msb_up);
        o1_synced = test[2] || (sync[2] && o7_msb_up);

        o7_reset = test[0] || (sync[0] && o0_msb_up && !o0_synced);
        o0_reset = test[1] || (sync[1] && o1_msb_up && !o1_synced);
        o1_reset = test[2] || (sync[2] && o7_msb_up && !o7_synced);

        // The pulse width comparison is done at phi2, before the oscillator
        // is updated at phi1. Thus the pulse waveform is delayed by one cycle
        // with respect to the oscillator.
        pulse_next = (o7[23-:12] >= { freq_pw_1.pw_hi[3:0], freq_pw_1.pw_lo }) | test[0];
    end

    always_ff @(posedge clk) begin
        if (cycle >= 2 && cycle <= 9) begin
            // Update oscillators.
            // In the real SID, an intermediate sum is latched by phi2, and this
            // sum is simultaneously synced, output to waveform generation bits,
            // and written back to osc on phi1.
            { o7, o6, o5, o4, o3, o2, o1, o0 } <= { o6, o5, o4, o3, o2, o1, o0, osc_next };
            { o1_msb_up, o0_msb_up } <= { o0_msb_up, o7_msb_up };

            // Save previous rise of OSC bit 19 for generation of the noise waveform.
            // OSC bit 19 is read before the update of OSC at phi1, i.e.
            // it's delayed by one cycle.
            osc19_prev    <= { osc19_prev[6:0], o7[19] };
            osc19_prev_up <= { osc19_prev_up[6:0], ~osc19_prev[7] & o7[19] };

            // Pulse.
            pulse <= { pulse[6:0], pulse_next };

            if (cycle == 4 || cycle == 7) begin
                // Reset of oscillators by test bit or synchronization.
                if (o7_reset) begin
                    o0 <= 0;
                end

                if (o0_reset) begin
                    o1 <= 0;
                end

                if (o1_reset) begin
                    o2 <= 0;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Waveform generators
    // ------------------------------------------------------------------------
    // Keep track of the current SID model.
    logic model_5 = 0, model_4 = 0, model_3;

    always_comb begin
        model_3 = model[cycle >= 7];
    end

    always_ff @(posedge clk) begin
        if (cycle >= 4 && cycle <= 10) begin
            { model_5, model_4 } <= { model_4, model_3 };
        end
    end

    // Pulse is generated earlier.

    // Noise.
    typedef struct packed {
        sid::reg23_t lfsr;
        logic [13:0] age;
        logic        nres_prev;
        logic        nclk_prev;
    } noise_t;

    noise_t     n5 = '0, n4 = '0, n3 = '0, n2 = '0, n1 = '0, n0 = '0;
    logic       nres;
    logic       nclk;
    logic       nset;
    sid::reg8_t noise;

    // Noise.
    always_comb begin
        // Noise LFSR reset and clock.
        nres = res | control_3.test;
        nclk = ~(nres | osc19_prev_up[1]);
        nset = (n5.age == ((model_3 == sid::MOS6581) ?
                           NOISE_TTL_6581 :
                           NOISE_TTL_8580));

        noise = { n0.lfsr[20], n0.lfsr[18], n0.lfsr[14],
                  n0.lfsr[11], n0.lfsr[9], n0.lfsr[5], n0.lfsr[2], n0.lfsr[0] };
    end

    always_ff @(posedge clk) begin
        if (cycle >= 4 && cycle <= 9) begin
            // The noise LFSR stays at 'h7ffffe after reset (clocked on reset release).
            // FIXME: Check whether this is also true for the MOS8580.
            // n0 is updated below.
            { n5, n4, n3, n2, n1, n0 } <= { n4, n3, n2, n1, n0, n5 };

            n0.nres_prev <= nres;
            n0.nclk_prev <= nclk;

            if (~nclk || !primed) begin
                // LFSR shift phase 1.
                if (nset || !primed) begin
                    // Reset LFSR.
                    n0.lfsr <= '1;
                end else begin
                    n0.age <= n5.age + { 13'b0, tick_ms };
                end
            end else begin
                n0.age <= 0;

                // The noise LFSR is clocked after OSC bit 19 goes high, or when
                // reset or test is released.
                if (~n5.nclk_prev & nclk) begin
                    // LFSR shift phase 2.
                    // Completion of the shift is delayed by 2 cycles after OSC
                    // bit 19 goes high.
                    n0.lfsr <= { n5.lfsr[21:0], (n5.nres_prev | n5.lfsr[22]) ^ n5.lfsr[17] };
                end else if (control_3.noise & (control_3.pulse | control_3.sawtooth | control_3.triangle)) begin
                    // Writeback to LFSR from combined waveforms when nclk = 1.
                    // FIXME: This should AND in actual bit values, which are
                    // first calculated after waveform selection below. For now,
                    // we assume that combined waveforms are used to write zeros
                    // to the LFSR.
                    // { n0.lfsr[20], n0.lfsr[18], n0.lfsr[14],
                    //   n0.lfsr[11], n0.lfsr[9], n0.lfsr[5], n0.lfsr[2], n0.lfsr[0] } <= '0;
                    n0.lfsr <= { n5.lfsr[22:21], 1'b0, n5.lfsr[19], 1'b0, n5.lfsr[17:15], 1'b0, n5.lfsr[13:12],
                                 1'b0, n5.lfsr[10], 1'b0, n5.lfsr[8:6], 1'b0, n5.lfsr[4:3], 1'b0, n5.lfsr[1], 1'b0 };
                end
            end
        end
    end

    // Sawtooth / triangle.
    sid::reg12_t st5 = 0, st4 = 0, st3 = 0, st2 = 0, st0 = 0, st1 = 0;
    logic        o2_msb_i;  // For ring modulation.
    logic        o2_tri_xor;
    sid::reg12_t saw_tri_next;
    sid::reg12_t saw_tri;

    always_comb begin
        // The sawtooth and triangle waveforms are constructed from the
        // upper 12 bits of the oscillator. When sawtooth is not selected,
        // and the MSB is high, the lower 11 of these 12 bits are
        // inverted. When triangle is selected, the lower 11 bits are
        // shifted up to produce the final output. The MSB may be modulated
        // by the preceding oscillator for ring modulation.
        o2_msb_i   = (cycle == 5 || cycle == 8) ? o0[23] : o3[23];
        o2_tri_xor = ~control_4.sawtooth & ((control_4.ring_mod & ~o2_msb_i) ^ o2[23]);

        // In the 8580, sawtooth / triangle is latched by phi2, and is thus
        // delayed by one SID cycle.
        saw_tri_next = { o2[23], o2[22:12] ^ { 11{o2_tri_xor} } };
        saw_tri      = (model_4 == sid::MOS6581) ? saw_tri_next : st5;
    end

    always_ff @(posedge clk) begin
        if (cycle >= 5 && cycle <= 10) begin
            { st5, st4, st3, st2, st1, st0 } <= { st4, st3, st2, st1, st0, saw_tri_next };
        end
    end

    // Power-on initialization.
    always_ff @(posedge clk) begin
        if (cycle == 10 && !primed) begin
            // All oscillators and noise LFSRs are initialized.
            primed <= 1;
        end
    end

    // ------------------------------------------------------------------------
    // Waveform selectors
    // ------------------------------------------------------------------------
    sid::reg4_t  waveform_4, waveform_5;

    // Pre-calculated waveforms for waveform selection.
    sid::reg12_t norm     = 0;  // Selected regular waveform
    sid::reg12_t norm_next;
    sid::reg8_t  pst      = 0;  // Combined waveforms
    sid::reg8_t  ps__6581 = 0;
    sid::reg8_t  ps__8580 = 0;
    sid::reg8_t  p_t_6581 = 0;
    sid::reg8_t  p_t_8580 = 0;
    sid::reg8_t  _st      = 0;

    // Waveform 0 value and age.
    // FIXME: Yosys doesn't support multidimensional packed arrays outside
    // of structs, nor arrays of structs.
    typedef struct packed {
        logic [5:0][11:0] value;
        logic [5:0][12:0] age;
    } waveform_0_t;

    // (* nowrshmsk *)
    waveform_0_t waveform_0 = '0;
    logic        waveform_0_faded;
    logic        waveform_0_tick;

    // Combined waveform lookup tables.
    sid::reg8_t sid_waveform_PS__6581[2048];
    sid::reg8_t sid_waveform_PS__8580[4096];
    sid::reg8_t sid_waveform_P_T_6581[2048];
    sid::reg8_t sid_waveform_P_T_8580[2048];

    always_comb begin
        // With respect to the oscillator, the waveform cycle delays are:
        // * saw_tri: 0 (6581) / 1 (8580)
        // * pulse:   1
        // * noise:   2

        waveform_4 = { control_4.noise, control_4.pulse, control_4.sawtooth, control_4.triangle };

        // All combined waveforms which include noise output zero after a few
        // cycles.
        unique case (waveform_4)
          'b1000:  norm_next = { noise, 4'b0 };
          'b0100:  norm_next = { 12{pulse[2]} };
          'b0010:  norm_next = saw_tri;
          'b0001:  norm_next = { saw_tri[10:0], 1'b0 };
          default: norm_next = 0;
        endcase
    end

    always_ff @(posedge clk) begin
        if (cycle >= 5 && cycle <= 10) begin
            // Regular waveforms.
            norm     <= norm_next;

            // Combined waveform candidates from BRAM and combinational logic.
            pst      <= sid_waveform_PST(model_4, saw_tri);
            ps__6581 <= sid_waveform_PS__6581[saw_tri[10:0]];
            ps__8580 <= sid_waveform_PS__8580[saw_tri];
            p_t_6581 <= sid_waveform_P_T_6581[saw_tri[10:0]];
            p_t_8580 <= sid_waveform_P_T_8580[saw_tri[10:0]];
            _st      <= sid_waveform__ST(model_4, saw_tri);
        end
    end

    always_comb begin
        waveform_5 = { control_5.noise, control_5.pulse, control_5.sawtooth, control_5.triangle };

        // Final waveform selection on cycle 2.
        // All inputs to the combinational logic are from cycle 1.
        unique case (waveform_5)
          'b0111:  wav = { pst & { 8{pulse[3]} }, 4'b0 };
          'b0110:  wav = { ((model_5 == sid::MOS6581) ? ps__6581 : ps__8580) & { 8{pulse[3]} }, 4'b0 };
          'b0101:  wav = { ((model_5 == sid::MOS6581) ? p_t_6581 : p_t_8580) & { 8{pulse[3]} }, 4'b0 };
          'b0011:  wav = { _st, 4'b0 };
          'b0000:  wav = waveform_0.value[5];
          default: wav = norm;
        endcase

        // Update of waveform 0 for next cycle.
        waveform_0_faded = (waveform_0.age[5] == ((model_5 == sid::MOS6581) ?
                                                   WF_0_TTL_6581 :
                                                   WF_0_TTL_8580));
        waveform_0_tick  = waveform_0_faded ? 0 : tick_ms;
    end

    always_ff @(posedge clk) begin
        if (cycle >= 6 && cycle <= 11) begin
            // Update of waveform 0.
            // .value[0] and .age[0] are updated below.
            { waveform_0.value[5:1] } <= { waveform_0.value[4:0] };
            { waveform_0.age[5:1]   } <= { waveform_0.age[4:0]   };

            if (waveform_5 == 'b0000) begin
                if (waveform_0_faded) begin
                    waveform_0.value[0] <= 0;
                end else begin
                    waveform_0.value[0] <= waveform_0.value[5];
                end
                waveform_0.age[0] <= waveform_0.age[5] + { 12'b0, waveform_0_tick };
            end else begin
                waveform_0.value[0] <= wav;
                waveform_0.age[0]   <= 0;
            end
        end
    end

    // od -An -tx1 -v reSID/src/wave6581_PS_.dat | head -128 | cut -b2- > sid_waveform_PS__6581.hex
    // od -An -tx1 -v reSID/src/wave8580_PS_.dat |             cut -b2- > sid_waveform_PS__8580.hex
    // od -An -tx1 -v reSID/src/wave6581_P_T.dat | head -128 | cut -b2- > sid_waveform_P_T_6581.hex
    // od -An -tx1 -v reSID/src/wave8580_P_T.dat | head -128 | cut -b2- > sid_waveform_P_T_8580.hex
    initial begin
        $readmemh("sid_waveform_PS__6581.hex", sid_waveform_PS__6581);
        $readmemh("sid_waveform_PS__8580.hex", sid_waveform_PS__8580);
        $readmemh("sid_waveform_P_T_6581.hex", sid_waveform_P_T_6581);
        $readmemh("sid_waveform_P_T_8580.hex", sid_waveform_P_T_8580);
    end

`ifdef VM_TRACE
    // Latch voices for simulation.
    /* verilator lint_off UNUSED */
    typedef struct packed {
        sid::reg24_t osc;
        sid::reg12_t saw_tri;
        logic [1:0]  pulse;  // Duplicate bits for analog display in GTKWave
        sid::reg8_t  noise;
        sid::reg12_t wav;
    } sim_t;

    sim_t sim[6];

    always_ff @(posedge clk) begin
        if (cycle >= 5 && cycle <= 10) begin
            sim[cycle - 5].osc     <= o2;
            sim[cycle - 5].saw_tri <= saw_tri;
            sim[cycle - 5].pulse   <= { 2{pulse[2]} };
            sim[cycle - 5].noise   <= noise;
        end

        if (cycle >= 6 && cycle <= 11) begin
            sim[cycle - 6].wav <= wav;
        end
    end
    /* verilator lint_on UNUSED */
`endif
endmodule

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
    input  sid::control_t control_4,
    input logic [2:0]     test,
    input logic [2:0]     sync,
    output sid::reg12_t   wav
);

    // Initialization flag.
    logic primed = 0;

    // Cycles beyond the 4 bit cycle counter.
    logic cycle_16 = 0;
    logic cycle_17 = 0;

    // Keep track of the current SID model for cycles 5 - 10 and 6 - 11.
    logic model_4;
    logic model_5 = 0;

    // Waveform selector for cycle 6 - 11.
    sid::reg4_t waveform_5 = 0;

    always_comb begin
        model_4 = model[~(cycle >= 5 && cycle <= 7 || cycle >= 11 && cycle <= 13)];
    end

    always_ff @(posedge clk) begin
        if (cycle >= 5 || cycle_16) begin
            cycle_16 <= cycle == 15;
            cycle_17 <= cycle_16;

            model_5    <= model_4;
            waveform_5 <= { control_4.noise, control_4.pulse, control_4.sawtooth, control_4.triangle };
        end
    end

    // ------------------------------------------------------------------------
    // Oscillators
    // ------------------------------------------------------------------------
    // Phase-accumulating oscillators.
    sid::reg24_t o5 = 0, o4 = 0, o3 = 0, o2 = 0, o1 = 0, o0 = 0;
    sid::reg24_t osc_next;
    // Inter-oscillator synchronization.
    logic        o5_msb_up;
    logic        o0_msb_up = 0, o1_msb_up = 0;
    logic        o5_synced, o0_synced, o1_synced;
    logic        o5_reset,  o0_reset,  o1_reset;
    // Latched signals for noise and pulse.
    logic [5:0]  osc19_prev    = '0;
    logic [5:0]  osc19_prev_up = '0;
    logic [5:0]  pulse         = '0;
    logic [5:0]  pulse_prev    = '0;
    logic        pulse_next;

    always_comb begin
        // Constant value / ripple carry add can in theory be combined in single iCE40 LCs.
        osc_next  = primed ? o5 + { 8'b0, freq_pw_1.freq_hi, freq_pw_1.freq_lo } : OSC_INIT;
        o5_msb_up = ~o5[23] & osc_next[23];

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
        // voice 3 osc = o5
        //
        //  ---------<----------      ---------<----------
        // |                    | =  |                    |
        //  -> v1 -> v2 -> v3 ->      -> o1 -> o0 -> o5 ->
        //
        o5_synced = test[0] || (sync[0] && o0_msb_up);
        o0_synced = test[1] || (sync[1] && o1_msb_up);
        o1_synced = test[2] || (sync[2] && o5_msb_up);

        o5_reset = test[0] || (sync[0] && o0_msb_up && !o0_synced);
        o0_reset = test[1] || (sync[1] && o1_msb_up && !o1_synced);
        o1_reset = test[2] || (sync[2] && o5_msb_up && !o5_synced);

        // The pulse width comparison is done at phi2, before the oscillator
        // is updated at phi1. Thus the pulse waveform is delayed by one cycle
        // with respect to the oscillator.
        pulse_next = (o5[23-:12] >= { freq_pw_1.pw_hi[3:0], freq_pw_1.pw_lo }) | test[0];
    end

    always_ff @(posedge clk) begin
        // Rotation on cycles 2 - 7 for update of oscillators.
        // Rotation on six additional cycles for oscillator synchronization and
        // writeback of the oscillator MSB, and to keep other processes in sync.
        if (cycle >= 2 && cycle <= 13) begin
            { o5, o4, o3, o2, o1, o0 } <= { o4, o3, o2, o1, o0, o5 };

            osc19_prev    <= { osc19_prev[4:0],    osc19_prev[5] };
            osc19_prev_up <= { osc19_prev_up[4:0], osc19_prev_up[5] };
            pulse         <= { pulse[4:0],         pulse[5] };
            pulse_prev    <= { pulse_prev[4:0],    pulse_prev[5] };

            if (cycle >= 2 && cycle <= 7) begin
                // Update oscillators.
                // In the real SID, an intermediate sum is latched by phi2, and this
                // sum is simultaneously synced, output to waveform generation bits,
                // and written back to osc on phi1.
                o0 <= osc_next;
                { o1_msb_up, o0_msb_up } <= { o0_msb_up, o5_msb_up };

                // Save previous rise of OSC bit 19 for generation of the noise waveform.
                // OSC bit 19 is read before the update of OSC at phi1, i.e.
                // it's delayed by one cycle.
                osc19_prev[0]    <= o5[19];
                osc19_prev_up[0] <= ~osc19_prev[5] & o5[19];

                // Pulse.
                pulse[0]      <= pulse_next;
                pulse_prev[0] <= pulse[5];
            end

            if (cycle == 4 || cycle == 7) begin
                // Reset of oscillators by test bit or synchronization.
                if (o5_reset) begin
                    o0 <= 0;
                end

                if (o0_reset) begin
                    o1 <= 0;
                end

                if (o1_reset) begin
                    o2 <= 0;
                end
            end

            if (cycle >= 6 && cycle <= 11) begin
                // Writeback to next cycle add for the 6581 oscillator MSB via
                // the sawtooth waveform selector.
                if (model_5 == sid::MOS6581 && waveform_5[1]) begin
                    o4[23] <= wav[11];
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Waveform generators
    // ------------------------------------------------------------------------

    // Waveform selector and waveform output from the previous cycle, with
    // aging for waveform 0.
    // FIXME: Yosys doesn't support multidimensional packed arrays outside
    // of structs, nor arrays of structs.
    typedef struct packed {
        logic [5:0][ 3:0] waveform;
        logic [5:0][11:0] wav;
        logic [5:0][12:0] age;
    } wav_prev_t;

    wav_prev_t wav_prev = '0;
    logic      wav_prev_faded;

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
    logic       nclk_prev = 0;
    logic       nset;
    sid::reg8_t noise;
    sid::reg8_t noise_lsl;
    sid::reg8_t noise_lsl_writeback;

    // Noise.
    always_comb begin
        // Noise LFSR reset and clock.
        nres = res | control_4.test;
        nclk = ~(nres | osc19_prev_up[2]);
        nset = (n5.age == ((model_4 == sid::MOS6581) ?
                           NOISE_TTL_6581 :
                           NOISE_TTL_8580));

        // Noise bits are taken out from the noise LFSR.
        noise     = { n0.lfsr[20], n0.lfsr[18], n0.lfsr[14], n0.lfsr[11],
                      n0.lfsr[9], n0.lfsr[5], n0.lfsr[2], n0.lfsr[0] };
        noise_lsl = { n0.lfsr[21], n0.lfsr[19], n0.lfsr[15], n0.lfsr[12],
                      n0.lfsr[10], n0.lfsr[6], n0.lfsr[3], n0.lfsr[1] };
    end

    always_ff @(posedge clk) begin
        // Rotation on cycles 5 - 10 for update of the noise LFSR.
        // Rotation on six additional cycles for writeback from combined
        // waveforms.
        if (cycle >= 5 || cycle_16) begin
            { n5, n4, n3, n2, n1, n0 } <= { n4, n3, n2, n1, n0, n5 };

            if (cycle >= 5 && cycle <= 10) begin
                // The noise LFSR is clocked after OSC bit 19 goes high, or when
                // reset or test is released.
                // The LFSR stays at 'h7ffffe after reset (clocked on reset release).
                n0.nres_prev <= nres;
                n0.nclk_prev <= nclk;
                nclk_prev    <= n5.nclk_prev;

                if (~nclk || !primed) begin
                    // LFSR shift phase 1.
                    if (nset || !primed) begin
                        // Reset LFSR.
                        // Note that the test bit in combination with combined
                        // waveforms should probably yield a different result, since
                        // zero bits can enter the LFSR.
                        n0.lfsr <= '1;
                    end else begin
                        n0.age <= n5.age + { 13'b0, tick_ms };
                    end
                end else begin
                    n0.age <= 0;

                    if (~n5.nclk_prev & nclk) begin
                        // LFSR shift phase 2.
                        // Completion of the shift is delayed by 2 cycles after OSC
                        // bit 19 goes high.
                        n0.lfsr <= { n5.lfsr[21:0], (n5.nres_prev | n5.lfsr[22]) ^ n5.lfsr[17] };
                    end
                end
            end

            // Writeback to noise LFSR from combined waveforms.
            if (cycle >= 6 && cycle <= 11) begin
                if (n0.nclk_prev) begin
                    // Shift phase != 1 - writeback to current bits.
                    if (waveform_5 > 'h8) begin
                        { n1.lfsr[20], n1.lfsr[18], n1.lfsr[14], n1.lfsr[11],
                          n1.lfsr[9], n1.lfsr[5], n1.lfsr[2], n1.lfsr[0] } <=
                        wav[11-:8];
                    end

                    // Shift phase 1 -> 2: Writeback to shifted bits.
                    // The transition from shift phase 1 to phase 2 coincides
                    // with the transition of waveforms and waveform selectors
                    // at the rising edge of phi1. This implies that in theory,
                    // both the previous and current waveforms and waveform
                    // selectors can influence the result. The 8580 sawtooth
                    // and triangle waveforms are special since they are
                    // latched by phi2 at the end of the previous cycle,
                    // i.e. the 8580 sawtooth and triangle waveforms are
                    // constant during the transition. The sawtooth and
                    // triangle waveform selectors can always transition,
                    // however.
                    // FIXME: The check for the pulse waveform is adapted from
                    // VICE in order to pass more tests, and should probably be
                    // replaced with a generic model for bit zeroing (see other
                    // FIXME below).
                    if (~nclk_prev &&
                        wav_prev.waveform[5] > 'h8 &&     // Combined waveforms in the previous cycle.
                        !(wav_prev.waveform[5] == 'hc &&  // Not only noise + pulse high in the
                          pulse_prev[3]) &&               // previous cycle.
                        waveform_5 > 'h8)                 // Combined waveforms in the current cycle.
                    begin
                        { n1.lfsr[21], n1.lfsr[19], n1.lfsr[15], n1.lfsr[12],
                          n1.lfsr[10], n1.lfsr[6], n1.lfsr[3], n1.lfsr[1] } <=
                        noise_lsl_writeback;
                    end
                end
            end
        end
    end

    // Pulse is generated earlier.

    // Sawtooth / triangle.
    sid::reg12_t st5 = 0, st4 = 0, st3 = 0, st2 = 0, st0 = 0, st1 = 0;
    logic        o2_msb_i;  // For ring modulation.
    logic        o2_tri_xor;
    sid::reg12_t saw_tri_next;
    sid::reg12_t saw_tri;
    sid::reg12_t saw_tri_5 = 0;

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
        // Rotation on cycles 5 - 10 for update of 8580 sawtooth / triangle.
        // Freewheeling rotation on six additional cycles for final mix-in of
        // 8580 sawtooth / triangle at phi2.
        if (cycle >= 5 || cycle_16) begin
            { st5, st4, st3, st2, st1, st0 } <= { st4, st3, st2, st1, st0, st5 };

            if (cycle >= 5 && cycle <= 10) begin
                st0 <= saw_tri_next;
            end
        end
    end

    // Power-on initialization.
    always_ff @(posedge clk) begin
        if (cycle == 11 && !primed) begin
            // All oscillators and noise LFSRs are initialized.
            primed <= 1;
        end
    end

    // ------------------------------------------------------------------------
    // Waveforms
    // ------------------------------------------------------------------------

    // With respect to the oscillator, the OSC3 cycle delays are:
    // * noise:   2
    // * pulse:   1
    // * saw_tri: 0 (6581) / 1 (8580)

    // Pre-calculated waveforms for waveform selection.
    sid::reg8_t pst      = 0;  // Combined waveforms
    sid::reg8_t ps__6581 = 0;
    sid::reg8_t ps__8580 = 0;
    sid::reg8_t p_t_6581 = 0;
    sid::reg8_t p_t_8580 = 0;
    sid::reg8_t _st      = 0;

    // Combined waveform lookup tables.
    sid::reg8_t sid_waveform_PS__6581[4096];
    sid::reg8_t sid_waveform_PS__8580[4096];
    sid::reg8_t sid_waveform_P_T_6581[2048];
    sid::reg8_t sid_waveform_P_T_8580[2048];

    always_ff @(posedge clk) begin
        // Cycles 5 - 10 for OSC3 and audio output. Cycles 11 - 16 for final
        // mix-in of 8580 sawtooth / triangle, used in 8580 noise LFSR
        // writeback and 8580 waveform 0 output in the next SID cycle.
        if (cycle >= 5 || cycle_16) begin
            // Waveform candidates: Combined waveforms from BRAM and
            // combinational logic, plus sawtooth / triangle.
            // Noise and pulse are mixed in below.
            pst       <= sid_waveform_PST(model_4, saw_tri);
            ps__6581  <= sid_waveform_PS__6581[saw_tri];
            ps__8580  <= sid_waveform_PS__8580[saw_tri];
            p_t_6581  <= sid_waveform_P_T_6581[saw_tri[10:0]];
            p_t_8580  <= sid_waveform_P_T_8580[saw_tri[10:0]];
            _st       <= sid_waveform__ST(model_4, saw_tri);
            saw_tri_5 <= saw_tri;
        end
    end

    sid::reg8_t noise_mask;
    sid::reg8_t noise_lsl_mask;

    always_comb begin
        // Final waveform selection / mixing, excluding noise.
        unique case (waveform_5[2:0])
          'b111: wav = { pst & { 8{pulse[3]} }, 4'b0 };
          'b110: wav = { ((model_5 == sid::MOS6581) ? ps__6581 : ps__8580) & { 8{pulse[3]} }, 4'b0 };
          'b101: wav = { ((model_5 == sid::MOS6581) ? p_t_6581 : p_t_8580) & { 8{pulse[3]} }, 4'b0 };
          'b100: wav = { 12{pulse[3]} };
          'b011: wav = { _st, 4'b0 };
          'b010: wav = saw_tri_5;
          'b001: wav = { saw_tri_5[10:0], 1'b0 };
          'b000: wav = wav_prev.wav[5];  // Waveform 0
        endcase

        // Zero noise outputs always zero the corresponding waveform bits, and
        // can also zero neighboring bits when pulse is selected.
        // FIXME: All combinations of noise and waveforms should be
        // investigated for bit zeroing. For now, we adapt the 8580 pulse bit
        // mask from VICE.
        // We perform writeback to both shifted and current bits after any LFSR
        // shift, in order to avoid a further delay of the waveform
        // output. Note note that in theory, the zeroing of bits may be
        // different for shifted (latched) and current (SRAM) bits.
        if (waveform_5[2]) begin
            // The four lowermost bits of the noise waveform are grounded, and
            // always pull the neighboring two bits down via the pulse line.
            noise_mask     = (noise < 'hfc) ? { noise[7:1] & noise[6:0], 1'b0 } : 'hfc;
            noise_lsl_mask = (noise_lsl < 'hfc) ? { noise_lsl[7:1] & noise_lsl[6:0], 1'b0 } : 'hfc;
        end else begin
            // Pulse not selected.
            noise_mask     = noise;
            noise_lsl_mask = noise_lsl;
        end

        // Noise LFSR writeback to shifted bits at shift phase 1 -> 2.
        // We assume that the corresponding previous and current waveform bits
        // must both be zero for a latched noise bit to be pulled down.
        noise_lsl_writeback =
            (wav_prev.wav[5][11-:8] | (wav[11-:8] & noise_lsl_mask));

        // Mix in noise.
        if (waveform_5[3]) begin
            if (waveform_5[2:0] == '0) begin
                // Only noise is selected.
                wav = { noise, 4'b0 };
            end else begin
                // Noise outputs can zero waveform output bits. The result is
                // also written back to noise LFSR bits at shift phase != 1.
                wav = { wav[11-:8] & noise_mask, 4'b0 };
            end
        end

        // Update of waveform 0 for next cycle.
        wav_prev_faded = (wav_prev.age[5] == ((model_5 == sid::MOS6581) ?
                                              WF_0_TTL_6581 :
                                              WF_0_TTL_8580));
    end

    always_ff @(posedge clk) begin
        // Update of previous waveform selector and waveform output, for
        // noise writeback and waveform 0 output.
        if (cycle >= 6 || cycle_16 || cycle_17) begin
            wav_prev.waveform <= { wav_prev.waveform[4:0], waveform_5 };
            wav_prev.wav      <= { wav_prev.wav[4:0], wav_prev.wav[5] };
            wav_prev.age      <= { wav_prev.age[4:0], wav_prev.age[5] };

            // The 6581 waveform is ready at phi1, while the final mix-in of 8580
            // sawtooth / triangle is not done until phi2.
            if (model_5 == sid::MOS6581 && cycle >= 6 && cycle <= 11 ||
                model_5 == sid::MOS8580 && (cycle >= 12 || cycle_16 || cycle_17))
            begin
                if (waveform_5 == '0) begin
                    if (wav_prev_faded) begin
                        wav_prev.wav[0] <= 0;
                    end else begin
                        wav_prev.age[0] <= wav_prev.age[5] + { 12'b0, tick_ms };
                    end
                end else begin
                    wav_prev.wav[0] <= wav;
                    wav_prev.age[0] <= 0;
                end
            end
        end
    end

    // od -An -tx1 -v reSID/src/wave6581_PS_.dat |             cut -b2- > sid_waveform_PS__6581.hex
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

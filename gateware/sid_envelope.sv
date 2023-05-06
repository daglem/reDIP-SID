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

module sid_envelope #(
    // Default to no init, since the counter will reach 0 after a maximum of
    // one exponential release cycle (at release = 0) after reset release.
    localparam INIT_ENV = 0,
    localparam ENV_INIT = INIT_ENV ? { 4{2'b10} } : 'hFF
)(
    input  logic               clk,
    input  sid::cycle_t        cycle,
    input  logic               res,
    input  sid::envelope_reg_t ereg_5,
    output sid::reg8_t         env
);

    // Initialization flag.
    logic primed = 0;

    // 8-bit envelope counter.
    // Odd bits are high on powerup. There is no immediate reset, however
    // env_cnt_en, rate_cnt_res, and exp_cnt_res are all set by reset.
    // This implies that, on the face of it, the counter will start out at
    // ~AA = 55, and will then count down in the release state while in reset,
    // wrapping around to FF each time 00 is reached. After reset release, the
    // counter will continue counting down until it finally reaches zero.
    // Note that the counter itself is FF at env=00, due to inversion in decay.
    typedef struct packed {
        sid::reg8_t  env_cnt;
        logic        prev_FF;
        logic        prev_00;
        logic        prev_gate;
        logic        attack;
        logic        sustain;
        sid::reg4_t  adr;
        logic        env_cnt_en;
        logic        env_cnt_up;
        logic        prev_env_cnt_up;
        logic        env_cnt_inv;
        // 15-bit rate counter.
        sid::reg15_t rate_cnt;
        logic        prev_rate_cnt_res;
        // 5-bit exponential decay counter.
        sid::reg5_t  exp_seg;
        sid::reg5_t  exp_cnt;
    } envelope_t;

    envelope_t e5 = '0, e4 = '0, e3 = '0, e2 = '0, e1 = '0, e0 = '0;

    logic        rise_gate;
    logic        rise_FF;
    logic        rise_00;
    sid::reg7_t  exp_step;
    logic        rate_cnt_res;
    logic        exp_cnt_res;

    always_comb begin
        // The counter output bits are inverted when the counter counts down.
        // In the real SID, the final result is latched by phi2. To save
        // storage, we instead invert the previous counter bits on the fly.
        // FIXME: The XOR with primed only works for INIT_ENV = 0.
        env = e5.env_cnt ^ { 8{~e5.prev_env_cnt_up ^ ~primed} };

        // Exponential decay curve segment steps.
        exp_step = {
            env == 8'h00,
            env == 8'h06,
            env == 8'h0E,
            env == 8'h1A,
            env == 8'h36,
            env == 8'h5D,
            env == 8'hFF
        };

        rise_gate = ~e5.prev_gate & ereg_5.gate;
        rise_FF   = ~e5.prev_FF & exp_step[0];
        rise_00   = ~e5.prev_00 & exp_step[6];

`ifndef RIPPLE_COUNTERS
        // Envelope rate counter reset / count.
        rate_cnt_res =
                      (e5.adr == 'h0 && e5.rate_cnt == 'h7f00) ||
                      (e5.adr == 'h1 && e5.rate_cnt == 'h0006) ||
                      (e5.adr == 'h2 && e5.rate_cnt == 'h003c) ||
                      (e5.adr == 'h3 && e5.rate_cnt == 'h0330) ||
                      (e5.adr == 'h4 && e5.rate_cnt == 'h20c0) ||
                      (e5.adr == 'h5 && e5.rate_cnt == 'h6755) ||
                      (e5.adr == 'h6 && e5.rate_cnt == 'h3800) ||
                      (e5.adr == 'h7 && e5.rate_cnt == 'h500e) ||
                      (e5.adr == 'h8 && e5.rate_cnt == 'h1212) ||
                      (e5.adr == 'h9 && e5.rate_cnt == 'h0222) ||
                      (e5.adr == 'hA && e5.rate_cnt == 'h1848) ||
                      (e5.adr == 'hB && e5.rate_cnt == 'h59b8) ||
                      (e5.adr == 'hC && e5.rate_cnt == 'h3840) ||
                      (e5.adr == 'hD && e5.rate_cnt == 'h77e2) ||
                      (e5.adr == 'hE && e5.rate_cnt == 'h7625) ||
                      (e5.adr == 'hF && e5.rate_cnt == 'h0a93) ||
                      res;

        // Exponential counter reset / count.
        exp_cnt_res =
                     // Exponential decay.
                     (e5.exp_seg[0] && e5.exp_cnt == 'h1c) ||
                     (e5.exp_seg[1] && e5.exp_cnt == 'h11) ||
                     (e5.exp_seg[2] && e5.exp_cnt == 'h1b) ||
                     (e5.exp_seg[3] && e5.exp_cnt == 'h08) ||
                     (e5.exp_seg[4] && e5.exp_cnt == 'h0f) ||
                     // No exponential decay.
                     // Note that in this FPGA cycle we cannot use
                     // e5.attack, which is precalculated for the next
                     // SID cycle. e5.env_cnt_up = attack for this cycle.
                     (e5.prev_rate_cnt_res && (e5.env_cnt_up || e5.exp_seg == '0)) ||
                     res;
`else
        // Envelope rate counter reset / count.
        rate_cnt_res =
                      (e5.adr == 'h0 && e5.rate_cnt ==     8) ||
                      (e5.adr == 'h1 && e5.rate_cnt ==    31) ||
                      (e5.adr == 'h2 && e5.rate_cnt ==    62) ||
                      (e5.adr == 'h3 && e5.rate_cnt ==    94) ||
                      (e5.adr == 'h4 && e5.rate_cnt ==   148) ||
                      (e5.adr == 'h5 && e5.rate_cnt ==   219) ||
                      (e5.adr == 'h6 && e5.rate_cnt ==   266) ||
                      (e5.adr == 'h7 && e5.rate_cnt ==   312) ||
                      (e5.adr == 'h8 && e5.rate_cnt ==   391) ||
                      (e5.adr == 'h9 && e5.rate_cnt ==   976) ||
                      (e5.adr == 'hA && e5.rate_cnt ==  1953) ||
                      (e5.adr == 'hB && e5.rate_cnt ==  3125) ||
                      (e5.adr == 'hC && e5.rate_cnt ==  3906) ||
                      (e5.adr == 'hD && e5.rate_cnt == 11719) ||
                      (e5.adr == 'hE && e5.rate_cnt == 19531) ||
                      (e5.adr == 'hF && e5.rate_cnt == 31250) ||
                      res;

        // Exponential counter reset / count.
        exp_cnt_res =
                     // Exponential decay.
                     (e5.exp_seg[0] && e5.exp_cnt ==  2) ||
                     (e5.exp_seg[1] && e5.exp_cnt ==  4) ||
                     (e5.exp_seg[2] && e5.exp_cnt ==  8) ||
                     (e5.exp_seg[3] && e5.exp_cnt == 16) ||
                     (e5.exp_seg[4] && e5.exp_cnt == 30) ||
                     // No exponential decay.
                     // Note that in this FPGA cycle we cannot use
                     // e5.attack, which is precalculated for the next
                     // SID cycle. e5.env_cnt_up = attack for this cycle.
                     (e5.prev_rate_cnt_res && (e5.env_cnt_up || e5.exp_seg == '0)) ||
                     res;
`endif
    end

    always_ff @(posedge clk) begin
        // Update counters.
        if (cycle >= 6 && cycle <= 11) begin
            { e5, e4, e3, e2, e1, e0 } <= { e4, e3, e2, e1, e0, e5 };

            // Counter control logic.

            // In the real SID, gate, FF, and 00 are latched by phi1, phi2,
            // and are thus first available at the next cycle. Since the
            // combinations of the signals don't depend on any other signals
            // from the next cycle except for reset, they can be precalculated
            // and stored for the next cycle.
            e0.prev_gate <= ereg_5.gate;
            e0.prev_FF   <= exp_step[0];
            e0.prev_00   <= exp_step[6];

            // The counter starts counting when the gate goes high or on reset,
            // and stops counting once it has reached zero.
            if (rise_gate | res) begin
                e0.env_cnt_en <= 1;
            end else if (rise_00) begin
                e0.env_cnt_en <= 0;
            end

            // The counter starts counting down after it has reached FF (decay),
            // or if the gate is low (release).
            // The counter starts counting up once the gate goes high (attack).
            if (rise_FF | ~ereg_5.gate) begin
                e0.attack <= 0;
            end else if (rise_gate) begin
                e0.attack <= 1;
            end

            // Counting direction is delayed by another cycle.
            e0.env_cnt_up       <= e5.attack;
            e0.prev_env_cnt_up  <= e5.env_cnt_up;
            // Invert counter bits on change of counting direction.
            // Yet another cycle delay.
            e0.env_cnt_inv <= e5.env_cnt_up ^ e5.attack;

            // Both the high and low 4 bits of the envelope counter are compared
            // with the 4-bit sustain value.
            e0.sustain <= (env == { ereg_5.sustain, ereg_5.sustain }) & ereg_5.gate & ~e5.attack;

            // The counter counts up every time exp_cnt_res is set, as long as
            // the counter is not frozen at zero, and we're not in the sustain state.
            // In the real SID, the inversion and counter latch is done on different
            // clock phases.
            // The counter bits are inverted when the counting direction changes.
            // The count is delayed by yet another cycle.
            e0.env_cnt <= primed ?
                          (e5.env_cnt ^ { 8{e5.env_cnt_inv} }) + { 7'b0, e5.env_cnt_en & exp_cnt_res & ~e5.sustain } :
                          ENV_INIT;

`ifndef RIPPLE_COUNTERS
            // LFSR counters were used in the real SID, see
            // https://github.com/libsidplayfp/SID_schematics/wiki/Envelope-Overview

            if (rate_cnt_res || !primed) begin
                e0.rate_cnt <= '1;
            end else begin
                e0.rate_cnt <= { e5.rate_cnt[13:0], e5.rate_cnt[14] ^ e5.rate_cnt[13] };
            end

            if (exp_cnt_res || !primed) begin
                e0.exp_cnt <= '1;
            end else if (e5.prev_rate_cnt_res) begin
                e0.exp_cnt <= { e5.exp_cnt[3:0], e5.exp_cnt[4] ^ e5.exp_cnt[2] };
            end

            // Latch reset signal for next cycle.
            e0.prev_rate_cnt_res <= rate_cnt_res;
`else
            // LFSR counters were used in the real SID, however ripple counters
            // don't necessarily use any more resources thanks to FPGA carry
            // logic, and they also simplify testing.

            // The period of the LFSR15 is 2^15 - 1; wrap counter around at 2^15 - 2.
            if (rate_cnt_res || e5.rate_cnt == 'h7FFE) begin
                e0.rate_cnt <= 0;
            end else begin
                e0.rate_cnt <= e5.rate_cnt + 1;
            end

            // The period of the LFSR5 is 2^5 - 1; wrap counter around at 2^5 - 2.
            // Note that this check is redundant, since the counter can only
            // reach this value (30) when exp_seg[4] is set (famous last words).
            if (exp_cnt_res || e5.exp_cnt == 'h1E) begin
                e0.exp_cnt <= 0;
            end else if (e5.prev_rate_cnt_res) begin
                e0.exp_cnt <= e5.exp_cnt + 1;
            end

            // Latch reset signal for next cycle.
            e0.prev_rate_cnt_res <= rate_cnt_res;
`endif

            // Set/reset selectors for exponential curve segments.
            // In the real SID, the selectors are both latched and input to
            // combinational logic for reset of the exponential counter at the
            // same phi1 cycle. However since the reset signal is latched by
            // phi2, we can postpone the use to the next cycle.
            for (int i = 0; i < $bits(e0.exp_seg); i++) begin : seg
                if (exp_step[i] | exp_step[i + 2] | res) begin
                    e0.exp_seg[i] <= 0;
                end else if (exp_step[i + 1]) begin
                    e0.exp_seg[i] <= 1;
                end
            end

            // Multiplexer for rate period index (attack / decay / release).
            // FIXME: Yosys doesn't understand case (expr) inside.
            unique casez ({ ereg_5.gate, e5.attack })
              2'b?1: e0.adr <= ereg_5.attack;
              2'b10: e0.adr <= ereg_5.decay;
              2'b00: e0.adr <= ereg_5.release_;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (cycle == 11 && !primed) begin
            // All counters and LFSRs are initialized.
            primed <= 1;
        end
    end

`ifdef VM_TRACE
    // Latch voices for simulation.
    /* verilator lint_off UNUSED */
    typedef struct packed {
        sid::reg7_t exp_step;
        logic       rise_gate;
        logic       rise_FF;
        logic       rise_00;
        sid::reg8_t env;
    } sim_t;

    sim_t      sim      [6];
    envelope_t sim_state[6];

    always_ff @(posedge clk) begin
        if (cycle >= 6 && cycle <= 11) begin
            sim[cycle - 6].exp_step  <= exp_step;
            sim[cycle - 6].rise_gate <= rise_gate;
            sim[cycle - 6].rise_FF   <= rise_FF;
            sim[cycle - 6].rise_00   <= rise_00;
            sim[cycle - 6].env       <= env;
            sim_state[cycle - 6]     <= e5;
        end
    end
    /* verilator lint_on UNUSED */
`endif
endmodule

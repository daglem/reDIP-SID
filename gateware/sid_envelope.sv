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

module sid_envelope #(
    // Default is no init, since the counter will reach zero in 86 cycles on reset.
    localparam INIT_ENV = 0
)(
    input  logic               clk,
    input  logic               res,
    input  sid::phase_t        phase,
    input  sid::envelope_reg_t reg_i,
    output sid::reg8_t         out = 0
);

    // 8-bit envelope counter.
    // Odd bits are high on powerup. There is no immediate reset, however
    // env_cnt_inc, rate_cnt_res, and exp_cnt_res are all set by reset.
    // This implies that, on the face of it, the counter will start out at 'hAA,
    // and will then count up in the decay(!) state while in reset, until it
    // reaches zero in 'h100 - 'hAA = 86 cycles.
    // Since initial values != 0 require LUTs, we make this configurable.
    sid::reg8_t  env_cnt = INIT_ENV ? { 4{2'b10} } : 0;
    logic        env_cnt_inc = 0;
    logic        env_cnt_inv;
    logic        prev_gate   = 0;
    logic        rise_gate   = 0;
    logic        attack      = 0;
    logic        prev_attack = 0;
    logic        sustain_cmp = 0;
    logic        sustain;
    // 15-bit rate counter.
    sid::reg15_t rate_cnt = 0;
    logic        rate_cnt_res = 0;
    logic        prev_rate_cnt_res = 0;
    sid::reg7_t  exp_step = 0;
    logic        prev_FF = 0;
    logic        prev_00 = 0;
    logic        rise_FF = 0;
    logic        rise_00 = 0;
    sid::reg5_t  exp_seg = 0;
    // 5-bit exponential decay counter.
    sid::reg5_t  exp_cnt = 0;
    logic        exp_cnt_res = 0;
    sid::reg4_t  adr = 0;

    always_comb begin
        rise_gate   = ~prev_gate & reg_i.gate;
        sustain     = sustain_cmp & reg_i.gate & ~attack;
        // Invert counter bits on change of counter direction.
        env_cnt_inv = prev_attack ^ attack;
    end

    // Exponential decay curve segment steps.
    always_ff @(posedge clk) begin
        if (phase[sid::PHI2]) begin
            // These signals are delayed by one cycle (latched by phi1);
            // store values before update of exp_step.
            rise_FF <= ~prev_FF & exp_step[0];
            rise_00 <= ~prev_00 & exp_step[6];
            prev_FF <= exp_step[0];
            prev_00 <= exp_step[6];

            exp_step <= {
                env_cnt == 8'h00,
                env_cnt == 8'h06,
                env_cnt == 8'h0E,
                env_cnt == 8'h1A,
                env_cnt == 8'h36,
                env_cnt == 8'h5D,
                env_cnt == 8'hFF
            };
        end
    end

    // Set/reset selectors for exponential curve segments.
    for (genvar i = 0; i < $bits(exp_seg); i++) begin : seg
        always_ff @(posedge clk) begin
            if (phase[sid::PHI2_PHI1]) begin
                if (exp_step[i] | exp_step[i + 2] | res) begin
                    exp_seg[i] <= 0;
                end else if (exp_step[i + 1]) begin
                    exp_seg[i] <= 1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin

        // Counter control logic.
        if (phase[sid::PHI2_PHI1]) begin
            // Both the high and low 4 bits of the envelope counter are compared
            // with the 4-bit sustain value.
            sustain_cmp <= (env_cnt == { reg_i.sustain, reg_i.sustain });
            // Store gate value after any register write on PHI2.
            prev_gate   <= reg_i.gate;
            prev_attack <= attack;

            // The counter stops counting once it has reached zero,
            // and restarts once the gate goes high.
            if (rise_00) begin
                env_cnt_inc <= 0;
            end else if (rise_gate | res) begin
                env_cnt_inc <= 1;
            end

            // The counter starts counting down after it has reached FF,
            // or if the gate is low (decay / release).
            // The counter starts counting up once the gate goes high (attack).
            if (rise_FF | ~reg_i.gate) begin
                attack <= 0;
            end else if (rise_gate) begin
                attack <= 1;
            end
        end

        // Count up or down.
        if (phase[sid::PHI1]) begin
            // The counter counts up every time exp_cnt_res is set, as long as
            // the counter is not frozen at zero, and we're not in the sustain state.
            // The counter bits are inverted when the counter direction changes.
            // In the real SID, the inversion is done on the following phi2.
            // The counter can be implemented using a single PLB ripple carry adder,
            // with an additional input per LUT4 for inversion.
            env_cnt <= (env_cnt + { 7'b0, env_cnt_inc & ~sustain & exp_cnt_res}) ^ { 8{env_cnt_inv} };
        end
        
        // Output envelope value before any read of ENV3 at phi2.
        if (phase[sid::PHI1_PHI2]) begin
            out <= env_cnt ^ { 8{~attack} };
        end

        // Multiplexer for rate period index (attack / decay / release).
        if (phase[sid::PHI2_PHI1]) begin
            // The reset flag for the rate counter below is latched by the next phi2.
            // FIXME: Yosys doesn't understand case (expr) inside.
            casez ({ reg_i.gate, attack })
              2'b?1: adr <= reg_i.attack;
              2'b10: adr <= reg_i.decay;
              2'b00: adr <= reg_i.release_;
            endcase
        end

        // TODO: Add alternative LFSR15 / LFSR5 implementations of counters.

        // Envelope rate counter reset / count.
        if (phase[sid::PHI2]) begin
            prev_rate_cnt_res <= rate_cnt_res;
            
            rate_cnt_res <=
                (adr == 'h0 && rate_cnt ==     8) ||
                (adr == 'h1 && rate_cnt ==    31) ||
                (adr == 'h2 && rate_cnt ==    62) ||
                (adr == 'h3 && rate_cnt ==    94) ||
                (adr == 'h4 && rate_cnt ==   148) ||
                (adr == 'h5 && rate_cnt ==   219) ||
                (adr == 'h6 && rate_cnt ==   266) ||
                (adr == 'h7 && rate_cnt ==   312) ||
                (adr == 'h8 && rate_cnt ==   391) ||
                (adr == 'h9 && rate_cnt ==   976) ||
                (adr == 'hA && rate_cnt ==  1953) ||
                (adr == 'hB && rate_cnt ==  3125) ||
                (adr == 'hC && rate_cnt ==  3906) ||
                (adr == 'hD && rate_cnt == 11719) ||
                (adr == 'hE && rate_cnt == 19531) ||
                (adr == 'hF && rate_cnt == 31250) ||
                res;
        end

        if (phase[sid::PHI2_PHI1]) begin
            // The period of the LFSR15 is 2^15 - 1; wrap counter around at 2^15 - 2.
            if (rate_cnt_res || rate_cnt == 'h7FFE) begin
                rate_cnt <= 0;
            end else begin
                rate_cnt <= rate_cnt + 1;
            end
        end
            
        // Exponential counter reset / count.
        if (phase[sid::PHI2]) begin
            exp_cnt_res <=
                // Exponential decay.
                (exp_seg[0] && exp_cnt ==  2) ||
                (exp_seg[1] && exp_cnt ==  4) ||
                (exp_seg[2] && exp_cnt ==  8) ||
                (exp_seg[3] && exp_cnt == 16) ||
                (exp_seg[4] && exp_cnt == 30) ||
                // No exponential decay.
                (prev_rate_cnt_res && (attack || exp_seg == '0)) ||
                res;
        end

        if (phase[sid::PHI2_PHI1]) begin
            // The period of the LFSR5 is 2^5 - 1; wrap counter around at 2^5 - 2.
            // Note that this check is redundant, since the counter can only
            // reach this value (30) when exp_seg[4] is set (famous last words).
            if (exp_cnt_res || exp_cnt == 'h1E) begin
                exp_cnt <= 0;
            end else if (prev_rate_cnt_res) begin
                exp_cnt <= exp_cnt + 1;
            end
        end
    end
endmodule

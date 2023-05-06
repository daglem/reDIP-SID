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

module sid_api (
    input  logic        clk,
    input  sid::bus_i_t bus_i,
    input  sid::cs_t    cs,
    output sid::reg8_t  data_o,
    input  sid::pot_i_t pot_i,
    output sid::pot_o_t pot_o,
    input  sid::audio_t audio_i,
    output sid::audio_t audio_o = '0
);

    initial begin
        $dumpfile("sid_api.fst");
        $dumpvars;
    end

    // SID core clock phase.
    logic phi2_prev = 0;

    // SID pipeline cycle counters.
    sid::cycle_t voice_cycle_count = 0;
    sid::cycle_t voice_cycle;
    logic        voice_cycle_idle  = 0;
    sid::cycle_t filter_cycle      = 0;

    always_comb begin
        // Idling of voice pipeline.
        voice_cycle_idle = filter_cycle == 4 || filter_cycle == 5 || filter_cycle == 9 || filter_cycle == 10;
        voice_cycle      = voice_cycle_idle ? 0 : voice_cycle_count;
    end

    always_ff @(posedge clk) begin
        // Start voice pipeline after the falling edge of phi2.
        // Keep counting until the counter wraps around to zero.
        // Pause voice pipeline at filter pipeline cycle 5 and 6, for the
        // latter pipeline to catch up.
        voice_cycle_count <= voice_cycle_count + 4'(phi2_prev & ~bus_i.phi2 || (voice_cycle_count != 0 &&
                                                                                !voice_cycle_idle));

        // Start filter pipeline at voice pipeline cycle 7; one cycle before
        // the first voice output is ready.
        // Keep counting until the counter wraps around to zero.
        filter_cycle <= filter_cycle + 4'(voice_cycle == 6 || filter_cycle != 0);

        phi2_prev <= bus_i.phi2;
    end

    // Tick approximately every ms, for smaller counters in submodules.
    // ~1MHz / 1024 = ~1kHz
    logic  [9:0] count_us = 0;
    logic [10:0] count_us_next;
    logic        tick_ms;

    always_comb begin
        // Use carry as tick.
        count_us_next = { 1'b0, count_us } + 1;
        tick_ms = count_us_next[10];
    end

    always_ff @(posedge clk) begin
        if (voice_cycle == 1) begin
            // Update counter, discarding carry.
            count_us <= count_us_next[9:0];
        end
    end

    // FIXME: This would be safer if Yosys were to understand structure literals.
    // sid::cfg_t sid_cfg = '{ sid1_model: ... };
`ifdef SID2
    sid::cfg_t  sid1_cfg = { sid::MOS8580, sid::D400, 9'd250, 11'sd0 };
    sid::cfg_t  sid2_cfg = { sid::MOS8580, sid::D420 | sid::D500 | sid::DE00, 9'd250, 11'sd0 };
`else
    sid::cfg_t  sid1_cfg = { sid::MOS6581, sid::D400, 9'd250, 11'sd0 };
    sid::cfg_t  sid2_cfg = { sid::MOS6581, sid::D400, 9'd250, 11'sd0 };
`endif
    // NB! Don't put multi-bit variables in arrays, as Yosys handles that incorrectly.
    logic [1:0] sid_cs;
    logic [1:0] model;

    always_comb begin
        model = { sid2_cfg.model, sid1_cfg.model };
    end

    // SID read-only registers.
    sid::pot_reg_t sid1_pot;
    sid::reg8_t    sid1_osc3 = 0, sid2_osc3 = 0;
    sid::reg8_t    sid1_env3 = 0, sid2_env3 = 0;

    always_comb begin
        // Chip select decode.
        // SID 2 address is configurable.
        // SID 1 is always located at D400.
        sid_cs[1] = sid2_cfg.addr == sid::D400 ? ~cs.cs_n :
                    sid2_cfg.addr[sid::D420_BIT] & ~cs.cs_n & cs.a5 |
                    sid2_cfg.addr[sid::D500_BIT] & ~cs.cs_n & cs.a8 |
                    sid2_cfg.addr[sid::DE00_BIT] & ~cs.cs_io1_n;
        sid_cs[0] = sid2_cfg.addr == sid::D400 ? ~cs.cs_n :
                    ~cs.cs_n & ~sid_cs[1];

        // Default to SID 1.
        // Return FF for SID 2 POTX/Y.
        mreg.pot  = (sid_cs == 2'b10) ? '1 : sid1_pot;
        mreg.osc3 = (sid_cs == 2'b10) ? sid2_osc3 : sid1_osc3;
        mreg.env3 = (sid_cs == 2'b10) ? sid2_env3 : sid1_env3;
    end

    // SID control registers.
    sid::freq_pw_t      freq_pw_1;
    logic [2:0]         test;
    logic [2:0]         sync;
    sid::control_t      control_3, control_4, control_5;
    sid::envelope_reg_t ereg_5;
    sid::filter_reg_t   freg_1;
    sid::misc_reg_t     mreg;

    sid_control control (
        .clk          (clk),
        .tick_ms      (tick_ms),
        .voice_cycle  (voice_cycle),
        .filter_cycle (filter_cycle),
        .bus_i        (bus_i),
        .cs           (sid_cs),
        .model        (model),
        .freq_pw_1    (freq_pw_1),
        .test         (test),
        .sync         (sync),
        .control_3    (control_3),
        .control_4    (control_4),
        .control_5    (control_5),
        .ereg_5       (ereg_5),
        .freg_1       (freg_1),
        .mreg         (mreg),
        .data_o       (data_o)
    );

    // SID waveform generator.
    sid::reg12_t   wav;

    sid_waveform waveform (
        .clk       (clk),
        .tick_ms   (tick_ms),
        .cycle     (voice_cycle),
        .res       (bus_i.res),
        .model     (model),
        .freq_pw_1 (freq_pw_1),
        .test      (test),
        .sync      (sync),
        .control_3 (control_3),
        .control_4 (control_4),
        .control_5 (control_5),
        .wav       (wav)
    );

    // SID envelope generator.
    sid::reg8_t    env;

    sid_envelope envelope (
        .clk    (clk),
        .cycle  (voice_cycle),
        .res    (bus_i.res),
        .ereg_5 (ereg_5),
        .env    (env)
    );

    // Store OSC3 and ENV3 for both SIDs.
    always_ff @(posedge clk) begin
        if (voice_cycle == 8) begin
            sid1_osc3 <= wav[11-:8];
            sid1_env3 <= env;
        end

        if (voice_cycle == 11) begin
            sid2_osc3 <= wav[11-:8];
            sid2_env3 <= env;
        end
    end

    // Pipeline for voice outputs.
    sid::s22_t dca;

    sid_voice voice (
        .clk   (clk),
        .cycle (voice_cycle),
        .model (model),
        .wav   (wav),
        .env   (env),
        .dca   (dca)
    );

    // Pipeline for filter outputs.
    sid::s20_t filter_o;
    sid::s24_t ext_in_1 = '0;
    sid::s24_t ext_in_2 = '0;
    sid::s24_t audio_o1 = '0;

    always_ff @(posedge clk) begin
        if (filter_cycle == 1) begin
            { ext_in_1, ext_in_2 } <= audio_i;
        end else if (filter_cycle == 6) begin
            ext_in_1 <= ext_in_2;
        end

        if (filter_cycle == 9) begin
            audio_o1 <= { filter_o, 4'b0 };
        end else if (filter_cycle == 14) begin
            audio_o <= { audio_o1, filter_o, 4'b0 };
        end
    end

    sid_filter filter (
        .clk     (clk),
        .cycle   (filter_cycle),
        .freg    (freg_1),
        .cfg     (filter_cycle <= 5 ? sid1_cfg : sid2_cfg),
        // EXT IN or internal voice.
        .voice_i (filter_cycle == 5 || filter_cycle == 10 ? ext_in_1[23-:22] : dca),
        .audio_o (filter_o)
    );

    // SID POTX / POTY.
    sid_pot potxy (
       .clk   (clk),
       .cycle (voice_cycle),
       .pot_i (pot_i),
       .pot_o (pot_o),
       .pot   (sid1_pot)
    );
endmodule

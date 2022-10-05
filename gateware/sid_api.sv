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

module sid_api #(
    // FC offset for average 6581 filter curve.
    localparam FC_OFFSET_6581 = 12'sh600
)(
    input  logic        clk,
    input  logic        phi2,
    input  sid::bus_i_t bus_i,
    input  sid::cs_t    cs,
    output sid::reg8_t  data_o,
    input  sid::pot_i_t pot_i,
    output sid::pot_o_t pot_o,
    input  sid::audio_t audio_i,
    output sid::audio_t audio_o
);

    initial begin
        $dumpfile("sid_api.fst");
        $dumpvars;
    end

    // SID core clock phase.
    logic        phi2_prev = 0;
    sid::phase_t phase     = 0;

    always_ff @(posedge clk) begin
        phi2_prev <= phi2;
        phase     <= { phase[2:0], phi2_prev & ~phi2 };
    end

    // FIXME: This would be safer if Yosys were to understand structure literals.
    // sid::cfg_t sid_cfg = '{ sid1_model: ... };
    sid::cfg_t  sid1_cfg = { sid::MOS6581, sid::D400, 9'd250, 11'sd0 };
    sid::cfg_t  sid2_cfg = { sid::MOS8580, sid::DE00, 9'd250, 11'sd0 };
    // NB! Don't put multi-bit variables in arrays, as Yosys handles that incorrectly.
    sid::reg8_t sid1_data_o, sid2_data_o;
    logic [1:0] sid_cs;

    // Digital outputs from SID cores.
    sid::core_o_t core1_o,   core2_o;
    sid::reg8_t   sid1_osc3, sid2_osc3;

    // SID core #1.
    sid_core sid1 (
        .clk     (clk),
        .model   (sid1_cfg.model),
        .bus_i   (bus_i),
        .phase   (phase),
        .cs      (sid_cs[0]),
        .data_o  (sid1_data_o),
        .pot_i   (pot_i),
        .pot_o   (pot_o),
        .out     (core1_o),
        .osc3    (sid1_osc3)
    );
    
    // SID core #2 - no POT pins.
    /* verilator lint_off PINCONNECTEMPTY */
    sid_core sid2 (
        .clk     (clk),
        .model   (sid2_cfg.model),
        .bus_i   (bus_i),
        .phase   (phase),
        .cs      (sid_cs[1]),
        .data_o  (sid2_data_o),
        .pot_i   (2'b00),
        .pot_o   (),
        .out     (core2_o),
        .osc3    (sid2_osc3)
    );
    /* verilator lint_on PINCONNECTEMPTY */

    // Pipeline for voice outputs.
    sid::model_e   voice_model;
    sid::voice_i_t voice_i;
    sid::reg8_t    osc_o;
    sid::reg24_t   voice_o;

    logic [3:0] voice_stage = 0, next_voice_stage;
    
    sid_voice voice_pipeline (
        .clk     (clk),
        .model   (voice_model),
        .voice_i (voice_i),
        .voice_o (voice_o),  // 1 cycle delay
        .osc_o   (osc_o)     // 1 cycle delay
    );
    
    // Pipeline for filter outputs.
    logic [1:0]     filter_no = 0;
    sid::filter_i_t filter_i;
    sid::s24_t      filter_o;
    sid::s24_t      filter_o_left;
    sid::s24_t      audio_i_right;
    // Filter states.
    sid::filter_v_t filter_v;
    sid::filter_v_t filter1_v = 0;
    sid::filter_v_t filter2_v = 0;

    logic [2:0] filter_stage = 0, next_filter_stage;

    sid_filter filter_pipeline (
        .clk      (clk),
        .stage    (filter_stage),
        .filter_i (filter_i),
        .state_o  (filter_v),
        .audio_o  (filter_o) // 8 cycle delay
    );
    
    always_comb begin
        if (voice_stage == 0) begin
            // Start voice pipeline when the SIDs are done.
            next_voice_stage = { 3'b0, phase[sid::PHI1_PHI2] };
        end else begin
            next_voice_stage = voice_stage + 1;
            // Since it's more than 16 cycles between each run,
            // we just let the counter wrap around to zero.
        end

        if (filter_no == 0) begin
            next_filter_stage = 0;
        end else begin
            next_filter_stage = filter_stage + 1;
        end
    end
    
    always_ff @(posedge clk) begin
        // Calculate 2*3 voice outputs.
        // osc_o and voice_o are delayed by 1 cycle.
        // FIXME: Calculate voice3 first, in order to have OSC3 ready 2 cycles earlier?
        case (voice_stage)
          1: begin
              voice_model     <= sid1_cfg.model;
              voice_i         <= core1_o.voice1;
          end
          2: begin
              voice_i         <= core1_o.voice2;
          end
          3: begin
              voice_i         <= core1_o.voice3;

              filter_i.voice1 <= voice_o;
          end
          4: begin
              voice_model     <= sid2_cfg.model;
              voice_i         <= core2_o.voice1;

              filter_i.voice2 <= voice_o;
          end
          5: begin
              voice_i         <= core2_o.voice2;

              filter_i.voice3 <= voice_o;
              sid1_osc3       <= osc_o;

              // Setup for SID #1 filter pipeline.
              filter_i.model     <= sid1_cfg.model;
              filter_i.fc_base   <= sid1_cfg.fc_base;
              filter_i.fc_offset <= sid1_cfg.fc_offset + FC_OFFSET_6581;
              filter_i.regs      <= core1_o.filter_regs;
              filter_i.ext_in    <= audio_i.left;
              filter_i.state     <= filter1_v;
              // Save audio input for SID #2.
              audio_i_right      <= audio_i.right;

              // Ready for SID #1 filter pipeline, see below.
          end
          6: begin
              voice_i         <= core2_o.voice3;

              filter_i.voice1 <= voice_o;
          end
          7: begin
              filter_i.voice2 <= voice_o;
          end
          8: begin
              filter_i.voice3 <= voice_o;
              sid2_osc3       <= osc_o;
          end
          9: begin
              // Setup for SID #2 filter pipeline.
              // The filter input state is only used during the first 4 cycles
              // in sid_filter, so it's safe to change it just now.
              filter_i.model     <= sid2_cfg.model;
              filter_i.fc_base   <= sid2_cfg.fc_base;
              filter_i.fc_offset <= sid2_cfg.fc_offset + FC_OFFSET_6581;
              filter_i.regs      <= core2_o.filter_regs;
              filter_i.ext_in    <= audio_i_right;
              filter_i.state     <= filter2_v;
          end
        endcase
              
        voice_stage <= next_voice_stage;

        // Calculate 2 audio stage outputs.
        if (voice_stage == 4 || voice_stage == 5) begin
            // Start SID #1 filter pipeline.
            // Wait one cycle for filter_stage to be increased to 1.
            filter_no <= 1;
        end else if (filter_stage == 0) begin
            // The filter pipeline is finished (stage wrapped around to zero).
            case (filter_no)
              1: begin
                  filter1_v     <= filter_v;
                  filter_o_left <= filter_o;
                  filter_no     <= 2;
              end
              2: begin
                  filter2_v     <= filter_v;
                  audio_o.left  <= filter_o_left;
                  audio_o.right <= filter_o;
                  filter_no     <= 0;
              end
            endcase
        end
        
        filter_stage <= next_filter_stage;
    end
    
    // Chip select decode.
    always_comb begin
        // SID #1 is always located at D400.
        // SID #2 address is configurable.
        unique case (sid2_cfg.addr)
          sid::D400: sid_cs = { ~cs.cs_n,         ~cs.cs_n          };
          sid::D420: sid_cs = { ~cs.cs_n & cs.a5, ~cs.cs_n & ~cs.a5 };
          sid::D500: sid_cs = { ~cs.cs_n & cs.a8, ~cs.cs_n & ~cs.a8 };
          sid::DE00: sid_cs = { ~cs.cs_io1_n,     ~cs.cs_n          };
        endcase
    end
    
    always_comb begin
        // Default to SID #1 for data out.
        data_o = sid_cs == 2'b10 ? sid2_data_o : sid1_data_o;
    end
endmodule

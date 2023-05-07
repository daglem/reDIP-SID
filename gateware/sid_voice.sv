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

// Waveform selector, voice DCA (digitally controlled amplifier).
// Modeling of non-linearities in MOS6581 waveform and envelope DACs.
module sid_voice #(
    localparam WAVEFORM_DC_6581 = -16'sh380,  // OSC3 = 'h38 at 5.94V.
    localparam WAVEFORM_DC_8580 = -16'sh800,  // No DC offsets in the MOS8580.
    // FIXME: The 6581 voice DC offset has been measured as low as 'h340 on one
    // SID chip, and should thus probably be configurable.
    localparam VOICE_DC_6581    = 32'('h800*'hff), // 1/2 the dynamic range.
    localparam VOICE_DC_8580    = 32'h0       // No DC offsets in the MOS8580.
)(
    input  logic        clk,
    input  sid::cycle_t cycle,
    input  logic[1:0]   model,
    input  sid::reg12_t wav,
    input  sid::reg8_t  env,
    output sid::s22_t   dca
);

    // Keep track of the current SID model.
    logic model_6;

    always_comb begin
        model_6 = model[cycle >= 10];
    end

    // MOS6581 waveform DAC output.
    sid::reg12_t wav_6581;
    sid::reg12_t wav_8580 = 0;

    sid_dac #(
        .BITS (12)
    ) waveform_dac (
        .vin  (wav_8580),
        .vout (wav_6581)
    );

    // MOS6581 envelope DAC output.
    sid::reg8_t env_6581;
    sid::reg8_t env_8580 = 0;

    sid_dac #(
        .BITS (8)
    ) envelope_dac (
        .vin  (env_8580),
        .vout (env_6581)
    );

    always_ff @(posedge clk) begin
        if (cycle >= 6 && cycle <= 11) begin
            wav_8580 <= wav;
            env_8580 <= env;
        end
    end

    // Registered inputs to voice DCA.
    sid::s32_t dca_DC  = 0;
    sid::s16_t wav_dac = 0;
    sid::s16_t env_dac = 0;

    // Output from voice DCA.
    /* verilator lint_off UNUSED */
    sid::s32_t dca_out;
    /* verilator lint_on UNUSED */

    // Voice DCA (digitally controlled amplifier).
    // dca_out = dca_DC + wav_dac*env_dac
    // The result fits in 22 bits.
    muladd voice_dca (
        .c (dca_DC),
        .s (1'b0),
        .a (wav_dac),
        .b (env_dac),
        .o (dca_out)
    );

    always_ff @(posedge clk) begin
        if (cycle >= 7 && cycle <= 12) begin
            // Setup for voice DCA multiply-add, ready on cycle 2.
            dca_DC  <= (model_6 == sid::MOS6581) ?
                       VOICE_DC_6581 :
                       VOICE_DC_8580;

            wav_dac <= (model_6 == sid::MOS6581) ?
                       16'(wav_6581) + WAVEFORM_DC_6581 :
                       16'(wav_8580) + WAVEFORM_DC_8580;

            env_dac <= (model_6 == sid::MOS6581) ?
                       16'(env_6581) :
                       16'(env_8580);
        end
    end

    always_comb begin
        // The DCA output fits in 22 bits.
        // Register output.
        dca = dca_out[21:0];
    end

`ifdef VM_TRACE
    // Latch voices for simulation.
    /* verilator lint_off UNUSED */
    typedef struct packed {
        sid::s16_t wav_dac;
        sid::s16_t env_dac;
        sid::s22_t dca;
    } sim_t;

    sim_t sim[6];

    always_ff @(posedge clk) begin
        if (cycle >= 8 && cycle <= 13) begin
            sim[cycle - 8].wav_dac <= wav_dac;
            sim[cycle - 8].env_dac <= env_dac;
            sim[cycle - 8].dca     <= dca;
        end
    end
    /* verilator lint_on UNUSED */
`endif
endmodule

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

module sid_pot #(
    // Default is no init, since operation will be normal within 512 cycles.
    localparam INIT_POT = 0
)(
    input  logic          clk,
    input  sid::cycle_t   cycle,
    input  sid::pot_i_t   pot_i,
    output sid::pot_o_t   pot_o,
    output sid::pot_reg_t pot = '0
);

    // 9 bit counter, used by both POTX and POTY.
    // Odd bits are high on powerup. There is no immediate reset, and depending
    // on the initial charge on the POT capacitor, any value between AA and FF
    // will be loaded into the POT register on the first round.
    // Since initial values != 0 require LUTs, we make this configurable.
    sid::reg9_t pot_cnt = INIT_POT ? { 1'b0, { 4{2'b10} } } : 0;
    logic       pos_FF;
    // Individual position detection.
    logic [1:0] pos_det = 0;

    // Counter logic.
    always_comb begin
        // Discharge external capacitors for 256 cycles.
        pot_o.discharge = pot_cnt[8];
        // Detection of counter = FF.
        pos_FF = (pot_cnt[7:0] == 'hFF);
    end

    always_ff @(posedge clk) begin
        if (cycle == 1) begin
            // Count phi1 cycles.
            pot_cnt <= pot_cnt + 1;
        end
    end

    // The timing of the loading of the POT registers follows the
    // implementation in the real SID, where the counter is loaded into the
    // POT register once the input is high, or the counter = FF.
    // In the real SID, the register load is delayed by one cycle, however
    // it is not necessary to emulate this accurately.
    for (genvar i = 0; i < 2; i++) begin : pots
        always_ff @(posedge clk) begin
            if (cycle == 1) begin
                // Reset/set position detection status / load POT register.
                if (pot_o.discharge) begin
                    pos_det[i]    <= 0;
                end else if (~pos_det[i] & (pot_i.charged[i] | pos_FF)) begin
                    // Load POT registers when the POT position is detected,
                    // once within every 512 cycles.
                    pos_det[i]  <= 1;
                    pot.xy[i] <= pot_cnt[7:0];
                end
            end
        end
    end
endmodule

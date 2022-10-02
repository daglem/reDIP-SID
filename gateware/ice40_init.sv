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

module ice40_init (
    input  logic       boot,
    input  logic [1:0] image,
    input  logic       sys_clk,
    output logic       clk_24,
    output logic       rst_24,
    output logic       clk_48,
    output logic       rst_48
);

    // Boot configuration image.
    SB_WARMBOOT warmboot (
        .BOOT (boot),
        .S1   (image[1]),
        .S0   (image[0])
    );

    // PLL: 24MHz -> 24MHz, 48MHz (icepll -i 24 -o 48 -p -m)
    // fout = fin*(DIVF + 1) / (2^DIVQ*(DIVR + 1))
    logic pll_lock;

    SB_PLL40_2F_CORE #(
        .FEEDBACK_PATH ("SIMPLE"),
        .PLLOUT_SELECT_PORTA("GENCLK_HALF"),
        .PLLOUT_SELECT_PORTB("GENCLK"),
        .DIVR          (4'b0000),    // DIVR =  0
        .DIVF          (7'b0011111), // DIVF = 31
        .DIVQ          (3'b100),     // DIVQ =  4
        .FILTER_RANGE  (3'b010)      // FILTER_RANGE = 2
    ) pll (
        .REFERENCECLK  (sys_clk),
        .PLLOUTGLOBALA (clk_24),
        .PLLOUTGLOBALB (clk_48),
        .LOCK          (pll_lock),
        .BYPASS        (1'b0),
        .RESETB        (1'b1)
    );

    // Hold reset for a minimum of 10us (minimum 240 cycles at 24MHz),
    // to allow BRAM to power up. For simplicity, we only start counting
    // after the PLL is locked.
    logic [7:0] bram_cnt = 0;

    // Reset for 24MHz clock.
    // Reset is asserted from the very beginning.
    always_comb begin
        rst_24 = !(bram_cnt == 8'hff);
    end

    always_ff @(posedge clk_24 or negedge pll_lock) begin
        if (!pll_lock) begin
            // Loss of PLL lock causes an asynchronous reset.
            bram_cnt <= 0;
        end else if (rst_24) begin
            // pll_lock goes high asynchronously, which implies
            // metastability in the first count (only).
            bram_cnt <= bram_cnt + 1;
        end
    end

    // Reset for 48MHz clock.
    // Asynchronous assertion, synchronized release.
    logic rst_48_sync_x = 0;
    logic rst_48_sync   = 0;

    always_comb begin
        rst_48 = rst_24 | rst_48_sync;
    end

    always_ff @(posedge clk_48) begin
        // Bring 24MHz reset signal into 48Mhz clock domain
        // for synchronized reset release.
        rst_48_sync_x <= rst_24;
        rst_48_sync   <= rst_48_sync_x;
    end
endmodule

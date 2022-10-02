/*
 * i2c_master.v
 *
 * vim: ts=4 sw=4
 *
 * Copyright (C) 2019-2021  Sylvain Munaut <tnt@246tNt.com>
 * SPDX-License-Identifier: CERN-OHL-P-2.0
 */

`default_nettype none

module i2c_master #(
	parameter integer DW = 3
)(
	// IOs
	output reg  scl_oe,
	output reg  sda_oe,
	input  wire sda_i,

	// Control
	input  wire [7:0] data_in,
	input  wire       ack_in,
	input  wire [1:0] cmd,
	input  wire       stb,

	output wire [7:0] data_out,
	output wire       ack_out,

	output wire ready,

	// Clock / Reset
	input  wire clk,
	input  wire rst
);

	// Commands
	localparam [1:0] CMD_START = 2'b00;
	localparam [1:0] CMD_STOP  = 2'b01;
	localparam [1:0] CMD_WRITE = 2'b10;
	localparam [1:0] CMD_READ  = 2'b11;

	// FSM states
	localparam
		ST_IDLE       = 0,
		ST_LOWER_SCL  = 1,
		ST_LOW_CYCLE  = 2,
		ST_RISE_SCL   = 3,
		ST_HIGH_CYCLE = 4;


	// Signals
	// -------

	reg [2:0] state;
	reg [2:0] state_nxt;

	reg [1:0] cmd_cur;

	reg [DW:0] cyc_cnt;
	wire cyc_now;

	reg [3:0] bit_cnt;
	wire bit_last;

	reg [8:0] data_reg;


	// State Machine
	// -------------

	always @(posedge clk)
		if (rst)
			state <= ST_IDLE;
		else
			state <= state_nxt;

	always @(*)
	begin
		// Default is to stay put
		state_nxt = state;

		// Act depending on current state
		case (state)
			ST_IDLE:
				if (stb)
					state_nxt = ST_LOW_CYCLE;

			ST_LOW_CYCLE:
				if (cyc_now)
					state_nxt = ST_RISE_SCL;

			ST_RISE_SCL:
				if (cyc_now)
					state_nxt = ST_HIGH_CYCLE;

			ST_HIGH_CYCLE:
				if (cyc_now)
					state_nxt = (cmd_cur == 2'b01) ? ST_IDLE : ST_LOWER_SCL;

			ST_LOWER_SCL:
				if (cyc_now)
					state_nxt = bit_last ? ST_IDLE : ST_LOW_CYCLE;
		endcase
	end

	// Misc control
	// ------------

	always @(posedge clk)
		if (stb)
			cmd_cur <= cmd;


	// Baud Rate generator
	// -------------------

	always @(posedge clk)
		if (state == ST_IDLE)
			cyc_cnt <= 0;
		else
			cyc_cnt <= cyc_cnt[DW] ? 0 : (cyc_cnt + 1);

	assign cyc_now = cyc_cnt[DW];


	// Bit count
	// ---------

	always @(posedge clk)
		if ((state == ST_LOWER_SCL) && cyc_now)
			bit_cnt <= bit_cnt + 1;
		else if (stb)
			case (cmd)
				2'b00:   bit_cnt <= 4'h8; // START
				2'b01:   bit_cnt <= 4'h8; // STOP
				2'b10:   bit_cnt <= 4'h0; // Write
				2'b11:   bit_cnt <= 4'h0; // Read
				default: bit_cnt <= 4'hx;
			endcase

	assign bit_last = bit_cnt[3];


	// Data register
	// -------------

	always @(posedge clk)
		if ((state == ST_HIGH_CYCLE) && cyc_now)
			data_reg <= { data_reg[7:0], sda_i };
		else if (stb)
			// Only handle Write / Read. START & STOP is handled in IO mux
			data_reg <= cmd[0] ? { 8'b11111111, ack_in } : { data_in, 1'b1 };


	// IO
	// --

	always @(posedge clk)
		if (rst)
			scl_oe <= 1'b0;
		else if (cyc_now) begin
			if (state == ST_LOWER_SCL)
				scl_oe <= 1'b1;
			else if (state == ST_RISE_SCL)
				scl_oe <= 1'b0;
		end

	always @(posedge clk)
		if (rst)
			sda_oe <= 1'b0;
		else if (cyc_now) begin
			if (~cmd_cur[1]) begin
				if (state == ST_LOW_CYCLE)
					sda_oe <=  cmd_cur[0];
				else if (state == ST_HIGH_CYCLE)
					sda_oe <= ~cmd_cur[0];
			end else begin
				if (state == ST_LOW_CYCLE)
					sda_oe <= ~data_reg[8];
			end
		end


	// User IF
	// -------

	assign data_out = data_reg[8:1];
	assign ack_out  = data_reg[0];

	assign ready = (state == ST_IDLE);

endmodule

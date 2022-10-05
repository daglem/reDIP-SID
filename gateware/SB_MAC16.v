// This module is copied from https://github.com/YosysHQ/yosys/raw/master/techlibs/ice40/cells_sim.v
/* verilator lint_off WIDTH */

//(* abc9_box, lib_whitebox *) // TODO
module SB_MAC16 (
	input CLK, CE,
	input [15:0] C, A, B, D,
	input AHOLD, BHOLD, CHOLD, DHOLD,
	input IRSTTOP, IRSTBOT,
	input ORSTTOP, ORSTBOT,
	input OLOADTOP, OLOADBOT,
	input ADDSUBTOP, ADDSUBBOT,
	input OHOLDTOP, OHOLDBOT,
	input CI, ACCUMCI, SIGNEXTIN,
	output [31:0] O,
	output CO, ACCUMCO, SIGNEXTOUT
);
	parameter [0:0] NEG_TRIGGER = 0;
	parameter [0:0] C_REG = 0;
	parameter [0:0] A_REG = 0;
	parameter [0:0] B_REG = 0;
	parameter [0:0] D_REG = 0;
	parameter [0:0] TOP_8x8_MULT_REG = 0;
	parameter [0:0] BOT_8x8_MULT_REG = 0;
	parameter [0:0] PIPELINE_16x16_MULT_REG1 = 0;
	parameter [0:0] PIPELINE_16x16_MULT_REG2 = 0;
	parameter [1:0] TOPOUTPUT_SELECT = 0;
	parameter [1:0] TOPADDSUB_LOWERINPUT = 0;
	parameter [0:0] TOPADDSUB_UPPERINPUT = 0;
	parameter [1:0] TOPADDSUB_CARRYSELECT = 0;
	parameter [1:0] BOTOUTPUT_SELECT = 0;
	parameter [1:0] BOTADDSUB_LOWERINPUT = 0;
	parameter [0:0] BOTADDSUB_UPPERINPUT = 0;
	parameter [1:0] BOTADDSUB_CARRYSELECT = 0;
	parameter [0:0] MODE_8x8 = 0;
	parameter [0:0] A_SIGNED = 0;
	parameter [0:0] B_SIGNED = 0;

	wire clock = CLK ^ NEG_TRIGGER;

	// internal wires, compare Figure on page 133 of ICE Technology Library 3.0 and Fig 2 on page 2 of Lattice TN1295-DSP
	// http://www.latticesemi.com/~/media/LatticeSemi/Documents/TechnicalBriefs/SBTICETechnologyLibrary201608.pdf
	// https://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/AD/DSPFunctionUsageGuideforICE40Devices.ashx
	wire [15:0] iA, iB, iC, iD;
	wire [15:0] iF, iJ, iK, iG;
	wire [31:0] iL, iH;
	wire [15:0] iW, iX, iP, iQ;
	wire [15:0] iY, iZ, iR, iS;
	wire HCI, LCI, LCO;

	// Regs C and A
	reg [15:0] rC, rA;
	always @(posedge clock, posedge IRSTTOP) begin
		if (IRSTTOP) begin
			rC <= 0;
			rA <= 0;
		end else if (CE) begin
			if (!CHOLD) rC <= C;
			if (!AHOLD) rA <= A;
		end
	end
	assign iC = C_REG ? rC : C;
	assign iA = A_REG ? rA : A;

	// Regs B and D
	reg [15:0] rB, rD;
	always @(posedge clock, posedge IRSTBOT) begin
		if (IRSTBOT) begin
			rB <= 0;
			rD <= 0;
		end else if (CE) begin
			if (!BHOLD) rB <= B;
			if (!DHOLD) rD <= D;
		end
	end
	assign iB = B_REG ? rB : B;
	assign iD = D_REG ? rD : D;

	// Multiplier Stage
	wire [15:0] p_Ah_Bh, p_Al_Bh, p_Ah_Bl, p_Al_Bl;
	wire [15:0] Ah, Al, Bh, Bl;
	assign Ah = {A_SIGNED ? {8{iA[15]}} : 8'b0, iA[15: 8]};
	assign Al = {A_SIGNED && MODE_8x8 ? {8{iA[ 7]}} : 8'b0, iA[ 7: 0]};
	assign Bh = {B_SIGNED ? {8{iB[15]}} : 8'b0, iB[15: 8]};
	assign Bl = {B_SIGNED && MODE_8x8 ? {8{iB[ 7]}} : 8'b0, iB[ 7: 0]};
	assign p_Ah_Bh = Ah * Bh; // F
	assign p_Al_Bh = {8'b0, Al[7:0]} * Bh; // J
	assign p_Ah_Bl = Ah * {8'b0, Bl[7:0]}; // K
	assign p_Al_Bl = Al * Bl; // G

	// Regs F and J
	reg [15:0] rF, rJ;
	always @(posedge clock, posedge IRSTTOP) begin
		if (IRSTTOP) begin
			rF <= 0;
			rJ <= 0;
		end else if (CE) begin
			rF <= p_Ah_Bh;
			if (!MODE_8x8) rJ <= p_Al_Bh;
		end
	end
	assign iF = TOP_8x8_MULT_REG ? rF : p_Ah_Bh;
	assign iJ = PIPELINE_16x16_MULT_REG1 ? rJ : p_Al_Bh;

	// Regs K and G
	reg [15:0] rK, rG;
	always @(posedge clock, posedge IRSTBOT) begin
		if (IRSTBOT) begin
			rK <= 0;
			rG <= 0;
		end else if (CE) begin
			if (!MODE_8x8) rK <= p_Ah_Bl;
			rG <= p_Al_Bl;
		end
	end
	assign iK = PIPELINE_16x16_MULT_REG1 ? rK : p_Ah_Bl;
	assign iG = BOT_8x8_MULT_REG ? rG : p_Al_Bl;

	// Adder Stage
	wire [23:0] iK_e = {A_SIGNED ? {8{iK[15]}} : 8'b0, iK};
	wire [23:0] iJ_e = {B_SIGNED ? {8{iJ[15]}} : 8'b0, iJ};
	assign iL = iG + (iK_e << 8) + (iJ_e << 8) + (iF << 16);

	// Reg H
	reg [31:0] rH;
	always @(posedge clock, posedge IRSTBOT) begin
		if (IRSTBOT) begin
			rH <= 0;
		end else if (CE) begin
			if (!MODE_8x8) rH <= iL;
		end
	end
	assign iH = PIPELINE_16x16_MULT_REG2 ? rH : iL;

	// Hi Output Stage
	wire [15:0] XW, Oh;
	reg [15:0] rQ;
	assign iW = TOPADDSUB_UPPERINPUT ? iC : iQ;
	assign iX = (TOPADDSUB_LOWERINPUT == 0) ? iA : (TOPADDSUB_LOWERINPUT == 1) ? iF : (TOPADDSUB_LOWERINPUT == 2) ? iH[31:16] : {16{iZ[15]}};
	assign {ACCUMCO, XW} = iX + (iW ^ {16{ADDSUBTOP}}) + HCI;
	assign CO = ACCUMCO ^ ADDSUBTOP;
	assign iP = OLOADTOP ? iC : XW ^ {16{ADDSUBTOP}};
	always @(posedge clock, posedge ORSTTOP) begin
		if (ORSTTOP) begin
			rQ <= 0;
		end else if (CE) begin
			if (!OHOLDTOP) rQ <= iP;
		end
	end
	assign iQ = rQ;
	assign Oh = (TOPOUTPUT_SELECT == 0) ? iP : (TOPOUTPUT_SELECT == 1) ? iQ : (TOPOUTPUT_SELECT == 2) ? iF : iH[31:16];
	assign HCI = (TOPADDSUB_CARRYSELECT == 0) ? 1'b0 : (TOPADDSUB_CARRYSELECT == 1) ? 1'b1 : (TOPADDSUB_CARRYSELECT == 2) ? LCO : LCO ^ ADDSUBBOT;
	assign SIGNEXTOUT = iX[15];

	// Lo Output Stage
	wire [15:0] YZ, Ol;
	reg [15:0] rS;
	assign iY = BOTADDSUB_UPPERINPUT ? iD : iS;
	assign iZ = (BOTADDSUB_LOWERINPUT == 0) ? iB : (BOTADDSUB_LOWERINPUT == 1) ? iG : (BOTADDSUB_LOWERINPUT == 2) ? iH[15:0] : {16{SIGNEXTIN}};
	assign {LCO, YZ} = iZ + (iY ^ {16{ADDSUBBOT}}) + LCI;
	assign iR = OLOADBOT ? iD : YZ ^ {16{ADDSUBBOT}};
	always @(posedge clock, posedge ORSTBOT) begin
		if (ORSTBOT) begin
			rS <= 0;
		end else if (CE) begin
			if (!OHOLDBOT) rS <= iR;
		end
	end
	assign iS = rS;
	assign Ol = (BOTOUTPUT_SELECT == 0) ? iR : (BOTOUTPUT_SELECT == 1) ? iS : (BOTOUTPUT_SELECT == 2) ? iG : iH[15:0];
	assign LCI = (BOTADDSUB_CARRYSELECT == 0) ? 1'b0 : (BOTADDSUB_CARRYSELECT == 1) ? 1'b1 : (BOTADDSUB_CARRYSELECT == 2) ? ACCUMCI : CI;
	assign O = {Oh, Ol};
endmodule

/* verilator lint_on WIDTH */

TOP = redip_sid
PKG = sid_pkg.sv
FUN = sid_waveform_PST.svh \
	sid_waveform__ST.svh
MOD = $(TOP).sv \
	ice40_init.sv \
	i2c_master.v \
	sgtl5000_init.v \
	i2s_dsp_mode.sv \
	muladd.sv \
	sid_io.sv \
	sid_pot.sv \
	sid_waveform.sv \
	sid_envelope.sv \
	sid_dac.sv \
	sid_voice.sv \
	sid_filter.sv \
	sid_core.sv \
	sid_api.sv \
	muacm.v
SRC = $(PKG) $(FUN) $(MOD)
#FLG = -DMUACM

all: $(TOP).bin

$(TOP).json: $(SRC) Makefile
	yosys -p 'read_verilog -sv $(FLG) $(PKG) $(MOD); synth_ice40 -abc9 -device u -dff -top $(TOP) -json $@'

%.asc: %.json %.pcf
	nextpnr-ice40 --up5k --package sg48 --freq 24 --json $*.json --pcf $*.pcf --asc $@

%.bin: %.asc
	icepack $< $@

prog: $(TOP).bin
	dfu-util -a 0 -D $< -R

sim:
	verilator --Mdir sim_trace --timescale "1ns / 1ns" --trace-fst --trace-structs --trace-underscore --clk clk --cc -O3 --x-assign fast --x-initial fast --noassert --exe --build sid_pkg.sv sid_api.sv --top sid_api sid_api_sim.cpp
	verilator --Mdir sim_audio --clk clk --cc -O3 --x-assign fast --x-initial fast --noassert --exe --build sid_pkg.sv sid_api.sv --top sid_api sid_api_sim.cpp

clean:
	rm -rf $(TOP).json $(TOP).asc $(TOP).bin sim_trace sim_audio

.PHONY: all prog sim clean

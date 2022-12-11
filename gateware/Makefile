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
	sid_api.sv

MUACM ?= 0
ifeq "$(MUACM)" "1"
MOD += muacm.v
FLG = -DMUACM
endif

SRC = $(PKG) $(FUN) $(MOD)

all: $(TOP).bin

SV2V ?= 0
ifeq "$(SV2V)" "1"
# For Yosys < 0.24
$(TOP).json: $(TOP).v
	yosys -p 'read_verilog -sv $<; synth_ice40 -abc9 -device u -dff -top $(TOP) -json $@'

$(TOP).v: $(SRC) Makefile
	sv2v -E always -E assert -E logic -E unbasedunsized -w $@ -DYOSYS $(FLG) $(PKG) $(MOD)
else
# For Yosys >= 0.24
$(TOP).json: $(SRC) Makefile
	yosys -p 'read_verilog -sv $(FLG) $(PKG) $(MOD); synth_ice40 -abc9 -device u -dff -top $(TOP) -json $@'
endif

%.asc: %.json %.pcf
	nextpnr-ice40 --up5k --package sg48 --freq 24 --json $*.json --pcf $*.pcf --asc $@

%.bin: %.asc
	icepack $< $@

prog: $(TOP).bin
	dfu-util -d 1d50:6159,:6156 -a 0 -D $< -R

sim:
	verilator --Mdir sim_trace --timescale "1ns / 1ns" --trace-fst --trace-structs --trace-underscore --clk clk --cc -O3 -CFLAGS "-Wall" --x-assign fast --x-initial fast --noassert --exe --build sid_pkg.sv sid_api.sv --top sid_api sid_api_sim.cpp
	verilator --Mdir sim_audio --clk clk --cc -O3 -CFLAGS "-Wall" --x-assign fast --x-initial fast --noassert --exe --build sid_pkg.sv sid_api.sv --top sid_api sid_api_sim.cpp

clean:
	rm -rf $(TOP).v $(TOP).json $(TOP).asc $(TOP).bin sim_trace sim_audio

.PHONY: all prog sim clean

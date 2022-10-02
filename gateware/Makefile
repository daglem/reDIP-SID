TOP = redip_sid
PKG = sid_pkg.sv
FUN = sid_waveform_PST.sv \
	sid_waveform__ST.sv
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

clean:
	rm -f $(TOP).json $(TOP).asc $(TOP).bin

.PHONY: all clean prog

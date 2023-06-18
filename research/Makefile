%.prg: %.a65
	xa -o $@ $<

all: combsample.d64

combsample.d64: combsample.prg
	c1541 -format $(basename $<),81 d64 $@
	c1541 -attach $@ -write $<

extract: combrun.d64
	c1541 -attach $< -extract
	dd bs=1 skip=2 if=6581wf30.dat > wave6581__ST.dat
	dd bs=1 skip=2 if=6581wf50.dat > wave6581_P_T.dat
	dd bs=1 skip=2 if=6581wf60.dat > wave6581_PS_.dat
	dd bs=1 skip=2 if=6581wf70.dat > wave6581_PST.dat

clean:
	rm combsample.d64 combsample.prg

.PHONY: all extract clean

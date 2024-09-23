%.prg: %.a65
	xa -o $@ $<

all: combsample.d64

combsample.d64: combsample.prg
	c1541 -format $(basename $<),81 d64 $@
	c1541 -attach $@ -write $<

extract: combrun.d64
	c1541 -attach $< -extract

clean:
	rm combsample.d64 combsample.prg

.PHONY: all extract clean

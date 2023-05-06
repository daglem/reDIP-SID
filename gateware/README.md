# reDIP SID Gateware

## Description

The reDIP SID FPGA gateware provides high quality SID emulation for the
[reDIP SID](https://github.com/daglem/reDIP-SID) hardware.

The gateware owes its existence to [reSID](https://github.com/daglem/reSID),
the [SID internals documentation](https://github.com/libsidplayfp/SID_schematics/wiki)
by Leandro "drfiemost" Nini and Dieter "ttlworks" Mueller, auxiliary code and
guidance from Sylvain "tnt" Munaut, and a lot of work :-)

The gateware implements cycle accurate emulation of the SID digital logic, and
quite a few SID analog peculiarities. In order to make reasonably accurate
emulation of some of these fit in the iCE40UP5K FPGA, a few novelties have been
invented:

* Combined sawtooth/triangle and pulse/sawtooth/triangle waveforms without lookup tables.
* MOS6581 waveform, envelope, and filter cutoff DAC emulation without lookup tables.
* Parameterizable filter cutoff curves requiring only a single 16kbit lookup table.

Furthermore, FPGA resources are shared by [pipelining](Pipelining.md) and
time-division multiplexing. This is in contrast to the real SID chip, where
there was sufficient die area to simply repeat functional modules for each
voice.

By default, a single MOS6581 chip is emulated. The gateware also implements
MOS8580 emulation and simultaneous emulation of two chips, however runtime
configuration of these features are not yet implemented.

## Installation

The gateware may be installed on the reDIP SID hardware via USB using
[dfu-util](https://dfu-util.sourceforge.net/):

* Connect a USB cable to enter the bootloader. The green LED should start blinking.
* Install the gateware with `./flash.sh` (Linux / Mac OS) or `flash.bat` (Windows).
* Disconnect USB. If the board is still powered, then press the user button to boot.

Depending on the previously installed gateware, in order to enter the
bootloader it may be required to keep the user button pressed while powering up
the board.

## License

This gateware is part of reDIP SID, a MOS 6581/8580 SID FPGA emulation platform.
Copyright (C) 2022  Dag Lem \<resid@nimrod.no\>

The source describes Open Hardware and is licensed under the CERN-OHL-S v2.

You may redistribute and modify the source and make products using it under
the terms of the [CERN-OHL-S v2](https://ohwr.org/cern_ohl_s_v2.txt).

This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.

Source location: [https://github.com/daglem/reDIP-SID](https://github.com/daglem/reDIP-SID)

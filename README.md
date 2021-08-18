# reDIP SID

## MOS 6581/8580 SID FPGA emulation platform
![Board](documentation/reDIP-SID-board.png)

## Overview
The reDIP SID is an open source hardware development board which combines the following in a DIP-28 size package:

* Lattice iCE40UP5K FPGA
* NXP SGTL5000 Audio Codec
* 128Mbit FLASH
* 64Mbit PSRAM
* User LED
* Push button
* USB-C receptacle for power and FPGA Full Speed USB
* 5V tolerant I/O

The reDIP SID is a leaner relative of the [reDIP SX](https://github.com/daglem/reDIP-SX),
more squarely focused on providing an open source hardware platform for MOS 6581/8580 SID emulation.

The reDIP SID also aims to be a good no-frills generic choice for FPGA projects which may find use for audio and/or 5V tolerant I/O.

## General use

### I/O interfaces

#### Header pins:

* 9V/12V input (for SID audio output DC bias)
* 5V input
* 19 FPGA GPIO
* 3 FPGA current drive / open-drain I/O
* 5 audio pins (stereo line input, stereo line output, SID audio output)
* GND

All FPGA I/O is 5V tolerant, and can drive 5V TTL. JP1 can be shorted to make the 5V input pin bidirectional, e.g. to power 5V TTL devices.

Note that the line inputs are not AC coupled - AC coupling must be externally added for audio applications.
Without external AC coupling, the line inputs can be used as generic ADCs.

#### SPI / Programming header:

A separate header footprint is provided for (Q)SPI peripherals / flash programming, with pinout borrowed from the [iCEBreaker Bitsy](https://github.com/icebreaker-fpga/icebreaker).

The header provides a 3.3V output, which may be used to power external devices.

#### USB-C functions:

* 5V power
* FPGA Full Speed USB

## MOS 6581/8580 SID compatibility

The board is fully pin compatible with the venerable MOS 6581/8580 SID sound chip.

For anyone wanting to experiment with a SID setup, while avoiding damaged sockets and release of magic smoke:

* Make sure that JP1 is open
* Use a 28 pin stamped DIP socket as an adapter, to avoid damage to the C64 SID socket. Do not attempt to mount the board directly in a SID socket!

## Board Front
![Board Front](documentation/reDIP-SID-board-front.png)

## Board Back
![Board Back](documentation/reDIP-SID-board-back.png)

# Pipelining

In order to make accurate SID emulation fit on a Lattice iCE40UP5K FPGA, it is
necessary to use pipelining and time-division multiplexing of resources.

Two synchronized pipelines are implemented; the voice pipeline and the filter
pipeline. The combined pipelines have a total of 14 pipeline stages. Two SID
chips are emulated, with audio outputs ready at cycle 15 and 20, respectively.

## Voice pipeline

The voice pipeline combines several SID modules, and produces one voice output
per cycle for two SID chips. The table below depicts the data path for SID 1,
voice 1.

| Stages | Module             | Cycle 1        | Cycle 2        | Cycle 3        | Cycle 4       | Cycle 5         | Cycle 6           | Cycle 7               | Cycle 8     |
|  ----: | -------------------| -------------- |--------------- | -------------- | --------------| ----------------| ----------------- | --------------------- | ----------- |
|  1 - 3 | Control registers  | Write voice 1  | Write voice 2  | Write voice 3  |               |                 |                   |                       |             |
|  2 - 4 | Oscillator         |                | Update osc. 1  | Update osc. 2  | Sync osc. 1-3 |                 |                   |                       |             |
|  2 - 7 | Waveform generator |                | Buffer pulse 1 | Buffer pulse 2 | Update noise  | Waveform select | Update waveform 0 |                       |             |
|  7 - 8 | Envelope generator |                |                |                |               |                 | Update counters   |                       |             |
|  7 - 8 | Voice DCA          |                |                |                |               |                 | Buffer wav/env    | DCA = wav*env         |             |
|        |                    |                |                |                |               |                 |                   |                       | Voice 1 out |

The voice pipeline starts on the falling edge of the ϕ₂ clock, brought into the
FPGA clock domain by a two-stage synchronizer.

As can be seen from the table above, output for voice 1 is ready on cycle
8. Outputs from the waveform and envelope generators are ready on cycle 6, so
data for the read-only registers OSC3 and ENV3 are also ready on cycle 8 (6 +
2).

The oscillator module adds a latency of two cycles; this is required for
synchronization of oscillators.

In order to meet MOS6510 bus timing, writes to the filter control registers for
SID 1 and 2 are included in the voice pipeline at cycle 1 and 4, respectively.
This is not shown in the table above.

## Filter pipeline

A separate pipeline is used to update filter state variables and produce audio
outputs for the two SID chips. The table below depicts the data path for the
audio output of SID 1.

| Stages | Description             | Cycle 1        | Cycle 2  | Cycle 3  | Cycle 4    | Cycle 5            | Cycle 6               | Cycle 7          | Cycle 8       | Cycle 9     |
| -----: | ----------------------- | -------------- | ---------| ---------| ---------- | -------------------| --------------------- | ---------------- | ------------- | ----------- |
|  1 - 5 | Direct path mux / sum   | vd = 0         | vd += v1 | vd += v2 | vd += v3   | vd += extin        | (vd2 = 0, buffer vd1) |                  |               |             |
|  1 - 5 | Filter input mux / sum  | vi = 0         | vi += v1 | vi += v2 | vi += v3   | vi += extin        | (vi2 = 0)             |                  |               |             |
|  2 - 4 | Computation of factors  |                | 1/Q, fc  | w0       | w0         |                    |                       |                  |               |             |
|  4 - 8 | Multiply-add            |                |          |          | 0 - w0*vbp | 0 - w0*vhp         | -(vlp + vi) + 1/Q*vbp |                  | vol*(vd + vf) |             |
|  5 - 7 | Filter state update     |                |          |          |            | vlp = vlp + muladd | vbp = vbp + muladd    | vhp = muladd     |               |             |
|  4 - 7 | Filter path mux / sum   |                |          |          | vf = 0     | vf += vlp          | vf += vbp             | vf += vhp        |               |             |
|        |                         |                |          |          |            |                    |                       |                  |               | Audio 1 out |

The filter pipeline starts at voice pipeline cycle 7. At filter pipeline cycles
4 and 5, idle cycles are injected in the voice pipeline (at cycle 10). As can
be seen from the table above, filter pipeline cycles 5 and 6 are used to mux
and sum in SID 1 EXT IN, and to initialize voice accumulators for SID 2.

## Timing for register read / write

Read / write of SID registers is done while the ϕ₂ clock is high.

In the following we will assume that we have a minimum of 20 FPGA cycles
available between each falling edge of ϕ₂. At a 24MHz FPGA clock, this
corresponds to a 1.2MHz clock, or a 1.02MHz NTSC C64 clock with a cycle to
cycle (C2C) jitter peak value of 147ns, or 15%.

On writes, the MOS6510 holds address and data signals for a minimum of 10ns
after the falling edge of ϕ₂ (THA and THR in the datasheet). The reDIP SID
gateware takes advantage of this by using iCEGate™ latches to freeze the
signals for as long as ϕ₂ is low. According to the MOS6510 datasheet, at a 1MHz
clock, the maximum pulse width of ϕ₂ is 510ns. Assuming that the corresponding
minimum period between the falling and rising edge of ϕ₂ is then in the
ballpark of 490ns, we have 20*490/1000 = 9.8 FPGA cycles available for
writes. Accounting for two cycles spent to bring ϕ₂ into the FPGA clock domain,
we are still within margin as the last SID register is written at cycle 6 in
the voice pipeline.

For reads, the MOS6510 datasheet specifies a minimum Data Stability Time Period
(TDSU) of 100ns, i.e. data must be output on the data bus at least 100ns before
the falling edge of ϕ₂. SID 1 OSC3/ENV3 are ready on cycle 8 in the voice
pipeline, i.e. SID 2 OSC3/ENV3 are ready on cycle 8 + 3 = 11, just after the
voice pipeline is paused for two cycles. Accounting for another two cycles
spent to bring ϕ₂ into the FPGA clock domain, a cycle to register OSC3/ENV3,
and a cycle for registered pin outputs, we get a minimum TDSU of (20 - 11 - 2 -
2 - 1 - 1)/24Mhz = 125ns, which is within specification.

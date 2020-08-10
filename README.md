# ics-adpcm

This is a programmable IMA-ADPCM decoder / mixer. It can be configured with up to 16 ADPCM channels (or "voices") with independent volumes and playback rates. Sample data is loaded from a shared 16MByte address space. The output mix is signed 16bit stereo PCM.

The aim is to minimize resource use and support slower, low power devices such as the Lattice iCE40 UP5K (logic cost is about 1000LCs, or less than 20%).

## Design goals

* Minimize resource use
     * Register files are implemented in a way that can be inferred as block RAMs instead of using FFs. On iCE40,2x 512byte RAMs are used.
     * Only one multiplier is used. On iCE40 UP5K, 1 "DSP Block" is used.
* Favor fmax over performance
     * One target for this project is > 35MHz on an UP5K
     * Other device shouldn't have much trouble meeting timing at >= 100MHz

## Features

* Playback of up to 16 concurrent, independently configurable ADPCM channels.
* ADPCM data loaded from a shared 16MByte address space using a ready/valid interface to also support slower memories i.e. flash.
* Per-channel signed 8bit stereo volume control.
* Per-channel Q4.12 16bit playback rate. This gives a maximum playback rate of approx. 16.0 the output rate and a minimum of (1/4096 = 0.0002).

## Limitations

* No hard filters / EG / interpolators. The channel registers can be modified during playback which allows an external gateware / soft CPU to emulate some of these effects.
* ADPCM decoding is always enabled. LPCM for cleaner single-cycle waveforms may be an optional extra later. High playback rates help mask the shortcomings of ADPCM here but isn't ideal.
* ADPCM start/end/loop addresses must be 1kbyte aligned.

## Prerequisites

* [yosys](https://github.com/YosysHQ/yosys)
* [nextpnr-ecp5](https://github.com/YosysHQ/nextpnr) if the included [/demo](/demo) is to be used
* [Verilator](https://www.veripool.org/wiki/verilator) if the included [/sim](/sim) tests are to be run
* [SymbiYosys](https://github.com/YosysHQ/SymbiYosys) if the included [/formal](/formal) tests are to be run

## ADPCM encoding

The IMA-ADPCM data used is compatible with what ffmpeg generates with the following command:

```
ffmpeg -i input.wav -ac 1 -f s16le -acodec adpcm_ima_wav output.adpcm
```

ffmpeg can be used to encode samples for playback but depending on the source material, a lookahead encoder such as [adpcm-xq](https://github.com/dbry/adpcm-xq) may produce better results. The expected header, which ffmpeg creates by default, is:

* 2 bytes: Initial predictor
* 2 bytes: Initial step index (high byte ignored)


The block size in 4bit nybbles can be configured using the `ADPCM_BLOCK_SIZE` but the default is to use what the above encoders (and many others) default to, which is 1kbyte.

## Usage

### PCM memory

IMA-ADPCM encoded data is read using the ports prefixed with `pcm_`. `pcm_read_address` and `pcm_address_valid` are used for reading and the module will wait indefinitely for `pcm_data_ready` to be asserted with valid data on `pcm_read_data`. The address is 16bit, not 8bit, the LSB shouldn't be disregarded.

### Channel registers

Channels are configured using the ports prefixed with `ch_write_`. During a write, the inputs must be held stable until `ch_write_ready` is asserted. `ch_write_ready` is asserted for one cycle only. Writes take at least 2 cycles but potentially more if there is contention during a write. `ch_write_byte_mask` can be used to do 8bit writes on the lower/upper bits of the `VOLUMES` register but can be set to `2'b11` if this isn't needed.

Each channel has 8x 16bit registers arranged in an array-of-structs layout in a register file. Only 6 of the 8 regsiters of each channel are used but the 2 unused ones remain as padding.

The start address for each channel is `(channel_id * 8 + offset)`.

`START`, `END` and `LOOP` are effectively 1kbyte block indexes since all addresses are 1kbyte aligned. All addresses must point to the start of an ADPCM block header.

| Offset | Name | Width | Description
| ------ |------|-------| -----------
| 0 | `START` | 14 | PCM memory start address
| 1 | `FLAGS` | 1 | `FLAGS[0]`: Enables automatic looping once `END` is reached. Playback ends otherwise.
| 2 | `END`| 14 | PCM memory end address. This isn't inclusive so the block this points to isn't played, so this should be set to address of (final block + 1). Playback stops unless `FLAGS[0]` is set to enable automatic looping.
| 3 | `LOOP` | 14 | PCM memory loop address. If `FLAGS[0]` is set and `END` is reached, playback restarts from this address. This value must be `>= START && < END`.
| 4 | `VOLUMES` | 16 | 8bit signed volumes. High 8bits is R, low 8bits is L.
| 5 | `PITCH` | 16 | Playback rate. Q4.12 fixed point value, so `0x1000` is a playback rate of 1.0. If the output rate is 44.1KHz, `PITCH = 0x800` would play the sample at (44.1KHz / 2 = 22.05KHz).

### Global registers

Channels are started and stopped using a separate interface using ports prefixed with `gb_write_`. There is 1 bit per configured channel, so the width of these registers depends on the value of the `CHANNELS` parameter. These registers serve as the key-on / key-off control.

| Offset | Name | Description
| ------ | ---- | -----------
| 0 | `PLAY` | Channels with a corresponding bit set to 1 will (re)start playback. All 0 bits are ignored.
| 1 | `STOP` | Channels with a corresponding bit set to 1 will stop playback. All 0 bits are ignored.

### Audio output

Signed 16bit stereo output is updated once per `OUTPUT_INTERVAL` cycles. `output_valid` is asserted for 1 cycle at which point `output_l` / `output_r` have valid data to be registered. The outputs are undefined at all other times.
 
## Tests

* The [/sim](/sim) directory contains Verilator-driven tests that assert that the ADPCM decoding and PCM output work as exepcted for different test cases
* The [/formal](/formal) directory contains SymbiYosys-driven tests for parts of the control interface. The PCM decoding / mixing / output is ignored which is covered by the above tests instead

## Demo

The [/demo](/demo) directory contains a ULX3S project that allows the user to play different notes with a switchable sample bank. It also includes a simple tracker for automatic playback.
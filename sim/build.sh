#!/bin/bash

set -e

verilator -cc ../ics_adpcm.v \
	-GADPCM_STEP_LUT_PATH=\"../adpcm_step_lut.hex\" \
	-GCLOCK_DIVISOR=256 \
	-O3 -Wall -Wno-fatal --exe \
	-CFLAGS "-std=c++14 -O3 -I../tinywav/ -I../json" \
	main.cpp Serialization.cpp tinywav/tinywav.cpp

make -C obj_dir/ -f Vics_adpcm.mk 


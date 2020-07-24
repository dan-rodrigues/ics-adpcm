#!/bin/bash

set -e

verilator -cc ics_adpcm.v -GCLOCK_DIVISOR=256 -O3 -Wno-fatal --exe \
	--trace \
	-CFLAGS "-std=c++14 -O3 -I../tinywav/" \
	sim/main.cpp sim/Serialization.cpp tinywav/tinywav.cpp

make -C obj_dir/ -f Vics_adpcm.mk 


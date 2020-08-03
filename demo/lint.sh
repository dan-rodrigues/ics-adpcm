#!/bin/sh

verilator -cc --Wall --lint-only adpcm_demo_top.v ../ics_adpcm.v


# The only supported board at the moment is the ULX3S
# Others may be added later

ULX3S_PREFIX = ulx3s

ECP5_PACKAGE = CABGA381
ECP5_SIZE = 85

###

TOP = adpcm_demo_top

ULX3S_PIN_DEF = ulx3s_v20.lpf

SAMPLES := samples/piano.hex samples/square.hex samples/steel_drum.hex
SOURCES := ../ics_adpcm.v \
	$(TOP).v \
	pll.v \
	dacpwm.v \
	debouncer.v \
	pitch_adjuster.v \
	tracker.v \
	spdif_tx.v \
	spi_midi_control.v \
	midi_encoder.v \
	midi_decoder.v \
	midi_status_input_buffer.v \

### Supported board targets:

ulx3s: ulx3s.bit

.PHONY: ulx3s

###

define synth
	yosys $(YOSYS_DEFINE_ARGS) -p \
		'$(YOSYS_SYNTH_COMMAND) $(YOSYS_SYNTH_FLAGS) $1' \
		$(SOURCES)
endef

ulx3s.json: YOSYS_SYNTH_COMMAND = synth_ecp5
ulx3s.json: YOSYS_SYNTH_FLAGS = -top $(TOP)

YOSYS_DEFINE_ARGS := -f 'verilog -DADPCM_STEP_LUT_PATH="../adpcm_step_lut.hex"'

%.json: $(SOURCES) $(SAMPLES)
	$(call synth, -json $@)

clean:
	rm -f $(ULX3S_PREFIX).config $(ULX3S_PREFIX).bit $(ULX3S_PREFIX).json

### ECP5:

%.config: $(ULX3S_PIN_DEF) %.json
	nextpnr-ecp5 --package $(ECP5_PACKAGE) --$(ECP5_SIZE)k --json $(filter-out $<,$^) --placer heap --lpf $< --textcfg $@ --seed 0

%.bit: %.config
	ecppack --input $< --bit $@

ulx3s_prog: $(ULX3S_PREFIX).bit
	fujprog $<

ulx3s_flash: $(ULX3S_PREFIX).bit
	fujprog -j flash $<

.SECONDARY:
.PHONY: ulx3s_prog ulx3s_flash clean


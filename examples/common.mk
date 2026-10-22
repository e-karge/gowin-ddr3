# Build rules of the examples, included by their Makefiles after BOARD,
# DEVICE, FAMILY, SYNTH_FAMILY and TARGET.
#   make          bitstream build/top.fs
#   make flash    load it with openFPGALoader
# The tools come from PATH; NEXTPNR_FLAGS takes e.g. --chipdb.
YOSYS ?= yosys
NEXTPNR ?= nextpnr-himbaechel
GOWIN_PACK ?= gowin_pack
OPENFPGALOADER ?= openFPGALoader
NEXTPNR_FLAGS ?=
DEFINES ?=
BUILD ?= build

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
EXAMPLES := $(ROOT)/examples
CST := $(EXAMPLES)/$(BOARD).cst

all: $(BUILD)/top.fs

$(BUILD)/synth.json: top.sv $(EXAMPLES)/ddr3_test.sv $(wildcard $(ROOT)/ddr3/*.sv $(ROOT)/ddr3/clk/*.sv) | $(BUILD)/
	$(YOSYS) -q $(DEFINES) -p "read -incdir $(ROOT); read -incdir $(EXAMPLES); read_verilog -sv top.sv; hierarchy -top top; synth_gowin -family $(SYNTH_FAMILY) -json $@"

$(BUILD)/pnr.json: $(BUILD)/synth.json $(CST)
	$(NEXTPNR) -q --json $< --write $@ --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST) $(NEXTPNR_FLAGS)

$(BUILD)/top.fs: $(BUILD)/pnr.json
	$(GOWIN_PACK) -d $(FAMILY) -o $@ $<

flash: $(BUILD)/top.fs
	$(OPENFPGALOADER) -b $(TARGET) $<

$(BUILD)/:
	mkdir -p $@

clean:
	rm -rf build

.PHONY: all flash clean

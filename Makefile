# tensor-mac: `make` runs everything. Targets: lint sim cocotb formal clean
RTL    := $(wildcard rtl/*.sv)
TOPS   := mac pe systolic_array
PYTHON ?= python3

.PHONY: all lint sim cocotb formal clean
all: lint sim cocotb formal

lint:
	@for t in $(TOPS); do verilator --lint-only -Wall --top-module $$t $(RTL) || exit 1; done
	@echo "lint clean: $(TOPS)"

sim:
	@mkdir -p sim
	iverilog -g2012 -o sim/mac.vvp $(RTL) tb/mac_tb.sv
	vvp -n sim/mac.vvp

cocotb:
	@for t in $(TOPS); do (cd dv && MODULE=test_$$t TOPLEVEL=$$t $(PYTHON) sim.py) || exit 1; done

formal:
	cd formal && sby -f -d out/mac mac.sby

clean:
	rm -rf sim dv/sim_build dv/__pycache__ dv/results.xml formal/out

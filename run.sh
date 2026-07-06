#!/usr/bin/env bash
# Project runner (WSL/Linux). One entry point for every flow in this repo.
# Usage:
#   ./run.sh lint   <top>            Verilator lint, <top> = module name in rtl/
#   ./run.sh sim    <top> [-wave]    lint + iverilog (rtl/*.sv + tb/<top>_tb.sv) + vvp
#   ./run.sh cocotb <block>          run dv/test_<block>.py against rtl toplevel <block>
#   ./run.sh formal <job>            SymbiYosys proof of formal/<job>.sby
# Examples:  ./run.sh sim mac -wave      ./run.sh cocotb systolic_array
set -u
cd "$(dirname "$0")" || exit 1

# cocotb venv (Python 3.13 + cocotb 2.x + numpy). Override with COCOTB_VENV if yours differs.
VENV="${COCOTB_VENV:-$HOME/.venvs/cocotb}"

usage() { grep '^#   ' "$0" | sed 's/^#  //'; exit 1; }

have_rtl() { ls rtl/*.sv >/dev/null 2>&1; }

cmd="${1:-}"
arg="${2:-}"
if [ -z "$cmd" ] || [ -z "$arg" ]; then usage; fi

case "$cmd" in
    lint)
        have_rtl || { echo "rtl/ has no .sv files yet"; exit 1; }
        verilator --lint-only -Wall --top-module "$arg" rtl/*.sv && echo "lint clean"
        ;;
    sim)
        have_rtl || { echo "rtl/ has no .sv files yet"; exit 1; }
        [ -f "tb/${arg}_tb.sv" ] || { echo "No tb/${arg}_tb.sv"; exit 1; }
        mkdir -p sim
        echo "== Lint (RTL only) =="
        if verilator --lint-only -Wall --top-module "$arg" rtl/*.sv; then
            echo "  lint clean"
        else
            echo "  lint found issues above - fix before calling the block done"
        fi
        echo "== Compile =="
        iverilog -g2012 -o "sim/$arg.vvp" rtl/*.sv "tb/${arg}_tb.sv" || { echo "Compile failed."; exit 1; }
        echo "== Simulate =="
        vvp "sim/$arg.vvp"
        if [ "${3:-}" = "-wave" ]; then
            gtkwave "sim/$arg.vcd" >/dev/null 2>&1 &
        fi
        ;;
    cocotb)
        if [ -x "$VENV/bin/python" ]; then
            # shellcheck disable=SC1091
            source "$VENV/bin/activate"
        fi
        ( cd dv && MODULE="test_$arg" TOPLEVEL="$arg" python3 sim.py )
        ;;
    formal)
        [ -f "formal/$arg.sby" ] || { echo "No formal/$arg.sby"; exit 1; }
        ( cd formal && sby -f -d "out/$arg" "$arg.sby" )
        ;;
    *)
        usage
        ;;
esac

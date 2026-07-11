#!/usr/bin/env bash
# Project runner. One entry point for every flow in this repo.
# Identical usage on macOS, Linux, and Windows (WSL or Git Bash).
# Usage:
#   ./run.sh lint   <top>            Verilator lint, <top> = module name in rtl/
#   ./run.sh sim    <top> [-wave]    lint + iverilog (rtl/*.sv + tb/<top>_tb.sv) + vvp
#   ./run.sh cocotb <block>          run dv/test_<block>.py against rtl toplevel <block>
#   ./run.sh formal <job>            SymbiYosys proof of formal/<job>.sby
#   ./run.sh doctor                  check the toolchain is installed
# Examples:  ./run.sh sim mac -wave      ./run.sh cocotb systolic_array
set -u
cd "$(dirname "$0")" || exit 1

# ---- host detection (keeps the rest of the script tool-name/path agnostic) --
case "$(uname -s 2>/dev/null)" in
    Darwin)               OS=mac ;;
    Linux)                OS=linux ;;    # includes WSL
    MINGW*|MSYS*|CYGWIN*) OS=windows ;;  # Git Bash / MSYS2 on native Windows
    *)                    OS=unknown ;;
esac

# cocotb venv (Python 3.13 + cocotb 2.x + numpy). Override with COCOTB_VENV.
VENV="${COCOTB_VENV:-$HOME/.venvs/cocotb}"

usage() { grep '^#   ' "$0" | sed 's/^#  //'; exit 1; }

have_rtl() { ls rtl/*.sv >/dev/null 2>&1; }

# require <cmd> <human-hint> — fail early with an OS-appropriate fix.
require() {
    command -v "$1" >/dev/null 2>&1 && return 0
    echo "error: '$1' not found on PATH ($2)." >&2
    case "$OS" in
        mac)   echo "  run ./setup-mac.sh to install the toolchain." >&2 ;;
        *)     echo "  see README.md (Windows/WSL/Linux setup) to install it." >&2 ;;
    esac
    return 1
}

# Activate the cocotb venv across layouts: POSIX venv uses bin/, a Windows
# (native) venv uses Scripts/. Resolve a python that has cocotb either way.
activate_venv() {
    if   [ -x "$VENV/bin/python" ];         then . "$VENV/bin/activate"
    elif [ -x "$VENV/Scripts/python.exe" ]; then . "$VENV/Scripts/activate"
    else
        echo "note: no cocotb venv at $VENV — using system python." >&2
        [ "$OS" = mac ] && echo "      run ./setup-mac.sh to create it." >&2
    fi
}
python_bin() { command -v python3 >/dev/null 2>&1 && echo python3 || echo python; }

# Open a waveform without caring how gtkwave is packaged on this OS.
open_wave() {
    local vcd="$1"
    if command -v gtkwave >/dev/null 2>&1; then
        gtkwave "$vcd" >/dev/null 2>&1 &
    elif [ "$OS" = mac ] && [ -x "/Applications/gtkwave.app/Contents/Resources/bin/gtkwave" ]; then
        "/Applications/gtkwave.app/Contents/Resources/bin/gtkwave" "$vcd" >/dev/null 2>&1 &
    elif [ "$OS" = mac ] && [ -d "/Applications/gtkwave.app" ]; then
        open -a gtkwave "$vcd"
    else
        echo "gtkwave not found — VCD written to $vcd (open it manually)."
    fi
}

cmd="${1:-}"
arg="${2:-}"

# doctor takes no <top>; everything else needs one.
if [ "$cmd" = doctor ]; then
    echo "host: $OS    venv: $VENV"
    rc=0
    for t in iverilog vvp verilator yosys z3 sby; do
        if command -v "$t" >/dev/null 2>&1; then printf '  ok  %-10s %s\n' "$t" "$(command -v "$t")"
        else printf '  --  %-10s missing\n' "$t"; rc=1; fi
    done
    if command -v gtkwave >/dev/null 2>&1 || [ -d /Applications/gtkwave.app ]; then
        printf '  ok  %-10s %s\n' gtkwave "$(command -v gtkwave || echo /Applications/gtkwave.app)"
    else printf '  --  %-10s missing\n' gtkwave; fi
    if [ -x "$VENV/bin/python" ] || [ -x "$VENV/Scripts/python.exe" ]; then
        printf '  ok  %-10s %s\n' venv "$VENV"
    else printf '  --  %-10s missing (run ./setup-mac.sh on macOS)\n' venv; rc=1; fi
    [ $rc -eq 0 ] && echo "toolchain looks good." || echo "some tools are missing (see above)."
    exit $rc
fi

if [ -z "$cmd" ] || [ -z "$arg" ]; then usage; fi

case "$cmd" in
    lint)
        require verilator "RTL lint" || exit 1
        have_rtl || { echo "rtl/ has no .sv files yet"; exit 1; }
        verilator --lint-only -Wall --top-module "$arg" rtl/*.sv && echo "lint clean"
        ;;
    sim)
        require iverilog "SystemVerilog sim" || exit 1
        have_rtl || { echo "rtl/ has no .sv files yet"; exit 1; }
        [ -f "tb/${arg}_tb.sv" ] || { echo "No tb/${arg}_tb.sv"; exit 1; }
        mkdir -p sim
        echo "== Lint (RTL only) =="
        if command -v verilator >/dev/null 2>&1; then
            if verilator --lint-only -Wall --top-module "$arg" rtl/*.sv; then
                echo "  lint clean"
            else
                echo "  lint found issues above - fix before calling the block done"
            fi
        else
            echo "  verilator not installed - skipping lint"
        fi
        echo "== Compile =="
        iverilog -g2012 -o "sim/$arg.vvp" rtl/*.sv "tb/${arg}_tb.sv" || { echo "Compile failed."; exit 1; }
        echo "== Simulate =="
        vvp "sim/$arg.vvp"
        if [ "${3:-}" = "-wave" ]; then
            open_wave "sim/$arg.vcd"
        fi
        ;;
    cocotb)
        require iverilog "cocotb Icarus backend" || exit 1
        activate_venv
        PY="$(python_bin)"
        ( cd dv && MODULE="test_$arg" TOPLEVEL="$arg" "$PY" sim.py )
        ;;
    formal)
        require sby "formal verification" || exit 1
        [ -f "formal/$arg.sby" ] || { echo "No formal/$arg.sby"; exit 1; }
        ( cd formal && sby -f -d "out/$arg" "$arg.sby" )
        ;;
    *)
        usage
        ;;
esac

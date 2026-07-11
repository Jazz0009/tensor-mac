#!/usr/bin/env bash
# setup-mac.sh — one-shot macOS toolchain installer for tensor-mac.
#
# Installs, via Homebrew, the exact open-source EDA flow that ./run.sh drives:
#   icarus-verilog (iverilog/vvp)  verilator  yosys  z3  gtkwave
#   symbiyosys (sby)               python 3.13 + cocotb/numpy venv
#
# Run it once after cloning:
#     ./setup-mac.sh
# then use the repo exactly like on Windows:
#     ./run.sh sim mac -wave
#
# Safe to re-run: every step checks for what is already present and skips it,
# so this doubles as an "update / repair the toolchain" command.
set -uo pipefail

cd "$(dirname "$0")" || exit 1

# ---- pins (kept in sync with the Windows environment) ----------------------
PY_FORMULA="python@3.13"          # Homebrew python; provides python3.13
VENV="${COCOTB_VENV:-$HOME/.venvs/cocotb}"
REQS="$(pwd)/requirements.txt"
SBY_REPO="https://github.com/YosysHQ/sby"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- 0. sanity -------------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "this script is for macOS. On Windows/WSL/Linux use the steps in README.md."

# ---- 1. Homebrew -----------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found — installing it"
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || die "Homebrew install failed. Install it from https://brew.sh then re-run ./setup-mac.sh"
    # Make brew visible on this shell (Apple Silicon vs Intel prefixes differ).
    if   [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew  ]; then eval "$(/usr/local/bin/brew shellenv)"
    fi
fi
command -v brew >/dev/null 2>&1 || die "brew still not on PATH; open a new terminal and re-run ./setup-mac.sh"
BREW_PREFIX="$(brew --prefix)"
ok "Homebrew at $BREW_PREFIX"

brew_formula() {   # install a formula only if missing
    if brew list --formula "$1" >/dev/null 2>&1; then ok "$1 already installed"
    else log "installing $1"; brew install "$1" || die "brew install $1 failed"; fi
}
brew_cask() {      # install a cask only if missing
    if brew list --cask "$1" >/dev/null 2>&1; then ok "$1 (cask) already installed"
    else log "installing $1 (cask)"; brew install --cask "$1" || warn "brew install --cask $1 failed (gtkwave is optional — waveform viewing only)"; fi
}

# ---- 2. core EDA tools -----------------------------------------------------
log "installing EDA toolchain via Homebrew"
brew_formula icarus-verilog     # iverilog + vvp  (sim, cocotb Icarus backend)
brew_formula verilator          # lint
brew_formula yosys              # synthesis + formal front-end (needed by sby)
brew_formula z3                 # SMT solver used by the formal jobs
brew_formula "$PY_FORMULA"      # python3.13 for the cocotb venv
brew_cask     gtkwave           # waveform viewer (cask on macOS)

# ---- 3. SymbiYosys (sby) ---------------------------------------------------
# Not in homebrew-core; install from source into the Homebrew prefix so it
# lands on PATH without sudo. Skipped if already present.
if command -v sby >/dev/null 2>&1; then
    ok "sby already installed ($(command -v sby))"
else
    log "installing SymbiYosys (sby) from source"
    SBY_SRC="$(mktemp -d)"
    if git clone --depth 1 "$SBY_REPO" "$SBY_SRC/sby" \
        && make -C "$SBY_SRC/sby" install PREFIX="$BREW_PREFIX"; then
        ok "sby installed to $BREW_PREFIX/bin/sby"
    else
        warn "sby install failed — 'run.sh formal' won't work until it's on PATH."
        warn "  retry manually: git clone $SBY_REPO && make -C sby install PREFIX=$BREW_PREFIX"
    fi
    rm -rf "$SBY_SRC"
fi

# ---- 4. cocotb venv (pinned, shared with Windows) --------------------------
PYBIN="$BREW_PREFIX/bin/python3.13"
[ -x "$PYBIN" ] || PYBIN="$(command -v python3.13 || command -v python3)"
[ -x "$PYBIN" ] || die "no python3 found even after installing $PY_FORMULA"

if [ -x "$VENV/bin/python" ]; then
    ok "cocotb venv already at $VENV"
else
    log "creating cocotb venv at $VENV"
    "$PYBIN" -m venv "$VENV" || die "venv creation failed"
fi

[ -f "$REQS" ] || die "requirements.txt not found next to setup-mac.sh"
log "installing pinned cocotb + numpy into the venv"
"$VENV/bin/python" -m pip install --upgrade pip >/dev/null || warn "pip self-upgrade failed (continuing)"
"$VENV/bin/python" -m pip install -r "$REQS" || die "pip install -r requirements.txt failed"
ok "python deps: $("$VENV/bin/python" -m pip show cocotb numpy 2>/dev/null | awk '/^Name|^Version/{printf "%s ", $2} END{print ""}')"

# ---- 5. report -------------------------------------------------------------
echo
log "toolchain summary"
report() { if command -v "$1" >/dev/null 2>&1; then printf '  \033[1;32m✓\033[0m %-10s %s\n' "$1" "$(command -v "$1")"; else printf '  \033[1;31m✗\033[0m %-10s (missing)\n' "$1"; fi; }
report iverilog
report vvp
report verilator
report yosys
report z3
report sby
if command -v gtkwave >/dev/null 2>&1 || [ -d /Applications/gtkwave.app ]; then
    printf '  \033[1;32m✓\033[0m %-10s %s\n' gtkwave "$(command -v gtkwave || echo /Applications/gtkwave.app)"
else
    printf '  \033[1;31m✗\033[0m %-10s (missing)\n' gtkwave
fi
printf '  \033[1;32m✓\033[0m %-10s %s\n' venv "$VENV"

echo
ok "setup complete. Try:  ./run.sh sim mac    (or)  ./run.sh cocotb mac"

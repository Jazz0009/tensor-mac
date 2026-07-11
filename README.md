# tensor-mac

A parameterized **INT8 systolic-array matrix-multiply accelerator** in synthesizable
SystemVerilog, verified the same way the underlying components were in
[vlsi-rtl-lab](https://github.com/Jazz0009/vlsi-rtl-lab): lint-clean RTL, self-checking
testbenches with real check counts, constrained-random **cocotb** regression against a NumPy
golden model, and **formal properties** (SymbiYosys + z3) on the control logic.

Built with **open-source tools only** — everything is reproducible from a clone.

## Status

| Block | Status |
|---|---|
| Architecture spec (`docs/SPEC.md`) | in progress |
| MAC unit | planned |
| Processing element | planned |
| Systolic array | planned |
| Control + operand feeders | planned |
| Top level + random regression vs NumPy | planned |
| Synthesis + gate-count report (Yosys) | planned |

## Architecture

The design and its rationale live in [`docs/SPEC.md`](docs/SPEC.md): number formats and
accumulator sizing, the dataflow choice, array geometry, and the top-level stream interfaces.
The stream plumbing builds on components designed, verified, and formally proven in
[vlsi-rtl-lab](https://github.com/Jazz0009/vlsi-rtl-lab) (synchronous FIFO, skid buffer,
round-robin arbiter); anything reused is copied into `rtl/` and re-verified in context, so this
repo stands alone.

## Layout

```
rtl/      synthesizable design (one module per file)
tb/       SystemVerilog self-checking testbenches
dv/       cocotb tests + golden models (Python)
formal/   SymbiYosys property jobs (*.sby)
docs/     spec + diagrams
```

## Toolchain (open source)

| Tool | Use |
|---|---|
| `verilator --lint-only` | RTL lint (width bugs, inferred latches) |
| `iverilog` / `vvp` | SystemVerilog simulation |
| `cocotb` + `numpy` | Constrained-random regression vs golden model |
| `sby` (SymbiYosys) + `z3` | Formal proofs on control invariants |
| `yosys` | Synthesis + gate-count report |
| `gtkwave` | Waveforms |

## Setup

The exact same `./run.sh` commands work on **macOS**, **Linux**, and **Windows**
(WSL or Git Bash). Tool names and Python/cocotb versions are pinned identically
across platforms — `requirements.txt` is the single source of truth for the
Python side. For the day-to-day push/pull routine when moving between machines,
see [`docs/SYNC.md`](docs/SYNC.md).

### macOS — clone, one-time setup, run

```bash
git clone https://github.com/Jazz0009/tensor-mac.git
cd tensor-mac
./setup-mac.sh          # Homebrew installs the whole toolchain + cocotb venv (once)
./run.sh sim mac        # then just run, forever
```

`setup-mac.sh` installs `icarus-verilog`, `verilator`, `yosys`, `z3`, `gtkwave`,
SymbiYosys (`sby`), and a pinned Python 3.13 + cocotb/numpy venv at
`~/.venvs/cocotb`. It is safe to re-run — every step skips what is already there,
so it doubles as a "repair/update the toolchain" command. If Homebrew is missing
it installs that too.

### Windows — clone, one-time setup, run

WSL (Ubuntu) is recommended so the flow is byte-for-byte identical to macOS:

```bash
sudo apt update
sudo apt install -y iverilog verilator yosys z3 gtkwave python3-venv git
# SymbiYosys (sby) is not packaged; build it once:
git clone https://github.com/YosysHQ/sby && (cd sby && sudo make install)

git clone https://github.com/Jazz0009/tensor-mac.git
cd tensor-mac
python3 -m venv ~/.venvs/cocotb
~/.venvs/cocotb/bin/pip install -r requirements.txt   # same pins as macOS
./run.sh sim mac
```

(Git Bash also works if the EDA tools are on `PATH`; the runner detects the venv
`Scripts/` layout automatically. WSL is smoother for the formal flow.)

### Check the toolchain

```bash
./run.sh doctor         # reports which tools + venv are present on this machine
```

## Reproduce

Once set up, all flows go through the one runner — identical on every OS:

```bash
./run.sh lint   <top>            # Verilator lint of rtl/ with <top> as toplevel
./run.sh sim    <top> [-wave]    # lint + iverilog (rtl/*.sv + tb/<top>_tb.sv) + vvp
./run.sh cocotb <block>          # dv/test_<block>.py against rtl toplevel <block>
./run.sh formal <job>            # SymbiYosys proof of formal/<job>.sby
./run.sh doctor                  # verify the toolchain is installed
```

cocotb runs use the pinned Python 3.13 + `cocotb` 2.x + `numpy` venv created by
setup (`requirements.txt`). Point `COCOTB_VENV` at a different venv if yours
lives elsewhere; the default is `~/.venvs/cocotb`. `-wave` opens the VCD in
GTKWave (handled per-OS, including the macOS `.app` bundle).

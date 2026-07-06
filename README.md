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

## Reproduce

All flows go through one runner (Linux/WSL):

```bash
./run.sh lint   <top>            # Verilator lint of rtl/ with <top> as toplevel
./run.sh sim    <top> [-wave]    # lint + iverilog (rtl/*.sv + tb/<top>_tb.sv) + vvp
./run.sh cocotb <block>          # dv/test_<block>.py against rtl toplevel <block>
./run.sh formal <job>            # SymbiYosys proof of formal/<job>.sby
```

cocotb runs expect a Python 3.11–3.13 environment with `cocotb` 2.x and `numpy` (set
`COCOTB_VENV` to point at yours, default `~/.venvs/cocotb`).

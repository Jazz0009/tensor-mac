"""cocotb regression for the `mac` unit — constrained-random vs a NumPy golden model.

Run with:  ./run.sh cocotb mac
The runner (dv/sim.py) builds rtl/*.sv with Icarus and points TOPLEVEL at `mac`.

The DUT is a signed DW×DW multiply + wide accumulate register with synchronous
active-high reset, a synchronous clear, and an enable. Priority on each posedge:
    rst  >  clear  >  en  >  hold
The golden model below re-implements exactly that contract in NumPy (int64, wide
enough that ACC_W can never overflow it) and checks the DUT after every cycle.
"""

import os

import cocotb
import numpy as np
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Design parameters. Mirror rtl/mac.sv defaults; read from the DUT when the
# simulator exposes them so this test tracks a re-parameterized build.
DW_DEFAULT = 8
K_DEFAULT = 8


def _acc_w(dw: int, k: int) -> int:
    """ACC_W = 2*DW + ceil(log2(K)) — the locked accumulator width from the spec."""
    return 2 * dw + (1 if k <= 1 else int(np.ceil(np.log2(k))))


def _param(dut, name: str, default: int) -> int:
    """Best-effort read of an HDL parameter; fall back to the known default."""
    try:
        return int(getattr(dut, name).value)
    except Exception:
        return default


class MacModel:
    """NumPy golden model of the accumulator. All math in signed int64 so the
    reference never wraps; the DUT (ACC_W bits) must agree because ACC_W is sized
    to hold the worst case across K accumulations."""

    def __init__(self, dw: int, k: int):
        self.dw = dw
        self.k = k
        self.acc_w = _acc_w(dw, k)
        self.acc = np.int64(0)

    def step(self, a: int, b: int, rst: int, clear: int, en: int) -> int:
        if rst:
            self.acc = np.int64(0)
        elif clear:
            self.acc = np.int64(0)
        elif en:
            self.acc = self.acc + np.int64(a) * np.int64(b)
        return int(self.acc)


async def _drive(dut, model, a, b, rst, clear, en):
    """Apply inputs, advance one clock, then compare DUT vs model off the edge."""
    dut.a_i.value = int(a)
    dut.b_i.value = int(b)
    dut.rst_i.value = int(rst)
    dut.clear_i.value = int(clear)
    dut.en_i.value = int(en)
    await RisingEdge(dut.clk_i)   # DUT samples here
    await Timer(1, unit="ns")     # step off the edge before reading acc_o
    expected = model.step(a, b, rst, clear, en)
    got = dut.acc_o.value.to_signed()   # !== X would raise here, surfacing as failure
    assert got == expected, (
        f"acc mismatch: a={a} b={b} rst={rst} clear={clear} en={en} "
        f"expected={expected} got={got}"
    )


async def _start(dut):
    """Common bring-up: clock + two reset cycles. Returns (model, dw, k)."""
    dw = _param(dut, "DW", DW_DEFAULT)
    k = _param(dut, "K", K_DEFAULT)
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    model = MacModel(dw, k)
    # Two synchronous resets to reach a known zero state.
    await _drive(dut, model, 0, 0, rst=1, clear=0, en=0)
    await _drive(dut, model, 0, 0, rst=1, clear=0, en=0)
    return model, dw, k


@cocotb.test()
async def test_reset_zeroes(dut):
    """After reset the accumulator reads exactly zero."""
    model, _, _ = await _start(dut)
    assert dut.acc_o.value.to_signed() == 0


@cocotb.test()
async def test_signed_corners(dut):
    """The INT8 sign corners, including the -128*-128 = +16384 outlier, accumulate
    correctly against the golden model."""
    model, _, _ = await _start(dut)
    corners = [
        (120, -2),      # pos * neg
        (-128, -128),   # the +16384 worst case
        (-128, 127),    # max-magnitude negative product
        (127, 127),     # max positive product
        (10, -92),
    ]
    for a, b in corners:
        await _drive(dut, model, a, b, rst=0, clear=0, en=1)


@cocotb.test()
async def test_hold_when_disabled(dut):
    """en=0 (rst=clear=0) must freeze the accumulator regardless of a_i/b_i."""
    model, _, _ = await _start(dut)
    await _drive(dut, model, 50, 3, rst=0, clear=0, en=1)   # seed a nonzero value
    for _ in range(4):
        await _drive(dut, model, 127, -128, rst=0, clear=0, en=0)  # noisy inputs, held


@cocotb.test()
async def test_clear_beats_enable(dut):
    """clear=1 while en=1 zeroes the accumulator (clear has priority over en)."""
    model, _, _ = await _start(dut)
    await _drive(dut, model, 77, -5, rst=0, clear=0, en=1)
    await _drive(dut, model, 77, -5, rst=0, clear=1, en=1)   # clear wins -> 0, not the product
    assert dut.acc_o.value.to_signed() == 0


@cocotb.test()
async def test_random_accumulate(dut):
    """Constrained-random signed INT8 operands over many K-length passes; the DUT
    must match the NumPy accumulator every cycle. Fixed seed so a failing case
    reproduces bit-for-bit on macOS and Windows/WSL."""
    model, dw, k = await _start(dut)
    seed = int(os.environ.get("MAC_SEED", "0xC0C0"), 0)
    rng = np.random.default_rng(seed)
    lo, hi = -(1 << (dw - 1)), (1 << (dw - 1)) - 1   # signed INT8 range

    passes = 200
    for _ in range(passes):
        await _drive(dut, model, 0, 0, rst=0, clear=1, en=1)   # fresh tile
        for _ in range(k):
            a = int(rng.integers(lo, hi + 1))
            b = int(rng.integers(lo, hi + 1))
            en = int(rng.integers(0, 2))                       # random hold cycles too
            await _drive(dut, model, a, b, rst=0, clear=0, en=en)

    dut._log.info(f"random regression passed: {passes} passes x K={k}, seed={hex(seed)}")

"""cocotb runner: builds rtl/*.sv with Icarus and runs dv/test_<MODULE>.py (used by `make cocotb`)."""
import os
import sys
from pathlib import Path

from cocotb_tools.runner import get_results, get_runner

HERE = Path(__file__).resolve().parent
module = os.environ["MODULE"]
toplevel = os.environ.get("TOPLEVEL", module.removeprefix("test_"))

runner = get_runner("icarus")
runner.build(sources=sorted((HERE.parent / "rtl").glob("*.sv")), hdl_toplevel=toplevel,
             build_dir=HERE / "sim_build", timescale=("1ns", "1ps"), always=True)
results = runner.test(hdl_toplevel=toplevel, test_module=module, timescale=("1ns", "1ps"))
_, failed = get_results(results)
sys.exit(1 if failed else 0)

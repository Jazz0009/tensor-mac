"""cocotb launcher (Python-runner flow, no make).

Invoked by ./run.sh cocotb <block>, which sets:
  MODULE   = test_<block>   (the dv/test_*.py module to run)
  TOPLEVEL = <block>        (the HDL toplevel, a module in rtl/)

Builds all of rtl/*.sv with Icarus so module hierarchies resolve without filelists.
"""
import os
import sys
from pathlib import Path

from cocotb_tools.runner import get_runner

HERE = Path(__file__).resolve().parent
RTL_DIR = HERE.parent / "rtl"


def main():
    module = os.environ.get("MODULE", "")
    if not module:
        sys.exit("Set MODULE=test_<block> (or use ./run.sh cocotb <block>)")
    toplevel = os.environ.get("TOPLEVEL", module.removeprefix("test_"))
    sources = sorted(RTL_DIR.glob("*.sv"))
    if not sources:
        sys.exit("rtl/ has no .sv sources yet")

    runner = get_runner("icarus")
    runner.build(
        sources=sources,
        hdl_toplevel=toplevel,
        build_dir=HERE / "sim_build",
        timescale=("1ns", "1ps"),
        always=True,
    )
    runner.test(
        hdl_toplevel=toplevel,
        test_module=module,
        timescale=("1ns", "1ps"),
    )


if __name__ == "__main__":
    main()

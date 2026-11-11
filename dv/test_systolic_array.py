import random
import math
import numpy as np
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# --- parameters: must match the DUT elaboration in dv/sim.py ---
N  = 2
DW = 8
K  = 8
ACC_W = 2*DW + (1 if K <= 1 else math.ceil(math.log2(K)))
N_CYCLES = 500
TOTAL = K + N - 1
LATENCY = 2*(N-1) + K
# One matmul per test iteration. For each:
#   1. draw random int8 matrices A (N x K) and B (K x N)
#   2. golden C = A @ B          (numpy, the independent model)
#   3. feed the tile into the array SKEWED over cycles, en_i high
#   4. hold enough cycles for the wavefront to fill + drain + accumulate
#   5. read every c_o[r][c], compare to golden C[r][c]
#   6. assert the result appeared on the cycle the latency formula predicts

@cocotb.test()
async def array_matmul(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    check = 0
    for cycle in range(N_CYCLES):
            
        # reset (sync, active-high) ...
        dut.rst_i.value = 1
        dut.a_i.value = [0]*N
        dut.b_i.value = [0]*N

        await RisingEdge(dut.clk_i)
        await RisingEdge(dut.clk_i)
        dut.rst_i.value = 0
        dut.en_i.value = 1
        dut.clear_i.value = 0
        await RisingEdge(dut.clk_i)    

        A = np.random.randint(-128, 128, size=(N, K))
        B = np.random.randint(-128, 128, size=(K, N))
        C = A @ B

        for cyc in range(LATENCY):
            for r in range(N):
                temp = cyc -r
                if temp < 0 or temp >= K:
                    dut.a_i[r].value = 0
                else :
                    dut.a_i[r].value = int(A[r, temp])   
            for c in range(N):
                temp = cyc - c
                if temp < 0 or temp >= K:
                    dut.b_i[c].value = 0
                else:
                    dut.b_i[c].value = int(B[temp, c])
            await RisingEdge(dut.clk_i)
            #Let the value settle before reading
        await Timer(1,unit="ns")
        for r in range(N):
            for c in range(N):
                got = int(dut.c_o[r*N + c].value.to_signed())   
                exp = int(C[r][c])                           
                assert got == exp, f"C[{r}][{c}] : got {got} : exp {exp}"
                check += 1                                              

    assert check != 0, "vacuous pass: no checks performed"
    dut._log.info(f"scoreboard OK: {check} Accumulators checked")

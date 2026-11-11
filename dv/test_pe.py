import random
import math
import cocotb 
from cocotb.clock import Clock 
from cocotb.triggers import RisingEdge, Timer 

DW = 8
K = 8
N_CYCLES = 10000
ACC_W = 2*DW + math.ceil(math.log2(K))

@cocotb.test()
async def mac_scoreboard(dut):
    cocotb.start_soon(Clock(dut.clk_i, 10, unit="ns").start())
    dut.rst_i.value = 1
    dut.a_i.value = 0
    dut.b_i.value = 0
    #Cleared a and b because reset does not clear them, not required 

    await RisingEdge(dut.clk_i)
    await RisingEdge(dut.clk_i)
    dut.rst_i.value = 0

    await RisingEdge(dut.clk_i)
    depth = 0
    check = 0
    a_o = 0
    b_o = 0
    #declaring accumulator
    accumulator = 0
    for cycle in range(N_CYCLES):
        if random.random() < 0.1:  
            a = random.choice([-128, 127])
        else:
            a = random.randint(-128, 127)

        if random.random() < 0.1:  
            b = random.choice([-128, 127])
        else:
            b = random.randint(-128, 127)
        
        enable = 1 if random.random() < 0.80 else 0
        reset  = 1 if random.random() < 0.05 else 0
        clear  = 1 if random.random() < 0.20 else 0
        if depth == K:
            clear = 1
            depth = 0

        if reset:
            accumulator = 0
            depth = 0
        elif clear:
            accumulator = 0
            depth = 0
        elif enable:
            accumulator = accumulator + (a*b)
            depth += 1

        if reset:
            a_o = 0
            b_o = 0

        elif enable:
            a_o = a
            b_o = b

        dut.a_i.value = a
        dut.b_i.value = b
        dut.rst_i.value = reset
        dut.clear_i.value = clear
        dut.en_i.value = enable


        await RisingEdge(dut.clk_i)
        await Timer(1,unit="ns")
        got = int(dut.acc_o.value.to_signed())
        a_out_captured = int(dut.a_o.value.to_signed())
        b_out_captured = int(dut.b_o.value.to_signed())
        #check
        assert got == accumulator, f"cycle {cycle} : a {a} : b {b} : accumulator {accumulator} : got {got}" 
        assert a_out_captured == a_o, f"cycle {cycle} : a_o {a_o} : got {a_out_captured}"
        assert b_out_captured == b_o, f"cycle {cycle} : b_o {b_o} : got {b_out_captured}"
        assert abs(accumulator) < 2**(ACC_W - 1), f"cycle {cycle} : a {a} : b {b} : accumulator {accumulator} : got {got}"
        check += 1
        
        

    assert check != 0, "vacuous pass: no checks performed"
    dut._log.info(f"scoreboard OK: {check} Multiply and add checked")

`timescale 1ns/1ps
// mac_tb.sv — self-checking TB for mac: signed corners, accumulate-over-K, clear-while-enabled. M11.
module mac_tb;
    localparam int DW = 8;
    localparam int K  = 8;
    localparam int ACC_W = 2*DW + ((K<=1)?1:($clog2(K)));

    logic clk_i, rst_i, en_i, clear_i;
    logic signed [DW-1:0]    a_i, b_i;
    logic signed [ACC_W-1:0] acc_o;

    mac #(.DW(DW), .K(K)) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .a_i(a_i),
        .b_i(b_i),
        .clear_i(clear_i),
        .en_i(en_i),
        .acc_o(acc_o)
    );

    int errors = 0;
    int checks = 0;
    logic signed [ACC_W-1:0] model = '0;   // independent reference accumulator

    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    // Compare DUT vs the independent model. !== so an X ever reaching here
    // surfaces as a real failure instead of being silently swallowed.
    task automatic check(input logic signed [ACC_W-1:0] got, expected);
        checks++;
        if (got !== expected) begin
            $display("FAIL t=%0t expected=%0d got=%0d check=%0d", $time, expected, got, checks);
            errors++;
        end
    endtask

    task automatic drive(input logic signed [DW-1:0] ta, tb,
                         input logic trst, tclear, ten);
        rst_i   = trst;
        a_i     = ta;
        b_i     = tb;
        clear_i = tclear;
        en_i    = ten;
        @(posedge clk_i);   // DUT samples here
        #1;                 // step off the edge before reading acc_o
        if      (trst)   model = '0;
        else if (tclear) model = '0;
        else if (ten)    model = model + ACC_W'(ta*tb);
        check(acc_o, model);
    endtask

    function automatic logic signed [DW-1:0] rand_op();
        return $random;
    endfunction

    initial begin
        $dumpfile("sim/mac.vcd");
        $dumpvars(0, mac_tb);

        drive('0, '0, 1'b1, 1'b0, 1'b0);
        drive('0, '0, 1'b1, 1'b0, 1'b0);

        // signed corners (rst=0, clear=0, en=1) — accumulate
        drive(120,   -2, 1'b0, 1'b0, 1'b1);   // pos * neg
        drive(-128, -128, 1'b0, 1'b0, 1'b1);   // the +16384 outlier
        drive(-128,  127, 1'b0, 1'b0, 1'b1);   // max-magnitude negative
        drive(10,  -92, 1'b0, 1'b0, 1'b1);

        // hold: en=0 -> accumulator must not change
        drive(0,  -32, 1'b0, 1'b0, 1'b0);

        // resume accumulate
        drive(120,   -2, 1'b0, 1'b0, 1'b1);

        // clear-while-enabled: clear=1 AND en=1 -> acc -> 0 (NOT the product)
        drive(120,   -2, 1'b0, 1'b1, 1'b1);

        // accumulate-over-K random signed operands
        for (int i = 0; i < K; i++)
            drive(rand_op(), rand_op(), 1'b0, 1'b0, 1'b1);

        if (errors == 0) $display("PASS - %0d checks performed", checks);
        else             $display("DONE with %0d error(s)", errors);
        $finish;
    end
endmodule

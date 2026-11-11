// mac.sv — signed DW×DW multiply + wide accumulate register (synchronous clear + enable).
module mac #(
    parameter int DW = 8,
    parameter int K = 8,
    localparam int ACC_W = 2*DW + ((K<=1)?1:($clog2(K)))
) (
    input logic clk_i, 
    input logic rst_i,
    input logic signed [DW-1:0] a_i,
    input logic signed [DW-1:0] b_i,
    input logic clear_i,
    input logic en_i,
    output logic signed [ACC_W-1:0] acc_o
);
    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            acc_o <= '0;
        end
        else if (clear_i) begin
            acc_o <= '0;
        end
        else if (en_i) begin
            acc_o <= acc_o + ACC_W'(a_i*b_i);
        end
    end

    `ifdef FORMAL
    localparam int F_ACC_W = ACC_W + 5;
    logic f_past_valid = 1'b0;
    logic signed [F_ACC_W-1:0] f_acc_wide;
    logic signed [4:0] f_depth;
    initial assume(rst_i);
   
    always_ff @(posedge clk_i) begin
        f_past_valid <= 1'b1;
        if(rst_i) begin
            f_acc_wide <= '0;
            f_depth <= '0;
        end
        else if(clear_i) begin 
            f_acc_wide <= '0;
            f_depth <= '0;
        end
        else if(en_i) begin
            f_acc_wide <= f_acc_wide + F_ACC_W'(a_i*b_i);
            f_depth <= f_depth + 1'b1;
        end
        assume (f_depth <= K);
        
        if (f_past_valid) begin
            assert (f_acc_wide == acc_o);
            assert ((f_acc_wide >= -(2**((2*DW) - 2))*f_depth) && (f_acc_wide <= (2**((2*DW) - 2))*f_depth)); 
        end 
    end
    `endif 
endmodule

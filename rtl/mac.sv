// mac.sv — signed DW×DW multiply + wide accumulate register (synchronous clear + enable). M11.
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
endmodule

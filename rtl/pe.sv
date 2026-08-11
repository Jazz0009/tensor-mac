// pe.sv — output-stationary processing element: one mac.sv + registered operand pass-through. M12.
module pe #(
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
    output logic signed [ACC_W-1:0] acc_o,
    output logic signed [DW-1:0] a_o,
    output logic signed [DW-1:0] b_o
);

    mac #(.DW(DW), .K(K)) u_mac0(
        .a_i(a_i),
        .b_i(b_i),
        .clk_i(clk_i),
        .rst_i(rst_i),
        .clear_i(clear_i),
        .en_i(en_i),
        .acc_o(acc_o)
    );

    always_ff @(posedge clk_i) begin
        if(rst_i) begin
            a_o <= '0;
            b_o <= '0;
        end
        else if(en_i) begin
            a_o <= a_i;
            b_o <= b_i;
        end
    end

endmodule

// systolic_array.sv — N×N grid of output-stationary PEs (A flows east, B flows south).
module systolic_array #(
    parameter  int N  = 2,
    parameter  int DW = 8,
    parameter  int K  = 8,
    localparam int ACC_W = 2*DW + ((K<=1)?1:($clog2(K)))
) (
    input  logic clk_i,
    input  logic rst_i,
    input  logic en_i,
    input  logic clear_i,
    input  logic signed [DW-1:0]    a_i [0:N-1],            // west edge: one A per row
    input  logic signed [DW-1:0]    b_i [0:N-1],            // north edge: one B per column
    output logic signed [ACC_W-1:0] c_o [0:N-1][0:N-1]      // each PE's accumulator
);

    logic signed [DW-1:0] a_h [0:N-1][0:N];
    logic signed [DW-1:0] b_v [0:N][0:N-1];
    // a_h carries A east across each row, b_v carries B south down each column.
    // N cells need N+1 links along the flow direction: index 0 is the injected edge, N is the drain.
    genvar r, c;
    generate
    for (r = 0; r < N; r++) begin : gen_row
        assign a_h[r][0] = a_i[r];
        for (c = 0; c < N; c++) begin : gen_col
            pe #(.DW(DW), .K(K)) u_pe(
                .clk_i(clk_i),
                .rst_i(rst_i),
                .a_i(a_h[r][c]),
                .b_i(b_v[r][c]),
                .a_o(a_h[r][c+1]),
                .b_o(b_v[r+1][c]),
                .clear_i(clear_i),
                .en_i(en_i),
                .acc_o(c_o[r][c])
            );
        end
    end
    for (c = 0; c < N; c++) begin : gen_bedge  
        assign b_v[0][c] = b_i[c];
    end
    
    endgenerate
endmodule

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

`ifdef FORMAL
    // Formal properties (SymbiYosys + z3). Compiled only under -DFORMAL, so this
    // block is invisible to `run.sh sim`/`lint`. Proven by ./run.sh formal mac.
    logic f_past_valid;
    initial f_past_valid = 1'b0;
    always_ff @(posedge clk_i) f_past_valid <= 1'b1;

    always_ff @(posedge clk_i) begin
        if (f_past_valid) begin
            // 1. Reset dominates everything: acc is exactly zero after rst.
            if ($past(rst_i)) begin
                a_reset_zeroes: assert (acc_o == '0);
            end
            // 2. Clear (when not reset) zeroes the accumulator, even if en was set:
            //    proves clear has priority over enable.
            else if ($past(clear_i)) begin
                a_clear_beats_enable: assert (acc_o == '0);
            end
            // 3. Enabled (not reset/cleared): acc advances by exactly the signed
            //    product — the accumulate contract, with no width truncation.
            else if ($past(en_i)) begin
                a_accumulate: assert (acc_o ==
                    $past(acc_o) + ACC_W'(signed'($past(a_i)) * signed'($past(b_i))));
            end
            // 4. Idle (not reset/cleared/enabled): the accumulator holds its value.
            else begin
                a_hold: assert (acc_o == $past(acc_o));
            end
        end
    end

    // Liveness sanity: the accumulator can actually reach a nonzero value, so the
    // proofs above aren't vacuously true on a stuck-at-zero design.
    always_ff @(posedge clk_i) begin
        if (f_past_valid) begin
            c_nonzero_acc: cover (acc_o != '0);
        end
    end
`endif
endmodule

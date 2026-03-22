module XNOR_unit #(
    parameter int PW = 32
)(
    input  logic          clk,
    input  logic          rst,   // active-high reset
    input  logic [PW-1:0] x,
    input  logic [PW-1:0] w,
    output logic [PW-1:0] out
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            out <= '0;
        else
           out <= ~(x ^ w);   // bitwise XNOR
    end

endmodule
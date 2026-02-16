module Accum_unit #(
    parameter int iwidth = 32,
    parameter int owidth = 32
)(
    input  logic                 clk,
    input  logic                 rst,   // active-high reset
    input  logic                 clr,
    input  logic                 en,    // accumulate when 1
    input  logic [iwidth-1:0]    din,
    output logic [owidth-1:0]    acc
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            acc <= '0;
        else if (clr)
            acc <= '0;
        else if (en)
            acc <= acc + din;   // wraps modulo 2^owidth
    end

endmodule

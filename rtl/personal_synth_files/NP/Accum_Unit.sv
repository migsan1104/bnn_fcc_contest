module Accum_Unit #(
    parameter int iwidth = 32,
    parameter int owidth = 32
)(
    input  logic                 clk,
    input  logic                 rst,   // active-high reset
    input  logic                 en,    // accumulate enable for valid popcount beats
    input  logic                 ld,    // first valid popcount beat
    input  logic                 clr,
    input  logic [iwidth-1:0]    din,
    output logic [owidth-1:0]    acc
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            acc <= '0;
        else if (clr)
            acc <= '0;
        else if (ld)
            acc <= din;
        else if (en)
            acc <= acc + din;
    end

endmodule

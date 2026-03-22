module Pop_unit #(
    parameter int iwidth = 32,
    parameter int owidth = 32
)(
    input  logic          clk,
    input  logic          rst,   // active-high reset
    input  logic [iwidth - 1:0] x,
    output logic [owidth - 1: 0] count
);

    logic [owidth - 1:0] count_next;
    integer i;

    // combinational popcount
    always_comb begin
        count_next = '0;
        for (i = 0; i < iwidth; i++) begin
            count_next += x[i];
        end
    end

    // registered output
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            count <= '0;
        else
            count <= count_next;
    end

endmodule
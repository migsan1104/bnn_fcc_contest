module Threshold_unit #(
    parameter int width = 8
)(
    input  logic             clk,
    input  logic             rst,     // active-high
    input  logic [width-1:0] value,   // usually popcount_total
    input  logic [width-1:0] thresh,
    output logic             y         // 1 if value >= thresh
);

    logic y_next;

    always_comb begin
        y_next = (value >= thresh);
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst)     
         y <= 1'b0;
        else 
         y <= y_next;
    end

endmodule


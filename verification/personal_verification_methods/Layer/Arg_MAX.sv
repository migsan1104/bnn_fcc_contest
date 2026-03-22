`timescale 1ns / 1ps

module Arg_MAX #(
    parameter int act_w      = 10,   // number of popcount entries
    parameter int popcount_w = 32,   // width of each popcount value
    parameter int out_w      = 8     // must be >= $clog2(act_w)
)(
    input  logic clk,
    input  logic rst,
    input  logic en,
    input  logic [act_w-1:0][popcount_w-1:0] popcount,

    output logic [out_w-1:0] bcc_out,
    output logic             out_valid
);

    // next winning class index
    logic [out_w-1:0] bcc_next;

    // current best popcount
    logic [popcount_w-1:0] best_val;

    int i;

    // compare every popcount entry and keep the index of the largest one
    always_comb begin
        bcc_next = '0;
        best_val = popcount[0];

        for (i = 1; i < act_w; i++) begin
            if (popcount[i] > best_val) begin
                best_val = popcount[i];
                bcc_next = i[out_w-1:0];
            end
        end
    end

    // register the winning class index
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bcc_out   <= '0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= en;
            if (en)
                bcc_out <= bcc_next;
        end
    end

endmodule
`timescale 1ns / 1ps

module Arg_MAX#(
    parameter int act_w = 10,                // Number of activation/popcount entries
    parameter int popcount_w = 32,           // Width of each popcount value
    parameter int out_w = 8                 // Must be >= $clog2(act_w)
)(
    input  logic clk,
    input  logic rst,
    input  logic en,
    input  logic [act_w-1:0] activation,
    input  logic [act_w-1:0][popcount_w-1:0] popcount,

    output logic [out_w-1:0] bcc_out,
    output logic             out_valid
);

    logic [out_w-1:0]       bcc_next;       // Next argmax index
    logic [popcount_w-1:0]  best_val;       // Current maximum popcount
    int                     i;              // Loop index

    // Combinational argmax
    always_comb begin
        bcc_next = '0;
        best_val = '0;
        for (i = 0; i < act_w; i++) begin
            if (activation[i]) begin
                if (popcount[i] > best_val) begin
                    best_val = popcount[i];
                    bcc_next = i;           // Assign index directly
                end
            end
        end
    end

    // Registered output
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

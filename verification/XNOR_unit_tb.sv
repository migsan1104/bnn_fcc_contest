`timescale 1 ns / 10 ps

//https://github.com/ARC-Lab-UF/sv-tutorial/blob/main/testbenches/basic/register_tb.sv
//https://github.com/ARC-Lab-UF/sv-tutorial/blob/main/testbenches/basic/mux2x1_tb.sv
module XNOR_unit_tb #(
    parameter int NUM_TESTS = 10000,
    parameter int PW = 32
);

    logic clk = 1'b0, rst;
    logic [PW-1:0] x, w, out;

    XNOR_unit #(.PW(PW)) DUT (.*);

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    initial begin : drive_inputs
        $timeformat(-9, 0, " ns");

        rst <= 1'b1;
        x <= '0;
        w <= '0;
        repeat (5) @(posedge clk);

        //deactivate reset on falling edge
        @(negedge clk);
        rst <= 1'b0;
        @(posedge clk);

        for (int i = 0; i < NUM_TESTS; i++) begin
            x <= $urandom;
            w <= $urandom;
            @(posedge clk);
        end

        $display("Tests completed.");
        disable generate_clock;
    end
    
    initial begin : check_output
        logic [PW-1:0] correct_out;
        logic [PW-1:0] x_prev, w_prev;
        //added in pipeline registers for x & w bc
        //there was a 1-cycle mismatch between out & correct_out

        x_prev = '0;
        w_prev = '0;
        forever begin
            @(posedge clk);
            #1

            if (rst) begin
                if (out != '0)
                    $error("[%0t] out should be reset", $realtime);

                x_prev = '0;
                w_prev = '0;
            end
            else begin
                correct_out = ~(x_prev ^ w_prev);
                if (correct_out != out) begin
                    $error("[%0t] out = %b instead of %d.", $realtime, out, correct_out);
                end
            end

            x_prev = x;
            w_prev = w;
        end
    end
endmodule





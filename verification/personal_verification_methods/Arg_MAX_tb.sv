`timescale 1ns/1ps

module Arg_MAX_tb;

  localparam int ACT_W      = 16;   // Number of activation entries
  localparam int POPCOUNT_W = 32;   // Width of each popcount value
  localparam int OUT_W      = 8;    // Width of argmax index output
  localparam int NTEST      = 100;  // Number of randomized tests

  logic clk;                        // Clock
  logic rst;                        // Reset
  logic en;                         // Enable
  logic [ACT_W-1:0] activation;     // Activation mask
  logic [ACT_W-1:0][POPCOUNT_W-1:0] popcount; // Popcount array
  logic [OUT_W-1:0] bcc_out;        // Output argmax index
  logic out_valid;                  // Output valid

  int passed;                       // Pass counter
  int total;                        // Total counter
  int t;                            // Test loop counter
  int i;                            // Index loop counter

  logic [OUT_W-1:0] expected_idx;   // Expected argmax index
  logic [POPCOUNT_W-1:0] best_val;  // Expected best value

  Arg_MAX #(
    .act_w(ACT_W),
    .popcount_w(POPCOUNT_W),
    .out_w(OUT_W)
  ) dut (
    .clk(clk),
    .rst(rst),
    .en(en),
    .activation(activation),
    .popcount(popcount),
    .bcc_out(bcc_out),
    .out_valid(out_valid)
  );

  initial clk = 1'b0;              // Clock init
  always #5 clk = ~clk;            // 100 MHz clock

  // Compute expected argmax for current activation/popcount
  task automatic compute_expected;
    begin
      expected_idx = '0;            // Default if no activation bits are 1
      best_val     = '0;            // Default best value
      for (i = 0; i < ACT_W; i++) begin
        if (activation[i]) begin
          if (popcount[i] > best_val) begin
            best_val     = popcount[i];
            expected_idx = i[OUT_W-1:0];
          end
        end
      end
    end
  endtask

  // Apply one test vector and check DUT outputs
  task automatic apply_and_check;
    begin
      compute_expected;             // Build golden result from currently assigned activation/popcount

      en <= 1'b1;                   // Pulse enable for one cycle
      @(posedge clk); #1;           // Wait for DUT registered outputs

      if (out_valid !== 1'b1) begin
        $display("FAIL: out_valid not 1 when en=1 time=%0t", $time);
        $fatal;
      end

      if (bcc_out !== expected_idx) begin
        $display("FAIL: bcc_out mismatch got=%0d expected=%0d time=%0t", bcc_out, expected_idx, $time);
        $fatal;
      end

      en <= 1'b0;                   // Disable next cycle
      @(posedge clk); #1;           // Advance one cycle

      if (out_valid !== 1'b0) begin
        $display("FAIL: out_valid not 0 when en=0 time=%0t", $time);
        $fatal;
      end

      passed++;
      total++;
    end
  endtask

  initial begin
    passed = 0;
    total  = 0;

    rst <= 1'b1;                    // Apply reset
    en  <= 1'b0;
    activation <= '0;
    popcount   <= '0;

    repeat (2) @(posedge clk);
    rst <= 1'b0;                    // Release reset
    @(posedge clk); #1;

    if (out_valid !== 1'b0) begin
      $display("FAIL: out_valid not 0 after reset time=%0t", $time);
      $fatal;
    end

    if (bcc_out !== '0) begin
      $display("FAIL: bcc_out not 0 after reset time=%0t", $time);
      $fatal;
    end

    // Directed test 1: one active entry
    activation <= '0;
    popcount   <= '0;
    activation[3] <= 1'b1;
    popcount[3]   <= 32'd200;
    @(posedge clk); #1;
    apply_and_check;

    // Directed test 2: multiple active entries
    activation <= '0;
    popcount   <= '0;
    activation[1] <= 1'b1;
    activation[5] <= 1'b1;
    popcount[1]   <= 32'd50;
    popcount[5]   <= 32'd250;
    @(posedge clk); #1;
    apply_and_check;

    // Random tests
    for (t = 0; t < NTEST; t++) begin
      activation <= '0;
      for (i = 0; i < ACT_W; i++) begin
        activation[i] <= $urandom_range(0, 1);
        popcount[i]   <= $urandom;
      end
      @(posedge clk); #1;

      if (activation == '0) begin
        activation[$urandom_range(0, ACT_W-1)] <= 1'b1; // Ensure at least one active bit sometimes
        @(posedge clk); #1;
      end

      apply_and_check;
    end

    $display("Tests passed: %0d / %0d", passed, total);
    $display("Simulation complete");
    $finish;
  end

endmodule
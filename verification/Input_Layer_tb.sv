`timescale 1ns/1ps

module Input_Layer_tb;

  localparam int OUT_W    = 8;    // Number of parallel outputs
  localparam int IN_W     = 64;   // Total input width
  localparam int THRESH   = 128;  // Threshold value
  localparam int CHUNK_W  = IN_W / OUT_W; // Bits per chunk
  localparam int NTEST    = 100;  // Number of randomized tests

  logic                 clk;      // Clock
  logic                 rst;      // Reset
  logic                 en;       // Enable latch
  logic [IN_W-1:0]      istream;  // Input vector
  logic                 valid;    // NEW: DUT valid
  logic [OUT_W-1:0]     ostream;  // Output bits

  int passed;                     // Pass counter
  int total;                      // Total counter
  int t;                          // Test loop counter
  int i;                          // Index loop counter

  logic [OUT_W-1:0] expected;     // Expected output bits
  logic [OUT_W-1:0] hold_val;     // Held output value for en=0 checks

  Input_Layer #(
    .out_w(OUT_W),
    .in_w(IN_W),
    .THRESH(THRESH)
  ) dut (
    .clk(clk),
    .rst(rst),
    .en(en),
    .istream(istream),
    .valid(valid),        // NEW
    .ostream(ostream)
  );

  initial clk = 1'b0;             // Clock init
  always #5 clk = ~clk;           // 100 MHz clock

  // Compute expected output from current istream
  task automatic compute_expected;
    logic [CHUNK_W-1:0] chunk;    // Current chunk slice
    begin
      expected = '0;
      for (i = 0; i < OUT_W; i++) begin
        chunk = istream[i*CHUNK_W +: CHUNK_W];
        expected[i] = (chunk > THRESH);
      end
    end
  endtask

  // Apply one vector and check behavior for en=1 and en=0
  task automatic apply_and_check;
    begin
      compute_expected;           // Build golden result

      en <= 1'b1;                 // Latch outputs
      @(posedge clk); #1;         // Wait for registered output

      if (valid !== 1'b1) begin   
        $display("FAIL: valid not 1 when en=1 got=%0b time=%0t", valid, $time);
        $fatal;
      end

      if (ostream !== expected) begin
        $display("FAIL: ostream mismatch got=0x%0h expected=0x%0h time=%0t", ostream, expected, $time);
        $fatal;
      end

      hold_val = ostream;         // Save output to check hold behavior

      en <= 1'b0;                 // Disable latch
      @(posedge clk); #1;         // Advance one cycle

      if (valid !== 1'b0) begin   // checking if valid signal turly works.
        $display("FAIL: valid not 0 when en=0 got=%0b time=%0t", valid, $time);
        $fatal;
      end

      if (ostream !== hold_val) begin // checking if enable going low causes the output to change.
        $display("FAIL: ostream changed while en=0 got=0x%0h expected_hold=0x%0h time=%0t", ostream, hold_val, $time);
        $fatal;
      end

      passed++;
      total++;
    end
  endtask

  initial begin
    passed = 0;
    total  = 0;

    rst <= 1'b1;                  // Apply reset
    en  <= 1'b0;
    istream <= '0;

    repeat (2) @(posedge clk);
    rst <= 1'b0;                  // Release reset
    @(posedge clk); #1;

    if (ostream !== '0) begin // checking if the reset works
      $display("FAIL: ostream not 0 after reset time=%0t", $time);
      $fatal;
    end

    // Directed test 1: all zeros input
    istream <= '0;
    @(posedge clk); #1;
    apply_and_check;

    // Directed test 2: all ones input
    istream <= {IN_W{1'b1}};
    @(posedge clk); #1;
    apply_and_check;

    // Directed test 3: set one chunk below threshold and one above threshold
    istream <= '0;
    istream[0*CHUNK_W +: CHUNK_W] <= CHUNK_W'(THRESH);        // Equal to threshold should output 0 since compare is >
    istream[1*CHUNK_W +: CHUNK_W] <= CHUNK_W'(THRESH + 1);    // Above threshold should output 1
    @(posedge clk); #1;
    apply_and_check;

    // Random tests
    for (t = 0; t < NTEST; t++) begin
      for (i = 0; i < OUT_W; i++) begin
        istream[i*CHUNK_W +: CHUNK_W] <= $urandom_range(0, (1<<CHUNK_W)-1);
      end
      @(posedge clk); #1;
      apply_and_check;
    end

    $display("Tests passed: %0d / %0d", passed, total);
    $display("Simulation complete");
    $finish;
  end

endmodule
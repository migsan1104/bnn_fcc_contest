`timescale 1ns / 1ps

module NP_UNIT_tb;

  localparam int PW  = 8;
  localparam int LAT = 4;

  // Everybody shares the same clock so the timelines are easy to read.
  logic clk;
  logic rst;

  // This one is the tiny case, so a single beat finishes the neuron.
  localparam int TBITS_1B = 8;
  localparam int ACC_W_1B = $clog2(TBITS_1B + 1);

  logic                valid_in_1b;
  logic                last_in_1b;
  logic [PW-1:0]       x_1b;
  logic [PW-1:0]       w_1b;
  logic [ACC_W_1B-1:0] threshold_1b;
  logic [ACC_W_1B-1:0] popcount_total_1b;
  logic                y_1b;
  logic                valid_out_1b;
  logic                valid_acc_1b;

  NP_UNIT #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TBITS_1B),
    .LAT(LAT)
  ) dut_1b (
    .clk            (clk),
    .rst            (rst),
    .valid_in       (valid_in_1b),
    .last_in        (last_in_1b),
    .x              (x_1b),
    .w              (w_1b),
    .threshold      (threshold_1b),
    .popcount_total (popcount_total_1b),
    .y              (y_1b),
    .valid_out      (valid_out_1b),
    .valid_acc      (valid_acc_1b)
  );

  // This long one matches the 784-bit first layer style, which is 98 beats at PW=8.
  localparam int TBITS_98B = 784;
  localparam int ACC_W_98B = $clog2(TBITS_98B + 1);

  logic                 valid_in_98b;
  logic                 last_in_98b;
  logic [PW-1:0]        x_98b;
  logic [PW-1:0]        w_98b;
  logic [ACC_W_98B-1:0] threshold_98b;
  logic [ACC_W_98B-1:0] popcount_total_98b;
  logic                 y_98b;
  logic                 valid_out_98b;
  logic                 valid_acc_98b;

  NP_UNIT #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TBITS_98B),
    .LAT(LAT)
  ) dut_98b (
    .clk            (clk),
    .rst            (rst),
    .valid_in       (valid_in_98b),
    .last_in        (last_in_98b),
    .x              (x_98b),
    .w              (w_98b),
    .threshold      (threshold_98b),
    .popcount_total (popcount_total_98b),
    .y              (y_98b),
    .valid_out      (valid_out_98b),
    .valid_acc      (valid_acc_98b)
  );

  // This middle case is useful because it is long enough to stress accumulation a bit.
  localparam int TBITS_16B = 128;
  localparam int ACC_W_16B = $clog2(TBITS_16B + 1);

  logic                 valid_in_16b;
  logic                 last_in_16b;
  logic [PW-1:0]        x_16b;
  logic [PW-1:0]        w_16b;
  logic [ACC_W_16B-1:0] threshold_16b;
  logic [ACC_W_16B-1:0] popcount_total_16b;
  logic                 y_16b;
  logic                 valid_out_16b;
  logic                 valid_acc_16b;

  NP_UNIT #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TBITS_16B),
    .LAT(LAT)
  ) dut_16b (
    .clk            (clk),
    .rst            (rst),
    .valid_in       (valid_in_16b),
    .last_in        (last_in_16b),
    .x              (x_16b),
    .w              (w_16b),
    .threshold      (threshold_16b),
    .popcount_total (popcount_total_16b),
    .y              (y_16b),
    .valid_out      (valid_out_16b),
    .valid_acc      (valid_acc_16b)
  );

  // The 8-beat case sits in between and gives another clean accumulation check.
  localparam int TBITS_8B = 64;
  localparam int ACC_W_8B = $clog2(TBITS_8B + 1);

  logic                valid_in_8b;
  logic                last_in_8b;
  logic [PW-1:0]       x_8b;
  logic [PW-1:0]       w_8b;
  logic [ACC_W_8B-1:0] threshold_8b;
  logic [ACC_W_8B-1:0] popcount_total_8b;
  logic                y_8b;
  logic                valid_out_8b;
  logic                valid_acc_8b;

  NP_UNIT #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TBITS_8B),
    .LAT(LAT)
  ) dut_8b (
    .clk            (clk),
    .rst            (rst),
    .valid_in       (valid_in_8b),
    .last_in        (last_in_8b),
    .x              (x_8b),
    .w              (w_8b),
    .threshold      (threshold_8b),
    .popcount_total (popcount_total_8b),
    .y              (y_8b),
    .valid_out      (valid_out_8b),
    .valid_acc      (valid_acc_8b)
  );

  // A plain 10 ns period is enough for a functional check like this.
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Keeping everything quiet at the start avoids bogus activity before reset settles.
  task automatic clear_all_inputs;
    begin
      valid_in_1b  <= 1'b0;
      last_in_1b   <= 1'b0;
      x_1b         <= '0;
      w_1b         <= '0;
      threshold_1b <= '0;

      valid_in_98b  <= 1'b0;
      last_in_98b   <= 1'b0;
      x_98b         <= '0;
      w_98b         <= '0;
      threshold_98b <= '0;

      valid_in_16b  <= 1'b0;
      last_in_16b   <= 1'b0;
      x_16b         <= '0;
      w_16b         <= '0;
      threshold_16b <= '0;

      valid_in_8b  <= 1'b0;
      last_in_8b   <= 1'b0;
      x_8b         <= '0;
      w_8b         <= '0;
      threshold_8b <= '0;
    end
  endtask

  // This helper waits on the live signal itself instead of a copied value.
  task automatic wait_for_valid_out(
    ref logic sig,
    input string name,
    input int max_cycles
  );
    int c;
    begin
      c = 0;
      while (sig !== 1'b1) begin
        @(posedge clk);
        c++;
        assert (c < max_cycles)
          else $fatal(1, "%s timed out waiting for valid_out", name);
      end
    end
  endtask

  // This one waits for valid_out to drop so the next image check is clean.
  task automatic wait_for_valid_out_deassert(
    ref logic sig,
    input string name,
    input int max_cycles
  );
    int c;
    begin
      c = 0;
      while (sig !== 1'b0) begin
        @(posedge clk);
        c++;
        assert (c < max_cycles)
          else $fatal(1, "%s timed out waiting for valid_out to deassert", name);
      end
    end
  endtask

  // A simple probability helper makes the random valid tests easy to write.
  function automatic bit chance(real p);
    real r;
    begin
      r = $urandom_range(0, 1000000) / 1000000.0;
      chance = (r < p);
    end
  endfunction

  // This prints the expected and actual values before we decide pass or fail.
  task automatic report_result(
    input string test_name,
    input int image_idx,
    input int expected_pop,
    input int actual_pop,
    input int expected_y,
    input int actual_y
  );
    begin
      $display("[%s] image=%0d expected_pop=%0d actual_pop=%0d expected_y=%0d actual_y=%0d %s",
               test_name,
               image_idx,
               expected_pop,
               actual_pop,
               expected_y,
               actual_y,
               ((actual_pop == expected_pop) && (actual_y == expected_y)) ? "CORRECT" : "INCORRECT");
    end
  endtask

  // A simple beat driver keeps the stimulus readable and makes last_in explicit.
  task automatic drive_beat_1b(
    input logic [PW-1:0] x_val,
    input logic [PW-1:0] w_val,
    input logic [ACC_W_1B-1:0] thresh_val,
    input logic last_val
  );
    begin
      valid_in_1b  <= 1'b1;
      last_in_1b   <= last_val;
      x_1b         <= x_val;
      w_1b         <= w_val;
      threshold_1b <= thresh_val;
      @(posedge clk);
    end
  endtask

  // This one does the exact same thing for the 98-beat DUT.
  task automatic drive_beat_98b(
    input logic [PW-1:0] x_val,
    input logic [PW-1:0] w_val,
    input logic [ACC_W_98B-1:0] thresh_val,
    input logic last_val
  );
    begin
      valid_in_98b  <= 1'b1;
      last_in_98b   <= last_val;
      x_98b         <= x_val;
      w_98b         <= w_val;
      threshold_98b <= thresh_val;
      @(posedge clk);
    end
  endtask

  // Repeating the same pattern per DUT keeps the tasks easy to debug in waves.
  task automatic drive_beat_16b(
    input logic [PW-1:0] x_val,
    input logic [PW-1:0] w_val,
    input logic [ACC_W_16B-1:0] thresh_val,
    input logic last_val
  );
    begin
      valid_in_16b  <= 1'b1;
      last_in_16b   <= last_val;
      x_16b         <= x_val;
      w_16b         <= w_val;
      threshold_16b <= thresh_val;
      @(posedge clk);
    end
  endtask

  // Having a dedicated driver here makes the 8-beat test look clean too.
  task automatic drive_beat_8b(
    input logic [PW-1:0] x_val,
    input logic [PW-1:0] w_val,
    input logic [ACC_W_8B-1:0] thresh_val,
    input logic last_val
  );
    begin
      valid_in_8b  <= 1'b1;
      last_in_8b   <= last_val;
      x_8b         <= x_val;
      w_8b         <= w_val;
      threshold_8b <= thresh_val;
      @(posedge clk);
    end
  endtask

  // After a burst we drop valid and last so the DUT can drain normally.
  task automatic idle_1b;
    begin
      valid_in_1b <= 1'b0;
      last_in_1b  <= 1'b0;
      x_1b        <= '0;
      w_1b        <= '0;
    end
  endtask

  // This deassertion step is tiny, but it makes the long test much safer.
  task automatic idle_98b;
    begin
      valid_in_98b <= 1'b0;
      last_in_98b  <= 1'b0;
      x_98b        <= '0;
      w_98b        <= '0;
    end
  endtask

  // It is nice when every DUT gets the same cleanup style after stimulus ends.
  task automatic idle_16b;
    begin
      valid_in_16b <= 1'b0;
      last_in_16b  <= 1'b0;
      x_16b        <= '0;
      w_16b        <= '0;
    end
  endtask

  // This keeps the final test from accidentally holding stale values on its pins.
  task automatic idle_8b;
    begin
      valid_in_8b <= 1'b0;
      last_in_8b  <= 1'b0;
      x_8b        <= '0;
      w_8b        <= '0;
    end
  endtask

  // A single-cycle bubble is handy for the random-valid streaming tests.
  task automatic idle_cycle_1b;
    begin
      valid_in_1b <= 1'b0;
      last_in_1b  <= 1'b0;
      x_1b        <= '0;
      w_1b        <= '0;
      @(posedge clk);
    end
  endtask

  // This gives the long-stream DUT the same one-cycle bubble behavior.
  task automatic idle_cycle_98b;
    begin
      valid_in_98b <= 1'b0;
      last_in_98b  <= 1'b0;
      x_98b        <= '0;
      w_98b        <= '0;
      @(posedge clk);
    end
  endtask

  // The first test is intentionally boring so if it fails, timing is probably off.
  task automatic test_1_beat;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 1-beat test ---");

      expected_pop = 8;
      expected_y   = 1;

      drive_beat_1b(8'hA5, 8'hA5, 5, 1'b1);
      idle_1b();

      wait_for_valid_out(valid_out_1b, "dut_1b", 50);

      actual_pop = popcount_total_1b;
      actual_y   = y_1b;
      report_result("dut_1b_single", 0, expected_pop, actual_pop, expected_y, actual_y);

      // Once valid_out rises, the total should already be sitting at 8.
      assert (popcount_total_1b == expected_pop[ACC_W_1B-1:0])
        else $fatal(1, "dut_1b popcount_total mismatch: got %0d expected %0d",
                    popcount_total_1b, expected_pop);

      // Since the threshold is 5, a perfect-match beat should produce y=1.
      assert (y_1b == expected_y[0])
        else $fatal(1, "dut_1b y mismatch: got %0d expected %0d",
                    y_1b, expected_y);

      // It is also worth checking that valid_acc showed up before or with the final output.
      assert (valid_acc_1b === 1'b1 || valid_out_1b === 1'b1)
        else $fatal(1, "dut_1b never indicated accumulated data was ready");

      $display("PASS: 1-beat test popcount=%0d y=%0d", popcount_total_1b, y_1b);
      @(posedge clk);
    end
  endtask

  // The 98-beat run is the one that really tells us whether accumulation survives a long stream.
  task automatic test_98_beats;
    int beat_idx;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 98-beat test ---");

      expected_pop = 98 * 8;
      expected_y   = 1;

      for (beat_idx = 0; beat_idx < 98; beat_idx++) begin
        drive_beat_98b(8'h3C, 8'h3C, 400, (beat_idx == 97));
      end
      idle_98b();

      wait_for_valid_out(valid_out_98b, "dut_98b", 250);

      actual_pop = popcount_total_98b;
      actual_y   = y_98b;
      report_result("dut_98b_single", 0, expected_pop, actual_pop, expected_y, actual_y);

      // Every beat is a full match, so the total should land exactly on 784.
      assert (popcount_total_98b == expected_pop[ACC_W_98B-1:0])
        else $fatal(1, "dut_98b popcount_total mismatch: got %0d expected %0d",
                    popcount_total_98b, expected_pop);

      // A threshold of 400 is comfortably below 784, so y should be high.
      assert (y_98b == expected_y[0])
        else $fatal(1, "dut_98b y mismatch: got %0d expected %0d",
                    y_98b, expected_y);

      $display("PASS: 98-beat test popcount=%0d y=%0d", popcount_total_98b, y_98b);
      @(posedge clk);
    end
  endtask

  // This one gives a medium-length burst, really usefull the first hidden layer of my topology
  task automatic test_16_beats;
    int beat_idx;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 16-beat test ---");

      expected_pop = 16 * 8;
      expected_y   = 1;

      for (beat_idx = 0; beat_idx < 16; beat_idx++) begin
        drive_beat_16b(8'hF0, 8'hF0, 100, (beat_idx == 15));
      end
      idle_16b();

      wait_for_valid_out(valid_out_16b, "dut_16b", 100);

      actual_pop = popcount_total_16b;
      actual_y   = y_16b;
      report_result("dut_16b_single", 0, expected_pop, actual_pop, expected_y, actual_y);

      // With sixteen perfect beats, the correct accumulated result is 128.
      assert (popcount_total_16b == expected_pop[ACC_W_16B-1:0])
        else $fatal(1, "dut_16b popcount_total mismatch: got %0d expected %0d",
                    popcount_total_16b, expected_pop);

      // A threshold of 100 should still pass because 128 is above it.
      assert (y_16b == expected_y[0])
        else $fatal(1, "dut_16b y mismatch: got %0d expected %0d",
                    y_16b, expected_y);

      $display("PASS: 16-beat test popcount=%0d y=%0d", popcount_total_16b, y_16b);
      @(posedge clk);
    end
  endtask

  // The 8-beat path is short enough to debug quickly but still exercises repeated accumulation.
  task automatic test_8_beats;
    int beat_idx;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 8-beat test ---");

      expected_pop = 8 * 8;
      expected_y   = 1;

      for (beat_idx = 0; beat_idx < 8; beat_idx++) begin
        drive_beat_8b(8'h5A, 8'h5A, 40, (beat_idx == 7));
      end
      idle_8b();

      wait_for_valid_out(valid_out_8b, "dut_8b", 80);

      actual_pop = popcount_total_8b;
      actual_y   = y_8b;
      report_result("dut_8b_single", 0, expected_pop, actual_pop, expected_y, actual_y);

      // If the first load and later accumulates are aligned, this settles at 64.
      assert (popcount_total_8b == expected_pop[ACC_W_8B-1:0])
        else $fatal(1, "dut_8b popcount_total mismatch: got %0d expected %0d",
                    popcount_total_8b, expected_pop);

      // Since 64 is above 40, the threshold compare should come out true.
      assert (y_8b == expected_y[0])
        else $fatal(1, "dut_8b y mismatch: got %0d expected %0d",
                    y_8b, expected_y);

      $display("PASS: 8-beat test popcount=%0d y=%0d", popcount_total_8b, y_8b);
      @(posedge clk);
    end
  endtask

  // This one sends five one-beat images back-to-back with the same threshold every time.
  task automatic test_1b_5_images_continuous;
    int img;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 1-beat, 5-image continuous test ---");

      expected_pop = 8;
      expected_y   = 1;

      for (img = 0; img < 5; img++) begin
        drive_beat_1b(8'hC3, 8'hC3, 5, 1'b1);
        idle_1b();

        wait_for_valid_out(valid_out_1b, "dut_1b continuous", 50);

        actual_pop = popcount_total_1b;
        actual_y   = y_1b;
        report_result("dut_1b_cont", img, expected_pop, actual_pop, expected_y, actual_y);

        // Every image is a perfect one-beat match, so the total should stay at 8.
        assert (popcount_total_1b == expected_pop[ACC_W_1B-1:0])
          else $fatal(1, "dut_1b continuous image %0d popcount_total mismatch: got %0d expected %0d",
                      img, popcount_total_1b, expected_pop);

        // The threshold stays constant here, so every image should produce the same y.
        assert (y_1b == expected_y[0])
          else $fatal(1, "dut_1b continuous image %0d y mismatch: got %0d expected %0d",
                      img, y_1b, expected_y);

        wait_for_valid_out_deassert(valid_out_1b, "dut_1b continuous", 20);
      end

      $display("PASS: 1-beat, 5-image continuous test");
      @(posedge clk);
    end
  endtask

  // Random valid gaps before each one-beat image should not break the final result.
  task automatic test_1b_5_images_random_valid;
    int img;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 1-beat, 5-image random-valid test ---");

      expected_pop = 8;
      expected_y   = 1;

      for (img = 0; img < 5; img++) begin
        while (!chance(0.8)) begin
          idle_cycle_1b();
        end

        drive_beat_1b(8'h5E, 8'h5E, 5, 1'b1);
        idle_1b();

        wait_for_valid_out(valid_out_1b, "dut_1b random", 60);

        actual_pop = popcount_total_1b;
        actual_y   = y_1b;
        report_result("dut_1b_rand", img, expected_pop, actual_pop, expected_y, actual_y);

        // Bubbles before the beat should not change the one-beat accumulation.
        assert (popcount_total_1b == expected_pop[ACC_W_1B-1:0])
          else $fatal(1, "dut_1b random image %0d popcount_total mismatch: got %0d expected %0d",
                      img, popcount_total_1b, expected_pop);

        // With a constant threshold, every image should still classify the same way.
        assert (y_1b == expected_y[0])
          else $fatal(1, "dut_1b random image %0d y mismatch: got %0d expected %0d",
                      img, y_1b, expected_y);

        wait_for_valid_out_deassert(valid_out_1b, "dut_1b random", 20);
      end

      $display("PASS: 1-beat, 5-image random-valid test");
      @(posedge clk);
    end
  endtask

  // This one pushes five full 98-beat images with no bubbles in the input stream.
  task automatic test_98b_5_images_continuous;
    int img;
    int beat_idx;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 98-beat, 5-image continuous test ---");

      expected_pop = 98 * 8;
      expected_y   = 1;

      for (img = 0; img < 5; img++) begin
        for (beat_idx = 0; beat_idx < 98; beat_idx++) begin
          drive_beat_98b(8'hA9, 8'hA9, 400, (beat_idx == 97));
        end
        idle_98b();

        wait_for_valid_out(valid_out_98b, "dut_98b continuous", 300);

        actual_pop = popcount_total_98b;
        actual_y   = y_98b;
        report_result("dut_98b_cont", img, expected_pop, actual_pop, expected_y, actual_y);

        // A full-match 98-beat image should always accumulate to 784.
        assert (popcount_total_98b == expected_pop[ACC_W_98B-1:0])
          else $fatal(1, "dut_98b continuous image %0d popcount_total mismatch: got %0d expected %0d",
                      img, popcount_total_98b, expected_pop);

        // The threshold stays fixed, so each image should produce the same y.
        assert (y_98b == expected_y[0])
          else $fatal(1, "dut_98b continuous image %0d y mismatch: got %0d expected %0d",
                      img, y_98b, expected_y);

        wait_for_valid_out_deassert(valid_out_98b, "dut_98b continuous", 30);
      end

      $display("PASS: 98-beat, 5-image continuous test");
      @(posedge clk);
    end
  endtask

  // This one inserts random valid bubbles between the beats of each 98-beat image.
  task automatic test_98b_5_images_random_valid;
    int img;
    int beat_idx;
    int expected_pop;
    int expected_y;
    int actual_pop;
    int actual_y;
    begin
      $display("\n--- Running 98-beat, 5-image random-valid test ---");

      expected_pop = 98 * 8;
      expected_y   = 1;

      for (img = 0; img < 5; img++) begin
        beat_idx = 0;

        while (beat_idx < 98) begin
          if (chance(0.8)) begin
            drive_beat_98b(8'h66, 8'h66, 400, (beat_idx == 97));
            beat_idx++;
          end else begin
            idle_cycle_98b();
          end
        end

        idle_98b();

        wait_for_valid_out(valid_out_98b, "dut_98b random", 400);

        actual_pop = popcount_total_98b;
        actual_y   = y_98b;
        report_result("dut_98b_rand", img, expected_pop, actual_pop, expected_y, actual_y);

        // Random bubbles should not matter as long as all 98 beats still arrive.
        assert (popcount_total_98b == expected_pop[ACC_W_98B-1:0])
          else $fatal(1, "dut_98b random image %0d popcount_total mismatch: got %0d expected %0d",
                      img, popcount_total_98b, expected_pop);

        // A fixed threshold means each image should keep producing the same classification.
        assert (y_98b == expected_y[0])
          else $fatal(1, "dut_98b random image %0d y mismatch: got %0d expected %0d",
                      img, y_98b, expected_y);

        wait_for_valid_out_deassert(valid_out_98b, "dut_98b random", 30);
      end

      $display("PASS: 98-beat, 5-image random-valid test");
      @(posedge clk);
    end
  endtask

  // This whole block resets the DUTs, runs the tests, and exits cleanly.
  initial begin
    clear_all_inputs();
    rst <= 1'b1;

    repeat (4) @(posedge clk);
    rst <= 1'b0;

    repeat (2) @(posedge clk);

    test_1_beat();
    test_98_beats();
    test_16_beats();
    test_8_beats();

    $display("\n==============================================");
    $display("PASSED FIRST SET OF 4 TESTS");
    $display("==============================================\n");

    test_1b_5_images_continuous();
    test_1b_5_images_random_valid();
    test_98b_5_images_continuous();
    test_98b_5_images_random_valid();

    $display("\nALL NP_UNIT TESTS PASSED");
    repeat (5) @(posedge clk);
    $finish;
  end

endmodule
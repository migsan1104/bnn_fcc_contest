module NP_UNIT #(
    parameter int PW               = 32,
    parameter int TOTAL_BITS_NEURON = 64,
    parameter int LAT              = 4
)(
    input  logic clk,
    input  logic rst,

    input  logic valid_in,
    input  logic last_in,

    input  logic [PW-1:0] x,
    input  logic [PW-1:0] w,

    input  logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] threshold,

    output logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] popcount_total,
    output logic y,
    output logic valid_out,
    output logic valid_acc
);

  localparam int ACC_W = $clog2(TOTAL_BITS_NEURON+1);

  logic acc_ld, acc_clr;

  //==================================================
  // Threshold register
  // - Load once at start of neuron 
  // - Clear whenever valid_out asserts 
  //==================================================
  logic [ACC_W-1:0] threshold_r;
  logic             have_threshold;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      threshold_r    <= '0;
      have_threshold <= 1'b0;
    end else begin
      // Clear after producing an output
      if (valid_out) begin
        threshold_r    <= '0;
        have_threshold <= 1'b0;
      end

      // Load threshold on first valid_in of a neuron window
      // (only if we don't already have one latched)
      if (valid_in && !have_threshold) begin
        threshold_r    <= threshold;
        have_threshold <= 1'b1;
      end
    end
  end

  //==================================================
  // FSM
  //==================================================
  NP_FSM #(.LAT(LAT)) u_fsm (
    .clk       (clk),
    .rst       (rst),
    .valid_in  (valid_in),
    .last_in   (last_in),
    .acc_ld    (acc_ld),
    .acc_clr   (acc_clr),
    .valid_out (valid_out),
    .valid_acc (valid_acc)
  );

  //==================================================
  // Datapath
  //==================================================
  NP_DP #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TOTAL_BITS_NEURON)
  ) u_dp (
    .clk            (clk),
    .rst            (rst),
    .x              (x),
    .w              (w),
    .acc_ld         (acc_ld),
    .acc_clr        (acc_clr),
    .threshold      (threshold_r),
    .popcount_total (popcount_total),
    .y              (y)
  );

endmodule

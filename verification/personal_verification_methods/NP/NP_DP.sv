module NP_DP #(
    parameter int PW                = 32,
    parameter int TOTAL_BITS_NEURON = 64
)(
    input  logic clk,
    input  logic rst,

    input  logic [PW-1:0] x,
    input  logic [PW-1:0] w,

    input  logic acc_en,
    input  logic acc_ld,
    input  logic acc_clr,

    input  logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] threshold,

    output logic [$clog2(TOTAL_BITS_NEURON+1)-1:0] popcount_total,
    output logic y
);

  localparam int POP_W = $clog2(PW + 1);
  localparam int ACC_W = $clog2(TOTAL_BITS_NEURON + 1);

  logic [PW-1:0] xnor_bits;
  logic [POP_W-1:0] popcount_beat;

  XNOR_unit #(.PW(PW)) u_xnor (
    .clk (clk),
    .rst (rst),
    .x   (x),
    .w   (w),
    .out (xnor_bits)
  );

  Pop_unit #(
    .iwidth(PW),
    .owidth(POP_W)
  ) u_pop (
    .clk   (clk),
    .rst   (rst),
    .x     (xnor_bits),
    .count (popcount_beat)
  );

  Accum_unit #(
    .iwidth(POP_W),
    .owidth(ACC_W)
  ) u_accum (
    .clk (clk),
    .rst (rst),
    .en  (acc_en),
    .ld  (acc_ld),
    .clr (acc_clr),
    .din (popcount_beat),
    .acc (popcount_total)
  );

  Threshold_unit #(
    .width(ACC_W)
  ) u_thresh (
    .clk    (clk),
    .rst    (rst),
    .value  (popcount_total),
    .thresh (threshold),
    .y      (y)
  );

endmodule

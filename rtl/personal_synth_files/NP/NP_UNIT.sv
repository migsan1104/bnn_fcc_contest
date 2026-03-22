module NP_UNIT #(
    parameter int LAYER_ID           = 0,   // Debug only
    parameter int LANE_ID            = 0,   // Debug only
    parameter int PW                 = 32,
    parameter int TOTAL_BITS_NEURON  = 64,
    parameter int LAT                = 4
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

  logic acc_en, acc_ld, acc_clr;

  NP_FSM #(.LAT(LAT)) u_fsm (
    .clk       (clk),
    .rst       (rst),
    .valid_in  (valid_in),
    .last_in   (last_in),
    .acc_en    (acc_en),
    .acc_ld    (acc_ld),
    .acc_clr   (acc_clr),
    .valid_out (valid_out),
    .valid_acc (valid_acc)
  );

  NP_DP #(
    .PW(PW),
    .TOTAL_BITS_NEURON(TOTAL_BITS_NEURON)
  ) u_dp (
    .clk            (clk),
    .rst            (rst),
    .x              (x),
    .w              (w),
    .acc_en         (acc_en),
    .acc_ld         (acc_ld),
    .acc_clr        (acc_clr),
    .threshold      (threshold),
    .popcount_total (popcount_total),
    .y              (y)
  );

endmodule
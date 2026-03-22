`timescale 1ns / 1ps

module NP_FSM #(
    parameter int LAT = 4
)(
    input  logic clk,
    input  logic rst,

    input  logic valid_in,
    input  logic last_in,

    output logic acc_en,
    output logic acc_ld,
    output logic acc_clr,
    output logic valid_out,
    output logic valid_acc
);

  typedef enum logic {S_IDLE, S_IN} state_t;
  state_t state, next_state;

  logic [$clog2(LAT+2)-1:0] current_lat, lat_next;
  logic [$clog2(LAT+2)-1:0] reverse_lat, reverse_next_lat;
  logic begin_lat_r, begin_lat_d;

  // Two-cycle datapath alignment: XNOR -> POPCOUNT
  logic valid_d1_r, valid_d1_d;
  logic valid_d2_r, valid_d2_d;

  // Keep last_in aligned with valid through the same two stages
  logic last_d1_r, last_d1_d;
  logic last_d2_r, last_d2_d;

  // 1 means: next valid_d2_r beat is first popcount beat of a neuron
  logic need_first_pop_r, need_first_pop_d;

 // This is used to create a pipeline that matchest last in with the rest of the np
  logic [LAT-1:0] last_pipe_r, last_pipe_d;

  integer i;

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state            <= S_IDLE;
      current_lat      <= '0;
      reverse_lat      <= '0;
      begin_lat_r      <= 1'b0;
      valid_d1_r       <= 1'b0;
      valid_d2_r       <= 1'b0;
      last_d1_r        <= 1'b0;
      last_d2_r        <= 1'b0;
      need_first_pop_r <= 1'b1;
      last_pipe_r      <= '0;
    end else begin
      state            <= next_state;
      current_lat      <= lat_next;
      reverse_lat      <= reverse_next_lat;
      begin_lat_r      <= begin_lat_d;
      valid_d1_r       <= valid_d1_d;
      valid_d2_r       <= valid_d2_d;
      last_d1_r        <= last_d1_d;
      last_d2_r        <= last_d2_d;
      need_first_pop_r <= need_first_pop_d;
      last_pipe_r      <= last_pipe_d;
    end
  end

  always_comb begin
    valid_out = 1'b0;
    valid_acc = 1'b0;
    acc_en    = 1'b0;
    acc_ld    = 1'b0;
    acc_clr   = 1'b0;

    next_state       = state;
    lat_next         = current_lat;
    reverse_next_lat = reverse_lat;
    begin_lat_d      = begin_lat_r;
    valid_d1_d       = valid_d1_r;
    valid_d2_d       = valid_d2_r;
    last_d1_d        = last_d1_r;
    last_d2_d        = last_d2_r;
    need_first_pop_d = need_first_pop_r;
    last_pipe_d      = last_pipe_r;

    case (state)

      S_IDLE: begin
        acc_clr           = 1'b1;
        lat_next          = '0;
        reverse_next_lat  = '0;
        begin_lat_d       = 1'b0;
        valid_d1_d        = 1'b0;
        valid_d2_d        = 1'b0;
        last_d1_d         = 1'b0;
        last_d2_d         = 1'b0;
        need_first_pop_d  = 1'b1;
        last_pipe_d       = '0;

        if (valid_in) begin
          next_state       = S_IN;
          valid_d1_d       = 1'b1;
          valid_d2_d       = 1'b0;
          last_d1_d        = last_in;
          last_d2_d        = 1'b0;
          reverse_next_lat = LAT;

          // Capture the first completion event immediately
          if (LAT > 0)
            last_pipe_d[0] = last_in;
        end
      end

      S_IN: begin
        // Advance valid/last through datapath alignment
        valid_d1_d = valid_in;
        valid_d2_d = valid_d1_r;
        last_d1_d  = valid_in ? last_in : 1'b0;
        last_d2_d  = last_d1_r;

        // Accumulator control:
        // first aligned popcount beat of a neuron loads,
        // remaining aligned popcount beats accumulate.
        if (valid_d2_r) begin
          if (need_first_pop_r) begin
            acc_ld = 1'b1;
          end else begin
            acc_en = 1'b1;
          end
        end

        // Re-arm for the next neuron as soon as the current neuron's
        // last aligned popcount beat has entered the accumulator path.
        if (valid_d2_r && last_d2_r) begin
          need_first_pop_d = 1'b1;
        end else if (valid_d2_r && need_first_pop_r) begin
          need_first_pop_d = 1'b0;
        end

        // Tail tracker: stay alive while input is arriving or while flushing
        // valid/last alignment and output latency pipe
        if (valid_in) begin
          reverse_next_lat = LAT;
        end else if (reverse_lat != '0) begin
          reverse_next_lat = reverse_lat - 1'b1;
        end else begin
          reverse_next_lat = '0;
        end

      
        begin_lat_d = 1'b0;
        lat_next    = '0;

        // Shift raw last_in through the latency pipe
        if (LAT > 0) begin
          last_pipe_d[0] = last_in;
          for (i = 1; i < LAT; i++) begin
            last_pipe_d[i] = last_pipe_r[i-1];
          end
        end

        // Output timing:
        // last_in at cycle N -> valid_out at cycle N+LAT
        // valid_acc is exactly one cycle earlier
        if (LAT == 1) begin
          valid_acc = last_in;
          valid_out = last_pipe_r[0];
        end else begin
        // this is essentially a shift register
          valid_acc = last_pipe_r[LAT-2];
          valid_out = last_pipe_r[LAT-1];
        end

        if ((reverse_lat == '0) &&
            !valid_in &&
            !valid_d1_r &&
            !valid_d2_r &&
            !(|last_pipe_r)) begin
          next_state = S_IDLE;
        end
      end

    endcase
  end

endmodule
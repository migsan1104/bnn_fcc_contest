module NP_FSM #(
    parameter int LAT = 4
)(
    //inputs
    input  logic clk,
    input  logic rst,

    input  logic valid_in,
    input  logic last_in,
    // outputs
    output logic acc_ld,
    output logic acc_clr,
    output logic valid_out,
    output logic valid_acc
);

  typedef enum logic {S_IDLE, S_IN} state_t;
  state_t state, next_state;
  // this is the forward lat counter, 0,1,2,3 ..., it is used for valid out and valid acc logic
  logic [LAT-1:0] current_lat, lat_next;
  // this is the reverse lat counter, goes from 4 3 2 1 .... , it is used to know when the pipeline is cleared
  // once cleared we can then go back to the IDLE STATE
  logic [LAT-1:0] reverse_lat, reverse_next_lat;
  // used to know when to begin the lat counter
  logic begin_lat_r, begin_lat_d;

  // sequential logic
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      state       <= S_IDLE;
      current_lat <= '0;
      reverse_lat <= '0;
      begin_lat_r <= 1'b0;
    end else begin
      state       <= next_state;
      current_lat <= lat_next;
      reverse_lat <= reverse_next_lat;
      begin_lat_r <= begin_lat_d;
    end
  end

  // combinational logic
  always_comb begin
    // defaults to avoid latches
    valid_out = 1'b0;
    valid_acc = 1'b0;
    acc_ld    = 1'b0;
    acc_clr   = 1'b0;

    next_state       = state;
    lat_next         = current_lat;
    reverse_next_lat = reverse_lat;
    begin_lat_d      = begin_lat_r;

    case (state)

      S_IDLE: begin
        acc_clr          = 1'b1;
        lat_next         = '0;
        reverse_next_lat = '0;
        begin_lat_d      = 1'b0;

        if (valid_in)
          next_state = S_IN;
      end

      S_IN: begin
        // reverse counter , dealing with the negative case aswell
        if (valid_in)
          reverse_next_lat = LAT'(3);
        else if (reverse_lat != '0)
          reverse_next_lat = reverse_lat - LAT'(1);
        else
          reverse_next_lat = '0;

        if (reverse_next_lat == '0)
          next_state = S_IDLE;

        // start latency counter on last_in
        if (last_in)
          begin_lat_d = 1'b1;

        // increment immediately when last_in first asserts
        if (begin_lat_r | last_in)
          lat_next = current_lat + LAT'(1);

        // accumulator is now  valid after 3 cycles 
        if (current_lat == LAT'(3)) begin
          valid_acc = 1'b1;
          acc_ld    = 1'b1;
        end

        // final output valid
        if (current_lat == LAT'(4)) begin
          valid_out   = 1'b1;
          begin_lat_d = 1'b0;
          lat_next    = '0;
        end
      end

    endcase
  end

endmodule

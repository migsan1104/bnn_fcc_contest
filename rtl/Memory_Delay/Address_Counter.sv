module Address_Counter #(
  parameter int ADDR_W    = 15,
  parameter int MAX_COUNT = 1024
)(
  input  logic               clk,
  input  logic               rst,       // synchronous active-high reset
  input  logic               go,
  input  logic               stall,

  output logic [ADDR_W-1:0]  addr,
  output logic               valid,
  output logic               done
);

  logic active;
  logic [$clog2(MAX_COUNT+1)-1:0] count;

  logic will_run;

  always_comb begin
    will_run = (active || go) && !stall;
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      active <= 1'b0;
      count  <= '0;
      addr   <= '0;
      valid  <= 1'b0;
      done   <= 1'b0;
    end else begin
      valid <= 1'b0;
      done  <= 1'b0;

      // latch active as soon as go is seen
      if (go)
        active <= 1'b1;

      // run when active-or-go and not stalled
      if (will_run) begin
        valid <= 1'b1;
        addr  <= count[ADDR_W-1:0];

        if (count == MAX_COUNT-1) begin
          active <= 1'b0;
          done   <= 1'b1;
        end else begin
          count <= count + 1;
        end
      end
    end
  end

endmodule
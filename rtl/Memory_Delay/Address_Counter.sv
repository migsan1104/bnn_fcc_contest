module Address_Counter #(
  parameter int ADDR_W    = 15,
  parameter int MAX_COUNT = 1024   // total number of addresses to generate
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

  always_ff @(posedge clk) begin
    if (rst) begin
      addr   <= '0;
      count  <= '0;
      active <= 1'b0;
      valid  <= 1'b0;
      done   <= 1'b0;
    end else begin
      valid <= 1'b0;
      done  <= 1'b0;

      // Start counting from zero
      if (go && !active) begin
        addr   <= '0;
        count  <= '0;
        active <= 1'b1;
      end

      // Generate address when not stalled
      if (active && !stall) begin
        valid <= 1'b1;

        if (count == MAX_COUNT-1) begin
          active <= 1'b0;
          done   <= 1'b1;
        end else begin
          addr  <= addr + 1;
          count <= count + 1;
        end
      end
    end
  end

endmodule

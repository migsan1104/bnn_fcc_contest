module Register #(
  parameter int DWIDTH = 8        // data width of the register
)(
  input  logic                  clk,
  input  logic                  rst,     // asynchronous active-high reset
  input  logic                  en,      // active-high enable
  input  logic [DWIDTH-1:0]     d,       // data input
  output logic [DWIDTH-1:0]     q        // data output
);

  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      q <= '0;                 // reset register to 0
    else if (en)
      q <= d;                  // load new data when enable is high
  end

endmodule
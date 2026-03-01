module BRAM #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 8,
    localparam int DEPTH = 1 << ADDR_W
)(
    input  logic                 clk,
    input  logic                 rst,      // synchronous reset for size counter

    // Port A
    input  logic                 a_ren,
    input  logic                 a_wen,
    input  logic [ADDR_W-1:0]    a_addr,
    input  logic [DATA_W-1:0]    a_wdata,
    output logic [DATA_W-1:0]    a_rdata,

    // Port B
    input  logic                 b_ren,
    input  logic                 b_wen,
    input  logic [ADDR_W-1:0]    b_addr,
    input  logic [DATA_W-1:0]    b_wdata,
    output logic [DATA_W-1:0]    b_rdata,

    output logic [ADDR_W:0]      size      // occupancy counter
);

  (* ram_style = "block" *) logic [DATA_W-1:0] mem [0:DEPTH-1];

  // dual-port synchronous read/write
  // we assume that port A is write side and port b is read side
  always_ff @(posedge clk) begin
    if (a_wen) mem[a_addr] <= a_wdata;     // write port A
    if (b_wen) mem[b_addr] <= b_wdata;     // write port B
    if (a_ren) a_rdata <= mem[a_addr];     // read port A
    if (b_ren) b_rdata <= mem[b_addr];     // read port B
  end

  // simple occupancy counter: +1 on write, -1 on read
  always_ff @(posedge clk) begin
    if (rst) begin
      size <= '0;                          // reset counter
    end else begin
      if (a_wen && !b_ren && size < DEPTH)
        size <= size + 1;                  // push
      else if (b_ren && !a_wen && size > 0)
        size <= size - 1;                  // pop
    end
  end

endmodule
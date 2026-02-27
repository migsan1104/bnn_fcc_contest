module BRAM #(
    parameter int DATA_W = 32,
    parameter int ADDR_W = 8,
    localparam int DEPTH = 1 << ADDR_W
)(
    input  logic                 clk,
    input  logic                 rst,          // synchronous reset for size counter

    // Port A
    input  logic                 a_en,
    input  logic                 a_we,
    input  logic [ADDR_W-1:0]    a_addr,
    input  logic [DATA_W-1:0]    a_wdata,
    output logic [DATA_W-1:0]    a_rdata,

    // Port B
    input  logic                 b_en,
    input  logic                 b_we,
    input  logic [ADDR_W-1:0]    b_addr,
    input  logic [DATA_W-1:0]    b_wdata,
    output logic [DATA_W-1:0]    b_rdata,

    output logic [ADDR_W:0]      size          // number of writes minus reads (simple occupancy counter)
);

  (* ram_style = "block" *) logic [DATA_W-1:0] mem [0:DEPTH-1];

  // Port A: sync read/write
  always_ff @(posedge clk) begin
    if (a_en) begin
      if (a_we) begin
        mem[a_addr] <= a_wdata;
      end
      a_rdata <= mem[a_addr];
    end
  end

  // Port B: sync read/write
  always_ff @(posedge clk) begin
    if (b_en) begin
      if (b_we) begin
        mem[b_addr] <= b_wdata;
      end
      b_rdata <= mem[b_addr];
    end
  end

  // Simple size counter based on write/read events
  // This does not look inside mem, so BRAM inference is preserved
  always_ff @(posedge clk) begin
    if (rst) begin
      size <= '0;
    end else begin
      case ({(a_en && a_we), (b_en && b_we)})
        2'b10: if (size != DEPTH[ADDR_W:0]) size <= size + 1; // one write
        2'b01: if (size != '0)              size <= size - 1; // one read (treated as "consume")
        default: size <= size;
      endcase
    end
  end

endmodule
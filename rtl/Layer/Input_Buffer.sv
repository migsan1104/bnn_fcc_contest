module Input_Buffer#(
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int N  = 64,
    parameter int DATA_NEEDED = 5,
    localparam int mem_needed = N / PW,
    localparam int addr_w     = $clog2(mem_needed)
)(
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 buffer_write,
    input  logic                 buffer_read,

    input  logic [addr_w-1:0]    raddr,

    input  logic [PN-1:0]        istream,
    output logic [PW-1:0]        ostream,

    output logic                 buffer_ready,
    output logic                 done
);

    logic fifo_empty;
    logic [PW-1:0] fifo_out;

    logic counter_go;
    logic counter_stall;
    logic counter_active;
    logic [addr_w-1:0] wr_addr;

    logic [addr_w:0] bram_size;

    // Buffer is ready once enough PW-words are stored in BRAM
    assign buffer_ready = (bram_size >= DATA_NEEDED);

    // Start draining FIFO whenever it is not empty
    assign counter_go = !fifo_empty;

    // Stall counter if FIFO has no readable slice
    assign counter_stall = fifo_empty;

    FIFO #(
      .W_WIDTH        (PN),
      .R_WIDTH        (PW),
      .DEPTH          (256),
      .PFULL_MARGIN   (32),
      .PEMPTY_MARGIN  (DATA_NEEDED)
    ) u_fifo (
      .clk      (clk),
      .rst      (rst),

      .wr_en    (buffer_write),
      .wr_data  (istream),
      .full     (),
      .pfull    (),

      .rd_en    (counter_active && !fifo_empty),
      .rd_data  (fifo_out),
      .empty    (fifo_empty),
      .pempty   ()
    );

    BRAM #(
      .DATA_W (PW),
      .ADDR_W (addr_w)
    ) u_bram (
      .clk     (clk),
      .rst     (rst),

      // Write FIFO slices into BRAM
      .a_en    (counter_active && !fifo_empty),
      .a_we    (counter_active && !fifo_empty),
      .a_addr  (wr_addr),
      .a_wdata (fifo_out),
      .a_rdata (),

      // Read side
      .b_en    (buffer_read),
      .b_we    (1'b0),
      .b_addr  (raddr),
      .b_wdata ('0),
      .b_rdata (ostream),

      .size    (bram_size)
    );

    Address_Counter #(
      .ADDR_W    (addr_w),
      .MAX_COUNT (mem_needed)
    ) u_addr_counter (
      .clk   (clk),
      .rst   (rst),
      .go    (counter_go),
      .stall (counter_stall),

      .addr  (wr_addr),
      .valid (counter_active),
      .done  (done)
    );

endmodule
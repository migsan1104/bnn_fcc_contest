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

    input  logic                 clear,        // 1-cycle pulse to reset buffer state for next layer

    input  logic                 buffer_write, // push PN-wide word into FIFO
    input  logic                 buffer_read,  // read enable for BRAM output
    input  logic [addr_w-1:0]    raddr,        // BRAM read address

    input  logic [PN-1:0]        istream,      // PN-wide input stream
    output logic [PW-1:0]        ostream,      // PW-wide output slice

    output logic                 buffer_ready, // high when BRAM has >= DATA_NEEDED slices
    output logic                 done          // address is now filled up
);

    logic fifo_empty;
    logic fifo_full;
    logic [PW-1:0] fifo_out;

    logic counter_go;
    logic counter_stall;
    logic counter_valid;
    logic [addr_w-1:0] wr_addr;

    logic [addr_w:0] bram_size;

    logic filling;

    // Buffer becomes ready once enough PW words are stored in BRAM
    assign buffer_ready = (bram_size >= DATA_NEEDED);

    // Stall counter when FIFO has no readable slice
    assign counter_stall = fifo_empty;

    // Start filling once when data first appears, predict empty->nonempty on a write
    wire start_fill = (!filling) &&
                      ( (!fifo_empty) ||
                        (buffer_write && fifo_empty && !fifo_full) );

    // consume one PW slice only when counter is producing an address and FIFO has data
    wire consume_slice = counter_valid && !fifo_empty;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            filling <= 1'b0;
        end else begin
            if (start_fill)
                filling <= 1'b1;
            if (done)
                filling <= 1'b0;
        end
    end

    assign counter_go = start_fill;

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
      .full     (fifo_full),
      .pfull    (),

      .rd_en    (consume_slice),
      .rd_data  (fifo_out),
      .empty    (fifo_empty),
      .pempty   ()
    );

    Address_Counter #(
      .ADDR_W    (addr_w),
      .MAX_COUNT (mem_needed)
    ) u_addr_counter (
      .clk   (clk),
      .rst   (rst | clear),
      .go    (counter_go),
      .stall (counter_stall),

      .addr  (wr_addr),
      .valid (counter_valid),
      .done  (done)
    );

    BRAM #(
      .DATA_W (PW),
      .ADDR_W (addr_w)
    ) u_bram (
      .clk     (clk),
      .rst     (rst | clear),

      // Port A write FIFO slices into BRAM
      .a_ren   (1'b0),
      .a_wen   (consume_slice),
      .a_addr  (wr_addr),
      .a_wdata (fifo_out),
      .a_rdata (),

      // Port B read side
      .b_ren   (buffer_read),
      .b_wen   (1'b0),
      .b_addr  (raddr),
      .b_wdata ('0),
      .b_rdata (ostream),

      .size    (bram_size)
    );

endmodule
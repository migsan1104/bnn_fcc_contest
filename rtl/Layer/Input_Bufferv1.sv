module Input_Bufferv1#(
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int N  = 64,
    parameter int DATA_NEEDED = 5,
    localparam int mem_needed = N / PW,
    localparam int addr_w     = (mem_needed <= 1) ? 1 : $clog2(mem_needed)
)(
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 clear,        // 1-cycle pulse to reset buffer state for next layer

    input  logic                 buffer_write, // write-enable for BRAM (valid input word present)
    input  logic                 buffer_read,  // read enable for BRAM output
    input  logic [addr_w-1:0]    raddr,        // BRAM read address

    input  logic [PW-1:0]        istream,      // PW-wide input word to store
    output logic [PW-1:0]        ostream,      // PW-wide output slice

    output logic                 buffer_ready // high when BRAM has >= DATA_NEEDED words
   // output logic                 done          // asserted when BRAM is filled to mem_needed
);

    logic counter_go;
    logic counter_stall;
    logic counter_valid;
    logic [addr_w-1:0] wr_addr;

    logic [addr_w:0] bram_size;
    logic filling;

    // Buffer becomes ready once enough PW words are stored in BRAM
  //  assign buffer_ready = (bram_size >= DATA_NEEDED);

    // Stall counter whenever there is no valid word to write this cycle
    assign counter_stall = !buffer_write;

    // Start filling on the first write pulse of a "session"
    wire start_fill = (!filling) && buffer_write;

    // Write to BRAM only when counter is issuing an address AND a valid word is present
    wire consume_slice = counter_valid && buffer_write;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            filling <= 1'b0;
        end else begin
            if (start_fill)
                filling <= 1'b1;
            if (buffer_ready)
                filling <= 1'b0;
        end
    end

    assign counter_go = start_fill;

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
      .done  (buffer_ready)
    );

    BRAM #(
      .DATA_W (PW),
      .ADDR_W (addr_w)
    ) u_bram (
      .clk     (clk),
      .rst     (rst | clear),

      // Port A write side
      .a_ren   (1'b0),
      .a_wen   (consume_slice),
      .a_addr  (wr_addr),
      .a_wdata (istream),
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
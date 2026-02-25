
module Input_Buffer#(
    parameter int PN = 8, // number of parralel inputs going in
    parameter int PW = 8, // number of parralel inputs going out
    parameter int N = 64,  // number of nuerons from prev layer
    localparam int mem_needed = N/PW,
    localparam int addr_w = $clog2(mem_needed)
    )
    (
    input logic clk,
    input logic rst,
    input buffer_write,
    input logic buffer_read,
    input logic done,
    output logic buffer_ready,
    output logic [$clog2(PN) - 1 : 0] istream, // input stream coming in 
    output logic [$clog2(PW) - 1 : 0] ostream // stream that gets fed into the parralel nuerons 
    );
    
    logic fifo_empty;
    assign buffer_ready = !fifo_empty;
    FIFO #(
      .W_WIDTH      (PN),
      .R_WIDTH      (PW),
      .DEPTH        (256),
      .PFULL_MARGIN (32)
    ) u_fifo (
      .clk      (clk),
      .rst      (rst),
    
      .wr_en    (buffer_write),
      .wr_data  (wr_data),
      .full     (),
      .pfull    (),
    
      .rd_en    (buffer_read),
      .rd_data  (istream),
      .rd_valid (),
      .empty    (fifo_empty)
    );
      BRAM #(
      .DATA_W (PW),
      .ADDR_W ()
    ) u_bram (
      .clk     (clk),
    
      // Port A
      .a_en    (a_en),
      .a_we    (a_we),
      .a_addr  (a_addr),
      .a_wdata (a_wdata),
      .a_rdata (a_rdata),
    
      // Port B
      .b_en    (b_en),
      .b_we    (b_we),
      .b_addr  (b_addr),
      .b_wdata (b_wdata),
      .b_rdata (b_rdata)
    );
    
        Address_Counter #(
      .ADDR_W    (),
      .MAX_COUNT (1024)
    ) u_addr_counter (
      .clk   (clk),
      .rst   (rst),
      .go    (go),
      .stall (stall),
    
      .addr  (addr),
      .valid (valid),
      .done  (done)
    );
endmodule
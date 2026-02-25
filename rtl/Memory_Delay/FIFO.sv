module FIFO #(
  parameter int W_WIDTH        = 64,   // write width
  parameter int R_WIDTH        = 8,    // read width (assumed W_WIDTH > R_WIDTH and divides evenly)
  parameter int DEPTH          = 256,  // number of W_WIDTH words stored, assumed power of 2
  parameter int PFULL_MARGIN   = 32,   // pfull asserts when only this many free WRITE words remain
  parameter int PEMPTY_MARGIN  = 5     // pempty asserts when stored WRITE words are less than this
)(
  input  logic                 clk,
  input  logic                 rst,      // synchronous active-high reset

  input  logic                 wr_en,    // push one W_WIDTH word when high
  input  logic [W_WIDTH-1:0]   wr_data,
  output logic                 full,     // completely full
  output logic                 pfull,    // programmable full

  input  logic                 rd_en,    // pop one R_WIDTH chunk when high
  output logic [R_WIDTH-1:0]   rd_data,
  output logic                 rd_valid, // pulses high for 1 cycle when rd_data updates
  output logic                 empty,    // 1 when no readable chunk is available right now
  output logic                 pempty    // 1 when stored words < PEMPTY_MARGIN
);

  localparam int ADDR_W  = $clog2(DEPTH);     // bits to address DEPTH words
  localparam int COUNT_W = $clog2(DEPTH+1);   // bits to count stored words 0..DEPTH
  localparam int R_PER_W = W_WIDTH / R_WIDTH; // number of read slices in one write word
  localparam int SLICE_W = $clog2(R_PER_W);   // bits to index slices inside a word

  // storage array , inferred Block RAM
  logic [W_WIDTH-1:0] mem [0:DEPTH-1];

  // pointers in memory space (W_WIDTH words)
  logic [ADDR_W-1:0]  wptr;                  // next memory location to write
  logic [ADDR_W-1:0]  rptr;                  // next memory location to fetch into buffers

  // occupancy in W_WIDTH words (includes words buffered in cur/next)
  logic [COUNT_W-1:0] word_count;

  // two-word prefetch buffers to hide BRAM read latency between words
  logic [W_WIDTH-1:0] cur_buf;               // current buffered word being sliced
  logic [W_WIDTH-1:0] next_buf;              // next buffered word to avoid bubbles
  logic               cur_valid;             // cur_buf contains a valid word
  logic               next_valid;            // next_buf contains a valid word
  logic [SLICE_W-1:0] cur_slice;             // which slice of cur_buf to output next

  // synchronous read interface to mem
  logic [ADDR_W-1:0]  r_addr;                // address presented to BRAM read port
  logic [W_WIDTH-1:0] mem_rdata;             // data returned from BRAM one cycle later
  logic               fetch_pending;         // we issued a read, capture mem_rdata next cycle
  logic               fetch_to_next;         // 0 load cur_buf, 1 load next_buf

  // internal control
  logic do_write;                            // accepted write this cycle
  logic do_read;                             // accepted read slice this cycle
  logic do_pop_word;                         // read consumed the last slice of cur_buf

  // bookkeeping for prefetch decision
  logic [COUNT_W-1:0] buf_words;             // number of buffered words (0,1,2)
  logic [COUNT_W-1:0] mem_words_remaining;   // words still in mem but not yet buffered

  // status thresholds
  logic [COUNT_W-1:0] pfull_threshold;

  // tidy status outputs
  assign full  = (word_count == DEPTH[COUNT_W-1:0]);
  assign pfull_threshold = DEPTH[COUNT_W-1:0] - PFULL_MARGIN[COUNT_W-1:0];
  assign pfull = (word_count >= pfull_threshold);
  assign empty = !cur_valid;                 // readable-empty: no chunk available right now
  assign pempty = (word_count < PEMPTY_MARGIN[COUNT_W-1:0]);

  // operation qualification
  always_comb begin
    do_write    = wr_en && !full;            // write allowed only when not full
    do_read     = rd_en && cur_valid;        // read allowed only when we have current word buffered
    do_pop_word = do_read && (cur_slice == R_PER_W-1);
  end

  // BRAM modeling for synthesis inference: synchronous read + synchronous write
  always_ff @(posedge clk) begin
    mem_rdata <= mem[r_addr];               // tools treat this as sync read
    if (do_write) mem[wptr] <= wr_data;     // write into memory
  end

  // buffered-word accounting for prefetch scheduling
  always_comb begin
    buf_words = (cur_valid ? 1 : 0) + (next_valid ? 1 : 0);
    mem_words_remaining = word_count - buf_words;
  end

  // main sequential control
  always_ff @(posedge clk) begin
    if (rst) begin
      wptr          <= '0;
      rptr          <= '0;
      word_count    <= '0;

      cur_buf       <= '0;
      next_buf      <= '0;
      cur_valid     <= 1'b0;
      next_valid    <= 1'b0;
      cur_slice     <= '0;

      r_addr        <= '0;
      fetch_pending <= 1'b0;
      fetch_to_next <= 1'b0;

      rd_data       <= '0;
      rd_valid      <= 1'b0;
    end else begin
      rd_valid <= 1'b0;                     // pulse only when we actually output a slice

      // advance write pointer on accepted write
      if (do_write) begin
        wptr <= wptr + 1;
      end

      // issue at most one BRAM read request at a time
      if (!fetch_pending) begin
        if (!cur_valid && (word_count != '0)) begin
          r_addr        <= rptr;            // fetch into cur_buf first
          fetch_pending <= 1'b1;
          fetch_to_next <= 1'b0;
        end else if (cur_valid && !next_valid && (mem_words_remaining != '0)) begin
          r_addr        <= rptr;            // prefetch next_buf while streaming cur_buf
          fetch_pending <= 1'b1;
          fetch_to_next <= 1'b1;
        end
      end

      // capture BRAM read result into the requested buffer
      if (fetch_pending) begin
        if (!fetch_to_next) begin
          cur_buf   <= mem_rdata;
          cur_valid <= 1'b1;
          cur_slice <= '0;
        end else begin
          next_buf   <= mem_rdata;
          next_valid <= 1'b1;
        end
        rptr          <= rptr + 1;          // consumed one word from memory into a buffer
        fetch_pending <= 1'b0;
      end

      // output read slices
      if (do_read) begin
        rd_data  <= cur_buf[cur_slice*R_WIDTH +: R_WIDTH];
        rd_valid <= 1'b1;

        if (!do_pop_word) begin
          cur_slice <= cur_slice + 1;
        end else begin
          if (next_valid) begin
            cur_buf    <= next_buf;         // seamless switch to next word
            cur_valid  <= 1'b1;
            next_valid <= 1'b0;
            cur_slice  <= '0;
          end else begin
            cur_valid <= 1'b0;              // no prefetched word available, will fetch later
            cur_slice <= '0;
          end
        end
      end

      // update occupancy in W_WIDTH words
      case ({do_write, do_pop_word})
        2'b10: word_count <= word_count + 1; // write adds one word
        2'b01: word_count <= word_count - 1; // finishing a word removes one word
        default: word_count <= word_count;   // both or neither
      endcase
    end
  end

endmodule
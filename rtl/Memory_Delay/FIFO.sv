module  FIFO #(
  parameter int W_WIDTH = 64,                 // write width
  parameter int R_WIDTH = 8,                  // read interface width
  parameter int DEPTH   = 256,                // number of W_WIDTH words stored , assumed to be a power of 2
  parameter int PFULL_MARGIN = 32             // programmable full
)(
  input  logic                 clk,
  input  logic                 rst,            // synchronous active-high reset

  input  logic                 wr_en,          // push one W_WIDTH word when high
  input  logic [W_WIDTH-1:0]   wr_data,
  output logic                 full,           // completely full
  output logic                 pfull,          // programable full

  input  logic                 rd_en,          // pop one R_WIDTH chunk when high
  output logic [R_WIDTH-1:0]   rd_data,
  output logic                 rd_valid,       // pulses high for 1 cycle when rd_data updates
  output logic                 empty           // 1 when no readable chunk is available right now
);

  localparam int ADDR_W  = $clog2(DEPTH);           // bits to address DEPTH words
  localparam int COUNT_W = $clog2(DEPTH+1);         // bits to count amount of words we are currently storing
  localparam int R_PER_W = W_WIDTH / R_WIDTH;       // number of read slices in one write word
  localparam int SLICE_W = $clog2(R_PER_W);         // bits to index slices inside a word

  logic [W_WIDTH-1:0] mem [0:DEPTH-1];              // storage array , inferred Block RAM

  logic [ADDR_W-1:0]  wptr;                         // points to next memory location to write
  logic [ADDR_W-1:0]  rptr;                         // points to next memory location to fetch into buffers

  logic [COUNT_W-1:0] word_count;                   // number of W_WIDTH words currently in the FIFO (includes buffered words)

  logic [W_WIDTH-1:0] cur_buf;                      // current buffered W_WIDTH word we are slicing out to rd_data
  logic [W_WIDTH-1:0] next_buf;                     // next buffered W_WIDTH word to allow seamless word-to-word streaming
  logic               cur_valid;                    // 1 when cur_buf contains a valid word
  logic               next_valid;                   // 1 when next_buf contains a valid word
  logic [SLICE_W-1:0] cur_slice;                    // index of which R_WIDTH slice to output next from cur_buf

  logic [ADDR_W-1:0]  r_addr;                       // address presented to the internal synchronous read port
  logic [W_WIDTH-1:0] mem_rdata;                    // data returned from memory 1 cycle after r_addr is set
  logic               fetch_pending;                // 1 when we issued a read and must capture mem_rdata next cycle
  logic               fetch_to_next;                // 0 means load cur_buf, 1 means load next_buf on fetch completion

  logic do_write;                                   // 1 when a write is accepted this cycle
  logic do_read;                                    // 1 when a read slice is accepted this cycle
  logic do_pop_word;                                // 1 when the read slice consumes the last slice of cur_buf

  logic [COUNT_W-1:0] buf_words;                    // number of buffered words (0,1,2)
  logic [COUNT_W-1:0] mem_words_remaining;          // number of words still sitting only in memory (not yet buffered)
  logic [COUNT_W-1:0] pfull_threshold;              // computed threshold = DEPTH - PFULL_MARGIN

  always_ff @(posedge clk) begin
    mem_rdata <= mem[r_addr];                       // synchronous read model so tools can map to BRAM
    if (do_write) mem[wptr] <= wr_data;             // synchronous write into memory
  end

  always_comb begin
    buf_words = (cur_valid ? 1 : 0) + (next_valid ? 1 : 0);              // buffered words count helps prefetch decision
    mem_words_remaining = word_count - buf_words;                         // words still in memory that are not buffered yet
  end

  always_comb full  = (word_count == DEPTH[COUNT_W-1:0]);                 // full means no more W_WIDTH words can be stored
  always_comb begin
    pfull_threshold = DEPTH[COUNT_W-1:0] - PFULL_MARGIN[COUNT_W-1:0];     // pfull triggers when only PFULL_MARGIN free slots remain
    pfull = (word_count >= pfull_threshold);
  end
  always_comb empty = !cur_valid;                                         // empty means we cannot output a read slice right now

  always_comb begin
    do_write    = wr_en && !full;                                         // accept write only when there is space
    do_read     = rd_en && cur_valid;                                     // accept read only when we have a current word buffered
    do_pop_word = do_read && (cur_slice == R_PER_W-1);                    // last slice means we finished this buffered word
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      wptr          <= '0;                                                // reset write pointer
      rptr          <= '0;                                                // reset fetch pointer
      word_count    <= '0;                                                // FIFO starts empty
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
      rd_valid <= 1'b0;                                                   // rd_valid is a one-cycle pulse when rd_data updates

      if (do_write) begin                                                 // writing pushes a full W_WIDTH word into FIFO
        wptr <= wptr + 1;                                                 // advance write pointer to next slot
      end

      if (!fetch_pending) begin                                           // issue at most one memory read request at a time
        if (!cur_valid && (word_count != '0)) begin                       // if no current word buffered but FIFO has data, fetch cur_buf
          r_addr        <= rptr;                                          // present address of next word to fetch
          fetch_pending <= 1'b1;                                          // remember that mem_rdata will be valid next cycle
          fetch_to_next <= 1'b0;                                          // next cycle, load cur_buf
        end else if (cur_valid && !next_valid && (mem_words_remaining != '0)) begin
          r_addr        <= rptr;                                          // if cur exists and next is empty, prefetch next_buf
          fetch_pending <= 1'b1;                                          // remember that mem_rdata will be valid next cycle
          fetch_to_next <= 1'b1;                                          // next cycle, load next_buf
        end
      end

      if (fetch_pending) begin                                            // complete the memory fetch and fill the correct buffer
        if (!fetch_to_next) begin
          cur_buf   <= mem_rdata;                                         // load current buffer with fetched word
          cur_valid <= 1'b1;                                              // mark current buffer valid
          cur_slice <= '0;                                                // start slicing from slice 0
        end else begin
          next_buf   <= mem_rdata;                                        // load next buffer with fetched word
          next_valid <= 1'b1;                                             // mark next buffer valid
        end
        rptr          <= rptr + 1;                                        // advance fetch pointer since we pulled one word from memory
        fetch_pending <= 1'b0;                                            // clear pending flag
      end

      if (do_read) begin                                                  // reading outputs one R_WIDTH slice each cycle
        rd_data  <= cur_buf[cur_slice*R_WIDTH +: R_WIDTH];                // output the selected slice from current buffer
        rd_valid <= 1'b1;                                                 // pulse valid for this output

        if (!do_pop_word) begin
          cur_slice <= cur_slice + 1;                                     // move to the next slice in the same word
        end else begin
          if (next_valid) begin                                           // if next word is already prefetched, switch immediately with no bubble
            cur_buf    <= next_buf;                                       // promote next word to be the current word
            cur_valid  <= 1'b1;                                           // current remains valid
            next_valid <= 1'b0;                                           // next is now empty and will be refilled by prefetch logic
            cur_slice  <= '0;                                             // start slicing the new current word from slice 0
          end else begin
            cur_valid <= 1'b0;                                            // if no next word buffered, we will fetch next on a later cycle
            cur_slice <= '0;                                              // reset slice index for the next buffered word
          end
        end
      end

      case ({do_write, do_pop_word})
        2'b10: word_count <= word_count + 1;                              // accepted write adds one W_WIDTH word to FIFO
        2'b01: word_count <= word_count - 1;                              // finishing last slice removes one W_WIDTH word from FIFO
        default: word_count <= word_count;                                // write+pop_word cancels out, or neither happens
      endcase
    end
  end

endmodule
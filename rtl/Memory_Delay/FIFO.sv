module FIFO #(
  parameter int W_WIDTH        = 64,   // width of each word written into the FIFO
  parameter int R_WIDTH        = 8,    // width of each slice read out of the FIFO
  parameter int DEPTH          = 256,  // number of W_WIDTH words the FIFO can store
  parameter int PFULL_MARGIN   = 32,   // programmable full threshold margin
  parameter int PEMPTY_MARGIN  = 5     // programmable empty threshold margin
)(
  input  logic                 clk,
  input  logic                 rst,      // synchronous active-high reset

  input  logic                 wr_en,    // write enable: push one W_WIDTH word
  input  logic [W_WIDTH-1:0]   wr_data,  // data to be written
  output logic                 full,     // FIFO cannot accept more writes
  output logic                 pfull,    // FIFO almost full

  input  logic                 rd_en,    // read enable: consume current slice
  output logic [R_WIDTH-1:0]   rd_data,  // current slice is visible whenever empty=0
  output logic                 empty,    // 1 means no readable slice available
  output logic                 pempty    // FIFO almost empty
);

  localparam int ADDR_W  = $clog2(DEPTH);        // bits needed to index memory depth
  localparam int COUNT_W = $clog2(DEPTH+1);      // bits needed to count stored words
  localparam int R_PER_W = W_WIDTH / R_WIDTH;    // number of read slices per word
  localparam int SLICE_W = $clog2(R_PER_W);      // bits needed to index slice inside a word

  // Block RAM storage array
  logic [W_WIDTH-1:0] mem [0:DEPTH-1];

  // Write and read pointers for whole words
  logic [ADDR_W-1:0]  wptr;
  logic [ADDR_W-1:0]  rptr;

  // Counts how many full W_WIDTH words are stored
  logic [COUNT_W-1:0] word_count;

  // Front word currently being sliced for reading
  logic [W_WIDTH-1:0] cur_buf;
  logic [W_WIDTH-1:0] next_buf;
  logic               cur_valid;
  logic               next_valid;
  logic [SLICE_W-1:0] cur_slice;

  // Signals used for synchronous RAM read
  logic [ADDR_W-1:0]  r_addr;
  logic [W_WIDTH-1:0] mem_rdata;
  logic               fetch_pending;
  logic               fetch_to_next;

  // Internal handshake logic
  logic do_write;
  logic do_read;
  logic do_pop_word;

  // Used to determine when to prefetch
  logic [COUNT_W-1:0] buf_words;
  logic [COUNT_W-1:0] mem_words_remaining;

  logic [COUNT_W-1:0] pfull_threshold;

  // Special flag for first-word fall-through bypass
  logic bypass_active;

  // Full and programmable full detection
  assign full  = (word_count == DEPTH[COUNT_W-1:0]);
  assign pfull_threshold = DEPTH[COUNT_W-1:0] - PFULL_MARGIN[COUNT_W-1:0];
  assign pfull = (word_count >= pfull_threshold);
  assign pempty = (word_count < PEMPTY_MARGIN[COUNT_W-1:0]);

  // Determine whether write or read will actually happen
  always_comb begin
    do_write    = wr_en && !full;      // write only if not full
    do_read     = rd_en && !empty;     // read only if data is available
    do_pop_word = do_read && (cur_slice == R_PER_W-1);  // true when finishing last slice of a word
  end

  // Synchronous RAM behavior: read returns data one cycle after address is set
  always_ff @(posedge clk) begin
    mem_rdata <= mem[r_addr];
    if (do_write) mem[wptr] <= wr_data;
  end

  // Track how many words are currently buffered in cur_buf and next_buf
  always_comb begin
    buf_words = (cur_valid ? 1 : 0) + (next_valid ? 1 : 0);
    mem_words_remaining = word_count - buf_words;
  end

  // Output logic: rd_data always shows current slice whenever empty=0
  always_comb begin
    empty = !(cur_valid || bypass_active);
    if (bypass_active) begin
      rd_data = wr_data[cur_slice*R_WIDTH +: R_WIDTH];  // directly slice write data when FIFO was empty
    end else if (cur_valid) begin
      rd_data = cur_buf[cur_slice*R_WIDTH +: R_WIDTH];  // normal case: slice from buffered word
    end else begin
      rd_data = '0;
    end
  end

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

      bypass_active <= 1'b0;
    end else begin

      // Advance write pointer when accepting a write
      if (do_write) begin
        wptr <= wptr + 1;
      end

      // If FIFO was empty and we write a word, immediately expose it via bypass
      if (!cur_valid && !bypass_active && (word_count == '0) && do_write) begin
        bypass_active <= 1'b1;
        cur_slice     <= '0;
        rptr          <= rptr + 1;
        fetch_pending <= 1'b0;
      end

      // Consume a slice when rd_en is asserted and data is available
      if (do_read) begin
        if (!do_pop_word) begin
          cur_slice <= cur_slice + 1;
        end else begin
          cur_slice <= '0;
          if (bypass_active) begin
            bypass_active <= 1'b0;
            cur_valid     <= 1'b0;
          end else if (next_valid) begin
            cur_buf    <= next_buf;
            cur_valid  <= 1'b1;
            next_valid <= 1'b0;
          end else begin
            cur_valid <= 1'b0;
          end
        end
      end

      // Prefetch logic for next word when not bypassing
      if (!bypass_active) begin
        if (!fetch_pending) begin
          if (!cur_valid && (word_count != '0)) begin
            r_addr        <= rptr;
            fetch_pending <= 1'b1;
            fetch_to_next <= 1'b0;
          end else if (cur_valid && !next_valid && (mem_words_remaining != '0)) begin
            r_addr        <= rptr;
            fetch_pending <= 1'b1;
            fetch_to_next <= 1'b1;
          end
        end

        if (fetch_pending) begin
          if (!fetch_to_next) begin
            cur_buf   <= mem_rdata;
            cur_valid <= 1'b1;
            cur_slice <= '0;
          end else begin
            next_buf   <= mem_rdata;
            next_valid <= 1'b1;
          end
          rptr          <= rptr + 1;
          fetch_pending <= 1'b0;
        end
      end

      // Update stored word count when full word is written or fully consumed
      case ({do_write, do_pop_word})
        2'b10: word_count <= word_count + 1;
        2'b01: word_count <= word_count - 1;
        default: word_count <= word_count;
      endcase

    end
  end

endmodule
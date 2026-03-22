`timescale 1ns / 1ps

module Input_Bufferv2#(
    parameter int TN = 22,                           // true image width in bits
    parameter int PN = 8,                            // width of each incoming word from input layer
    localparam int mem_needed = (TN + PN - 1) / PN,  // number of PN-wide words needed
    localparam int PW = mem_needed * PN,             // padded full-image width sent to H0
    localparam int addr_w = (mem_needed <= 1) ? 1 : $clog2(mem_needed)
)(
    input  logic                 clk,
    input  logic                 rst,

    input  logic                 buffer_write,    // writes one PN-wide word into current write bank
    input  logic                 buffer_read,     // kept for interface compatibility
    input  logic [addr_w-1:0]    raddr,           // kept for interface compatibility

    input  logic                 read_bank_sel,   // selects which bank is exposed on ostream
    input  logic                 clear_bank0,     // clears bank0 after it has been used
    input  logic                 clear_bank1,     // clears bank1 after it has been used

    input  logic [PN-1:0]        istream,         // incoming PN-wide word from input layer
    output logic [PW-1:0]        ostream,         // full zero-padded image from selected bank

    output logic                 start_allowed_bank0,   // high when bank0 has collected all words
    output logic                 start_allowed_bank1,   // high when bank1 has collected all words
    output logic                 buffer_has_addr_bank0, // high when bank0 holds a full image
    output logic                 buffer_has_addr_bank1, // high when bank1 holds a full image
    output logic                 buffer_stall           // early backpressure for H0 input path
);

    // This tracks which bank is currently being filled
    logic                        write_bank_sel;

    // These track how many words have been written into each bank
    logic [addr_w:0]             word_count_bank0;
    logic [addr_w:0]             word_count_bank1;

    // These track the next word slot to fill in each bank
    logic [addr_w-1:0]           wr_addr_bank0;
    logic [addr_w-1:0]           wr_addr_bank1;

    // These say when a write is accepted into a bank
    logic                        write_accept_bank0;
    logic                        write_accept_bank1;

    // These pulse when the last required word is written into a bank
    logic                        bank0_full_write;
    logic                        bank1_full_write;

    // These hold one full zero-padded image per bank
    logic [PW-1:0]               bank0_mem;
    logic [PW-1:0]               bank1_mem;

    // These define the early-stall threshold for H0
    localparam int stall_needed = (mem_needed > 2) ? (mem_needed - 2) : mem_needed;

    // A bank becomes readable only after the whole image has been collected
    assign start_allowed_bank0 = (word_count_bank0 == mem_needed);
    assign start_allowed_bank1 = (word_count_bank1 == mem_needed);

    // These now mean the bank holds one complete readable image
    assign buffer_has_addr_bank0 = start_allowed_bank0;
    assign buffer_has_addr_bank1 = start_allowed_bank1;

    // Only the selected write bank can accept data, and only until it is full
    assign write_accept_bank0 = buffer_write && !write_bank_sel && (word_count_bank0 < mem_needed);
    assign write_accept_bank1 = buffer_write &&  write_bank_sel && (word_count_bank1 < mem_needed);

    // These detect the exact write that finishes collecting a whole image
    assign bank0_full_write = write_accept_bank0 && (word_count_bank0 == mem_needed - 1);
    assign bank1_full_write = write_accept_bank1 && (word_count_bank1 == mem_needed - 1);

    // H0 stalls early so in-flight words from Input_Layer do not overflow the bank
    always_comb begin
        if (write_bank_sel)
            buffer_stall = (word_count_bank1 >= stall_needed);
        else
            buffer_stall = (word_count_bank0 >= stall_needed);
    end

    // This switches banks once the current write bank has collected the full image
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_bank_sel <= 1'b0;
        end else begin
            if (bank0_full_write)
                write_bank_sel <= 1'b1;
            else if (bank1_full_write)
                write_bank_sel <= 1'b0;
        end
    end

    // This handles fill count, write address, and storage for bank0
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            word_count_bank0 <= '0;
            wr_addr_bank0    <= '0;
            bank0_mem        <= '0;
        end else begin
            if (clear_bank0) begin
                word_count_bank0 <= '0;
                wr_addr_bank0    <= '0;
                bank0_mem        <= '0;
            end else if (write_accept_bank0) begin
                bank0_mem[wr_addr_bank0*PN +: PN] <= istream;
                word_count_bank0                  <= word_count_bank0 + 1'b1;
                wr_addr_bank0                     <= wr_addr_bank0 + 1'b1;
            end
        end
    end

    // This handles fill count, write address, and storage for bank1
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            word_count_bank1 <= '0;
            wr_addr_bank1    <= '0;
            bank1_mem        <= '0;
        end else begin
            if (clear_bank1) begin
                word_count_bank1 <= '0;
                wr_addr_bank1    <= '0;
                bank1_mem        <= '0;
            end else if (write_accept_bank1) begin
                bank1_mem[wr_addr_bank1*PN +: PN] <= istream;
                word_count_bank1                  <= word_count_bank1 + 1'b1;
                wr_addr_bank1                     <= wr_addr_bank1 + 1'b1;
            end
        end
    end

    // This exposes the full zero-padded image from the selected read bank
    always_comb begin
        if (read_bank_sel)
            ostream = bank1_mem;
        else
            ostream = bank0_mem;
    end

endmodule
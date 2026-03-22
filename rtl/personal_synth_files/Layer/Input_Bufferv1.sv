`timescale 1ns / 1ps

module Input_Bufferv1 #(
    parameter int LAYER_ID = 0,
    parameter int IB_WIDTH = 8,
    parameter int PW       = 8,
    parameter int TN       = 64,
    localparam int writer_id = LAYER_ID,

    // Number of PW-wide words needed to hold one full input vector
    localparam int MEM_NEEDED = (TN + PW - 1) / PW,

    // Address width for each BRAM bank
    localparam int ADDR_W     = (MEM_NEEDED <= 1) ? 1 : $clog2(MEM_NEEDED)
)(
    input  logic                clk,
    input  logic                rst,

    // Producer writes one word into the current write bank
    input  logic                buffer_write,

    // Consumer reads one word from the selected read bank
    input  logic                buffer_read,

    // Read address used by the consumer side
    input  logic [ADDR_W-1:0]   raddr,

    // Selects which bank is being read
    input  logic                read_bank_sel,

    // Clears bank0 after its image has been consumed
    input  logic                clear_bank0,

    // Clears bank1 after its image has been consumed
    input  logic                clear_bank1,

    // Input word written into the active write bank
    input  logic [IB_WIDTH-1:0] istream,

    // Output word read from the selected read bank
    output logic [PW-1:0]       ostream,

    // Goes high when bank0 contains a full image
    output logic                start_allowed_bank0,

    // Goes high when bank1 contains a full image
    output logic                start_allowed_bank1,

    // Says bank0 already has the requested read address stored
    output logic                buffer_has_addr_bank0,

    // Says bank1 already has the requested read address stored
    output logic                buffer_has_addr_bank1,

    // Exposes which bank the producer is currently writing into
    output logic                write_bank_sel_out,

    // Backpressures the producer when both banks are occupied
    output logic                stall
);

    // Current bank selected for incoming writes
    logic              write_bank_sel;

    // Remembers which bank we want to switch to once it becomes safe
    logic              pending_switch_bank;

    // Next write address for bank0
    logic [ADDR_W-1:0] wr_addr_bank0;

    // Next write address for bank1
    logic [ADDR_W-1:0] wr_addr_bank1;

    // Number of valid words currently stored in bank0
    logic [ADDR_W:0]   bram_size_bank0;

    // Number of valid words currently stored in bank1
    logic [ADDR_W:0]   bram_size_bank1;

    // Accepts a write into bank0 only when bank0 is the active write bank and not full
    logic              write_accept_bank0;

    // Accepts a write into bank1 only when bank1 is the active write bank and not full
    logic              write_accept_bank1;

    // True on the exact cycle bank0 receives its final word
    logic              bank0_full_write;

    // True on the exact cycle bank1 receives its final word
    logic              bank1_full_write;

    // True when bank0 holds no valid data
    logic              bank0_empty;

    // True when bank1 holds no valid data
    logic              bank1_empty;

    // Read data coming back from bank0
    logic [PW-1:0]     ostream_bank0;

    // Read data coming back from bank1
    logic [PW-1:0]     ostream_bank1;

    // A bank is empty when its tracked size is zero
    assign bank0_empty = (bram_size_bank0 == '0);

    // A bank is empty when its tracked size is zero
    assign bank1_empty = (bram_size_bank1 == '0);

    // Export the current write-bank ownership to the outside world
    assign write_bank_sel_out = write_bank_sel;

    // A bank is ready to start once it contains one full image
    assign start_allowed_bank0 = (bram_size_bank0 >= MEM_NEEDED);

    // A bank is ready to start once it contains one full image
    assign start_allowed_bank1 = (bram_size_bank1 >= MEM_NEEDED);

    // The requested read address is valid only if it is already stored in that bank
    assign buffer_has_addr_bank0 = (raddr < bram_size_bank0);

    // The requested read address is valid only if it is already stored in that bank
    assign buffer_has_addr_bank1 = (raddr < bram_size_bank1);

    assign write_accept_bank0 =
        buffer_write && !stall && !write_bank_sel &&
        !clear_bank0 && (bram_size_bank0 < MEM_NEEDED);

    assign write_accept_bank1 =
        buffer_write && !stall &&  write_bank_sel &&
        !clear_bank1 && (bram_size_bank1 < MEM_NEEDED);

    // Detect the exact cycle bank0 becomes full
    assign bank0_full_write = write_accept_bank0 && (bram_size_bank0 == MEM_NEEDED - 1);

    // Detect the exact cycle bank1 becomes full
    assign bank1_full_write = write_accept_bank1 && (bram_size_bank1 == MEM_NEEDED - 1);

    // The following logic is for write bank selection
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            write_bank_sel      <= 1'b0;
            pending_switch_bank <= 1'b0;
            stall               <= 1'b0;
        end else begin
            // If we are stalled, wait until the other bank is done being read from and cleared
            if (stall) begin
                if ((pending_switch_bank == 1'b0 && clear_bank0) ||
                    (pending_switch_bank == 1'b1 && clear_bank1)) begin
                    write_bank_sel      <= pending_switch_bank;
                    pending_switch_bank <= 1'b0;
                    stall               <= 1'b0;
                end
            end else begin
                // When bank0 just became full, try to switch to bank1
                if (bank0_full_write) begin
                    // If bank1 is empty or being cleared right now, switch immediately
                    if (bank1_empty || clear_bank1) begin
                        write_bank_sel      <= 1'b1;
                        pending_switch_bank <= 1'b0;
                    end else begin
                        // If bank1 is still being read from we have to stall
                        pending_switch_bank <= 1'b1;
                        stall               <= 1'b1;
                    end
                end
                // When bank1 just became full, try to switch to bank0
                else if (bank1_full_write) begin
                    // If bank0 is empty or being cleared right now, switch immediately
                    if (bank0_empty || clear_bank0) begin
                        write_bank_sel      <= 1'b0;
                        pending_switch_bank <= 1'b0;
                    end else begin
                        // Otherwise remember the desired bank and stall until it is cleared
                        pending_switch_bank <= 1'b0;
                        stall               <= 1'b1;
                    end
                end
            end
        end
    end

    // Track the address we need to write to next for bank0
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            wr_addr_bank0 <= '0;
        else begin
            // Clearing bank0 resets its write pointer
            if (clear_bank0)
                wr_addr_bank0 <= '0;
            // Accepted writes advance the write pointer
            else if (write_accept_bank0)
                wr_addr_bank0 <= wr_addr_bank0 + 1'b1;
        end
    end

    // Track the address we need to write to next for bank1
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            wr_addr_bank1 <= '0;
        else begin
            // Clearing bank1 resets its write pointer
            if (clear_bank1)
                wr_addr_bank1 <= '0;
            // Accepted writes advance the write pointer
            else if (write_accept_bank1)
                wr_addr_bank1 <= wr_addr_bank1 + 1'b1;
        end
    end

    // Bank0 BRAM uses port A for writes and port B for reads
    BRAM #(
        .DATA_W (PW),
        .ADDR_W (ADDR_W)
    ) u_bram_bank0 (
        .clk     (clk),
        .rst     (rst),
        .clear   (clear_bank0),
        

        .a_ren   (1'b0),
        .a_wen   (write_accept_bank0),
        .a_addr  (wr_addr_bank0),
        .a_wdata (istream[PW-1:0]),
        .a_rdata (),

        .b_ren   (buffer_read && !read_bank_sel),
        .b_wen   (1'b0),
        .b_addr  (raddr),
        .b_wdata ('0),
        .b_rdata (ostream_bank0),

        .size    (bram_size_bank0)
    );

    // Bank1 BRAM uses port A for writes and port B for reads
    BRAM #(
        .DATA_W (PW),
        .ADDR_W (ADDR_W)
    ) u_bram_bank1 (
        .clk     (clk),
        .rst     (rst),
        .clear   (clear_bank1),
        

        .a_ren   (1'b0),
        .a_wen   (write_accept_bank1),
        .a_addr  (wr_addr_bank1),
        .a_wdata (istream[PW-1:0]),
        .a_rdata (),

        .b_ren   (buffer_read && read_bank_sel),
        .b_wen   (1'b0),
        .b_addr  (raddr),
        .b_wdata ('0),
        .b_rdata (ostream_bank1),

        .size    (bram_size_bank1)
    );

    // Read data comes from whichever bank the consumer selected
    always_comb begin
        if (read_bank_sel)
            ostream = ostream_bank1;
        else
            ostream = ostream_bank0;
    end

endmodule
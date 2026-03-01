`timescale 1ns / 1ps

module Layer_Control#(

    parameter int PN = 8,               // Number of parallel neuron processors
    parameter int PW = 8,               // Number of bits processed per beat
    parameter int TN = 16,              // Total input bits per neuron
    parameter int N_NEURONS = 16,       // Total neurons in this layer
    parameter int TW = 32,              // Threshold width stored in RAM

    localparam int beats   = (TN + PW - 1) / PW,                 // Number of beats required to process one neuron
    localparam int BEAT_W  = (beats <= 1) ? 1 : $clog2(beats),   // Width of beat counter
    localparam int TW_addr = (N_NEURONS <= 1) ? 1 : $clog2(N_NEURONS), // Threshold RAM address width
    localparam int W_addr  = (beats*N_NEURONS <= 1) ? 1 : $clog2(beats * N_NEURONS), // Weight RAM address width
    localparam int GROUPS  = (N_NEURONS + PN - 1) / PN,          // Number of neuron groups processed in parallel
    localparam int GRP_W   = (GROUPS <= 1) ? 1 : $clog2(GROUPS)  // Width of group counter

)(

    input  logic clk,                   // System clock
    input  logic rst,                   // Synchronous active-high reset

    input  logic start_layer,           // One-cycle pulse to start layer execution
    input  logic cfg_done,              // High when weight and threshold RAMs are configured

    input  logic buffer_ready,          // High when Input_Buffer has enough pixel data
    output logic buffer_read,           // Enables reading from Input_Buffer BRAM
    output logic buffer_clear,          // One-cycle pulse to reset Input_Buffer
    output logic [BEAT_W-1:0] buffer_raddr, // Read address into Input_Buffer

    output logic [PN-1:0][W_addr-1:0]  w_ram_b_addr, // Weight RAM read addresses
    output logic [PN-1:0][TW_addr-1:0] t_ram_b_addr, // Threshold RAM read addresses

    output logic [PN-1:0] valid_in,     // Valid signal into each NP
    output logic [PN-1:0] last_in,      // Last-beat indicator into each NP

    output logic layer_active,          // High while layer is processing
    output logic controller_done        // One-cycle pulse when entire layer completes
);

    // State machine states
    typedef enum logic [2:0] {S_IDLE, S_WAIT_CFG, S_WAIT_BUF, S_STREAM, S_DONE, S_CLEAR} state_t;

    state_t state, state_n;             // Current and next state

    logic [BEAT_W-1:0] beat_idx, beat_idx_n;   // Beat counter within a neuron
    logic [GRP_W-1:0]  group_idx, group_idx_n; // Which group of PN neurons we are processing

    logic issue;                        // High when issuing RAM read addresses
    logic issue_d;                      // Delayed version of issue for sync RAM alignment
    logic last_issue;                   // High when current beat is final beat
    logic last_issue_d;                 // Delayed version aligned to RAM output

    logic [TW_addr-1:0] neuron_base;    // Base neuron index for this group
    logic [PN-1:0] lane_active;         // Indicates which NP lanes are valid for this group

    integer i;

    // Combinational FSM Logic
    always_comb begin

        // Default assignments
        state_n        = state;
        beat_idx_n     = beat_idx;
        group_idx_n    = group_idx;

        buffer_read    = 1'b0;
        buffer_clear   = 1'b0;
        buffer_raddr   = '0;

        w_ram_b_addr   = '0;
        t_ram_b_addr   = '0;

        valid_in       = '0;
        last_in        = '0;

        layer_active   = 1'b0;
        controller_done = 1'b0;

        issue          = 1'b0;
        last_issue     = 1'b0;

        // Base neuron index for this parallel group
        neuron_base = group_idx * PN;

        // Determine which NP lanes are active
        for (i = 0; i < PN; i++) begin
            lane_active[i] = ((neuron_base + i) < N_NEURONS);
        end

        case (state)

            // Wait for start signal
            S_IDLE: begin
                beat_idx_n  = '0;
                group_idx_n = '0;
                if (start_layer) state_n = S_WAIT_CFG;
            end

            // Wait until weights and thresholds are loaded
            S_WAIT_CFG: begin
                if (cfg_done) state_n = S_WAIT_BUF;
            end

            // Wait until input buffer has enough data
            S_WAIT_BUF: begin
                if (buffer_ready) state_n = S_STREAM;
            end

            // Main streaming state
            S_STREAM: begin

                layer_active = 1'b1;              // Indicate active processing

                issue        = 1'b1;              // Issue RAM reads this cycle
                last_issue   = (beat_idx == beats-1);

                buffer_read  = 1'b1;              // Enable pixel read
                buffer_raddr = beat_idx;          // Pixel address equals beat index

                // Generate weight and threshold addresses per NP lane
                for (i = 0; i < PN; i++) begin
                    t_ram_b_addr[i] = neuron_base + i;
                    w_ram_b_addr[i] = (neuron_base + i) * beats + beat_idx;
                end

                // Advance beat counter
                if (beat_idx == beats-1) begin
                    beat_idx_n = '0;

                    // Advance group counter
                    if (group_idx == GROUPS-1) begin
                        state_n     = S_DONE;
                        group_idx_n = '0;
                    end else begin
                        group_idx_n = group_idx + 1;
                    end

                end else begin
                    beat_idx_n = beat_idx + 1;
                end
            end

            // One-cycle done pulse
            S_DONE: begin
                controller_done = 1'b1;
                state_n         = S_CLEAR;
            end

            // Clear input buffer for next layer
            S_CLEAR: begin
                buffer_clear = 1'b1;
                state_n      = S_IDLE;
            end

        endcase
    end

    // Sequential State Update

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            beat_idx     <= '0;
            group_idx    <= '0;
            issue_d      <= 1'b0;
            last_issue_d <= 1'b0;
        end else begin
            state        <= state_n;
            beat_idx     <= beat_idx_n;
            group_idx    <= group_idx_n;
            issue_d      <= issue;                // Align valid with sync RAM read
            last_issue_d <= last_issue && issue;
        end
    end

    // Align Valid Signals to RAM Output
    always_comb begin
        valid_in = '0;
        last_in  = '0;

        for (i = 0; i < PN; i++) begin
            valid_in[i] = issue_d && lane_active[i];
            last_in[i]  = last_issue_d && lane_active[i];
        end
    end

endmodule
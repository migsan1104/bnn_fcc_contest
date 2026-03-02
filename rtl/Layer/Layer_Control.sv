`timescale 1ns / 1ps

module Layer_Control#(

    parameter int PN = 8,               // Number of parallel neuron processors instantiated in hardware
    parameter int PW = 8,               // Number of bits processed per beat
    parameter int TN = 16,              // Total input bits per neuron
    parameter int N_NEURONS = 16,       // Total neurons that exist in this layer
    parameter int TW = 32,              // Threshold width stored in RAM

    localparam int beats   = (TN + PW - 1) / PW,                 // Number of beats required to process one neuron
    localparam int BEAT_W  = (beats <= 1) ? 1 : $clog2(beats),   // Width of beat counter
    localparam int TW_addr = (N_NEURONS <= 1) ? 1 : $clog2(N_NEURONS), // Threshold RAM address width
    localparam int W_addr  = (beats*N_NEURONS <= 1) ? 1 : $clog2(beats * N_NEURONS), // Weight RAM address width
    localparam int GROUPS  = (N_NEURONS + PN - 1) / PN,          // Number of time-multiplexed passes needed because we only have PN hardware lanes
    localparam int GRP_W   = (GROUPS <= 1) ? 1 : $clog2(GROUPS)  // Width of group counter

)(

    input  logic clk,                   // System clock
    input  logic rst,                   // Synchronous active-high reset

    input  logic start_layer,           // One-cycle pulse to start layer execution
    input  logic cfg_done,              // High when weight and threshold RAMs are configured

    input  logic buffer_ready,          // High when Input_Buffer is full for this layer
    output logic buffer_read,           // Enables reading from Input_Buffer BRAM
    output logic buffer_clear,          // One-cycle pulse to reset Input_Buffer
    output logic [BEAT_W-1:0] buffer_raddr, // Read address into Input_Buffer

    output logic [PN-1:0]               w_ram_b_ren,  // Weight RAM read enables
    output logic [PN-1:0]               t_ram_b_ren,  // Threshold RAM read enables
    output logic [PN-1:0][W_addr-1:0]   w_ram_b_addr, // Weight RAM read addresses
    output logic [PN-1:0][TW_addr-1:0]  t_ram_b_addr, // Threshold RAM read addresses

    output logic [PN-1:0] valid_in,     // Valid signal into each NP aligned to RAM output
    output logic [PN-1:0] last_in,      // Last-beat indicator into each NP aligned to RAM output

    output logic layer_active,          // High while layer is processing
    output logic controller_done        // One-cycle pulse when entire layer completes
);

    typedef enum logic [2:0] {S_IDLE, S_WAIT_CFG, S_WAIT_BUF, S_STREAM, S_DONE, S_CLEAR} state_t; // FSM states

    state_t state, state_n;             // Current and next state

    logic [BEAT_W-1:0] beat_idx, beat_idx_n;   // Beat counter counts 0 to beats-1 for one neuron
    logic [GRP_W-1:0]  group_idx, group_idx_n; // Group counter selects which block of PN neurons we are currently mapping onto hardware

    logic issue;                        // High when issuing RAM read addresses
    logic last_issue;                   // High when issuing the final beat of a neuron

    logic issue_d;                      // Delayed issue aligned to synchronous RAM output
    logic last_issue_d;                 // Delayed last flag aligned to synchronous RAM output
    logic [GRP_W-1:0] group_idx_d;      // Delayed group index aligned to RAM output

    logic [TW_addr-1:0] neuron_base;    // neuron_base = group_idx * PN gives the first neuron index of the current hardware group
    logic [PN-1:0] lane_active;         // lane_active tells which NP lanes are valid in the current group

    logic [TW_addr-1:0] neuron_base_d;  // Delayed base neuron index for alignment with RAM output
    logic [PN-1:0] lane_active_d;       // Delayed active lane mask aligned with RAM output

    integer i;

    // Sequential logic
    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            beat_idx     <= '0;
            group_idx    <= '0;
            issue_d      <= 1'b0;
            last_issue_d <= 1'b0;
            group_idx_d  <= '0;
        end else begin
            state     <= state_n;
            beat_idx  <= beat_idx_n;
            group_idx <= group_idx_n;

            issue_d      <= issue;                   // Align valid signal with synchronous RAM read latency
            last_issue_d <= last_issue && issue;     // Align last flag with synchronous RAM read latency
            if (issue) group_idx_d <= group_idx;     // Capture group index when issuing RAM addresses
        end
    end

    // Combinational FSM
    always_comb begin

        state_n         = state;
        beat_idx_n      = beat_idx;
        group_idx_n     = group_idx;

        buffer_read     = 1'b0;
        buffer_clear    = 1'b0;
        buffer_raddr    = '0;

        w_ram_b_ren     = '0;
        t_ram_b_ren     = '0;
        w_ram_b_addr    = '0;
        t_ram_b_addr    = '0;

        layer_active    = 1'b0;
        controller_done = 1'b0;

        issue           = 1'b0;
        last_issue      = 1'b0;

        neuron_base = group_idx * PN;  // Compute the first neuron index handled by this hardware group

        for (i = 0; i < PN; i++) begin
            lane_active[i] = ((neuron_base + i) < N_NEURONS); // Disable lanes in the final partial group
        end

        case (state)

            S_IDLE: begin
                beat_idx_n  = '0;
                group_idx_n = '0;
                if (start_layer) state_n = S_WAIT_CFG;
            end

            S_WAIT_CFG: begin
                if (cfg_done) state_n = S_WAIT_BUF;
            end

            S_WAIT_BUF: begin
                if (buffer_ready) state_n = S_STREAM;
            end

            S_STREAM: begin

                layer_active = 1'b1;

                issue      = 1'b1;
                last_issue = (beat_idx == beats-1);

                buffer_read  = 1'b1;
                buffer_raddr = beat_idx;

                for (i = 0; i < PN; i++) begin
                    t_ram_b_addr[i] = neuron_base + i;                      // Threshold index equals neuron index
                    w_ram_b_addr[i] = ((neuron_base + i) * beats) + beat_idx; // Weight address walks through beats for each neuron
                    t_ram_b_ren[i]  = issue && lane_active[i];
                    w_ram_b_ren[i]  = issue && lane_active[i];
                end
                // we are at the final beat
                if (beat_idx == beats-1) begin
                    beat_idx_n = '0;
                    // now we are at the final group
                    if (group_idx == GROUPS-1) begin
                        group_idx_n = '0;
                        state_n     = S_DONE;
                    end else begin
                        group_idx_n = group_idx + 1'b1;
                    end
                end else begin
                    beat_idx_n = beat_idx + 1'b1;
                end
            end

            S_DONE: begin
                controller_done = 1'b1;
                state_n         = S_CLEAR;
            end

            S_CLEAR: begin
                buffer_clear = 1'b1;
                state_n      = S_IDLE;
            end

        endcase
    end

    // Delayed lane computation for synchronous RAM alignment
    always_comb begin
        neuron_base_d = group_idx_d * PN;  // Delayed base neuron index for correct alignment
        for (i = 0; i < PN; i++) begin
            lane_active_d[i] = ((neuron_base_d + i) < N_NEURONS);
        end
    end

    // Align valid and last signals to RAM output
    always_comb begin
        valid_in = '0;
        last_in  = '0;
        for (i = 0; i < PN; i++) begin
            valid_in[i] = issue_d && lane_active_d[i];
            last_in[i]  = last_issue_d && lane_active_d[i];
        end
    end

endmodule
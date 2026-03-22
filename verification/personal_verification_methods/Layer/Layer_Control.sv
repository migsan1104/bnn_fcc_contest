`timescale 1ns / 1ps

module Layer_Control#(

    parameter int LAYER_ID = 0,
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int TN = 16,
    parameter int N_NEURONS = 16,
    parameter int TW = 32,

    localparam int beats   = (TN + PW - 1) / PW,
    localparam int BEAT_W  = (beats <= 1) ? 1 : $clog2(beats),
    localparam int GROUPS  = (N_NEURONS + PN - 1) / PN,
    localparam int TW_addr = (GROUPS <= 1) ? 1 : $clog2(GROUPS),
    localparam int W_addr  = (beats * GROUPS <= 1) ? 1 : $clog2(beats * GROUPS),
    localparam int GRP_W   = (GROUPS <= 1) ? 1 : $clog2(GROUPS)

)(
    input  logic clk,
    input  logic rst,

    input  logic start_layer,

    input  logic start_allowed_bank0,
    input  logic start_allowed_bank1,
    input  logic buffer_has_addr_bank0,
    input  logic buffer_has_addr_bank1,

    input  logic write_bank_sel,

    output logic read_bank_sel,
    output logic buffer_read,
    output logic clear_bank0,
    output logic clear_bank1,
    output logic [BEAT_W-1:0] buffer_raddr,

    output logic [PN-1:0]              w_ram_b_ren,
    output logic [PN-1:0]              t_ram_b_ren,
    output logic [PN-1:0][W_addr-1:0]  w_ram_b_addr,
    output logic [PN-1:0][TW_addr-1:0] t_ram_b_addr,

    output logic [PN-1:0] valid_in,
    output logic [PN-1:0] last_in,

    output logic layer_active,
    output logic controller_done
);

    typedef enum logic [2:0] {S_IDLE, S_WAIT_BUF, S_WAIT_RESUME, S_STREAM, S_DONE} state_t;

    state_t state, state_n;

    logic [BEAT_W-1:0] beat_idx, beat_idx_n;
    logic [GRP_W-1:0]  group_idx, group_idx_n;

    logic active_bank, active_bank_n;

    logic issue, last_issue;
    logic issue_d, last_issue_d;
    logic [GRP_W-1:0] group_idx_d;

    logic [PN-1:0] lane_active, lane_active_d;

    assign read_bank_sel = active_bank;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= S_IDLE;
            beat_idx     <= '0;
            group_idx    <= '0;
            active_bank  <= 1'b0;
            issue_d      <= 1'b0;
            last_issue_d <= 1'b0;
            group_idx_d  <= '0;
        end else begin
            state        <= state_n;
            beat_idx     <= beat_idx_n;
            group_idx    <= group_idx_n;
            active_bank  <= active_bank_n;

            issue_d      <= issue;
            last_issue_d <= issue && last_issue;

            if (issue)
                group_idx_d <= group_idx;
        end
    end

    always_comb begin
        int i;
        int neuron_idx;
        int local_weight_addr;

        state_n        = state;
        beat_idx_n     = beat_idx;
        group_idx_n    = group_idx;
        active_bank_n  = active_bank;

        buffer_read     = 1'b0;
        clear_bank0     = 1'b0;
        clear_bank1     = 1'b0;
        buffer_raddr    = beat_idx;

        w_ram_b_ren     = '0;
        t_ram_b_ren     = '0;
        w_ram_b_addr    = '0;
        t_ram_b_addr    = '0;

        layer_active    = 1'b0;
        controller_done = 1'b0;

        issue      = 1'b0;
        last_issue = 1'b0;

        for (i = 0; i < PN; i++) begin
            neuron_idx     = group_idx * PN + i;
            lane_active[i] = (neuron_idx < N_NEURONS);
        end

        case (state)

        S_IDLE: begin
            if (start_layer)
                state_n = S_WAIT_BUF;
        end

        S_WAIT_BUF: begin
            if (start_layer &&
               (write_bank_sel == 1'b0 ? start_allowed_bank1 : start_allowed_bank0)) begin
                active_bank_n = ~write_bank_sel;
                state_n       = S_STREAM;
            end
        end

        S_WAIT_RESUME: begin
            layer_active = 1'b1;
            if (write_bank_sel != active_bank &&
               (active_bank ? buffer_has_addr_bank1 : buffer_has_addr_bank0))
                state_n = S_STREAM;
        end

        S_STREAM: begin
            layer_active = 1'b1;
            buffer_raddr = beat_idx;

            if (active_bank == write_bank_sel ||
               !(active_bank ? buffer_has_addr_bank1 : buffer_has_addr_bank0)) begin
                state_n = S_WAIT_RESUME;
            end else begin
                issue       = 1'b1;
                last_issue  = (beat_idx == beats-1);
                buffer_read = 1'b1;

                for (i = 0; i < PN; i++) begin
                    if (lane_active[i]) begin
                        local_weight_addr = group_idx * beats + beat_idx;
                        w_ram_b_addr[i]   = local_weight_addr[W_addr-1:0];

                       //at the end of every beat we enable the threshold ram to read from the next address.
                       // this address is stored in group_idx
                        if (beat_idx == beats-1) begin
                            t_ram_b_addr[i] = group_idx;
                            t_ram_b_ren[i]  = issue;
                        end else begin
                            t_ram_b_addr[i] = '0;
                            t_ram_b_ren[i]  = 1'b0;
                        end
                    end else begin
                        w_ram_b_addr[i] = '0;
                        t_ram_b_addr[i] = '0;
                        t_ram_b_ren[i]  = 1'b0;
                    end

                    w_ram_b_ren[i] = issue && lane_active[i];
                end

                if (beat_idx == beats-1) begin
                    beat_idx_n = '0;
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
        end

        S_DONE: begin
            controller_done = 1'b1;

            if (active_bank == 1'b0) clear_bank0 = 1'b1;
            else                     clear_bank1 = 1'b1;

            if (start_layer)
                state_n = S_WAIT_BUF;
            else
                state_n = S_IDLE;
        end

        default: begin
            state_n = S_IDLE;
        end

        endcase
    end

    always_comb begin
        int i;
        valid_in = '0;
        last_in  = '0;

        for (i = 0; i < PN; i++) begin
            lane_active_d[i] = ((group_idx_d * PN + i) < N_NEURONS);
            valid_in[i]      = issue_d && lane_active_d[i];
            last_in[i]       = last_issue_d && lane_active_d[i];
        end
    end

endmodule
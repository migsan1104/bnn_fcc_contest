`timescale 1ns/1ps

module Config_Layer_Control #(
    parameter int LAYER_ID  = 0,
    parameter int LAYER_W   = 1,
    parameter int PN        = 8,
    parameter int PW        = 8,
    parameter int TN        = 16,
    parameter int N_NEURONS = 16,
    parameter int TW        = 32,

    // Each neuron needs this many PW-wide words
    localparam int BEATS    = (TN + PW - 1) / PW,

    // Neurons are striped across PN banks
    localparam int GROUPS   = (N_NEURONS + PN - 1) / PN,

    // Local weight RAM depth per bank is GROUPS * BEATS
    localparam int W_ADDR_W = (GROUPS * BEATS <= 1) ? 1 : $clog2(GROUPS * BEATS),

    // Local threshold RAM depth is GROUPS
    localparam int T_ADDR_W = (GROUPS <= 1) ? 1 : $clog2(GROUPS),

    // Total number of weight words to write
    localparam int TOTAL_W_WORDS = N_NEURONS * BEATS,

    // Total number of threshold words to write
    localparam int TOTAL_T_WORDS = N_NEURONS,

    // Total real weight bits before padding
    localparam int TOTAL_W_BITS  = N_NEURONS * TN,

    // Total real threshold bits
    localparam int TOTAL_T_BITS  = N_NEURONS * TW,

    // Width for weight word counter
    localparam int WCOUNT_W = (TOTAL_W_WORDS <= 1) ? 1 : $clog2(TOTAL_W_WORDS + 1),

    // Width for threshold word counter
    localparam int TCOUNT_W = (TOTAL_T_WORDS <= 1) ? 1 : $clog2(TOTAL_T_WORDS + 1),

    // Width for remaining weight bits counter
    localparam int WBITS_W  = (TOTAL_W_BITS <= 1) ? 1 : $clog2(TOTAL_W_BITS + 1),

    // Width for remaining threshold bits counter
    localparam int TBITS_W  = (TOTAL_T_BITS <= 1) ? 1 : $clog2(TOTAL_T_BITS + 1),

    // Width for neuron index
    localparam int NEUR_W   = (N_NEURONS <= 1) ? 1 : $clog2(N_NEURONS),

    // Width for beat index
    localparam int BEAT_W   = (BEATS <= 1) ? 1 : $clog2(BEATS),

    // Width for group index
    localparam int GROUP_W  = (GROUPS <= 1) ? 1 : $clog2(GROUPS),

    // Packer must hold a full word plus one extra byte
    localparam int PACK_W   = ((PW > TW) ? PW : TW) + 8,

    // Bytes per neuron in the incoming payload stream
    localparam int W_BYTES_PER_NEURON = (TN + 7) / 8,
    localparam int T_BYTES_PER_NEURON = (TW + 7) / 8,

    localparam int WBYTE_W = (W_BYTES_PER_NEURON <= 1) ? 1 : $clog2(W_BYTES_PER_NEURON + 1),
    localparam int TBYTE_W = (T_BYTES_PER_NEURON <= 1) ? 1 : $clog2(T_BYTES_PER_NEURON + 1),

    // Neuron-local pack widths
    localparam int WNEUR_PACK_W = (W_BYTES_PER_NEURON <= 1) ? 8 : (W_BYTES_PER_NEURON * 8),
    localparam int TNEUR_PACK_W = (T_BYTES_PER_NEURON <= 1) ? 8 : (T_BYTES_PER_NEURON * 8)
)(
    input  logic clk,
    input  logic rst,

    // Shared header from Config_Manager
    input  logic               msg_valid,
    output logic               msg_ready,
    input  logic [LAYER_W-1:0] msg_layer,
    input  logic [7:0]         msg_type,
    input  logic [15:0]        msg_layer_inputs,
    input  logic [15:0]        msg_num_neurons,
    input  logic [15:0]        msg_BN,
    input  logic [31:0]        msg_total_bytes,

    // Shared payload byte stream
    input  logic               payload_valid,
    output logic               payload_ready,
    input  logic [7:0]         payload_data,
    input  logic               payload_last,

    // Weight RAM port A write side
    output logic [PN-1:0][PW-1:0]       w_ram_a_data,
    output logic [PN-1:0][W_ADDR_W-1:0] w_ram_a_addr,
    output logic [PN-1:0]               w_ram_wen_a,

    // Threshold RAM port A write side
    output logic [PN-1:0][TW-1:0]       t_ram_a_data,
    output logic [PN-1:0][T_ADDR_W-1:0] t_ram_a_addr,
    output logic [PN-1:0]               t_ram_wen_a,

    // Status
    output logic cfg_busy,
    output logic cfg_done,
    output logic cfg_error
);

    // Current design has three compute layers, so layer 2 is the output layer
    localparam int LAST_LAYER_ID = 2;

    // Weight message always comes first, then threshold message for hidden layers
    typedef enum logic [2:0] {
        S_IDLE,
        S_FILL_W,
        S_DRAIN_W,
        S_WAIT_T_HDR,
        S_FILL_T,
        S_DRAIN_T
    } state_t;

    // Message type encoding from the config manager
    localparam logic [7:0] MSG_TYPE_WEIGHTS    = 8'h00;
    localparam logic [7:0] MSG_TYPE_THRESHOLDS = 8'h01;

    // Main FSM state
    state_t state_r, state_next;

    // Original continuous packer kept for thresholds
    logic [PACK_W-1:0] pack_r, pack_next;

    // Number of valid bits currently sitting in the threshold packer
    logic [$clog2(PACK_W+1)-1:0] pack_count_r, pack_count_next;

    // Track how many weight words were written
    logic [WCOUNT_W-1:0] w_word_count_r, w_word_count_next;

    // Track how many threshold words were written
    logic [TCOUNT_W-1:0] t_word_count_r, t_word_count_next;

    // Handy debug counters for the waveform
    logic [WCOUNT_W-1:0] debug_w_words_stored;
    logic [TCOUNT_W-1:0] debug_t_words_stored;

    // Count down the real bits left before padding kicks in
    logic [WBITS_W-1:0] w_bits_left_r, w_bits_left_next;
    logic [TBITS_W-1:0] t_bits_left_r, t_bits_left_next;

    // Done stays high after the required config finishes
    logic cfg_done_r, cfg_done_next;

    // Error stays high until a new config starts or reset happens
    logic cfg_error_r, cfg_error_next;

    // Current weight write location
    logic [NEUR_W-1:0]      w_neuron_idx;
    logic [BEAT_W-1:0]      w_beat_idx;
    logic [$clog2(PN)-1:0]  w_bank_idx;
    logic [GROUP_W-1:0]     w_group_idx;

    // Current threshold write location
    logic [NEUR_W-1:0]      t_neuron_idx;
    logic [$clog2(PN)-1:0]  t_bank_idx;
    logic [GROUP_W-1:0]     t_group_idx;

    // Next full threshold word to be written
    logic [TW-1:0] t_word_full;

    // Marks when enough bits exist for a normal threshold full-word write
    logic have_full_t_word;

    // Marks when the very last threshold word is partial and must be padded
    logic flush_last_t_word;

    // New neuron-aware weight collection registers
    logic [WNEUR_PACK_W-1:0] w_neuron_pack_r, w_neuron_pack_next;
    logic [WBYTE_W-1:0]      w_neuron_byte_count_r, w_neuron_byte_count_next;

    logic [PW-1:0]           w_word_full;
    logic                    have_full_w_neuron;

    integer i;

    function automatic [PW-1:0] get_weight_word_from_neuron_pack(
        input logic [WNEUR_PACK_W-1:0] pack_bits,
        input int beat_idx
    );
        automatic logic [PW-1:0] temp;
        automatic int start_bit;
        automatic int b;
        begin
            temp      = '1;
            start_bit = beat_idx * PW;

            for (b = 0; b < PW; b++) begin
                if ((start_bit + b) < TN)
                    temp[b] = pack_bits[start_bit + b];
                else
                    temp[b] = 1'b1;
            end

            get_weight_word_from_neuron_pack = temp;
        end
    endfunction

    // Weight word count determines which neuron and beat is being written
    assign w_neuron_idx = w_word_count_r / BEATS;
    assign w_beat_idx   = w_word_count_r % BEATS;
    assign w_bank_idx   = w_neuron_idx % PN;
    assign w_group_idx  = w_neuron_idx / PN;

    // Threshold count directly maps to neuron and bank/group
    assign t_neuron_idx = t_word_count_r;
    assign t_bank_idx   = t_neuron_idx % PN;
    assign t_group_idx  = t_neuron_idx / PN;

    // Threshold packer still uses the old continuous extraction
    assign t_word_full = pack_r[TW-1:0];

    // Weight extraction is now neuron-local
    assign w_word_full        = get_weight_word_from_neuron_pack(w_neuron_pack_r, w_beat_idx);
    assign have_full_w_neuron = (w_neuron_byte_count_r == W_BYTES_PER_NEURON);

    // Normal threshold word write becomes legal once enough bits are buffered
    assign have_full_t_word = (pack_count_r >= TW);

    // Final threshold word may be short and padded with zeros
    assign flush_last_t_word =
        (t_word_count_r == TOTAL_T_WORDS-1) &&
        (t_bits_left_r != 0) &&
        (t_bits_left_r < TW) &&
        (pack_count_r >= t_bits_left_r);

    // Used for waveform/transcript debugging
    assign debug_w_words_stored = w_word_count_r;
    assign debug_t_words_stored = t_word_count_r;

    // Registers update here every clock
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_r                <= S_IDLE;
            pack_r                 <= '0;
            pack_count_r           <= '0;
            w_word_count_r         <= '0;
            t_word_count_r         <= '0;
            w_bits_left_r          <= '0;
            t_bits_left_r          <= '0;
            cfg_done_r             <= 1'b0;
            cfg_error_r            <= 1'b0;
            w_neuron_pack_r        <= '0;
            w_neuron_byte_count_r  <= '0;
        end else begin
            state_r                <= state_next;
            pack_r                 <= pack_next;
            pack_count_r           <= pack_count_next;
            w_word_count_r         <= w_word_count_next;
            t_word_count_r         <= t_word_count_next;
            w_bits_left_r          <= w_bits_left_next;
            t_bits_left_r          <= t_bits_left_next;
            cfg_done_r             <= cfg_done_next;
            cfg_error_r            <= cfg_error_next;
            w_neuron_pack_r        <= w_neuron_pack_next;
            w_neuron_byte_count_r  <= w_neuron_byte_count_next;
        end
    end

    // FSM and outputs are driven here
    always_comb begin
        state_next               = state_r;
        pack_next                = pack_r;
        pack_count_next          = pack_count_r;
        w_word_count_next        = w_word_count_r;
        t_word_count_next        = t_word_count_r;
        w_bits_left_next         = w_bits_left_r;
        t_bits_left_next         = t_bits_left_r;
        cfg_done_next            = cfg_done_r;
        cfg_error_next           = cfg_error_r;
        w_neuron_pack_next       = w_neuron_pack_r;
        w_neuron_byte_count_next = w_neuron_byte_count_r;

        msg_ready     = 1'b0;
        payload_ready = 1'b0;

        // Busy only while a message is actively being consumed
        cfg_busy  = (state_r != S_IDLE);
        cfg_done  = cfg_done_r;
        cfg_error = cfg_error_r;

        // Keep RAM outputs quiet unless a real write is happening
        for (i = 0; i < PN; i++) begin
            w_ram_a_data[i] = '1;
            w_ram_a_addr[i] = '0;
            w_ram_wen_a[i]  = 1'b0;
            t_ram_a_data[i] = '0;
            t_ram_a_addr[i] = '0;
            t_ram_wen_a[i]  = 1'b0;
        end

        case (state_r)

            // Wait for the weight header for this layer
            S_IDLE: begin
                if (msg_valid && (msg_layer == LAYER_ID[LAYER_W-1:0])) begin
                    msg_ready = 1'b1;

                    // Starting a new config clears old done/error state
                    pack_next                = '0;
                    pack_count_next          = '0;
                    w_word_count_next        = '0;
                    t_word_count_next        = '0;
                    w_bits_left_next         = TOTAL_W_BITS;
                    t_bits_left_next         = TOTAL_T_BITS;
                    cfg_done_next            = 1'b0;
                    cfg_error_next           = 1'b0;
                    w_neuron_pack_next       = '0;
                    w_neuron_byte_count_next = '0;

                    // Only a weight header is valid here
                    if (msg_type == MSG_TYPE_WEIGHTS) begin
                        state_next = S_FILL_W;
                    end else begin
                        cfg_error_next = 1'b1;
                    end
                end
            end

            // Collect exactly the byte-aligned payload for one neuron
            S_FILL_W: begin
                if (have_full_w_neuron) begin
                    state_next = S_DRAIN_W;
                end else begin
                    payload_ready = 1'b1;

                    if (payload_valid) begin
                        w_neuron_pack_next[w_neuron_byte_count_r*8 +: 8] = payload_data;
                        w_neuron_byte_count_next                         = w_neuron_byte_count_r + 1'b1;

                        if (w_neuron_byte_count_r + 1 == W_BYTES_PER_NEURON)
                            state_next = S_DRAIN_W;
                        else
                            state_next = S_FILL_W;
                    end
                end
            end

            // Write BEATS words for the current neuron from the neuron-local pack
            S_DRAIN_W: begin
                w_ram_wen_a[w_bank_idx]  = 1'b1;
                w_ram_a_addr[w_bank_idx] = w_group_idx * BEATS + w_beat_idx;
                w_ram_a_data[w_bank_idx] = w_word_full;

                // Debug print for weight write
                $display("[CFG_W] L=%0d t=%0t bank=%0d group=%0d beat=%0d addr=%0d neuron=%0d data=%h",
                    LAYER_ID,
                    $time,
                    w_bank_idx,
                    w_group_idx,
                    w_beat_idx,
                    (w_group_idx * BEATS + w_beat_idx),
                    w_neuron_idx,
                    w_word_full
                );

                w_word_count_next = w_word_count_r + 1'b1;

                if (w_bits_left_r >= PW)
                    w_bits_left_next = w_bits_left_r - PW;
                else
                    w_bits_left_next = '0;

                // Finished the last beat of this neuron
                if (w_beat_idx == BEATS-1) begin
                    w_neuron_pack_next       = '0;
                    w_neuron_byte_count_next = '0;

                    // Finished the last neuron of the whole layer
                    if (w_word_count_r + 1 == TOTAL_W_WORDS) begin
                        if (LAYER_ID == LAST_LAYER_ID) begin
                            cfg_done_next = 1'b1;
                            state_next    = S_IDLE;
                        end else begin
                            state_next = S_WAIT_T_HDR;
                        end
                    end else begin
                        state_next = S_FILL_W;
                    end
                end else begin
                    state_next = S_DRAIN_W;
                end
            end

            // Threshold header for the same layer should arrive right after weights
            S_WAIT_T_HDR: begin
                if (msg_valid && (msg_layer == LAYER_ID[LAYER_W-1:0])) begin
                    msg_ready = 1'b1;
                    pack_next = '0;
                    pack_count_next = '0;

                    if (msg_type == MSG_TYPE_THRESHOLDS)
                        state_next = S_FILL_T;
                    else
                        cfg_error_next = 1'b1;
                end
            end

            // Keep taking bytes until a threshold word is ready
            S_FILL_T: begin
                if (have_full_t_word || flush_last_t_word) begin
                    state_next = S_DRAIN_T;
                end else begin
                    payload_ready = 1'b1;

                    if (payload_valid) begin
                        pack_next[pack_count_r +: 8] = payload_data;
                        pack_count_next              = pack_count_r + 8;
                        state_next                   = S_DRAIN_T;
                    end
                end
            end

            // Threshold writes finish the full config sequence for hidden layers
            S_DRAIN_T: begin
                if (have_full_t_word) begin
                    t_ram_wen_a[t_bank_idx]  = 1'b1;
                    t_ram_a_addr[t_bank_idx] = t_group_idx;
                    t_ram_a_data[t_bank_idx] = t_word_full;

                    // Debug print for threshold write
                    $display("[CFG_T] L=%0d t=%0t bank=%0d group=%0d addr=%0d neuron=%0d data=%0d (0x%h)",
                        LAYER_ID,
                        $time,
                        t_bank_idx,
                        t_group_idx,
                        t_group_idx,
                        t_neuron_idx,
                        t_word_full,
                        t_word_full
                    );

                    pack_next         = pack_r >> TW;
                    pack_count_next   = pack_count_r - TW;
                    t_word_count_next = t_word_count_r + 1'b1;

                    if (t_bits_left_r >= TW)
                        t_bits_left_next = t_bits_left_r - TW;
                    else
                        t_bits_left_next = '0;

                    if (t_word_count_r + 1 == TOTAL_T_WORDS) begin
                        cfg_done_next = 1'b1;
                        state_next    = S_IDLE;
                    end
                    else if ((pack_count_r - TW) >= TW)
                        state_next = S_DRAIN_T;
                    else
                        state_next = S_FILL_T;
                end
                else if (flush_last_t_word) begin
                    t_ram_wen_a[t_bank_idx]  = 1'b1;
                    t_ram_a_addr[t_bank_idx] = t_group_idx;
                    t_ram_a_data[t_bank_idx] = pack_r[TW-1:0];

                    // Debug print for final padded threshold write
                    $display("[CFG_T] L=%0d t=%0t bank=%0d group=%0d addr=%0d neuron=%0d data=%0d (0x%h)",
                        LAYER_ID,
                        $time,
                        t_bank_idx,
                        t_group_idx,
                        t_group_idx,
                        t_neuron_idx,
                        pack_r[TW-1:0],
                        pack_r[TW-1:0]
                    );

                    pack_next         = '0;
                    pack_count_next   = '0;
                    t_word_count_next = t_word_count_r + 1'b1;
                    t_bits_left_next  = '0;

                    cfg_done_next = 1'b1;
                    state_next    = S_IDLE;
                end
                else begin
                    state_next = S_FILL_T;
                end
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    
    // DEBUG PRINTS / ASSERTIONS used in the verification version. 
    
    always_ff @(posedge clk) begin
        int expected_bank;
        int expected_group;
        int expected_waddr;

        if (!rst) begin
            // Show each incoming threshold byte as it is packed.
            // Restrict to layer 0 so the log stays readable.
            if ((LAYER_ID == 0) && (state_r == S_FILL_T) && payload_valid && payload_ready) begin
                $display("[T_PACK] L=%0d t=%0t neuron=%0d byte_idx=%0d byte=%02h pack_next=%08h pack_count_next=%0d last=%0b",
                    LAYER_ID,
                    $time,
                    t_word_count_r,
                    (pack_count_r >> 3),
                    payload_data,
                    (pack_r | ({{(PACK_W-8){1'b0}}, payload_data} << pack_count_r)),
                    (pack_count_r + 8),
                    payload_last
                );
            end

            // Weight-side sanity
            if (w_ram_wen_a[w_bank_idx]) begin
                expected_bank  = w_neuron_idx % PN;
                expected_group = w_neuron_idx / PN;
                expected_waddr = expected_group * BEATS + w_beat_idx;

                assert (w_neuron_idx < N_NEURONS)
                else $fatal("Config Layer %0d: invalid weight neuron index (neuron=%0d N_NEURONS=%0d)",
                            LAYER_ID, w_neuron_idx, N_NEURONS);

                assert (w_beat_idx < BEATS)
                else $fatal("Config Layer %0d: invalid weight beat index (beat=%0d BEATS=%0d)",
                            LAYER_ID, w_beat_idx, BEATS);

                assert (w_bank_idx == expected_bank[$clog2(PN)-1:0])
                else $fatal("Config Layer %0d: weight bank mismatch (neuron=%0d got=%0d exp=%0d)",
                            LAYER_ID, w_neuron_idx, w_bank_idx, expected_bank);

                assert (w_group_idx == expected_group[GROUP_W-1:0])
                else $fatal("Config Layer %0d: weight group mismatch (neuron=%0d got=%0d exp=%0d)",
                            LAYER_ID, w_neuron_idx, w_group_idx, expected_group);

                assert (w_ram_a_addr[w_bank_idx] == expected_waddr[W_ADDR_W-1:0])
                else $fatal("Config Layer %0d: weight addr mismatch (neuron=%0d beat=%0d got=%0d exp=%0d)",
                            LAYER_ID, w_neuron_idx, w_beat_idx, w_ram_a_addr[w_bank_idx], expected_waddr);

                assert (w_ram_a_data[w_bank_idx] == w_word_full)
                else $fatal("Config Layer %0d: weight data mismatch on write (bank=%0d addr=%0d)",
                            LAYER_ID, w_bank_idx, w_ram_a_addr[w_bank_idx]);
            end

            // Threshold-side sanity
            if (t_ram_wen_a[t_bank_idx]) begin
                expected_bank  = t_neuron_idx % PN;
                expected_group = t_neuron_idx / PN;

                assert (t_neuron_idx < N_NEURONS)
                else $fatal("Config Layer %0d: invalid threshold neuron index (neuron=%0d N_NEURONS=%0d)",
                            LAYER_ID, t_neuron_idx, N_NEURONS);

                assert (t_bank_idx == expected_bank[$clog2(PN)-1:0])
                else $fatal("Config Layer %0d: threshold bank mismatch (neuron=%0d got=%0d exp=%0d)",
                            LAYER_ID, t_neuron_idx, t_bank_idx, expected_bank);

                assert (t_group_idx == expected_group[GROUP_W-1:0])
                else $fatal("Config Layer %0d: threshold group mismatch (neuron=%0d got=%0d exp=%0d)",
                            LAYER_ID, t_neuron_idx, t_group_idx, expected_group);

                assert (t_ram_a_addr[t_bank_idx] == expected_group[T_ADDR_W-1:0])
                else $fatal("Config Layer %0d: threshold addr mismatch (neuron=%0d got=%0d exp=%0d)",
                            LAYER_ID, t_neuron_idx, t_ram_a_addr[t_bank_idx], expected_group);
            end

            // Weight message size sanity from parameters
            if (state_r == S_WAIT_T_HDR || (state_r == S_IDLE && cfg_done_r && LAYER_ID != LAST_LAYER_ID)) begin
                assert (w_word_count_r == TOTAL_W_WORDS)
                else $fatal("Config Layer %0d: weight config ended early/late (got=%0d exp=%0d)",
                            LAYER_ID, w_word_count_r, TOTAL_W_WORDS);
            end

            // Final done checking
            if (cfg_done_r) begin
                if (LAYER_ID == LAST_LAYER_ID) begin
                    assert (w_word_count_r == TOTAL_W_WORDS)
                    else $fatal("Config Layer %0d: output-layer cfg_done before all weights were written", LAYER_ID);
                end
                else begin
                    assert (w_word_count_r == TOTAL_W_WORDS)
                    else $fatal("Config Layer %0d: cfg_done before all weights were written", LAYER_ID);

                    assert (t_word_count_r == TOTAL_T_WORDS)
                    else $fatal("Config Layer %0d: cfg_done before all thresholds were written", LAYER_ID);
                end
            end
        end
    end

endmodule
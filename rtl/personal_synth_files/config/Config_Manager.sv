module Config_Manager #(
    parameter int BUS_WIDTH = 64,   // AXI config bus width by default 64
    parameter int LAYERS    = 3     // number of configurable layers
)(
    input  logic clk,
    input  logic rst,

    // AXI stream configuration input
    input  logic [BUS_WIDTH-1:0]   config_data_in,
    input  logic                   config_valid,
    input  logic [BUS_WIDTH/8-1:0] config_keep,
    input  logic                   config_last,
    output logic                   config_ready,

    // Parsed header sent to layer controllers
    output logic                        msg_valid,
    input  logic                        msg_ready,
    output logic [$clog2(LAYERS)-1:0]   msg_layer,
    output logic [7:0]                  msg_type,
    output logic [15:0]                 msg_layer_inputs,
    output logic [15:0]                 msg_num_neurons,
    output logic [15:0]                 msg_BN,
    output logic [31:0]                 msg_total_bytes,

    // Payload byte stream
    output logic                        payload_valid,
    input  logic                        payload_ready,
    output logic [7:0]                  payload_data,
    output logic                        payload_last,

    output logic                        busy,
    output logic                        error
);

    localparam int BUS_BYTES    = BUS_WIDTH / 8;
    localparam int HEADER_BYTES = 16;
    localparam int HEADER_BITS  = HEADER_BYTES * 8;

    typedef enum logic [2:0] {
        S_IDLE,
        S_HEADER,
        S_SEND_MSG,
        S_PAYLOAD,
        S_DONE,
        S_ERROR
    } state_t;

    state_t state_r, state_next;

    // Beat buffer holds one AXI word while we walk through its bytes
    logic [BUS_WIDTH-1:0]   beat_data_r, beat_data_next;
    logic [BUS_BYTES-1:0]   beat_keep_r, beat_keep_next;
    logic                   beat_last_r, beat_last_next;
    logic                   beat_valid_r, beat_valid_next;

    // Byte pointer inside the buffered beat, very similar fo fifo pointers
    logic [$clog2(BUS_BYTES+1)-1:0] byte_idx_r, byte_idx_next;

    // Header accumulator
    logic [HEADER_BITS-1:0] header_r, header_next;
    logic [4:0] header_count_r, header_count_next;

    // Parsed header fields, still dont know what to do with reserved lol
    logic [7:0] msg_type_r, msg_type_next;
    logic [$clog2(LAYERS)-1:0] msg_layer_r, msg_layer_next;
    logic [15:0] msg_layer_inputs_r, msg_layer_inputs_next;
    logic [15:0] msg_num_neurons_r, msg_num_neurons_next;
    logic [15:0] msg_BN_r, msg_BN_next;
    logic [31:0] msg_total_bytes_r, msg_total_bytes_next;

    // Payload progress counter, current and next
    logic [31:0] payload_bytes_seen_r, payload_bytes_seen_next;

    // Sticky error flag, used for testing stuff
    logic error_r, error_next;

    logic [7:0] curr_byte;
    logic       curr_byte_valid;

    logic advance_byte;
    logic accept_beat;

    assign accept_beat = config_valid && config_ready;

    // Extract current byte from buffered beat
    always_comb begin
        curr_byte       = '0;
        curr_byte_valid = 1'b0;

        if (beat_valid_r && byte_idx_r < BUS_BYTES) begin
            curr_byte       = beat_data_r[8*byte_idx_r +: 8];
            curr_byte_valid = beat_keep_r[byte_idx_r];
        end
    end

    // Sequential register update
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_r <= S_IDLE;

            beat_data_r  <= '0;
            beat_keep_r  <= '0;
            beat_last_r  <= 0;
            beat_valid_r <= 0;
            byte_idx_r   <= 0;

            header_r       <= '0;
            header_count_r <= 0;

            msg_type_r         <= 0;
            msg_layer_r        <= 0;
            msg_layer_inputs_r <= 0;
            msg_num_neurons_r  <= 0;
            msg_BN_r           <= 0;
            msg_total_bytes_r  <= 0;

            payload_bytes_seen_r <= 0;

            error_r <= 0;
        end else begin
            // move state
            state_r <= state_next;
            // update registers
            beat_data_r  <= beat_data_next;
            beat_keep_r  <= beat_keep_next;
            beat_last_r  <= beat_last_next;
            beat_valid_r <= beat_valid_next;
            byte_idx_r   <= byte_idx_next;

            header_r       <= header_next;
            header_count_r <= header_count_next;

            msg_type_r         <= msg_type_next;
            msg_layer_r        <= msg_layer_next;
            msg_layer_inputs_r <= msg_layer_inputs_next;
            msg_num_neurons_r  <= msg_num_neurons_next;
            msg_BN_r           <= msg_BN_next;
            msg_total_bytes_r  <= msg_total_bytes_next;

            payload_bytes_seen_r <= payload_bytes_seen_next;

            error_r <= error_next;
        end
    end

    // Main control logic
    always_comb begin
        state_next = state_r;

        beat_data_next  = beat_data_r;
        beat_keep_next  = beat_keep_r;
        beat_last_next  = beat_last_r;
        beat_valid_next = beat_valid_r;
        byte_idx_next   = byte_idx_r;

        header_next       = header_r;
        header_count_next = header_count_r;

        msg_type_next         = msg_type_r;
        msg_layer_next        = msg_layer_r;
        msg_layer_inputs_next = msg_layer_inputs_r;
        msg_num_neurons_next  = msg_num_neurons_r;
        msg_BN_next           = msg_BN_r;
        msg_total_bytes_next  = msg_total_bytes_r;

        payload_bytes_seen_next = payload_bytes_seen_r;

        error_next = error_r;

        msg_valid = 0;

        msg_layer = msg_layer_r;
        msg_type  = msg_type_r;
        msg_layer_inputs = msg_layer_inputs_r;
        msg_num_neurons  = msg_num_neurons_r;
        msg_BN           = msg_BN_r;
        msg_total_bytes  = msg_total_bytes_r;

        payload_valid = 0;
        payload_data  = curr_byte;
        payload_last  = 0;

        busy  = (state_r != S_IDLE);
        error = error_r;

        advance_byte = 0;

        // Ready when beat buffer is empty
        config_ready = !beat_valid_r;

        // Accept a new AXI beat
        if (accept_beat) begin
            beat_data_next  = config_data_in;
            beat_keep_next  = config_keep;
            beat_last_next  = config_last;
            beat_valid_next = 1;
            byte_idx_next   = 0;
        end

        // Skip invalid bytes
        if (!advance_byte && beat_valid_r && !curr_byte_valid) begin
            if (byte_idx_r == BUS_BYTES-1) begin
                beat_valid_next = 0;
                byte_idx_next   = 0;
            end else begin
                byte_idx_next = byte_idx_r + 1;
            end
        end
       //  comb logic for each state
        case (state_r)
            // first state, before message header is sent
            S_IDLE: begin
                header_next = '0;
                header_count_next = 0;
                payload_bytes_seen_next = 0;
                error_next = 0;

                if (beat_valid_r && curr_byte_valid) begin
                    header_next[7:0] = curr_byte;
                    header_count_next = 1;
                    advance_byte = 1;
                    state_next = S_HEADER;
                end
            end
            // we now parse the header that should arrive in two beats, 128/64 = 2
            S_HEADER: begin
                if (beat_valid_r && curr_byte_valid) begin
                    header_next[8*header_count_r +: 8] = curr_byte;
                    advance_byte = 1;

                    if (header_count_r == HEADER_BYTES-1) begin
                        header_count_next = 0;

                        msg_type_next         = header_next[7:0];
                        msg_layer_next        = header_next[15:8];
                        msg_layer_inputs_next = header_next[31:16];
                        msg_num_neurons_next  = header_next[47:32];
                        msg_BN_next           = header_next[63:48];
                        msg_total_bytes_next  = header_next[95:64];

                        payload_bytes_seen_next = 0;
                        // this should not happen 
                        if (header_next[15:8] >= LAYERS) begin
                            error_next = 1;
                            state_next = S_ERROR;
                        end else begin
                            state_next = S_SEND_MSG;
                        end
                    end else begin
                        header_count_next = header_count_r + 1;
                    end
                end
            end
           // message hadnshake
            S_SEND_MSG: begin
                msg_valid = 1;

                if (msg_ready)
                    state_next = S_PAYLOAD;
            end

            S_PAYLOAD: begin
                if (beat_valid_r && curr_byte_valid) begin
                    payload_valid = 1;
                    payload_last  = (payload_bytes_seen_r + 1 == msg_total_bytes_r);

                    if (payload_ready) begin
                        payload_bytes_seen_next = payload_bytes_seen_r + 1;
                        advance_byte = 1;

                        if (payload_bytes_seen_r + 1 == msg_total_bytes_r)
                            state_next = S_DONE;
                    end
                end
            end
            // we are done with the message, wait for the next header to arrive 
            S_DONE: begin
                state_next = S_IDLE;
            end
           // error state, used for debugging and wave form analysis
            S_ERROR: begin
                state_next = S_ERROR;
            end

        endcase

        if (advance_byte) begin
            if (byte_idx_r == BUS_BYTES-1) begin
                beat_valid_next = 0;
                byte_idx_next   = 0;
            end else begin
                byte_idx_next = byte_idx_r + 1;
            end
        end
    end

endmodule
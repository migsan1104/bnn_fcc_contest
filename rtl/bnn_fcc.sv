`timescale 1ns / 1ps

module bnn_fcc #(
    parameter int INPUT_DATA_WIDTH  = 8,   // One input pixel is 8 bits.
    parameter int INPUT_BUS_WIDTH   = 64,  // AXI input stream width.
    parameter int CONFIG_BUS_WIDTH  = 32,  // AXI config stream width.
    parameter int OUTPUT_DATA_WIDTH = 4,   // Classification label width.
    parameter int OUTPUT_BUS_WIDTH  = 8,   // AXI output stream width.

    parameter int TOTAL_LAYERS = 4,        // Full network depth including input and output.

    // Full network topology including the raw input stage
    parameter int TOPOLOGY[0:TOTAL_LAYERS-1] = '{0:784, 1:256, 2:256, 3:10, default:0},

    // Input layer emits this many binarized bits per beat
    parameter int PARALLEL_INPUTS = 8,

    // PN for each compute layer
    parameter int PARALLEL_NEURONS[0:TOTAL_LAYERS-2] = '{0:32, 1:256, 2:10, default:8},

    // PW for each compute layer
    parameter int LAYER_PARALLEL_INPUTS[0:TOTAL_LAYERS-2] = '{0:784, 1:32, 2:256, default:8},

    // Shared threshold RAM width
    parameter int THRESHOLD_WIDTH = 32,

    // NP latency for each compute layer
    parameter int LAYER_LATENCY[0:TOTAL_LAYERS-2] = '{default:4}
)(
    input  logic clk,
    input  logic rst,

    // Config stream goes here
    input  logic                          config_valid,
    output logic                          config_ready,
    input  logic [CONFIG_BUS_WIDTH-1:0]   config_data,
    input  logic [CONFIG_BUS_WIDTH/8-1:0] config_keep,
    input  logic                          config_last,

    // Raw image stream goes here
    input  logic                          data_in_valid,
    output logic                          data_in_ready,
    input  logic [INPUT_BUS_WIDTH-1:0]    data_in_data,
    input  logic [INPUT_BUS_WIDTH/8-1:0]  data_in_keep,
    input  logic                          data_in_last,

    // Final class output comes out here
    output logic                          data_out_valid,
    input  logic                          data_out_ready,
    output logic [OUTPUT_BUS_WIDTH-1:0]   data_out_data,
    output logic [OUTPUT_BUS_WIDTH/8-1:0] data_out_keep,
    output logic                          data_out_last
);

    // Compute layers are everything after the input layer
    localparam int LAYERS = TOTAL_LAYERS - 1;

    // Layer id width for the shared config bus
    localparam int LAYER_W = (LAYERS <= 1) ? 1 : $clog2(LAYERS);

    // The final compute layer sees this many inputs per neuron
    localparam int FINAL_LAYER_TN = TOPOLOGY[LAYERS-1];

    // Final popcount width follows the final layer input count
    localparam int FINAL_POP_W = $clog2(FINAL_LAYER_TN + 1);

    // One AXI beat carries this many input pixels
    localparam int INPUT_BUS_ELEMENTS = INPUT_BUS_WIDTH / INPUT_DATA_WIDTH;

    // Pixels are binarized against this threshold
    localparam int INPUT_BIN_THRESH = 1 << (INPUT_DATA_WIDTH - 1);

    // Parsed config header lives on these wires
    logic                    msg_valid;
    logic                    msg_ready;
    logic [LAYER_W-1:0]      msg_layer;
    logic [7:0]              msg_type;
    logic [15:0]             msg_layer_inputs;
    logic [15:0]             msg_num_neurons;
    logic [15:0]             msg_BN;
    logic [31:0]             msg_total_bytes;

    // Config payload bytes live on these wires
    logic                    payload_valid;
    logic                    payload_ready;
    logic [7:0]              payload_data;
    logic                    payload_last;

    // These wires decide when compute is globally allowed to run
    logic                    all_cfg_done;
    logic [LAYERS-1:0]       start_layer_vec;

    // Binarized words from the input layer feed H0
    logic [PARALLEL_INPUTS-1:0] first_layer_bits;
    logic                       first_layer_write;

    // Each compute layer reports config and run status here
    logic [LAYERS-1:0]       cfg_done_arr;
    logic [LAYERS-1:0]       cfg_busy_arr;
    logic [LAYERS-1:0]       cfg_error_arr;
    logic [LAYERS-1:0]       layer_active_arr;
    logic [LAYERS-1:0]       layer_done_arr;

    // Hidden layers also report input buffer state here
    logic [LAYERS-1:0]       input_buffer_ready_arr;
    logic [LAYERS-1:0]       input_buffer_stall_arr;
    logic [LAYERS-1:0]       write_bank_sel_arr;

    // Final compute layer outputs are collected here
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0]                  final_out;
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0][FINAL_POP_W-1:0] final_pop_out;
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0]                  final_valid_acc;
    logic [PARALLEL_NEURONS[LAYERS-1]-1:0]                  final_valid_out;

    // Argmax runs when the final popcount vector is ready and output register is free
    logic bnn_count_valid;

    // TKEEP-masked input beat goes here before binarization
    logic [INPUT_BUS_WIDTH-1:0] masked_input_data;

    // Raw argmax outputs before AXI output holding register
    logic [OUTPUT_BUS_WIDTH-1:0] argmax_data;
    logic                        argmax_valid;
    logic [31:0]                 argmax_valid_count;

    // AXI output holding register
    logic [OUTPUT_BUS_WIDTH-1:0] data_out_data_r;
    logic                        data_out_valid_r;

    // The skid buffer holds one incoming AXI beat during backpressure
    logic                         skid_valid;
    logic                         skid_ready;
    logic [INPUT_BUS_WIDTH-1:0]   skid_data;
    logic [INPUT_BUS_WIDTH/8-1:0] skid_keep;
    logic                         skid_last;

    // H0 consumes whenever config is done and a skid beat is present
    logic consume_skid;
    // DEBUG: counter for number of images received
    logic [31:0] data_in_last_count;

    // DEBUG: running cycle counter since last argmax_valid
    logic [31:0] cycles_since_argmax;
    logic        seen_first_argmax;

    integer i;
    always_ff @(posedge clk or posedge rst) begin
         if (rst) begin
            data_in_last_count <= '0;
        end else begin
            if (data_in_last) begin
                data_in_last_count <= data_in_last_count + 1'b1;
            end
        end
    end

    // DEBUG: first argmax_valid starts counter at 0, then it increments every clock
    // until the next argmax_valid, where it resets back to 0.
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            cycles_since_argmax <= '0;
            seen_first_argmax   <= 1'b0;
        end else begin
            if (argmax_valid) begin
                seen_first_argmax   <= 1'b1;
                cycles_since_argmax <= '0;
            end else if (seen_first_argmax) begin
                cycles_since_argmax <= cycles_since_argmax + 1'b1;
            end
        end
    end

    // Split the config stream into header fields and payload bytes
    Config_Manager #(
        .BUS_WIDTH (CONFIG_BUS_WIDTH),
        .LAYERS    (LAYERS)
    ) u_config_manager (
        .clk              (clk),
        .rst              (rst),

        .config_data_in   (config_data),
        .config_valid     (config_valid),
        .config_keep      (config_keep),
        .config_last      (config_last),
        .config_ready     (config_ready),

        .msg_valid        (msg_valid),
        .msg_ready        (msg_ready),
        .msg_layer        (msg_layer),
        .msg_type         (msg_type),
        .msg_layer_inputs (msg_layer_inputs),
        .msg_num_neurons  (msg_num_neurons),
        .msg_BN           (msg_BN),
        .msg_total_bytes  (msg_total_bytes),

        .payload_valid    (payload_valid),
        .payload_ready    (payload_ready),
        .payload_data     (payload_data),
        .payload_last     (payload_last),

        .busy             (),
        .error            ()
    );

    // All compute layers are allowed to run once configuration is finished
    assign all_cfg_done = &cfg_done_arr;

    // Keep start high so each layer can begin when its input bank becomes ready
    assign start_layer_vec = {LAYERS{all_cfg_done}};

    // H0 consumes any valid skid beat once configuration is complete
    assign consume_skid = skid_valid && all_cfg_done;

    // Upstream is throttled by H0 stall, but the skid buffer still catches one beat safely
    assign data_in_ready = all_cfg_done && skid_ready && !input_buffer_stall_arr[0];

    // Any AXI byte with TKEEP low gets forced to zero
    always_comb begin
        masked_input_data = '0;
        for (i = 0; i < INPUT_BUS_ELEMENTS; i++) begin
            if (skid_keep[i]) begin
                masked_input_data[i*INPUT_DATA_WIDTH +: INPUT_DATA_WIDTH] =
                    skid_data[i*INPUT_DATA_WIDTH +: INPUT_DATA_WIDTH];
            end
        end
    end

    // This one register absorbs the extra beat when H0 suddenly stalls
    AXIS_Skid_Buffer #(
        .DATA_W (INPUT_BUS_WIDTH),
        .KEEP_W (INPUT_BUS_WIDTH / 8)
    ) u_data_in_skid (
        .clk     (clk),
        .rst     (rst),

        .s_valid (data_in_valid),
        .s_ready (skid_ready),
        .s_data  (data_in_data),
        .s_keep  (data_in_keep),
        .s_last  (data_in_last),

        .m_valid (skid_valid),
        .m_ready (consume_skid),
        .m_data  (skid_data),
        .m_keep  (skid_keep),
        .m_last  (skid_last)
    );

    // Raw pixels are binarized only when a skid-buffered beat is actually consumed
    Input_Layer #(
        .out_w  (PARALLEL_INPUTS),
        .in_w   (INPUT_BUS_WIDTH),
        .THRESH (INPUT_BIN_THRESH)
    ) u_input_layer (
        .clk     (clk),
        .rst     (rst),
        .en      (consume_skid),
        .istream (masked_input_data),
        .valid   (first_layer_write),
        .ostream (first_layer_bits)
    );

    // Hidden block holds every compute layer after the input layer
    BNN_Hidden #(
        .TOTAL_LAYERS         (TOTAL_LAYERS),
        .TOPOLOGY             (TOPOLOGY),
        .FIRST_LAYER_IB_WIDTH (PARALLEL_INPUTS),
        .PARALLEL_INPUTS      (LAYER_PARALLEL_INPUTS),
        .PARALLEL_NEURONS     (PARALLEL_NEURONS),
        .THRESHOLD_WIDTH      (THRESHOLD_WIDTH),
        .LAYER_LATENCY        (LAYER_LATENCY)
    ) u_bnn_hidden (
        .clk                    (clk),
        .rst                    (rst),

        .start_layer_vec        (start_layer_vec),

        .msg_valid              (msg_valid),
        .msg_ready              (msg_ready),
        .msg_layer              (msg_layer),
        .msg_type               (msg_type),
        .msg_layer_inputs       (msg_layer_inputs),
        .msg_num_neurons        (msg_num_neurons),
        .msg_BN                 (msg_BN),
        .msg_total_bytes        (msg_total_bytes),

        .payload_valid          (payload_valid),
        .payload_ready          (payload_ready),
        .payload_data           (payload_data),
        .payload_last           (payload_last),

        .first_layer_istream    (first_layer_bits),
        .first_layer_write      (first_layer_write),

        .cfg_done_arr           (cfg_done_arr),
        .cfg_busy_arr           (cfg_busy_arr),
        .cfg_error_arr          (cfg_error_arr),

        .input_buffer_ready_arr (input_buffer_ready_arr),
        .input_buffer_stall_arr (input_buffer_stall_arr),
        .write_bank_sel_arr     (write_bank_sel_arr),

        .layer_active_arr       (layer_active_arr),
        .layer_done_arr         (layer_done_arr),

        .final_out              (final_out),
        .final_pop_out          (final_pop_out),
        .final_valid_acc        (final_valid_acc),
        .final_valid_out        (final_valid_out)
    );

    // Only start argmax when a final popcount vector is ready and the output register is free
    assign bnn_count_valid = (|final_valid_acc) && !data_out_valid_r;

    // Argmax chooses the class with the largest popcount
    Arg_MAX #(
        .act_w      (PARALLEL_NEURONS[LAYERS-1]),
        .popcount_w (FINAL_POP_W),
        .out_w      (OUTPUT_BUS_WIDTH)
    ) u_argmax (
        .clk       (clk),
        .rst       (rst),
        .en        (bnn_count_valid),
        .popcount  (final_pop_out),
        .bcc_out   (argmax_data),
        .out_valid (argmax_valid)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            argmax_valid_count <= '0;
        end else begin
            if (argmax_valid) begin
                argmax_valid_count <= argmax_valid_count + 1'b1;
            end
        end
    end

    // Hold output valid until the downstream side accepts the beat
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out_data_r  <= '0;
            data_out_valid_r <= 1'b0;
        end else begin
            // Clear valid after a successful AXI handshake
            if (data_out_valid_r && data_out_ready) begin
                data_out_valid_r <= 1'b0;
            end

            // Capture a new argmax result only when the output register is free
            if (argmax_valid && !data_out_valid_r) begin
                data_out_data_r  <= argmax_data;
                data_out_valid_r <= 1'b1;
            end
        end
    end

    assign data_out_data  = data_out_data_r;
    assign data_out_valid = data_out_valid_r;
    assign data_out_keep  = '1;
    assign data_out_last  = data_out_valid_r;

endmodule
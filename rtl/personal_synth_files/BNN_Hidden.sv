`timescale 1ns / 1ps

module BNN_Hidden #(
    parameter int TOTAL_LAYERS = 4,

    // Compute layers start after the input layer, and the output layer is included here too.
    localparam int LAYERS = TOTAL_LAYERS - 1,

    // Full network shape including the raw input stage.
    parameter int TOPOLOGY[0:TOTAL_LAYERS-1] = '{0:784, 1:256, 2:256, 3:10, default:0},

    // Width of each binarized word coming out of the input layer.
    parameter int FIRST_LAYER_IB_WIDTH = 8,

    // PW for each compute layer.
    parameter int PARALLEL_INPUTS[0:LAYERS-1]  = '{default:8},

    // PN for each compute layer.
    parameter int PARALLEL_NEURONS[0:LAYERS-1] = '{default:8},

    // Shared threshold RAM width.
    parameter int THRESHOLD_WIDTH = 32,

    // NP latency for each compute layer.
    parameter int LAYER_LATENCY[0:LAYERS-1] = '{default:4},

    // Width of the shared layer id.
    localparam int LAYER_W = (LAYERS <= 1) ? 1 : $clog2(LAYERS)
)(
    input  logic clk,
    input  logic rst,

    // Top level decides when each compute layer is allowed to start.
    input  logic [LAYERS-1:0] start_layer_vec,

    // Shared config header bus.
    input  logic               msg_valid,
    output logic               msg_ready,
    input  logic [LAYER_W-1:0] msg_layer,
    input  logic [7:0]         msg_type,
    input  logic [15:0]        msg_layer_inputs,
    input  logic [15:0]        msg_num_neurons,
    input  logic [15:0]        msg_BN,
    input  logic [31:0]        msg_total_bytes,

    // Shared config payload stream.
    input  logic               payload_valid,
    output logic               payload_ready,
    input  logic [7:0]         payload_data,
    input  logic               payload_last,

    // Binarized stream from the input layer into H0.
    input  logic [FIRST_LAYER_IB_WIDTH-1:0] first_layer_istream,
    input  logic                            first_layer_write,

    // Per-layer config status.
    output logic [LAYERS-1:0] cfg_done_arr,
    output logic [LAYERS-1:0] cfg_busy_arr,
    output logic [LAYERS-1:0] cfg_error_arr,

    // Per-layer input buffer status.
    output logic [LAYERS-1:0] input_buffer_ready_arr,
    output logic [LAYERS-1:0] input_buffer_stall_arr,
    output logic [LAYERS-1:0] write_bank_sel_arr,

    // Per-layer run status.
    output logic [LAYERS-1:0] layer_active_arr,
    output logic [LAYERS-1:0] layer_done_arr,

    // Final compute layer outputs for the top level.
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0] final_out,
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0][$clog2(TOPOLOGY[LAYERS-1] + 1)-1:0] final_pop_out,
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0] final_valid_acc,
    output logic [PARALLEL_NEURONS[LAYERS-1]-1:0] final_valid_out
);

    // Find the biggest PN so the shared buses are wide enough.
    function automatic int get_max_parallel_neurons();
        int max_v;
        begin
            max_v = PARALLEL_NEURONS[0];
            for (int i = 1; i < LAYERS; i++) begin
                if (PARALLEL_NEURONS[i] > max_v) max_v = PARALLEL_NEURONS[i];
            end
            return max_v;
        end
    endfunction

    // Find the biggest logical TN seen by any compute layer.
    function automatic int get_max_layer_tn();
        int max_v;
        begin
            max_v = TOPOLOGY[0];
            for (int i = 1; i < LAYERS; i++) begin
                if (TOPOLOGY[i] > max_v) max_v = TOPOLOGY[i];
            end
            return max_v;
        end
    endfunction

    // Shared bus widths used across all layers.
    localparam int MAX_PARALLEL_NEURONS = get_max_parallel_neurons();
    localparam int MAX_LAYER_TN         = get_max_layer_tn();
    localparam int MAX_POP_W            = $clog2(MAX_LAYER_TN + 1);

    // Each layer gets its own ready on the shared header bus.
    logic [LAYERS-1:0] msg_ready_vec;

    // Each layer gets its own ready on the shared payload bus.
    logic [LAYERS-1:0] payload_ready_vec;

    // Shared buses carry layer outputs forward even when widths differ.
    logic [LAYERS-1:0][MAX_PARALLEL_NEURONS-1:0]                stage_out_bus;
    logic [LAYERS-1:0][MAX_PARALLEL_NEURONS-1:0]                stage_valid_acc_bus;
    logic [LAYERS-1:0][MAX_PARALLEL_NEURONS-1:0]                stage_valid_out_bus;
    logic [LAYERS-1:0][MAX_PARALLEL_NEURONS-1:0][MAX_POP_W-1:0] stage_pop_bus;

    // Any layer can claim the shared header bus.
    assign msg_ready = |msg_ready_vec;

    // Any layer can claim the shared payload bus.
    assign payload_ready = |payload_ready_vec;

    // Grab the final layer outputs from the shared buses.
    assign final_out       = stage_out_bus[LAYERS-1][PARALLEL_NEURONS[LAYERS-1]-1:0];
    assign final_valid_acc = stage_valid_acc_bus[LAYERS-1][PARALLEL_NEURONS[LAYERS-1]-1:0];
    assign final_valid_out = stage_valid_out_bus[LAYERS-1][PARALLEL_NEURONS[LAYERS-1]-1:0];

    // Trim the shared popcount bus back down to the real final width.
    always_comb begin
        final_pop_out = '0;
        for (int j = 0; j < PARALLEL_NEURONS[LAYERS-1]; j++) begin
            final_pop_out[j] = stage_pop_bus[LAYERS-1][j][$clog2(TOPOLOGY[LAYERS-1] + 1)-1:0];
        end
    end

    genvar g;
    generate
        for (g = 0; g < LAYERS; g++) begin : GEN_LAYERS

            // H0 is written by the input layer, later layers are written by the previous layer.
            localparam int CUR_IB_WIDTH = (g == 0) ? FIRST_LAYER_IB_WIDTH : PARALLEL_NEURONS[g-1];

            // H0 logically sees all 784 binarized bits, later layers see the previous layer neuron count.
            localparam int CUR_TN = (g == 0) ? TOPOLOGY[0]
                                             : TOPOLOGY[g];

            // Exact input stream going into this layer's input buffer.
            logic [CUR_IB_WIDTH-1:0] istream_local;

            // Write pulse into this layer's input buffer.
            logic                    write_local;

            // Exact outputs from this layer.
            logic [PARALLEL_NEURONS[g]-1:0] out_local;
            logic [PARALLEL_NEURONS[g]-1:0][$clog2(CUR_TN + 1)-1:0] pop_local;
            logic [PARALLEL_NEURONS[g]-1:0] valid_acc_local;
            logic [PARALLEL_NEURONS[g]-1:0] valid_out_local;

            if (g == 0) begin
                // H0 takes the binarized stream straight from the input layer.
                assign istream_local = first_layer_istream;
                assign write_local   = first_layer_write;
            end else begin
                // Later layers read the previous layer's output bus.
                assign istream_local = stage_out_bus[g-1][CUR_IB_WIDTH-1:0];
                assign write_local   = |stage_valid_out_bus[g-1][CUR_IB_WIDTH-1:0];
            end

            // One full compute layer wrapper.
            BNN_Layer #(
                .LAYER_ID  (g),
                .LAYER_W   (LAYER_W),
                .IB_WIDTH  (CUR_IB_WIDTH),
                .PW        (PARALLEL_INPUTS[g]),
                .PN        (PARALLEL_NEURONS[g]),
                .TN        (CUR_TN),
                .N_NEURONS (TOPOLOGY[g+1]),
                .TW        (THRESHOLD_WIDTH),
                .LAT       (LAYER_LATENCY[g])
            ) u_bnn_layer (
                .clk                (clk),
                .rst                (rst),

                .start_layer        (start_layer_vec[g]),

                .msg_valid          (msg_valid),
                .msg_ready          (msg_ready_vec[g]),
                .msg_layer          (msg_layer),
                .msg_type           (msg_type),
                .msg_layer_inputs   (msg_layer_inputs),
                .msg_num_neurons    (msg_num_neurons),
                .msg_BN             (msg_BN),
                .msg_total_bytes    (msg_total_bytes),

                .payload_valid      (payload_valid),
                .payload_ready      (payload_ready_vec[g]),
                .payload_data       (payload_data),
                .payload_last       (payload_last),

                .buffer_write       (write_local),
                .istream            (istream_local),

                .out                (out_local),
                .pop_out            (pop_local),
                .valid_acc          (valid_acc_local),
                .valid_out          (valid_out_local),

                .cfg_done           (cfg_done_arr[g]),
                .cfg_busy           (cfg_busy_arr[g]),
                .cfg_error          (cfg_error_arr[g]),
                .input_buffer_ready (input_buffer_ready_arr[g]),
                .input_buffer_stall (input_buffer_stall_arr[g]),
                .write_bank_sel_out (write_bank_sel_arr[g]),
                .layer_active       (layer_active_arr[g]),
                .layer_done         (layer_done_arr[g])
            );

            // Pack this layer's exact outputs into the shared buses.
            always_comb begin
                stage_out_bus[g]       = '0;
                stage_valid_acc_bus[g] = '0;
                stage_valid_out_bus[g] = '0;
                stage_pop_bus[g]       = '0;

                stage_out_bus[g][PARALLEL_NEURONS[g]-1:0]       = out_local;
                stage_valid_acc_bus[g][PARALLEL_NEURONS[g]-1:0] = valid_acc_local;
                stage_valid_out_bus[g][PARALLEL_NEURONS[g]-1:0] = valid_out_local;

                for (int j = 0; j < PARALLEL_NEURONS[g]; j++) begin
                    stage_pop_bus[g][j][$clog2(CUR_TN + 1)-1:0] = pop_local[j];
                end
            end

        end
    endgenerate

endmodule
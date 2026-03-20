`timescale 1ns / 1ps

module BNN_Layer #(
    parameter int LAYER_ID  = 0,
    parameter int LAYER_W   = 1,

    // Width of words written into the input buffer
    parameter int IB_WIDTH  = 8,

    // Width read from the input buffer each cycle
    parameter int PW        = 8,

    // Number of neuron processors running in parallel
    parameter int PN        = 8,

    // Total input bits each neuron consumes
    parameter int TN        = 16,

    // Total neurons in this layer
    parameter int N_NEURONS = 16,

    // Stored threshold width
    parameter int TW        = 32,

    // NP pipeline latency
    parameter int LAT       = 4,

    // Weight beats needed per neuron
    localparam int BEATS     = (TN + PW - 1) / PW,

    // Max neurons that can land in one bank
    localparam int GROUPS    = (N_NEURONS + PN - 1) / PN,

    // Local weight RAM address width per bank
    localparam int W_ADDR_W  = (GROUPS * BEATS <= 1) ? 1 : $clog2(GROUPS * BEATS),

    // Local threshold RAM address width per bank
    localparam int TW_ADDR_W = (GROUPS <= 1) ? 1 : $clog2(GROUPS),

    // Input buffer read address width
    localparam int IB_ADDR_W = (BEATS <= 1) ? 1 : $clog2(BEATS)
)(
    input  logic clk,
    input  logic rst,

    // Kicks off compute for this layer
    input  logic start_layer,

    // Shared config header bus
    input  logic               msg_valid,
    output logic               msg_ready,
    input  logic [LAYER_W-1:0] msg_layer,
    input  logic [7:0]         msg_type,
    input  logic [15:0]        msg_layer_inputs,
    input  logic [15:0]        msg_num_neurons,
    input  logic [15:0]        msg_BN,
    input  logic [31:0]        msg_total_bytes,

    // Shared config payload stream
    input  logic               payload_valid,
    output logic               payload_ready,
    input  logic [7:0]         payload_data,
    input  logic               payload_last,

    // Activation stream written into the input buffer
    input  logic                buffer_write,
    input  logic [IB_WIDTH-1:0] istream,

    // Outputs from this layer
    output logic [PN-1:0] out,
    output logic [PN-1:0][$clog2(TN+1)-1:0] pop_out,
    output logic [PN-1:0] valid_acc,
    output logic [PN-1:0] valid_out,

    // Status
    output logic cfg_done,
    output logic cfg_busy,
    output logic cfg_error,
    output logic input_buffer_ready,
    output logic input_buffer_stall,
    output logic write_bank_sel_out,
    output logic layer_active,
    output logic layer_done
);

    // These signals drive the read side of the double-buffered input memory
    logic                 buffer_read;
    logic                 clear_bank0;
    logic                 clear_bank1;
    logic                 read_bank_sel;
    logic [IB_ADDR_W-1:0] buffer_raddr;

    // This feedback tells the layer which bank is ready and which addresses exist
    logic                 start_allowed_bank0;
    logic                 start_allowed_bank1;
    logic                 buffer_has_addr_bank0;
    logic                 buffer_has_addr_bank1;

    // The selected bank feeds PW bits each cycle into the compute layer
    logic [PW-1:0]        input_buffer_out;

    // Port A is used by config logic to write weights into each NP weight RAM
    logic [PN-1:0][PW-1:0]        w_ram_a_data;
    logic [PN-1:0][W_ADDR_W-1:0]  w_ram_a_addr;
    logic [PN-1:0]                w_ram_wen_a;

    // Threshold writes also come from the config controller on port A
    logic [PN-1:0][TW-1:0]        t_ram_a_data;
    logic [PN-1:0][TW_ADDR_W-1:0] t_ram_a_addr;
    logic [PN-1:0]                t_ram_wen_a;

    // Port B write side is unused from this wrapper, so keep it tied low
    logic [PN-1:0][PW-1:0] w_ram_b_data_cfg_tie;
    logic [PN-1:0][TW-1:0] t_ram_b_data_cfg_tie;
    logic [PN-1:0]         w_ram_wen_b_cfg_tie;
    logic [PN-1:0]         t_ram_wen_b_cfg_tie;

    assign w_ram_b_data_cfg_tie = '0;
    assign t_ram_b_data_cfg_tie = '0;
    assign w_ram_wen_b_cfg_tie  = '0;
    assign t_ram_wen_b_cfg_tie  = '0;

    // We report ready based on whichever bank the layer is currently trying to read
    assign input_buffer_ready = read_bank_sel ? start_allowed_bank1 : start_allowed_bank0;

    // Config manager for this layer fills the local weight and threshold memories
    Config_Layer_Control #(
        .LAYER_ID  (LAYER_ID),
        .LAYER_W   (LAYER_W),
        .PN        (PN),
        .PW        (PW),
        .TN        (TN),
        .N_NEURONS (N_NEURONS),
        .TW        (TW)
    ) u_cfg_ctrl (
        .clk              (clk),
        .rst              (rst),

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

        .w_ram_a_data     (w_ram_a_data),
        .w_ram_a_addr     (w_ram_a_addr),
        .w_ram_wen_a      (w_ram_wen_a),

        .t_ram_a_data     (t_ram_a_data),
        .t_ram_a_addr     (t_ram_a_addr),
        .t_ram_wen_a      (t_ram_wen_a),

        .cfg_busy         (cfg_busy),
        .cfg_done         (cfg_done),
        .cfg_error        (cfg_error)
    );

    // Incoming activations are parked here until the compute side consumes them
    Input_Bufferv1 #(
        .LAYER_ID(LAYER_ID),
        .IB_WIDTH (IB_WIDTH),
        .PW       (PW),
        .TN       (TN)
    ) u_input_buffer (
        .clk                   (clk),
        .rst                   (rst),

        .buffer_write          (buffer_write),
        .buffer_read           (buffer_read),
        .raddr                 (buffer_raddr),

        .read_bank_sel         (read_bank_sel),
        .clear_bank0           (clear_bank0),
        .clear_bank1           (clear_bank1),

        .istream               (istream),
        .ostream               (input_buffer_out),

        .start_allowed_bank0   (start_allowed_bank0),
        .start_allowed_bank1   (start_allowed_bank1),
        .buffer_has_addr_bank0 (buffer_has_addr_bank0),
        .buffer_has_addr_bank1 (buffer_has_addr_bank1),

        .write_bank_sel_out    (write_bank_sel_out),
        .stall                 (input_buffer_stall)
    );

    // The layer block pulls from the selected bank and runs the neuron processors
    Layer #(
        .LAYER_ID  (LAYER_ID),
        .PN        (PN),
        .PW        (PW),
        .TN        (TN),
        .N_NEURONS (N_NEURONS),
        .TW        (TW),
        .LAT       (LAT)
    ) u_layer (
        .clk                   (clk),
        .rst                   (rst),

        .start_layer           (start_layer),

        .start_allowed_bank0   (start_allowed_bank0),
        .start_allowed_bank1   (start_allowed_bank1),
        .buffer_has_addr_bank0 (buffer_has_addr_bank0),
        .buffer_has_addr_bank1 (buffer_has_addr_bank1),

        // This tells the controller which bank is currently being filled
        .write_bank_sel        (write_bank_sel_out),

        .read_bank_sel         (read_bank_sel),
        .buffer_read           (buffer_read),
        .clear_bank0           (clear_bank0),
        .clear_bank1           (clear_bank1),
        .buffer_raddr          (buffer_raddr),

        .input_buffer          (input_buffer_out),

        .w_ram_a_data          (w_ram_a_data),
        .t_ram_a_data          (t_ram_a_data),
        .w_ram_b_data          (w_ram_b_data_cfg_tie),
        .t_ram_b_data          (t_ram_b_data_cfg_tie),

        .w_ram_a_addr          (w_ram_a_addr),
        .t_ram_a_addr          (t_ram_a_addr),

        .w_ram_wen_a           (w_ram_wen_a),
        .w_ram_wen_b           (w_ram_wen_b_cfg_tie),
        .t_ram_wen_a           (t_ram_wen_a),
        .t_ram_wen_b           (t_ram_wen_b_cfg_tie),

        .out                   (out),
        .pop_out               (pop_out),
        .valid_acc             (valid_acc),
        .valid_out             (valid_out),

        .layer_active          (layer_active),
        .done                  (layer_done)
    );

endmodule
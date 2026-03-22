`timescale 1ns/1ps

module Layer #(
    parameter int LAYER_ID = 0,
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int TN = 16,
    parameter int N_NEURONS = 16,
    parameter int TW = 32,
    parameter int LAT = 4,

    localparam int beats   = (TN + PW - 1) / PW,
    localparam int BEAT_W  = (beats <= 1) ? 1 : $clog2(beats),
    localparam int GROUPS  = (N_NEURONS + PN - 1) / PN,
    localparam int TW_addr = (GROUPS <= 1) ? 1 : $clog2(GROUPS),
    localparam int W_addr  = (beats * GROUPS <= 1) ? 1 : $clog2(beats * GROUPS),
    localparam int OUTC_W  = (GROUPS <= 1) ? 1 : $clog2(GROUPS + 1)
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

    input  logic [PW-1:0] input_buffer,

    input  logic [PN-1:0][PW-1:0] w_ram_a_data,
    input  logic [PN-1:0][TW-1:0] t_ram_a_data,
    input  logic [PN-1:0][PW-1:0] w_ram_b_data,
    input  logic [PN-1:0][TW-1:0] t_ram_b_data,

    input  logic [PN-1:0][W_addr-1:0]  w_ram_a_addr,
    input  logic [PN-1:0][TW_addr-1:0] t_ram_a_addr,

    input  logic [PN-1:0] w_ram_wen_a,
    input  logic [PN-1:0] w_ram_wen_b,
    input  logic [PN-1:0] t_ram_wen_a,
    input  logic [PN-1:0] t_ram_wen_b,

    output logic [PN-1:0] out,
    output logic [PN-1:0][$clog2(TN+1)-1:0] pop_out,

    output logic [PN-1:0] valid_acc,
    output logic [PN-1:0] valid_out,

    output logic layer_active,
    output logic done
);

  logic controller_done;

  logic [PN-1:0] w_ram_b_ren;
  logic [PN-1:0] t_ram_b_ren;

  logic [PN-1:0][W_addr-1:0]  w_ram_b_addr;
  logic [PN-1:0][TW_addr-1:0] t_ram_b_addr;

  logic [PN-1:0] valid_in;
  logic [PN-1:0] last_in;

  logic [OUTC_W-1:0] group_count;
  logic [OUTC_W-1:0] group_count_next;

  logic any_valid_out;
  logic any_valid_acc;
  logic done_next;

  // Count one group whenever any NP finishes a group.
  assign any_valid_out = |valid_out;
  assign any_valid_acc = |valid_acc;

  // Current image index advances only after a done pulse.
  logic [31:0] image_idx;

  always_ff @(posedge clk or posedge rst) begin
    if (rst)
      image_idx <= 32'd0;
    else if (done)
      image_idx <= image_idx + 1'b1;
  end

  always_comb begin
    group_count_next = group_count;
    if (any_valid_out)
      group_count_next = group_count + 1'b1;
  end

  // done pulses when the last group finishes.
  always_comb begin
    done_next = 1'b0;
    if (any_valid_out && (group_count_next == GROUPS[OUTC_W-1:0]))
      done_next = 1'b1;
  end

  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      group_count <= '0;
      done        <= 1'b0;
    end else begin
      done <= 1'b0;

      if (done_next)
        group_count <= '0;
      else
        group_count <= group_count_next;

      if (done_next)
        done <= 1'b1;
    end
  end

  Layer_Control #(
    .LAYER_ID  (LAYER_ID),
    .PN        (PN),
    .PW        (PW),
    .TN        (TN),
    .N_NEURONS (N_NEURONS),
    .TW        (TW)
  ) u_ctrl (
    .clk                   (clk),
    .rst                   (rst),
    .start_layer           (start_layer),
    .start_allowed_bank0   (start_allowed_bank0),
    .start_allowed_bank1   (start_allowed_bank1),
    .buffer_has_addr_bank0 (buffer_has_addr_bank0),
    .buffer_has_addr_bank1 (buffer_has_addr_bank1),
    .write_bank_sel        (write_bank_sel),
    .read_bank_sel         (read_bank_sel),
    .buffer_read           (buffer_read),
    .clear_bank0           (clear_bank0),
    .clear_bank1           (clear_bank1),
    .buffer_raddr          (buffer_raddr),
    .w_ram_b_ren           (w_ram_b_ren),
    .t_ram_b_ren           (t_ram_b_ren),
    .w_ram_b_addr          (w_ram_b_addr),
    .t_ram_b_addr          (t_ram_b_addr),
    .valid_in              (valid_in),
    .last_in               (last_in),
    .layer_active          (layer_active),
    .controller_done       (controller_done)
  );

  NP_Layer #(
    .LAYER_ID (LAYER_ID),
    .PN       (PN),
    .PW       (PW),
    .TN       (TN),
    .N        (N_NEURONS),
    .TW       (TW),
    .LAT      (LAT)
  ) u_np_layer (
    .clk         (clk),
    .rst         (rst),
    .group_count (group_count),
    .image_idx   (image_idx),
    .input_buffer(input_buffer),
    .w_ram_a_data(w_ram_a_data),
    .t_ram_a_data(t_ram_a_data),
    .w_ram_b_data(w_ram_b_data),
    .t_ram_b_data(t_ram_b_data),
    .w_ram_a_addr(w_ram_a_addr),
    .t_ram_a_addr(t_ram_a_addr),
    .w_ram_b_addr(w_ram_b_addr),
    .t_ram_b_addr(t_ram_b_addr),
    .w_ram_wen_a (w_ram_wen_a),
    .w_ram_wen_b (w_ram_wen_b),
    .t_ram_wen_a (t_ram_wen_a),
    .t_ram_wen_b (t_ram_wen_b),
    .valid_in    (valid_in),
    .last_in     (last_in),
    .w_ram_ren_b (w_ram_b_ren),
    .t_ram_ren_b (t_ram_b_ren),
    .out         (out),
    .pop_out     (pop_out),
    .valid_acc   (valid_acc),
    .valid_out   (valid_out)
  );

  // ------------------------------------------------------------
  // DEBUG PRINTS
  //
  // For LAYER_ID 0 or 1:
  //   print the packed layer output in true hex when a layer beat completes.
  //
  // For LAYER_ID 2:
  //   print final popcounts when valid_acc arrives.
  //

  integer dbg_i;
  always_ff @(posedge clk) begin
    if (!rst) begin

      // Hidden / intermediate layers: print actual layer beat output in hex
      if ((LAYER_ID != 2) && any_valid_out) begin
        $display("[LAYER_OUT] IMG=%0d L=%0d BEAT=%0d OUT=0x%0h",
          image_idx,
          LAYER_ID,
          group_count,
          out
        );
      end

      // Output layer and H1 popcount debug
      if ((LAYER_ID == 2 || LAYER_ID == 1) && any_valid_acc) begin
        $write("[LAYER_POP] IMG=%0d L=%0d BEAT=%0d",
          image_idx,
          LAYER_ID,
          group_count
        );
        for (dbg_i = 0; dbg_i < PN; dbg_i++) begin
          if (valid_acc[dbg_i]) begin
            $write(" n%0d=0x%0h", dbg_i, pop_out[dbg_i]);
          end
        end
        $write("\n");
      end

    end
  end

endmodule
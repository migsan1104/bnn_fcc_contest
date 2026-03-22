`timescale 1ns / 1ps

module NP_Layer#(
    parameter int LAYER_ID = 0,
    parameter int PN = 8,
    parameter int PW = 8,
    parameter int TN = 16,
    parameter int N  = 16,
    parameter int TW = 32,
    parameter int LAT = 4,
    localparam int beats   = (TN + PW - 1) / PW,
    localparam int GROUPS  = (N + PN - 1) / PN,
    localparam int TW_addr = (GROUPS <= 1) ? 1 : $clog2(GROUPS),
    localparam int W_addr  = (beats * GROUPS <= 1) ? 1 : $clog2(beats * GROUPS)
)(
    input  logic clk,
    input  logic rst,
    input  logic [GROUPS-1:0] group_count,

    input  logic [PW-1:0] input_buffer,

    input  logic [PN-1:0][PW-1:0] w_ram_a_data,
    input  logic [PN-1:0][TW-1:0] t_ram_a_data,

    input  logic [PN-1:0][PW-1:0] w_ram_b_data,
    input  logic [PN-1:0][TW-1:0] t_ram_b_data,

    input  logic [PN-1:0][W_addr-1:0]  w_ram_a_addr,
    input  logic [PN-1:0][TW_addr-1:0] t_ram_a_addr,

    input  logic [PN-1:0][W_addr-1:0]  w_ram_b_addr,
    input  logic [PN-1:0][TW_addr-1:0] t_ram_b_addr,

    input  logic [PN-1:0] w_ram_wen_a,
    input  logic [PN-1:0] w_ram_wen_b,
    input  logic [PN-1:0] t_ram_wen_a,
    input  logic [PN-1:0] t_ram_wen_b,

    input  logic [PN-1:0] valid_in,
    input  logic [PN-1:0] last_in,

    input  logic [PN-1:0] w_ram_ren_b,
    input  logic [PN-1:0] t_ram_ren_b,

    output logic [PN-1:0] out,
    output logic [PN-1:0][$clog2(TN+1)-1:0] pop_out,

    output logic [PN-1:0] valid_acc,
    output logic [PN-1:0] valid_out
);

  localparam int POP_W      = $clog2(TN+1);
  localparam int REM        = TN % PW;
  localparam int LAST_VALID = (REM == 0) ? PW : REM;

  logic [PN-1:0][PW-1:0]    w_from_ram;
  logic [PN-1:0][TW-1:0]    t_from_ram;

  logic [PW-1:0]            last_mask;
  logic [PN-1:0][PW-1:0]    x_to_np;
  logic [PN-1:0][PW-1:0]    w_to_np;

  logic [PN-1:0]            raw_out;
  logic [PN-1:0][POP_W-1:0] raw_pop_out;

  // Threshold request delayed by 3 cycles before BRAM port B
  logic [PN-1:0]              t_ram_ren_b_reg_0;
  logic [PN-1:0]              t_ram_ren_b_reg_1;
  logic [PN-1:0]              t_ram_ren_b_reg_2;

  logic [PN-1:0][TW_addr-1:0] t_ram_b_addr_reg_0;
  logic [PN-1:0][TW_addr-1:0] t_ram_b_addr_reg_1;
  logic [PN-1:0][TW_addr-1:0] t_ram_b_addr_reg_2;

  // Build mask for partial final beat
  always_comb begin
    int k;
    last_mask = '0;
    for (k = 0; k < LAST_VALID; k++) begin
      last_mask[k] = 1'b1;
    end
  end

  // Feed NP inputs
  always_comb begin
    int k;
    for (k = 0; k < PN; k++) begin
      x_to_np[k] = input_buffer;
      w_to_np[k] = w_from_ram[k];
      if ((REM != 0) && last_in[k] && valid_in[k]) begin
        x_to_np[k] = input_buffer & last_mask;
        w_to_np[k] = (w_from_ram[k] & last_mask) | ~last_mask;
      end
    end
  end

  // Delay threshold read request by 3 cycles
  always_ff @(posedge clk or posedge rst) begin
    if (rst) begin
      t_ram_ren_b_reg_0  <= '0;
      t_ram_ren_b_reg_1  <= '0;
      t_ram_ren_b_reg_2  <= '0;
      t_ram_b_addr_reg_0 <= '0;
      t_ram_b_addr_reg_1 <= '0;
      t_ram_b_addr_reg_2 <= '0;
    end else begin
      t_ram_ren_b_reg_0  <= t_ram_ren_b;
      t_ram_ren_b_reg_1  <= t_ram_ren_b_reg_0;
      t_ram_ren_b_reg_2  <= t_ram_ren_b_reg_1;

      t_ram_b_addr_reg_0 <= t_ram_b_addr;
      t_ram_b_addr_reg_1 <= t_ram_b_addr_reg_0;
      t_ram_b_addr_reg_2 <= t_ram_b_addr_reg_1;
    end
  end

  // Output masking
  always_comb begin
    int k;
    out     = '0;
    pop_out = '0;
    for (k = 0; k < PN; k++) begin
      if (valid_out[k]) begin
        out[k] = raw_out[k];
      end
      if (valid_acc[k]) begin
        pop_out[k] = raw_pop_out[k];
      end
    end
  end

  genvar i;
  generate
    for (i = 0; i < PN; i++) begin : GEN_NP

      BRAM #(
        .DATA_W(PW),
        .ADDR_W(W_addr)
      ) u_wram (
        .clk     (clk),
        .rst     (rst),
        .clear   (1'b0),
        .a_ren   (1'b0),
        .a_wen   (w_ram_wen_a[i]),
        .a_addr  (w_ram_a_addr[i]),
        .a_wdata (w_ram_a_data[i]),
        .a_rdata (),
        .b_ren   (w_ram_ren_b[i]),
        .b_wen   (w_ram_wen_b[i]),
        .b_addr  (w_ram_b_addr[i]),
        .b_wdata (w_ram_b_data[i]),
        .b_rdata (w_from_ram[i]),
        .size    ()
      );

      BRAM #(
        .DATA_W(TW),
        .ADDR_W(TW_addr)
      ) u_tram (
        .clk     (clk),
        .rst     (rst),
        .clear   (1'b0),
        .a_ren   (1'b0),
        .a_wen   (t_ram_wen_a[i]),
        .a_addr  (t_ram_a_addr[i]),
        .a_wdata (t_ram_a_data[i]),
        .a_rdata (),
        .b_ren   (t_ram_ren_b_reg_2[i]),
        .b_wen   (t_ram_wen_b[i]),
        .b_addr  (t_ram_b_addr_reg_2[i]),
        .b_wdata (t_ram_b_data[i]),
        .b_rdata (t_from_ram[i]),
        .size    ()
      );

      NP_UNIT #(
        .LAYER_ID          (LAYER_ID),
        .LANE_ID           (i),
        .PW                (PW),
        .TOTAL_BITS_NEURON (TN),
        .LAT               (LAT)
      ) u_np (
        .clk            (clk),
        .rst            (rst),
        .valid_in       (valid_in[i]),
        .last_in        (last_in[i]),
        .x              (x_to_np[i]),
        .w              (w_to_np[i]),
        .threshold      (t_from_ram[i][POP_W-1:0]),
        .popcount_total (raw_pop_out[i]),
        .y              (raw_out[i]),
        .valid_out      (valid_out[i]),
        .valid_acc      (valid_acc[i])
      );

    end
  endgenerate

endmodule
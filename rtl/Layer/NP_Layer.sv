module NP_Layer#(
    parameter int PN = 8,  // number of parallel neuron processors
    parameter int PW = 8,  // parallel weights/inputs per NP
    parameter int TN = 16, // total inputs per neuron
    parameter int N  = 16, // number of neurons per NP accumulation
    parameter int TW = 32, // threshold width
    parameter int LAT = 4,
    localparam int beats   = (TN + PW - 1) / PW,                 // number of beats needed to complete one neuron
    localparam int TW_addr = (N <= 1) ? 1 : $clog2(N),            // threshold RAM address width, avoid 0-width
    localparam int W_addr  = (beats*N <= 1) ? 1 : $clog2(beats*N) // weight RAM address width
)(
    input  logic clk,
    input  logic rst,

    input  logic [PW-1:0] input_buffer, // PW-wide input from buffer

    input  logic [PN-1:0][PW-1:0] w_ram_a_data, // write data for weights RAM port A
    input  logic [PN-1:0][TW-1:0] t_ram_a_data, // write data for threshold RAM port A

    input  logic  [PN-1:0][PW-1:0] w_ram_b_data, // write data for weights RAM port B
    input  logic [PN-1:0][TW-1:0] t_ram_b_data, // write data for threshold RAM port B

    input  logic [PN-1:0][W_addr-1:0]  w_ram_a_addr, // weights RAM port A address
    input  logic [PN-1:0][TW_addr-1:0] t_ram_a_addr, // threshold RAM port A address

    input  logic [PN-1:0][W_addr-1:0]  w_ram_b_addr, // weights RAM port B address
    input  logic [PN-1:0][TW_addr-1:0] t_ram_b_addr, // threshold RAM port B address

    input  logic [PN-1:0] w_ram_wen_a, // write enable for weights RAM port A
    input  logic [PN-1:0] w_ram_wen_b, // write enable for weights RAM port B
    input  logic [PN-1:0] t_ram_wen_a, // write enable for threshold RAM port A
    input  logic [PN-1:0] t_ram_wen_b, // write enable for threshold RAM port B

    input  logic [PN-1:0] valid_in,    // valid into each NP
    input  logic [PN-1:0] last_in,     // last-beat indicator into each NP

    input  logic [PN-1:0] w_ram_ren_b, // read enable array for weights RAM port B
    input  logic [PN-1:0] t_ram_ren_b, // read enable array for threshold RAM port B

    output logic [PN-1:0] out,
    output logic [PN-1:0][$clog2(N+1)-1:0] pop_out,

    output logic [PN-1:0] valid_acc,   // per-NP accumulation-valid from NP_UNIT
    output logic [PN-1:0] valid_out    // per-NP output-valid from NP_UNIT
);

  localparam int ACC_W = $clog2(N+1);                 // accumulator width used by threshold slice
  localparam int REM   = TN % PW;                     // number of valid bits in last beat when TN not multiple of PW
  localparam int LAST_VALID = (REM == 0) ? PW : REM;  // valid bits in last beat

  logic [PN-1:0][PW-1:0] w_from_ram;                  // weight beat from BRAM
  logic [PN-1:0][TW-1:0] t_from_ram;                  // threshold word from BRAM

  logic [PW-1:0]         last_mask;                   // mask of valid bits for last beat
  logic [PN-1:0][PW-1:0] x_to_np;                     // possibly padded x beat
  logic [PN-1:0][PW-1:0] w_to_np;                     // possibly padded w beat

  integer k;

  // Build a mask with LAST_VALID LSBs = 1 and padded MSBs = 0
  always_comb begin
    last_mask = '0;
    for (k = 0; k < LAST_VALID; k++) begin
      last_mask[k] = 1'b1;
    end
  end

  // Pad only on last beat when TN is not a multiple of PW
  always_comb begin
    for (k = 0; k < PN; k++) begin
      x_to_np[k] = input_buffer;
      w_to_np[k] = w_from_ram[k];
      if ((REM != 0) && last_in[k] && valid_in[k]) begin
        x_to_np[k] = input_buffer & last_mask;                 // padded x bits forced to 0
        w_to_np[k] = (w_from_ram[k] & last_mask) | ~last_mask; // padded w bits forced to 1
      end
    end
  end

  genvar i;
  generate
    for (i = 0; i < PN; i++) begin : GEN_NP

      // weight RAM for NP i
      BRAM #(
        .DATA_W(PW),
        .ADDR_W(W_addr)
      ) u_wram (
        .clk     (clk),
        .rst     (rst),
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

      // threshold RAM for NP i
      BRAM #(
        .DATA_W(TW),
        .ADDR_W(TW_addr)
      ) u_tram (
        .clk     (clk),
        .rst     (rst),
        .a_ren   (1'b0),
        .a_wen   (t_ram_wen_a[i]),
        .a_addr  (t_ram_a_addr[i]),
        .a_wdata (t_ram_a_data[i]),
        .a_rdata (),
        .b_ren   (t_ram_ren_b[i]),
        .b_wen   (t_ram_wen_b[i]),
        .b_addr  (t_ram_b_addr[i]),
        .b_wdata (t_ram_b_data[i]),
        .b_rdata (t_from_ram[i]),
        .size    ()
      );

      // neuron processor
      NP_UNIT #(
        .PW               (PW),
        .TOTAL_BITS_NEURON(TN),
        .LAT              (LAT)
      ) u_np (
        .clk            (clk),
        .rst            (rst),
        .valid_in       (valid_in[i]),
        .last_in        (last_in[i]),
        .x              (x_to_np[i]),
        .w              (w_to_np[i]),
        .threshold      (t_from_ram[i][ACC_W-1:0]),
        .popcount_total (pop_out[i]),
        .y              (out[i]),
        .valid_out      (valid_out[i]),
        .valid_acc      (valid_acc[i])
      );

    end
  endgenerate

endmodule
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

    input  logic [PN-1:0][PW-1:0] w_ram_b_data, // write data for weights RAM port B
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
    output logic [PN-1:0][$clog2(N+1)-1:0] pop_out
);

  localparam int ACC_W = $clog2(N+1);

  logic [PN-1:0][PW-1:0] w_from_ram;
  logic [PN-1:0][TW-1:0] t_from_ram;
  logic [PN-1:0]         valid_acc;
  logic [PN-1:0]         valid_out;

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
        .x              (input_buffer),
        .w              (w_from_ram[i]),
        .threshold      (t_from_ram[i][ACC_W-1:0]),
        .popcount_total (pop_out[i]),
        .y              (out[i]),
        .valid_out      (valid_out[i]),
        .valid_acc      (valid_acc[i])
      );

    end
  endgenerate

endmodule
module NP_Layer#(
    parameter PN = 8, // Number of parralel nueron processors 
    parameter PW = 8, // number of parralel weights and inputs put into the NP
    parameter N = 16, // total number of inputs needed for one nueron
    parameter TN = 16, // number of parralel neurons
    parameter TW = 32, // threshold weight
    parameter addrw = 8, // address width for rams
    parameter LAT = 4
)(
    input  logic clk,
    input  logic rst,

    input  logic [PW-1:0] input_buffer, // PW width input from buffer

    input  logic [PN-1:0][PW-1:0] w_ram_a_data, // array of data for weight rams port A
    input  logic [PN-1:0][TW-1:0] t_ram_a_data, // array of data for threshold rams port A

    input  logic [PN-1:0][PW-1:0] w_ram_b_data, // array of data for weight rams port B
    input  logic [PN-1:0][TW-1:0] t_ram_b_data, // array of data for threshold rams port B

    input  logic [PN-1:0][addrw-1:0] w_ram_a_addr, // address for weights port a
    input  logic [PN-1:0][addrw-1:0] t_ram_a_addr, // address for thresholds port a

    input  logic [PN-1:0][addrw-1:0] w_ram_b_addr, // address for weights port B
    input  logic [PN-1:0][addrw-1:0] t_ram_b_addr, // address for thresholds port B

    input  logic [PN-1:0] w_ram_wen_a, // array to store w_en for port A of weight rams
    input  logic [PN-1:0] w_ram_wen_b, // array to store w_en for port B of weight rams
    input  logic [PN-1:0] t_ram_wen_a, // array to store w_en for port A of threshold rams
    input  logic [PN-1:0] t_ram_wen_b, // array to store w_en for port B of threshold rams
 
    input  logic [PN-1:0] valid_in, // array to store valid_ins for all NPs
    input  logic [PN-1:0] last_in,  // array to store last_ins that feed into the NPs
     
    output logic [PN-1:0] out,
    output logic [PN-1:0][$clog2(N+1)-1:0] pop_out // pop_count array
);

  localparam ACC_W = $clog2(N+1);

  logic [PN-1:0][PW-1:0] w_from_ram;
  logic [PN-1:0][TW-1:0] t_from_ram;
  logic [PN-1:0] valid_acc;
  logic [PN-1:0] valid_out;

  genvar i;
  generate
    for (i = 0; i < PN; i++) begin : GEN_NP

      // weight ram for each NP
      BRAM #(
        .DATA_W(PW),
        .ADDR_W(addrw)
      ) u_wram (
        .clk     (clk),
        .a_en    (1'b1),
        .a_we    (w_ram_wen_a[i]),
        .a_addr  (w_ram_a_addr[i]),
        .a_wdata (w_ram_a_data[i]),
        .a_rdata (),
        .b_en    (1'b1),
        .b_we    (w_ram_wen_b[i]),
        .b_addr  (w_ram_b_addr[i]),
        .b_wdata (w_ram_b_data[i]),
        .b_rdata (w_from_ram[i])
      );

      // threshold ram for each NP
      BRAM #(
        .DATA_W(TW),
        .ADDR_W(addrw)
      ) u_tram (
        .clk     (clk),
        .a_en    (1'b1),
        .a_we    (t_ram_wen_a[i]),
        .a_addr  (t_ram_a_addr[i]),
        .a_wdata (t_ram_a_data[i]),
        .a_rdata (),
        .b_en    (1'b1),
        .b_we    (t_ram_wen_b[i]),
        .b_addr  (t_ram_b_addr[i]),
        .b_wdata (t_ram_b_data[i]),
        .b_rdata (t_from_ram[i])
      );

      // neuron processor instance
      NP_UNIT #(
        .PW(PW),
        .TOTAL_BITS_NEURON(N),
        .LAT(LAT)
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

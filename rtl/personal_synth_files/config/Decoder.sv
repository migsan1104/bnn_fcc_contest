module Decoder #(
  parameter int N = 3                // number of input bits
)(
  input  logic [N-1:0] in,           // binary input
  output logic [(1<<N)-1:0] out      // 2^N  outputs
);

  always_comb begin
    out = '0;                        // default all outputs to 0
    out[in] = 1'b1;                  // assert only the selected index
  end

endmodule
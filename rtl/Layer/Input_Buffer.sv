
module Input_Buffer#(
    parameter PN = 8, // number of parralel inputs going in
    parameter PW = 8, // number of parralel inputs going out
    parameter N = 64  // number of nuerons 
    )
    (
    input logic clk,
    input logic rst,
    input logic go,
    input logic done,
    output logic [$clog2(PN) - 1 : 0] istream, // input stream coming in 
    output logic [$clog2(PW) - 1 : 0] ostream // stream that gets fed into the parralel nuerons 
    );
endmodule

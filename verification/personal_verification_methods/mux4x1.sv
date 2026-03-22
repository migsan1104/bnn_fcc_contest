module mux4x1 #(
    parameter int D_WIDTH = 8   // width of each data input
)(
    input  logic [D_WIDTH-1:0] d0,   // input 0
    input  logic [D_WIDTH-1:0] d1,   // input 1
    input  logic [D_WIDTH-1:0] d2,   // input 2
    input  logic [D_WIDTH-1:0] d3,   // input 3
    input  logic [1:0]         sel,  // 2-bit select
    output logic [D_WIDTH-1:0] y     // mux output
);

    // Select which input drives the output
    always_comb begin
        case (sel)
            2'b00: y = d0;
            2'b01: y = d1;
            2'b10: y = d2;
            2'b11: y = d3;
            default: y = '0;   // safety default
        endcase
    end

endmodule
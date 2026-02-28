module mux2x1 #(
    parameter int D_WIDTH = 8   // width of the data inputs and output
)(
    input  logic [D_WIDTH-1:0] a,   // input 0
    input  logic [D_WIDTH-1:0] b,   // input 1
    input  logic               sel, // select signal
    output logic [D_WIDTH-1:0] y    // mux output
);

    // If sel = 0 → output a
    // If sel = 1 → output b
    assign y = sel ? b : a;

endmodule
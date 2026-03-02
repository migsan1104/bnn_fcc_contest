module Input_Layer#(
    parameter int out_w = 8,                 // Number of parallel outputs (one per input chunk)
    parameter int in_w  = 64,                // Total input width
    parameter int THRESH = 128,              // Threshold value for each chunk
    localparam int CHUNK_W = in_w / out_w    // Bits per chunk 
)(
    input  logic               clk,
    input  logic               rst,
    input  logic               en,            // Latch outputs when high
    input  logic [in_w-1:0]    istream,       // Input vector split into out_w chunks
    output logic [out_w-1:0]   ostream        // One bit per chunk after threshold compare
);

    logic [out_w-1:0] ostream_next;           // Combinational threshold results
    integer i;

    // parralel comb block
    always_comb begin
        ostream_next = '0;
        for (i = 0; i < out_w; i++) begin
            ostream_next[i] = (istream[i*CHUNK_W +: CHUNK_W] > THRESH);
        end
    end

    // Register output
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ostream <= '0;
        end else if (en) begin
            ostream <= ostream_next;
        end
    end

endmodule
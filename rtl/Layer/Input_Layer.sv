module Input_Layer #(
    parameter int unsigned out_w   = 8,                 // number of parallel outputs
    parameter int unsigned in_w    = 64,                // total input width
    localparam int unsigned CHUNK_W = in_w / out_w,     // bits per chunk (assumes divisible)
    parameter logic [CHUNK_W-1:0] THRESH = '0          // threshold per chunk (type-safe)
)(
    input  logic               clk,
    input  logic               rst,        // async active-high reset
    input  logic               en,         // latch outputs when high
    input  logic [in_w-1:0]    istream,    // input vector split into out_w chunks
    output logic               valid,
    output logic [out_w-1:0]   ostream     // one bit per chunk after compare
);

    logic [out_w-1:0] ostream_next;
    integer i;

    always_comb begin
        ostream_next = '0;
        for (i = 0; i < out_w; i++) begin
            logic [CHUNK_W-1:0] chunk;
            chunk = istream[i*CHUNK_W +: CHUNK_W];
            ostream_next[i] = (chunk > THRESH);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid   <= 1'b0;
            ostream <= '0;
        end else begin
            valid <= en;
            if (en) begin
                ostream <= ostream_next;
            end
        end
    end

endmodule
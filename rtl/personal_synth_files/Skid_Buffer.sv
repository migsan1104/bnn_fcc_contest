`timescale 1ns / 1ps

module AXIS_Skid_Buffer #(
    parameter int DATA_W = 64,
    parameter int KEEP_W = DATA_W / 8
)(
    input  logic              clk,
    input  logic              rst,

    // Upstream AXI side
    input  logic              s_valid,
    output logic              s_ready,
    input  logic [DATA_W-1:0] s_data,
    input  logic [KEEP_W-1:0] s_keep,
    input  logic              s_last,

    // Downstream side
    output logic              m_valid,
    input  logic              m_ready,
    output logic [DATA_W-1:0] m_data,
    output logic [KEEP_W-1:0] m_keep,
    output logic              m_last
);

    // One register is enough to catch the extra beat during backpressure
    logic [DATA_W-1:0] data_r;
    logic [KEEP_W-1:0] keep_r;
    logic              last_r;
    logic              valid_r;

    // Upstream can send when the skid entry is empty or being consumed now
    assign s_ready = !valid_r || m_ready;

    // Downstream sees whatever is currently parked in the skid register
    assign m_valid = valid_r;
    assign m_data  = data_r;
    assign m_keep  = keep_r;
    assign m_last  = last_r;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_r  <= '0;
            keep_r  <= '0;
            last_r  <= 1'b0;
            valid_r <= 1'b0;
        end else begin
            // A successful upstream handshake loads or replaces the skid entry
            if (s_valid && s_ready) begin
                data_r  <= s_data;
                keep_r  <= s_keep;
                last_r  <= s_last;
                valid_r <= 1'b1;
            end
            // If nothing new arrives, consuming the current entry makes it empty
            else if (m_ready && valid_r) begin
                valid_r <= 1'b0;
            end
        end
    end

endmodule
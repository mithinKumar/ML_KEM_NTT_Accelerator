`timescale 1ns / 1ps

module ntt_dma_translator (
    input  wire        clk,
    input  wire        reset_n,

    // AXI-Stream Slave (from PS DMA sendchannel)
    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // AXI-Stream Master (to PS DMA recvchannel)
    output wire [15:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,

    // Hardware Interface to ntt_top Memory Ports
    output wire        ext_coeff_we,
    output wire [7:0]  ext_coeff_waddr,
    output wire [11:0] ext_coeff_wdata,
    
    output wire [7:0]  ext_coeff_raddr,
    input  wire [11:0] ext_coeff_rdata,
    
    // Status Interface from ntt_top
    input  wire        ntt_done
);

    wire reset = ~reset_n;

    // -------------------------------------------------------------
    // RX FSM (DMA to NTT Memory)
    // -------------------------------------------------------------
    reg [7:0] rx_addr;
    
    // We are always ready to receive data as long as we haven't hit address overflow,
    // though realistically DMA will always send exactly 256 elements.
    assign s_axis_tready = 1'b1;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_addr <= 8'd0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                if (s_axis_tlast || rx_addr == 8'd255) begin
                    rx_addr <= 8'd0; // Reset address for next packet
                end else begin
                    rx_addr <= rx_addr + 1'b1;
                end
            end
        end
    end

    // Connect RX directly to the NTT Write Port
    assign ext_coeff_we    = s_axis_tvalid;
    assign ext_coeff_waddr = rx_addr;
    assign ext_coeff_wdata = s_axis_tdata[11:0]; // Truncate 16-bit to 12-bit

    // -------------------------------------------------------------
    // TX FSM (NTT Memory to DMA)
    // -------------------------------------------------------------
    reg [7:0] tx_addr;
    reg       tx_active;
    
    reg ntt_done_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) ntt_done_reg <= 1'b0;
        else ntt_done_reg <= ntt_done;
    end
    wire ntt_done_pulse = ntt_done && !ntt_done_reg;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tx_addr   <= 8'd0;
            tx_active <= 1'b0;
        end else begin
            if (ntt_done_pulse) begin
                // When NTT finishes, trigger the DMA transmission
                tx_active <= 1'b1;
                tx_addr   <= 8'd0;
            end else if (tx_active && m_axis_tready) begin
                if (tx_addr == 8'd255) begin
                    tx_active <= 1'b0;
                    tx_addr   <= 8'd0;
                end else begin
                    tx_addr <= tx_addr + 1'b1;
                end
            end
        end
    end

    // Connect TX directly to the NTT Read Port
    assign ext_coeff_raddr = tx_addr;

    // The Master stream is valid whenever tx_active is high
    assign m_axis_tvalid = tx_active;
    assign m_axis_tlast  = (tx_addr == 8'd255) && tx_active;
    
    // Pad the 12-bit output to 16 bits for AXI-Stream
    assign m_axis_tdata = {4'b0000, ext_coeff_rdata};

endmodule

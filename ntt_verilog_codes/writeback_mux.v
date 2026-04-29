module writeback_mux (
    input  wire [7:0]  addr_a,
    input  wire [7:0]  addr_b,

    input  wire [11:0] out_a,
    input  wire [11:0] out_b,

    input  wire        valid_a,
    input  wire        valid_b,

    output reg         wr_en,
    output reg  [7:0]  wr_addr,
    output reg  [11:0] wr_data
);

    always @(*) begin
        // Default: no write
        wr_en   = 1'b0;
        wr_addr = 8'd0;
        wr_data = 12'd0;

        if (valid_a) begin
            wr_en   = 1'b1;
            wr_addr = addr_a;
            wr_data = out_a;
        end
        else if (valid_b) begin
            wr_en   = 1'b1;
            wr_addr = addr_b;
            wr_data = out_b;
        end
    end

endmodule
module coeff_mem (
    input  wire        clk,

    // Read port A
    input  wire [7:0]  addr_a,
    output wire [11:0] rd_data_a,

    // Read port B
    input  wire [7:0]  addr_b,
    output wire [11:0] rd_data_b,

    // External read port
    input  wire [7:0]  addr_ext,
    output wire [11:0] rd_data_ext,

    // Single write port
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,
    input  wire [11:0] wr_data
);

    reg [11:0] mem [0:255];

    assign rd_data_a   = mem[addr_a];
    assign rd_data_b   = mem[addr_b];
    assign rd_data_ext = mem[addr_ext];

    always @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end

endmodule   
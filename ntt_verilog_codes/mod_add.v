module mod_add (
    input  wire [11:0] a,
    input  wire [11:0] b,
    output wire [11:0] y
);

    localparam [11:0] Q = 12'd3329;

    wire [12:0] sum_full;
    assign sum_full = {1'b0, a} + {1'b0, b};

    assign y = (sum_full >= Q) ? (sum_full - Q) : sum_full[11:0];

endmodule
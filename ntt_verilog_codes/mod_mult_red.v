module mod_mult_red (
    input  wire [11:0] a,
    input  wire [11:0] b,
    output wire [11:0] y
);

    localparam integer Q = 3329;

    wire [23:0] prod_full;
    assign prod_full = a * b;

    assign y = prod_full % Q;

endmodule
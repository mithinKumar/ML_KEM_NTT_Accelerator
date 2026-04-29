module mod_sub (
    input  wire [11:0] a,
    input  wire [11:0] b,
    output wire [11:0] y
);

    localparam [11:0] Q = 12'd3329;

    assign y = (a >= b) ? (a - b) : (a + Q - b);

endmodule
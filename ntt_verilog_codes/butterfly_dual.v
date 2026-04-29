module butterfly_core (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    input  wire        mode,       // 0 = Forward (CT), 1 = Inverse (GS)
    input  wire [1:0]  phase,      // 0,1,2,3 = butterfly micro-cycle

    input  wire [11:0] a_in,
    input  wire [11:0] b_in,
    input  wire [11:0] tw_in,

    output reg  [11:0] out_a,
    output reg  [11:0] out_b,
    output reg         valid_a,
    output reg         valid_b
);

    reg [11:0] reg_a, reg_b;
    reg [11:0] reg_mul;
    reg [11:0] reg_sum;
    reg [11:0] reg_diff;

    wire [11:0] mul_res, sum_res, diff_res;

    // Scale by 2^-1 modulo 3329 for Inverse NTT (GS)
    wire [11:0] sum_res_scaled  = sum_res[0]  ? ((sum_res + 13'd3329) >> 1) : (sum_res >> 1);
    wire [11:0] diff_res_scaled = diff_res[0] ? ((diff_res + 13'd3329) >> 1) : (diff_res >> 1);
    
    // MUXing the inputs to the arithmetic blocks based on mode
    wire [11:0] mult_in_a = (mode == 1'b0) ? reg_b : reg_diff; 
    wire [11:0] add_sub_in_b = (mode == 1'b0) ? reg_mul : reg_b;

    mod_mult_red u_mod_mult_red (.a(mult_in_a), .b(tw_in), .y(mul_res));
    mod_add      u_mod_add      (.a(reg_a),     .b(add_sub_in_b), .y(sum_res));
    mod_sub      u_mod_sub      (.a(reg_a),     .b(add_sub_in_b), .y(diff_res));

    // ----------------------------------------------------------------
    // Sequential Internal State
    // ----------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reg_a    <= 12'd0; 
            reg_b    <= 12'd0;
            reg_mul  <= 12'd0; 
            reg_sum  <= 12'd0; 
            reg_diff <= 12'd0;
        end else begin
            if (enable) begin
                case (phase)
                    2'd0: begin
                        reg_a <= a_in;
                        reg_b <= b_in;
                    end
                    2'd1: begin
                        if (mode == 1'b0) begin
                            reg_mul <= mul_res;
                        end else begin
                            reg_sum  <= sum_res_scaled;
                            reg_diff <= diff_res_scaled;
                        end
                    end
                    2'd2: begin
                        if (mode == 1'b0) begin
                            reg_diff <= diff_res; 
                        end else begin
                            reg_mul <= mul_res;
                        end
                    end
                    2'd3: begin
                        // Wait for next cycle
                    end
                endcase
            end
        end
    end

    // ----------------------------------------------------------------
    // Combinational Writeback Outputs (Pipeline Fix)
    // ----------------------------------------------------------------
    always @(*) begin
        // Defaults
        valid_a = 1'b0;
        valid_b = 1'b0;
        out_a   = 12'd0;
        out_b   = 12'd0;

        if (enable) begin
            if (phase == 2'd2) begin
                valid_a = 1'b1;
                if (mode == 1'b0) begin
                    out_a = sum_res;  // CT: Forward Add/Sub
                end else begin
                    out_a = reg_sum;  // GS: Inverse Add
                end
            end 
            else if (phase == 2'd3) begin
                valid_b = 1'b1;
                if (mode == 1'b0) begin
                    out_b = reg_diff; // CT: Forward Diff
                end else begin
                    out_b = reg_mul;  // GS: Inverse Mult
                end
            end
        end
    end

endmodule
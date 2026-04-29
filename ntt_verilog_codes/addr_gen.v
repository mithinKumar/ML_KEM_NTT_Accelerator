module addr_gen (
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire       mode,         // 0 = forward NTT, 1 = inverse NTT
    input  wire       advance_step, // increment once per completed butterfly

    output reg  [9:0] counter,
    output reg        active,
    output reg        done,

    output wire [2:0] stage_raw,    // Counter[9:7]
    output wire [2:0] stage_eff,    // adjusted stage used for address generation
    output wire [6:0] step_idx,     // Counter[6:0]

    output reg  [8:0] addr_a_raw,
    output reg  [8:0] addr_b_raw,
    output reg  [8:0] addr_tw_raw
);

    // ----------------------------------------------------------------
    // Counter layout from paper
    // Counter[9:7] = stage
    // Counter[6:0] = intra-stage step index
    // ----------------------------------------------------------------
    assign stage_raw = counter[9:7];
    assign step_idx  = counter[6:0];

    // Forward: i = Counter[9:7]
    // Inverse: i = (Counter[9:7] ^ 7) - 1
    wire [2:0] stage_xor;
    assign stage_xor = stage_raw ^ 3'b111;
    assign stage_eff = (mode == 1'b0) ? stage_raw : (stage_xor - 3'd1);

    // Total valid steps = 7 stages * 128 steps = 896
    localparam [9:0] LAST_COUNT = 10'd895;

    // ----------------------------------------------------------------
    // Counter / active / done control
    // ----------------------------------------------------------------
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            counter <= 0;
            active  <= 0;
            done    <= 0;
        end else begin
            if (start) begin
                counter <= 0;
                active  <= 1;
                done    <= 0;
            end else if (active) begin
                if (advance_step) begin
                    if (counter == LAST_COUNT) begin
                        active <= 0;
                        done   <= 1;
                    end else begin
                        counter <= counter + 1;
                    end
                end
            end
        end
        end
            // ----------------------------------------------------------------
    // Address generation
    // Paper-faithful raw 9-bit addresses:
    //   coeff region begins with 0...
    //   twiddle region begins with 10...
    // ----------------------------------------------------------------
    always @(*) begin
        // defaults
        addr_a_raw  = 9'd0;
        addr_b_raw  = 9'd0;
        addr_tw_raw = 9'd0;

        case (stage_eff)

            // --------------------------------------------------------
            // Stage 0 special case
            // A  = {0,0,j[6:0]}
            // B  = {0,1,j[6:0]}
            // TW = {1,0,1,0,0,0,0,0,0}
            // --------------------------------------------------------
            3'd0: begin
                addr_a_raw  = {1'b0, 1'b0, step_idx[6:0]};
                addr_b_raw  = {1'b0, 1'b1, step_idx[6:0]};
                addr_tw_raw = 9'b101000000;
            end

            // --------------------------------------------------------
            // Stage 1
            // A  = {0, j[6],    0, j[5:0]}
            // B  = {0, j[6],    1, j[5:0]}
            // TW = {1,0,j[6],      6'b100000}
            // --------------------------------------------------------
            3'd1: begin
                addr_a_raw  = {1'b0, step_idx[6],    1'b0, step_idx[5:0]};
                addr_b_raw  = {1'b0, step_idx[6],    1'b1, step_idx[5:0]};
                addr_tw_raw = {2'b10, step_idx[6],   6'b100000};
            end

            // --------------------------------------------------------
            // Stage 2
            // A  = {0, j[6:5],  0, j[4:0]}
            // B  = {0, j[6:5],  1, j[4:0]}
            // TW = {1,0,j[6:5],    5'b10000}
            // --------------------------------------------------------
            3'd2: begin
                addr_a_raw  = {1'b0, step_idx[6:5],  1'b0, step_idx[4:0]};
                addr_b_raw  = {1'b0, step_idx[6:5],  1'b1, step_idx[4:0]};
                addr_tw_raw = {2'b10, step_idx[6:5], 5'b10000};
            end

            // --------------------------------------------------------
            // Stage 3
            // A  = {0, j[6:4],  0, j[3:0]}
            // B  = {0, j[6:4],  1, j[3:0]}
            // TW = {1,0,j[6:4],    4'b1000}
            // --------------------------------------------------------
            3'd3: begin
                addr_a_raw  = {1'b0, step_idx[6:4],  1'b0, step_idx[3:0]};
                addr_b_raw  = {1'b0, step_idx[6:4],  1'b1, step_idx[3:0]};
                addr_tw_raw = {2'b10, step_idx[6:4], 4'b1000};
            end

            // --------------------------------------------------------
            // Stage 4
            // A  = {0, j[6:3],  0, j[2:0]}
            // B  = {0, j[6:3],  1, j[2:0]}
            // TW = {1,0,j[6:3],    3'b100}
            // --------------------------------------------------------
            3'd4: begin
                addr_a_raw  = {1'b0, step_idx[6:3],  1'b0, step_idx[2:0]};
                addr_b_raw  = {1'b0, step_idx[6:3],  1'b1, step_idx[2:0]};
                addr_tw_raw = {2'b10, step_idx[6:3], 3'b100};
            end

            // --------------------------------------------------------
            // Stage 5
            // A  = {0, j[6:2],  0, j[1:0]}
            // B  = {0, j[6:2],  1, j[1:0]}
            // TW = {1,0,j[6:2],    2'b10}
            // --------------------------------------------------------
            3'd5: begin
                addr_a_raw  = {1'b0, step_idx[6:2],  1'b0, step_idx[1:0]};
                addr_b_raw  = {1'b0, step_idx[6:2],  1'b1, step_idx[1:0]};
                addr_tw_raw = {2'b10, step_idx[6:2], 2'b10};
            end

            // --------------------------------------------------------
            // Stage 6
            // A  = {0, j[6:1],  0, j[0]}
            // B  = {0, j[6:1],  1, j[0]}
            // TW = {1,0,j[6:1],    1'b1}
            // --------------------------------------------------------
            3'd6: begin
                addr_a_raw  = {1'b0, step_idx[6:1],  1'b0, step_idx[0]};
                addr_b_raw  = {1'b0, step_idx[6:1],  1'b1, step_idx[0]};
                addr_tw_raw = {2'b10, step_idx[6:1], 1'b1};
            end

            default: begin
                addr_a_raw  = 9'd0;
                addr_b_raw  = 9'd0;
                addr_tw_raw = 9'd0;
            end
        endcase
    end

endmodule
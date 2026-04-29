module ntt_controller (
    input  wire       clk,
    input  wire       reset,
    input  wire       start,

    // From addr_gen
    input  wire       addr_done,

    // To butterfly / addr_gen / top-level
    output reg        busy,
    output reg        done,
    output reg        butterfly_enable,
    output reg [1:0]  phase,
    output reg        advance_step
);

    localparam IDLE = 1'b0;
    localparam RUN  = 1'b1;

    reg state;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= IDLE;
            busy             <= 1'b0;
            done             <= 1'b0;
            butterfly_enable <= 1'b0;
            phase            <= 2'd0;
            advance_step     <= 1'b0;
        end else begin
            // defaults each cycle
            advance_step <= 1'b0;

            case (state)
                IDLE: begin
                    busy             <= 1'b0;
                    butterfly_enable <= 1'b0;
                    phase            <= 2'd0;

                    if (start) begin
                        state            <= RUN;
                        busy             <= 1'b1;
                        done             <= 1'b0;
                        butterfly_enable <= 1'b1;
                        phase            <= 2'd0;
                    end
                end

                RUN: begin
                    busy             <= 1'b1;
                    butterfly_enable <= 1'b1;

                    if (addr_done) begin
                        state            <= IDLE;
                        busy             <= 1'b0;
                        done             <= 1'b1;
                        butterfly_enable <= 1'b0;
                        phase            <= 2'd0;
                    end else begin
                        case (phase)
                            2'd0: begin
                                phase <= 2'd1;
                            end

                            2'd1: begin
                                phase <= 2'd2;
                            end

                            2'd2: begin
                                phase <= 2'd3;
                                advance_step <= 1'b1; // <-- MOVED HERE to fix pipeline slip
                            end

                            2'd3: begin
                                phase        <= 2'd0;
                                advance_step <= 1'b0; // <-- ADDED HERE
                            end

                            default: begin
                                phase <= 2'd0;
                            end
                        endcase
                    end
                end

                default: begin
                    state            <= IDLE;
                    busy             <= 1'b0;
                    done             <= 1'b0;
                    butterfly_enable <= 1'b0;
                    phase            <= 2'd0;
                    advance_step     <= 1'b0;
                end
            endcase
        end
    end

endmodule
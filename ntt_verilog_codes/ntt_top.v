module ntt_top (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        mode,        // 0 = forward NTT, 1 = inverse NTT (hook kept for later)

    // Optional external coefficient write port (for loading input polynomial)
    input  wire        ext_coeff_we,
    input  wire [7:0]  ext_coeff_waddr,
    input  wire [11:0] ext_coeff_wdata,

    // Optional coefficient read port (for reading final outputs)
    input  wire [7:0]  ext_coeff_raddr,
    output wire [11:0] ext_coeff_rdata,

    output wire        busy,
    output wire        done
);

    wire        butterfly_enable;
    wire [1:0]  phase;
    wire        advance_step;
    wire        addr_done;

    wire [9:0] counter;
    wire       addr_active;
    wire [2:0] stage_raw;
    wire [2:0] stage_eff;
    wire [6:0] step_idx;

    wire [8:0] addr_a_raw;
    wire [8:0] addr_b_raw;
    wire [8:0] addr_tw_raw;

    wire [7:0] coeff_addr_a;
    wire [7:0] coeff_addr_b;
    wire [6:0] tw_addr;

    assign coeff_addr_a = addr_a_raw[7:0];
    assign coeff_addr_b = addr_b_raw[7:0];
    assign tw_addr      = addr_tw_raw[6:0];

    wire [11:0] coeff_rd_a;
    wire [11:0] coeff_rd_b;
    wire [11:0] tw_data;

    wire [11:0] bf_out_a;
    wire [11:0] bf_out_b;
    wire        bf_valid_a;
    wire        bf_valid_b;

    wire        core_wr_en;
    wire [7:0]  core_wr_addr;
    wire [11:0] core_wr_data;

    wire        coeff_wr_en;
    wire [7:0]  coeff_wr_addr;
    wire [11:0] coeff_wr_data;

    assign coeff_wr_en   = ext_coeff_we ? 1'b1           : core_wr_en;
    assign coeff_wr_addr = ext_coeff_we ? ext_coeff_waddr : core_wr_addr;
    assign coeff_wr_data = ext_coeff_we ? ext_coeff_wdata : core_wr_data;

    // --- Edge Detection for AXI-Lite Start ---
    reg start_reg;
    always @(posedge clk or posedge reset) begin
        if (reset) start_reg <= 1'b0;
        else start_reg <= start;
    end
    wire start_pulse = start && !start_reg;

    ntt_controller u_ntt_controller (
        .clk(clk),
        .reset(reset),
        .start(start_pulse),
        .addr_done(addr_done),
        .busy(busy),
        .done(done),
        .butterfly_enable(butterfly_enable),
        .phase(phase),
        .advance_step(advance_step)
    );

    addr_gen u_addr_gen (
        .clk(clk),
        .reset(reset),
        .start(start_pulse),
        .mode(mode),
        .advance_step(advance_step),
        .counter(counter),
        .active(addr_active),
        .done(addr_done),
        .stage_raw(stage_raw),
        .stage_eff(stage_eff),
        .step_idx(step_idx),
        .addr_a_raw(addr_a_raw),
        .addr_b_raw(addr_b_raw),
        .addr_tw_raw(addr_tw_raw)
    );

    coeff_mem u_coeff_mem (
        .clk(clk),
        .addr_a(coeff_addr_a),
        .rd_data_a(coeff_rd_a),
        .addr_b(coeff_addr_b),
        .rd_data_b(coeff_rd_b),
        .addr_ext(ext_coeff_raddr),
        .rd_data_ext(ext_coeff_rdata),
        .wr_en(coeff_wr_en),
        .wr_addr(coeff_wr_addr),
        .wr_data(coeff_wr_data)
    );

    twiddle_mem u_twiddle_mem (
        .mode(mode),            // <-- ADD THIS LINE
        .addr_tw(tw_addr),
        .tw_data(tw_data)
    );

    butterfly_core u_butterfly_core (
        .clk(clk),
        .reset(reset),
        .enable(butterfly_enable),
        .mode(mode),            // <-- ADD THIS LINE
        .phase(phase),
        .a_in(coeff_rd_a),
        .b_in(coeff_rd_b),
        .tw_in(tw_data),
        .out_a(bf_out_a),
        .out_b(bf_out_b),
        .valid_a(bf_valid_a),
        .valid_b(bf_valid_b)
    );

    writeback_mux u_writeback_mux (
        .addr_a(coeff_addr_a),
        .addr_b(coeff_addr_b),
        .out_a(bf_out_a),
        .out_b(bf_out_b),
        .valid_a(bf_valid_a),
        .valid_b(bf_valid_b),
        .wr_en(core_wr_en),
        .wr_addr(core_wr_addr),
        .wr_data(core_wr_data)
    );

endmodule
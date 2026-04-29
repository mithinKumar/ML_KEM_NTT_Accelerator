`timescale 1ns / 1ps

module ntt_ctrl_parser (
    // Inputs from AXI-Lite MMIO registers
    input  wire [31:0] slv_reg4_out,
    input  wire [31:0] slv_reg5_out,
    
    // Output back to AXI-Lite MMIO register
    output wire [31:0] usr_reg6_in,
    
    // Parsed control signals to/from NTT hardware
    output wire        mode,
    output wire        start,
    input  wire        ready
);

    // Parse specific bits from the 32-bit registers
    assign mode  = slv_reg4_out[0];
    assign start = slv_reg5_out[0];
    
    // Zero-pad the ready signal to 32 bits for the readback register
    assign usr_reg6_in = {31'b0, ready};

endmodule

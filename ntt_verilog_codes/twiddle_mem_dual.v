module twiddle_mem (
    input  wire        mode,      // 0 = Forward, 1 = Inverse
    input  wire [6:0]  addr_tw,
    output wire [11:0] tw_data
);
    // 256 x 12 memory (0-127 for forward, 128-255 for inverse)
    reg [11:0] mem [0:255];
    
    wire [7:0] actual_addr;
    // If mode is 1, add 128 to the address to read from the inverse bank
    assign actual_addr = (mode == 1'b1) ? ({1'b1, addr_tw}) : ({1'b0, addr_tw});

    assign tw_data = mem[actual_addr];

    initial begin
        // Ensure this hex file has 256 entries now
        $readmemh("D:/download/downloads/embedded_sys_project/vivado/ntt_verilog_codes/twiddle_mem_dual_new.hex", mem);//append the inverse twiddles to the end of the hex file
    end
endmodule
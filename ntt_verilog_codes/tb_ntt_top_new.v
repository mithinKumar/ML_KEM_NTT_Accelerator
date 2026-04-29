`timescale 1ns / 1ps

module tb_ntt_top_new();

    // System Signals
    reg clk;
    reg reset;
    reg start;
    reg mode;
    
    // External write/read ports (tied to zero)
    reg        ext_coeff_we = 0;
    reg [7:0]  ext_coeff_waddr = 0;
    reg [11:0] ext_coeff_wdata = 0;
    reg [7:0]  ext_coeff_raddr = 0;
    wire [11:0] ext_coeff_rdata;
    
    wire busy;
    wire done;

    // Instantiate the Unit Under Test (UUT)
    ntt_top uut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .mode(mode),
        .ext_coeff_we(ext_coeff_we),
        .ext_coeff_waddr(ext_coeff_waddr),
        .ext_coeff_wdata(ext_coeff_wdata),
        .ext_coeff_raddr(ext_coeff_raddr),
        .ext_coeff_rdata(ext_coeff_rdata),
        .busy(busy),
        .done(done)
    );

    // Clock generation (100 MHz)
    always #5 clk = ~clk;

    // Memory array to hold the expected "Golden" results
    reg [11:0] expected_mem [0:255];
    integer total_tests;
    integer passed_tests;
    
    parameter Q = 3329;
    parameter SCALE_FACTOR = 3303; // 128^-1 mod 3329

    // ----------------------------------------------------------------
    // VERIFICATION TASK: Run and Check
    // ----------------------------------------------------------------
    // This task executes a single test case, compares memory, and flags errors.
    task run_test_case;
        input integer test_num;
        input reg test_mode; // 0 = Forward, 1 = Inverse
        integer i;
        integer errors;
        integer hw_val;
        integer scaled_val;
        begin
            errors = 0;

            if (expected_mem[0] === 12'bx || uut.u_coeff_mem.mem[0] === 12'bx) begin
                $display("FATAL ERROR: .hex files failed to load for Test Case %0d!", test_num);
                $display("Check if the files exist in the same directory as the simulation.");
                $finish;
            end
            
            // 1. Trigger the NTT Accelerator
            @(posedge clk);
            start = 1;
            mode  = test_mode; 
            @(posedge clk);
            start = 0;

            // 2. Wait for completion
            wait (done == 1'b1);
            @(posedge clk);

            // 3. Compare RTL memory against Expected memory
            for (i = 0; i < 256; i = i + 1) begin
                if (uut.u_coeff_mem.mem[i] === 12'bx) begin
                    errors = errors + 1;
                    $display("   -> ERROR at addr %0d: RTL generated 'X' (Unknown)", i);
                end
                else begin
                    hw_val = uut.u_coeff_mem.mem[i];
                    
                    if (hw_val !== expected_mem[i]) begin
                        errors = errors + 1;
                        if (errors <= 5) begin
                            $display("   -> ERROR at addr %0d: Expected %03x, Got %03x", 
                                     i, expected_mem[i], hw_val);
                        end
                    end
                end
            end

            // 4. Pass/Fail Reporting
            if (errors == 0) begin
                $display("[PASS] Test Case %0d completed successfully.", test_num);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] Test Case %0d failed with %0d mismatched coefficients.", test_num, errors);
            end
            
            total_tests = total_tests + 1;
            #50; // Pause between tests
        end
    endtask

    // ----------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // ----------------------------------------------------------------
    initial begin
        // Initialize
        clk = 0;
        reset = 1;
        start = 0;
        mode = 0;
        total_tests = 0;
        passed_tests = 0;

        #100;
        reset = 0;
        #20;
        
        $display("==================================================");
        $display("       STARTING NEW NTT ACCELERATOR VERIFICATION  ");
        $display("==================================================");

        // -----------------------------------------------------------
        // TEST CASE 1: Forward NTT
        // -----------------------------------------------------------
        $readmemh("D:/download/downloads/embedded_sys_project/vivado/ntt_verilog_codes/tc1_input_new.hex", uut.u_coeff_mem.mem);
        $readmemh("D:/download/downloads/embedded_sys_project/vivado/ntt_verilog_codes/tc1_expected_new.hex", expected_mem);
        
        $display("Running Test Case 1...");
        run_test_case(1, 0);
        
        // -----------------------------------------------------------
        // TEST CASE 2: Inverse NTT
        // -----------------------------------------------------------
        $readmemh("D:/download/downloads/embedded_sys_project/vivado/ntt_verilog_codes/tc2_input_new.hex", uut.u_coeff_mem.mem);
        $readmemh("D:/download/downloads/embedded_sys_project/vivado/ntt_verilog_codes/tc2_expected_new.hex", expected_mem);
        
        $display("Running Test Case 2...");
        run_test_case(2, 1);
        
        // -----------------------------------------------------------
        // TEST CASE 3: Edge Case (All Zeros)
        // -----------------------------------------------------------
        $readmemh("D:/download/downloads/embedded_sys_project/vivado/ntt_verilog_codes/tc3_zeros_input_new.hex", uut.u_coeff_mem.mem);
        $readmemh("D:/download/downloads/embedded_sys_project/vivado/ntt_verilog_codes/tc3_zeros_expected_new.hex", expected_mem);
        
        $display("Running Test Case 3...");
        run_test_case(3, 0);
        
        // -----------------------------------------------------------
        // FINAL SUMMARY
        // -----------------------------------------------------------
        $display("==================================================");
        $display("VERIFICATION COMPLETE: %0d / %0d TESTS PASSED", passed_tests, total_tests);
        $display("==================================================");
        
        if (passed_tests == total_tests)
            $display("ALL CLEAR - RTL matches Golden Model.");
        else
            $display("FAILED - Review waveforms and error logs.");

        #100;
        $finish;
    end

    // Optional: Dump waveforms
    initial begin
        $dumpfile("ntt_waves_new.vcd");
        $dumpvars(0, tb_ntt_top_new);
    end

endmodule

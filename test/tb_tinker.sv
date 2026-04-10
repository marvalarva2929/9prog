`timescale 1ns/1ps

// iverilog -g2012 -o ../vvp/tb_tinker.vvp tb_tinker.sv ../tinker.sv
// vvp ../vvp/tb_tinker.vvp

module tb_tinker;

    reg  clk;
    reg  reset;
    wire hlt;

    tinker_core dut (.clk(clk), .reset(reset), .hlt(hlt));

    initial clk = 0;
    always #5 clk = ~clk;

    task write_instr;
        input [63:0] addr;
        input [31:0] instr;
        begin
            dut.memory.bytes[addr]   = instr[7:0];
            dut.memory.bytes[addr+1] = instr[15:8];
            dut.memory.bytes[addr+2] = instr[23:16];
            dut.memory.bytes[addr+3] = instr[31:24];
        end
    endtask

    task write_mem64;
        input [63:0] addr;
        input [63:0] val;
        begin
            dut.memory.bytes[addr]   = val[7:0];
            dut.memory.bytes[addr+1] = val[15:8];
            dut.memory.bytes[addr+2] = val[23:16];
            dut.memory.bytes[addr+3] = val[31:24];
            dut.memory.bytes[addr+4] = val[39:32];
            dut.memory.bytes[addr+5] = val[47:40];
            dut.memory.bytes[addr+6] = val[55:48];
            dut.memory.bytes[addr+7] = val[63:56];
        end
    endtask

    localparam OP_ADD    = 5'h18;
    localparam OP_ADDI   = 5'h19;
    localparam OP_SUB    = 5'h1A;
    localparam OP_AND    = 5'h00;
    localparam OP_OR     = 5'h01;
    localparam OP_XOR    = 5'h02;
    localparam OP_SHFTLI = 5'h07;
    localparam OP_MOV    = 5'h10;
    localparam OP_MOV2   = 5'h12;
    localparam OP_MOV3   = 5'h13;
    localparam OP_SUBI   = 5'h1B;
    localparam OP_BRNZ   = 5'h0B;
    localparam OP_CALL   = 5'h0C;
    localparam OP_RETURN = 5'h0D;
    localparam OP_PRIV   = 5'h0F;

    initial begin
        $dumpfile("../sim/tb_tinker.vcd");
        $dumpvars(0, tb_tinker);
    end

    // test add and basic alu
    task test_alu;
        integer i;
        begin
            $display("=== Test: ALU ===");
            for (i = 0; i < 64; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            write_instr(64'h2000, {OP_MOV2,  5'd1, 5'd0, 5'd0, 12'd100});
            write_instr(64'h2004, {OP_MOV2,  5'd2, 5'd0, 5'd0, 12'd30});
            write_instr(64'h2008, {OP_ADD,   5'd3, 5'd1, 5'd2, 12'd0});
            write_instr(64'h200C, {OP_SUB,   5'd4, 5'd1, 5'd2, 12'd0});
            write_instr(64'h2010, {OP_AND,   5'd5, 5'd1, 5'd2, 12'd0});
            write_instr(64'h2014, {OP_OR,    5'd6, 5'd1, 5'd2, 12'd0});
            write_instr(64'h2018, {OP_XOR,   5'd7, 5'd1, 5'd2, 12'd0});
            write_instr(64'h201C, {OP_PRIV,  27'b0});

            reset = 1; @(posedge clk); @(posedge clk); reset = 0;
            for (i = 0; i < 300 && !hlt; i = i + 1) @(posedge clk);

            if (!hlt) $display("  FAIL: no halt");
            else begin
                $display("  ADD r3=%0d %s", dut.reg_file.registers[3],
                    dut.reg_file.registers[3]===64'd130 ? "PASS":"FAIL");
                $display("  SUB r4=%0d %s", dut.reg_file.registers[4],
                    dut.reg_file.registers[4]===64'd70 ? "PASS":"FAIL");
                $display("  AND r5=%0d %s", dut.reg_file.registers[5],
                    dut.reg_file.registers[5]===(64'd100&64'd30) ? "PASS":"FAIL");
                $display("  OR  r6=%0d %s", dut.reg_file.registers[6],
                    dut.reg_file.registers[6]===(64'd100|64'd30) ? "PASS":"FAIL");
                $display("  XOR r7=%0d %s", dut.reg_file.registers[7],
                    dut.reg_file.registers[7]===(64'd100^64'd30) ? "PASS":"FAIL");
            end
        end
    endtask

    // test load and store
    task test_mem;
        integer i;
        begin
            $display("=== Test: Load/Store ===");
            for (i = 0; i < 64; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            write_mem64(64'h3000, 64'hDEADBEEFCAFEF00D);

            write_instr(64'h2000, {OP_PRIV, 27'b0}); // placeholder, overwritten below
            // build r1 = 0x3000: MOV2 r1,3; SHFTLI r1,12
            write_instr(64'h2000, {OP_MOV2,  5'd1, 5'd0, 5'd0, 12'd3});
            write_instr(64'h2004, {OP_SHFTLI,5'd1, 5'd0, 5'd0, 12'd12});
            // r2 = mem[r1+0]
            write_instr(64'h2008, {OP_MOV,   5'd2, 5'd1, 5'd0, 12'd0});
            // mem[r1+8] = r2
            write_instr(64'h200C, {OP_MOV3,  5'd1, 5'd2, 5'd0, 12'd8});
            // r3 = mem[r1+8]
            write_instr(64'h2010, {OP_MOV,   5'd3, 5'd1, 5'd0, 12'd8});
            write_instr(64'h2014, {OP_PRIV,  27'b0});

            reset = 1; @(posedge clk); @(posedge clk); reset = 0;
            for (i = 0; i < 300 && !hlt; i = i + 1) @(posedge clk);

            if (!hlt) $display("  FAIL: no halt");
            else if (dut.reg_file.registers[3] === 64'hDEADBEEFCAFEF00D)
                $display("  PASS: r3=0x%h", dut.reg_file.registers[3]);
            else
                $display("  FAIL: r3=0x%h", dut.reg_file.registers[3]);
        end
    endtask

    // test BRNZ loop: count down from 5
    task test_branch;
        integer i;
        begin
            $display("=== Test: BRNZ loop ===");
            for (i = 0; i < 128; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            // r1=5, r2=0
            write_instr(64'h2000, {OP_MOV2,  5'd1, 5'd0, 5'd0, 12'd5});
            write_instr(64'h2004, {OP_MOV2,  5'd2, 5'd0, 5'd0, 12'd0});
            // build r5 = 0x2014 (loop top) in r5: MOV2 r5,2; SHFTLI r5,12; ADDI r5,20
            write_instr(64'h2008, {OP_MOV2,  5'd5, 5'd0, 5'd0, 12'd2});
            write_instr(64'h200C, {OP_SHFTLI,5'd5, 5'd0, 5'd0, 12'd12});
            write_instr(64'h2010, {OP_ADDI,  5'd5, 5'd0, 5'd0, 12'd20});
            // loop top at 0x2014: r2++, r1--, BRNZ r5,r1
            write_instr(64'h2014, {OP_ADDI,  5'd2, 5'd0, 5'd0, 12'd1});
            write_instr(64'h2018, {OP_SUBI,  5'd1, 5'd0, 5'd0, 12'd1});
            write_instr(64'h201C, {OP_BRNZ,  5'd5, 5'd1, 5'd0, 12'd0});
            write_instr(64'h2020, {OP_PRIV,  27'b0});

            reset = 1; @(posedge clk); @(posedge clk); reset = 0;
            for (i = 0; i < 500 && !hlt; i = i + 1) @(posedge clk);

            if (!hlt) $display("  FAIL: no halt");
            else if (dut.reg_file.registers[2]===64'd5 && dut.reg_file.registers[1]===64'd0)
                $display("  PASS: r2=%0d r1=%0d", dut.reg_file.registers[2], dut.reg_file.registers[1]);
            else
                $display("  FAIL: r2=%0d r1=%0d", dut.reg_file.registers[2], dut.reg_file.registers[1]);
        end
    endtask

    // test call and return
    task test_call_ret;
        integer i;
        begin
            $display("=== Test: CALL/RETURN ===");
            for (i = 0; i < 256; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            // build r6 = 0x2040 (function address): MOV2 r6,2; SHFTLI r6,12; ADDI r6,64
            write_instr(64'h2000, {OP_MOV2,  5'd6, 5'd0, 5'd0, 12'd2});
            write_instr(64'h2004, {OP_SHFTLI,5'd6, 5'd0, 5'd0, 12'd12});
            write_instr(64'h2008, {OP_ADDI,  5'd6, 5'd0, 5'd0, 12'd64});
            write_instr(64'h200C, {OP_CALL,  5'd6, 5'd0, 5'd0, 12'd0});
            write_instr(64'h2010, {OP_MOV2,  5'd3, 5'd0, 5'd0, 12'h099});
            write_instr(64'h2014, {OP_PRIV,  27'b0});

            // function at 0x2040
            write_instr(64'h2040, {OP_MOV2,  5'd2, 5'd0, 5'd0, 12'd7});
            write_instr(64'h2044, {5'h0D,    27'b0}); // RETURN

            reset = 1; @(posedge clk); @(posedge clk); reset = 0;
            for (i = 0; i < 500 && !hlt; i = i + 1) @(posedge clk);

            if (!hlt) $display("  FAIL: no halt");
            else begin
                $display("  r2=%0d %s", dut.reg_file.registers[2],
                    dut.reg_file.registers[2]===64'd7 ? "PASS":"FAIL");
                $display("  r3=0x%h %s", dut.reg_file.registers[3],
                    dut.reg_file.registers[3]===64'h99 ? "PASS":"FAIL");
            end
        end
    endtask

    initial begin
        $display("===== tinker_core testbench =====");
        reset = 1;
        repeat(4) @(posedge clk);
        reset = 0;

        test_alu;
        test_mem;
        test_branch;
        test_call_ret;

        $display("===== done =====");
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

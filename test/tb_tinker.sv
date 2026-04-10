`timescale 1ns/1ps

// ============================================================
// Testbench for multi-cycle tinker_core
// ============================================================
// Build & run:
//   iverilog -g2012 -o ../vvp/tb_tinker.vvp tb_tinker.sv ../tinker.sv
//   vvp ../vvp/tb_tinker.vvp
//   gtkwave ../sim/tb_tinker.vcd   (optional waveform)
// ============================================================

module tb_tinker;

    reg  clk;
    reg  reset;
    wire hlt;

    // Instantiate DUT
    tinker_core dut (
        .clk  (clk),
        .reset(reset),
        .hlt  (hlt)
    );

    // 10 ns clock period
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Helper task: write a 32-bit instruction into memory ----
    // Memory is byte-addressed, little-endian, starting at PC_START = 0x2000
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

    // ---- Helper task: write a 64-bit value into memory ----
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

    // ---- Instruction encoding helpers ----
    // instr[31:27]=opcode, [26:22]=rd, [21:17]=rs, [16:12]=rt, [11:0]=imm12
    function [31:0] enc_r;
        input [4:0] op, rd, rs, rt;
        enc_r = {op, rd, rs, rt, 12'b0};
    endfunction

    function [31:0] enc_i;
        input [4:0] op, rd, rs;
        input [11:0] imm;
        enc_i = {op, rd, rs, 5'b0, imm};
    endfunction

    function [31:0] enc_priv;
        input [11:0] L;
        enc_priv = {5'h0F, 27'b0} | {27'b0, L[11:0]};  // priv: opcode=0x0F
    endfunction

    // Opcode constants (must match tinker.sv defines)
    localparam OP_ADD    = 5'h18;
    localparam OP_ADDI   = 5'h19;
    localparam OP_SUB    = 5'h1A;
    localparam OP_MUL    = 5'h1C;
    localparam OP_AND    = 5'h00;
    localparam OP_OR     = 5'h01;
    localparam OP_XOR    = 5'h02;
    localparam OP_NOT    = 5'h03;
    localparam OP_SHFTL  = 5'h06;
    localparam OP_SHFTLI = 5'h07;
    localparam OP_MOV    = 5'h10;
    localparam OP_MOV1   = 5'h11;
    localparam OP_MOV2   = 5'h12;
    localparam OP_MOV3   = 5'h13;
    localparam OP_BR     = 5'h08;
    localparam OP_BRR2   = 5'h0A;
    localparam OP_BRNZ   = 5'h0B;
    localparam OP_CALL   = 5'h0C;
    localparam OP_RETURN = 5'h0D;
    localparam OP_BRGT   = 5'h0E;
    localparam OP_PRIV   = 5'h0F;

    // Waveform dump
    initial begin
        $dumpfile("../sim/tb_tinker.vcd");
        $dumpvars(0, tb_tinker);
    end

    // ============================================================
    // Test 1: ADD instruction
    //   r1 = 10, r2 = 20 (via MOV2), ADD r3, r1, r2 → r3 == 30
    //   Then HALT
    // ============================================================
    task test_add;
        integer i;
        begin
            $display("=== Test: ADD ===");
            // Clear memory region
            for (i = 0; i < 64; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            // MOV2 r1, 10  → r1[11:0] = 10
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd1, 5'd0, 12'd10));
            // MOV2 r2, 20  → r2[11:0] = 20
            write_instr(64'h2004, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd20));
            // ADD r3, r1, r2
            write_instr(64'h2008, enc_r(OP_ADD, 5'd3, 5'd1, 5'd2));
            // PRIV 0 (halt)
            write_instr(64'h200C, {OP_PRIV, 27'b0});

            // Reset
            reset = 1; @(posedge clk); @(posedge clk);
            reset = 0;

            // Run until halt or timeout
            for (i = 0; i < 200 && !hlt; i = i + 1)
                @(posedge clk);

            if (!hlt)
                $display("  FAIL: did not halt");
            else if (dut.reg_file.registers[3] === 64'd30)
                $display("  PASS: r3 = %0d", dut.reg_file.registers[3]);
            else
                $display("  FAIL: r3 = %0d (expected 30)", dut.reg_file.registers[3]);
        end
    endtask

    // ============================================================
    // Test 2: Load and Store (MOV)
    //   Store 0xDEADBEEF at address 0x3000, then load it back
    // ============================================================
    task test_load_store;
        integer i;
        begin
            $display("=== Test: Load/Store ===");
            for (i = 0; i < 128; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            // Pre-load a 64-bit value at 0x3000
            write_mem64(64'h3000, 64'hDEADBEEF_CAFEF00D);

            // MOV2 r1, 0 → r1 = 0 (base)
            // We need r1 = 0x3000. Use ADDI:
            // First: MOV2 r1, 0x000 ; SHFTLI r1, 12 ; MOV2 r1, 0x3 ; etc.
            // Easier approach: pre-set r1 via direct register write in testbench
            // (cheat for test harness)
            dut.reg_file.registers[1] = 64'h3000;
            dut.reg_file.registers[2] = 64'h0;

            // MOV r2, (r1)(0)  → r2 = mem[r1+0]
            write_instr(64'h2000, enc_i(OP_MOV, 5'd2, 5'd1, 12'd0));
            // MOV3 (r1)(8), r2  → mem[r1+8] = r2
            write_instr(64'h2004, enc_i(OP_MOV3, 5'd1, 5'd2, 12'd8));
            // MOV r3, (r1)(8)  → r3 = mem[r1+8]
            write_instr(64'h2008, enc_i(OP_MOV, 5'd3, 5'd1, 12'd8));
            // HALT
            write_instr(64'h200C, {OP_PRIV, 27'b0});

            reset = 1; @(posedge clk); @(posedge clk);
            reset = 0;
            // Restore registers after reset (reset zeros them)
            @(posedge clk);  // let reset take effect
            dut.reg_file.registers[1] = 64'h3000;

            for (i = 0; i < 200 && !hlt; i = i + 1)
                @(posedge clk);

            if (!hlt)
                $display("  FAIL: did not halt");
            else if (dut.reg_file.registers[3] === 64'hDEADBEEF_CAFEF00D)
                $display("  PASS: r3 = 0x%h", dut.reg_file.registers[3]);
            else
                $display("  FAIL: r3 = 0x%h (expected 0xDEADBEEFCAFEF00D)",
                         dut.reg_file.registers[3]);
        end
    endtask

    // ============================================================
    // Test 3: Branch (BRNZ) — simple loop counting down
    //   r1 = 5, loop: r1 -= 1, if r1 != 0 branch back, then halt
    //   r2 counts loop iterations
    // ============================================================
    task test_branch;
        integer i;
        begin
            $display("=== Test: BRNZ branch (loop) ===");
            for (i = 0; i < 64; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            //  0x2000: MOV2 r1, 5       — r1 = 5
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd1, 5'd0, 12'd5));
            //  0x2004: MOV2 r2, 0       — r2 = 0 (iteration counter)
            write_instr(64'h2004, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd0));
            //  0x2008: ADDI r2, 1       — r2++ (loop body)
            write_instr(64'h2008, enc_i(OP_ADDI, 5'd2, 5'd0, 12'd1));
            //  0x200C: SUBI r1, 1       — r1--
            write_instr(64'h200C, {OP_SUB+5'h1, 5'd1, 5'd0, 5'd0, 12'd1}); // SUBI
            //  0x2010: MOV2 r4, 0       — r4 = 0x2008 (loop top address)
            //          We need r4 = 0x2008. Hard to do without SHFTLI, use BRR2 instead.
            //  Simpler: use BRR2 (pc-relative branch)
            //  At 0x2010 (PC=0x2010 when fetched): BRR2 with offset -8 goes to 0x2008
            write_instr(64'h2010, {5'h0A, 27'b0} | (12'hFF8)); // BRR2 -8 (offset=-8 = 0xFF8)
            //  0x2014: BRNZ r4, r1 — if r1 != 0, branch (but we used BRR2 above already)
            // Actually let me restructure: use SUBI then BRNZ

            // Redo with cleaner layout:
            // 0x2000: MOV2 r1, 5
            // 0x2004: ADDI r2, 1   (loop top)
            // 0x2008: SUBI r1, 1
            // 0x200C: MOV2 r4, 0 ... hmm still need address in register for BRNZ

            // Use BRR2 offset approach:
            // at 0x200C: BRR2 with signed imm = -8 → pc = 0x200C + (-8) = 0x2004
            for (i = 0; i < 64; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            //  0x2000: MOV2 r1, 5
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd1, 5'd0, 12'd5));
            //  0x2004: MOV2 r2, 0
            write_instr(64'h2004, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd0));
            //  0x2008: ADDI r2, 1  (loop top: r2++)
            write_instr(64'h2008, enc_i(OP_ADDI, 5'd2, 5'd0, 12'd1));
            //  0x200C: SUBI r1, 1  (r1--)
            write_instr(64'h200C, {5'h1B, 5'd1, 5'd0, 5'd0, 12'd1}); // OP_SUBI=0x1B
            //  0x2010: BRR2 -8     (if taken: pc = 0x2010 + sext(-8) = 0x2008)
            //          But BRR2 is unconditional! Need BRNZ.
            // Use BRNZ rd, rs: if r[rs]!=0 then pc=r[rd]
            // Store loop address 0x2008 in r5 first, then BRNZ r5, r1
            // Better: reorganize

            for (i = 0; i < 128; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            // r5 will hold address 0x2008 (loop top)
            // Use MOV2 + SHFTLI to build address
            //  0x2000: MOV2 r1, 5
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd1, 5'd0, 12'd5));
            //  0x2004: MOV2 r2, 0
            write_instr(64'h2004, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd0));
            //  0x2008: ADDI r2, 1  ← loop top
            write_instr(64'h2008, enc_i(OP_ADDI, 5'd2, 5'd0, 12'd1));
            //  0x200C: SUBI r1, 1
            write_instr(64'h200C, {5'h1B, 5'd1, 5'd0, 5'd0, 12'd1});
            //  0x2010: BRR2 sext(imm=-8) → pc = 0x2010 + (-8) = 0x2008  (unconditional)
            //          We want conditional. Use a different structure:
            //          BRNZ needs r[rd] = target address. Pre-load it.
            //  Actually let's just put halt check inline:
            //  0x2010: BRNZ r5, r1   — r5=loop_top=0x2008; if r1!=0 goto r5
            //          We need r5=0x2008. Load it before the loop.

            for (i = 0; i < 128; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            // Build 0x2008 in r5: MOV2 r5, 8; SHFTLI r5, 13 → 0x1000; OR with more...
            // Simpler: use the fact that 0x2008 = 8200 decimal
            // MOV2 sets lower 12 bits. SHFTLI shifts left by imm.
            // r5 = 0x2008:
            //   MOV2 r5, 2     → r5 = 0x002
            //   SHFTLI r5, 12  → r5 = 0x2000
            //   ADDI r5, 8     → r5 = 0x2008

            //  0x2000: MOV2 r5, 2
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd5, 5'd0, 12'd2));
            //  0x2004: SHFTLI r5, 12
            write_instr(64'h2004, {5'h07, 5'd5, 5'd0, 5'd0, 12'd12}); // OP_SHFTLI=0x07
            //  0x2008: ADDI r5, 8
            write_instr(64'h2008, enc_i(OP_ADDI, 5'd5, 5'd0, 12'd8));
            //  0x200C: MOV2 r1, 5    → r1 = 5 (loop counter)
            write_instr(64'h200C, enc_i(OP_MOV2, 5'd1, 5'd0, 12'd5));
            //  0x2010: MOV2 r2, 0    → r2 = 0 (iteration counter)
            write_instr(64'h2010, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd0));
            //  0x2014: ADDI r2, 1    ← loop top (r5 = 0x2014 needed)
            //   Oops, loop top moved. Let me just fix r5 = 0x2014:
            //   r5 = 0x2014 = 8212 = 0x2000 + 0x14
            //   MOV2 r5, 2; SHFTLI r5, 12 → 0x2000; ADDI r5, 0x14=20

            for (i = 0; i < 128; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            //  0x2000: MOV2 r1, 5
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd1, 5'd0, 12'd5));
            //  0x2004: MOV2 r2, 0
            write_instr(64'h2004, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd0));
            //  0x2008: MOV2 r5, 2
            write_instr(64'h2008, enc_i(OP_MOV2, 5'd5, 5'd0, 12'd2));
            //  0x200C: SHFTLI r5, 12  → r5 = 0x2000
            write_instr(64'h200C, {5'h07, 5'd5, 5'd0, 5'd0, 12'd12});
            //  0x2010: ADDI r5, 20    → r5 = 0x2014 (loop top)
            write_instr(64'h2010, enc_i(OP_ADDI, 5'd5, 5'd0, 12'd20));
            //  0x2014: ADDI r2, 1     ← loop top: r2++
            write_instr(64'h2014, enc_i(OP_ADDI, 5'd2, 5'd0, 12'd1));
            //  0x2018: SUBI r1, 1     → r1--
            write_instr(64'h2018, {5'h1B, 5'd1, 5'd0, 5'd0, 12'd1});
            //  0x201C: BRNZ r5, r1    → if r1!=0: pc = r5 = 0x2014
            write_instr(64'h201C, {5'h0B, 5'd5, 5'd1, 5'd0, 12'd0}); // BRNZ rd=r5, rs=r1
            //  0x2020: HALT
            write_instr(64'h2020, {OP_PRIV, 27'b0});

            reset = 1; @(posedge clk); @(posedge clk);
            reset = 0;

            for (i = 0; i < 500 && !hlt; i = i + 1)
                @(posedge clk);

            if (!hlt)
                $display("  FAIL: did not halt");
            else if (dut.reg_file.registers[2] === 64'd5 &&
                     dut.reg_file.registers[1] === 64'd0)
                $display("  PASS: loop ran 5 times, r2=%0d, r1=%0d",
                         dut.reg_file.registers[2], dut.reg_file.registers[1]);
            else
                $display("  FAIL: r2=%0d (expected 5), r1=%0d (expected 0)",
                         dut.reg_file.registers[2], dut.reg_file.registers[1]);
        end
    endtask

    // ============================================================
    // Test 4: CALL and RETURN
    // ============================================================
    task test_call_return;
        integer i;
        begin
            $display("=== Test: CALL/RETURN ===");
            for (i = 0; i < 256; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            // Main at 0x2000:
            //   MOV2 r1, 0x42        — r1 = marker before call
            //   MOV2 r6, (addr of func)
            //   ... (build address in r6)
            //   CALL r6              — call function
            //   MOV2 r3, 0x99        — should execute after return
            //   HALT

            // Function at 0x2040:
            //   ADDI r2, 7           — r2 = 7
            //   RETURN

            // Build func address 0x2040 in r6:
            //   MOV2 r6, 2; SHFTLI r6,12 → 0x2000; ADDI r6, 0x40=64

            //  0x2000: MOV2 r1, 0x42
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd1, 5'd0, 12'h042));
            //  0x2004: MOV2 r6, 2
            write_instr(64'h2004, enc_i(OP_MOV2, 5'd6, 5'd0, 12'd2));
            //  0x2008: SHFTLI r6, 12
            write_instr(64'h2008, {5'h07, 5'd6, 5'd0, 5'd0, 12'd12});
            //  0x200C: ADDI r6, 64  → r6 = 0x2040
            write_instr(64'h200C, enc_i(OP_ADDI, 5'd6, 5'd0, 12'd64));
            //  0x2010: CALL r6
            write_instr(64'h2010, {5'h0C, 5'd6, 5'd0, 5'd0, 12'd0});
            //  0x2014: MOV2 r3, 0x99  (should execute after return)
            write_instr(64'h2014, enc_i(OP_MOV2, 5'd3, 5'd0, 12'h099));
            //  0x2018: HALT
            write_instr(64'h2018, {OP_PRIV, 27'b0});

            // Function at 0x2040:
            //  0x2040: MOV2 r2, 7
            write_instr(64'h2040, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd7));
            //  0x2044: RETURN
            write_instr(64'h2044, {5'h0D, 27'b0});

            reset = 1; @(posedge clk); @(posedge clk);
            reset = 0;

            for (i = 0; i < 500 && !hlt; i = i + 1)
                @(posedge clk);

            if (!hlt)
                $display("  FAIL: did not halt");
            else begin
                if (dut.reg_file.registers[2] === 64'd7)
                    $display("  PASS: r2=%0d (function executed)", dut.reg_file.registers[2]);
                else
                    $display("  FAIL: r2=%0d (expected 7, function may not have run)",
                             dut.reg_file.registers[2]);
                if (dut.reg_file.registers[3] === 64'h099)
                    $display("  PASS: r3=0x%h (post-return code ran)", dut.reg_file.registers[3]);
                else
                    $display("  FAIL: r3=0x%h (expected 0x99, return may have failed)",
                             dut.reg_file.registers[3]);
            end
        end
    endtask

    // ============================================================
    // Test 5: Arithmetic — ADD, SUB, MUL, AND, OR, XOR, NOT
    // ============================================================
    task test_arithmetic;
        integer i;
        begin
            $display("=== Test: Arithmetic / Logic ===");
            for (i = 0; i < 128; i = i + 1)
                dut.memory.bytes[32'h2000 + i] = 8'h0;

            //  r1 = 100, r2 = 30
            write_instr(64'h2000, enc_i(OP_MOV2, 5'd1, 5'd0, 12'd100));
            write_instr(64'h2004, enc_i(OP_MOV2, 5'd2, 5'd0, 12'd30));
            // r3 = r1 + r2 = 130
            write_instr(64'h2008, enc_r(OP_ADD, 5'd3, 5'd1, 5'd2));
            // r4 = r1 - r2 = 70
            write_instr(64'h200C, enc_r(OP_SUB, 5'd4, 5'd1, 5'd2));
            // r5 = r1 & r2 = 100 & 30 = 4
            write_instr(64'h2010, enc_r(OP_AND, 5'd5, 5'd1, 5'd2));
            // r6 = r1 | r2 = 100 | 30 = 126
            write_instr(64'h2014, enc_r(OP_OR, 5'd6, 5'd1, 5'd2));
            // r7 = r1 ^ r2
            write_instr(64'h2018, enc_r(OP_XOR, 5'd7, 5'd1, 5'd2));
            // HALT
            write_instr(64'h201C, {OP_PRIV, 27'b0});

            reset = 1; @(posedge clk); @(posedge clk);
            reset = 0;

            for (i = 0; i < 300 && !hlt; i = i + 1)
                @(posedge clk);

            if (!hlt) begin
                $display("  FAIL: did not halt");
            end else begin
                $write("  ADD: r3=%0d %s\n", dut.reg_file.registers[3],
                       dut.reg_file.registers[3]===64'd130 ? "PASS" : "FAIL");
                $write("  SUB: r4=%0d %s\n", dut.reg_file.registers[4],
                       dut.reg_file.registers[4]===64'd70 ? "PASS" : "FAIL");
                $write("  AND: r5=%0d %s\n", dut.reg_file.registers[5],
                       dut.reg_file.registers[5]===(64'd100 & 64'd30) ? "PASS" : "FAIL");
                $write("  OR:  r6=%0d %s\n", dut.reg_file.registers[6],
                       dut.reg_file.registers[6]===(64'd100 | 64'd30) ? "PASS" : "FAIL");
                $write("  XOR: r7=%0d %s\n", dut.reg_file.registers[7],
                       dut.reg_file.registers[7]===(64'd100 ^ 64'd30) ? "PASS" : "FAIL");
            end
        end
    endtask

    // ============================================================
    // Main test sequence
    // ============================================================
    initial begin
        $display("===== Tinker Multi-Cycle Core Testbench =====");
        reset = 1;
        repeat(4) @(posedge clk);
        reset = 0;

        test_add;
        test_arithmetic;
        test_branch;
        test_load_store;
        test_call_return;

        $display("===== Done =====");
        $finish;
    end

    // Safety timeout
    initial begin
        #100000;
        $display("TIMEOUT: simulation exceeded limit");
        $finish;
    end

endmodule

// Full-system testbench for cpu_top.
// Covers every opcode, PSR branch conditions, load/store through the cache
// and CDC path, the sum loop, CALL/RET, HALT, and an illegal opcode.
//
// The cache has 10 lines. Index is (word_addr >> 2) % 10, so every
// data address is legal. Word 0x28 aliases with word 0.
`timescale 1ns/1ps

`define CHECK(got, exp, msg) \
    if ((got) !== (exp)) begin \
        errors = errors + 1; \
        $display("  FAIL %s  got=%h exp=%h", msg, (got), (exp)); \
    end

module tb_cpu_top;
    reg         clk_cpu;
    reg         rst_cpu_n;
    reg         clk_mem;
    reg         rst_mem_n;
    wire        halted;
    wire        illegal;

    integer     errors;
    integer     cycles;
    integer     npc;
    reg [31:0]  prog [0:511];

    localparam [7:0]
        OP_NOP      = 8'h00,
        OP_LOAD     = 8'h01,
        OP_LOAD_IND = 8'h02,
        OP_LOAD_IMM = 8'h03,
        OP_STORE    = 8'h04,
        OP_STORE_IND= 8'h05,
        OP_ADD      = 8'h06,
        OP_SUB      = 8'h07,
        OP_MUL      = 8'h08,
        OP_AND      = 8'h09,
        OP_OR       = 8'h0A,
        OP_NOT      = 8'h0B,
        OP_CMP      = 8'h0C,
        OP_EQ       = 8'h0D,
        OP_JMP      = 8'h0E,
        OP_JMP_IF   = 8'h0F,
        OP_XOR      = 8'h10,
        OP_SHL      = 8'h11,
        OP_SHR      = 8'h12,
        OP_SAR      = 8'h13,
        OP_ROL      = 8'h14,
        OP_ROR      = 8'h15,
        OP_ADDI     = 8'h16,
        OP_SUBI     = 8'h17,
        OP_ANDI     = 8'h18,
        OP_ORI      = 8'h19,
        OP_XORI     = 8'h1A,
        OP_MOV      = 8'h1B,
        OP_SLT      = 8'h1C,
        OP_SLTU     = 8'h1D,
        OP_LUI      = 8'h1E,
        OP_BEQ      = 8'h20,
        OP_BNE      = 8'h21,
        OP_BLT      = 8'h22,
        OP_BGE      = 8'h23,
        OP_BLTU     = 8'h24,
        OP_BGEU     = 8'h25,
        OP_JMP_REG  = 8'h26,
        OP_CALL     = 8'h27,
        OP_RET      = 8'h28,
        OP_HALT     = 8'hFF;

    cpu_top dut (
        .clk_cpu     (clk_cpu),
        .rst_cpu_n   (rst_cpu_n),
        .clk_mem     (clk_mem),
        .rst_mem_n   (rst_mem_n),
        .halted_out  (halted),
        .illegal_out (illegal)
    );

    initial clk_cpu = 1'b0;
    always #5 clk_cpu = ~clk_cpu;

    initial clk_mem = 1'b0;
    always #7.5 clk_mem = ~clk_mem;

    function [31:0] gpr;
        input integer n;
        begin
            gpr = dut.u_cpu_core.u_regfile.reg_mem[n];
        end
    endfunction

    function [31:0] dmem;
        input integer a;
        begin
            dmem = dut.u_mem_subsys.u_data_mem.mem[a];
        end
    endfunction

    function [31:0] pc_now;
        input integer unused;
        begin
            pc_now = dut.u_cpu_core.u_pc_unit.pc_q;
        end
    endfunction

    function [31:0] sp_now;
        input integer unused;
        begin
            sp_now = dut.u_cpu_core.u_return_stack.sp_q;
        end
    endfunction

    task emit;
        input [7:0]  op;
        input [3:0]  rd;
        input [3:0]  rs1;
        input [3:0]  rs2;
        input [11:0] imm;
        begin
            prog[npc] = {op, rd, rs1, rs2, imm};
            npc = npc + 1;
        end
    endtask

    task set_target;
        input integer slot;
        input integer target;
        reg [31:0] tmp;
        begin
            tmp = prog[slot];
            tmp[11:0] = target[11:0];
            prog[slot] = tmp;
        end
    endtask

    task reset_prog;
        integer i;
        begin
            npc = 0;
            for (i = 0; i < 512; i = i + 1)
                prog[i] = 32'd0;
        end
    endtask

    task install_prog;
        integer i;
        begin
            for (i = 0; i < 4096; i = i + 1)
                dut.u_program_memory.mem[i] = 32'd0;
            for (i = 0; i < npc; i = i + 1)
                dut.u_program_memory.mem[i] = prog[i];
        end
    endtask

    task clear_dmem;
        integer a;
        begin
            for (a = 0; a < 40; a = a + 1)
                dut.u_mem_subsys.u_data_mem.mem[a] = 32'd0;
            dut.u_mem_subsys.u_data_mem.mem[14'h028] = 32'd0;
            dut.u_mem_subsys.u_data_mem.mem[14'h029] = 32'd0;
            dut.u_mem_subsys.u_data_mem.mem[14'h02A] = 32'd0;
            dut.u_mem_subsys.u_data_mem.mem[14'h02B] = 32'd0;
        end
    endtask

    task apply_reset;
        begin
            rst_cpu_n = 1'b0;
            rst_mem_n = 1'b0;
            repeat (4) @(posedge clk_cpu);
            @(negedge clk_cpu);
            rst_cpu_n = 1'b1;
            rst_mem_n = 1'b1;
        end
    endtask

    task run_cpu;
        input integer limit;
        begin
            cycles = 0;
            while (halted !== 1'b1 && cycles < limit) begin
                @(posedge clk_cpu);
                cycles = cycles + 1;
            end
            if (halted !== 1'b1) begin
                errors = errors + 1;
                $display("  FAIL timeout after %0d cycles, pc=%0h",
                    cycles, dut.u_cpu_core.u_pc_unit.pc_q);
            end
        end
    endtask

    task launch;
        input integer limit;
        begin
            install_prog();
            apply_reset();
            run_cpu(limit);
        end
    endtask

    // Branch should be taken: r8 = 1 and store it at addr. Fall-through stores 0.
    task branch_taken;
        input [7:0]  brop;
        input [3:0]  rs1;
        input [11:0] addr;
        integer s_br;
        integer s_jmp;
        integer l_ok;
        begin
            s_br = npc;
            emit(brop, 4'd0, rs1, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd8, 4'd0, 4'd0, 12'd0);
            s_jmp = npc;
            emit(OP_JMP, 4'd0, 4'd0, 4'd0, 12'd0);
            l_ok = npc;
            emit(OP_LOAD_IMM, 4'd8, 4'd0, 4'd0, 12'd1);
            set_target(s_br, l_ok);
            set_target(s_jmp, npc);
            emit(OP_STORE, 4'd8, 4'd0, 4'd0, addr);
        end
    endtask

    // Branch should not be taken: r8 = 1. Taking it stores 0.
    task branch_not_taken;
        input [7:0]  brop;
        input [3:0]  rs1;
        input [11:0] addr;
        integer s_br;
        integer s_jmp;
        begin
            s_br = npc;
            emit(brop, 4'd0, rs1, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd8, 4'd0, 4'd0, 12'd1);
            s_jmp = npc;
            emit(OP_JMP, 4'd0, 4'd0, 4'd0, 12'd0);
            set_target(s_br, npc);
            emit(OP_LOAD_IMM, 4'd8, 4'd0, 4'd0, 12'd0);
            set_target(s_jmp, npc);
            emit(OP_STORE, 4'd8, 4'd0, 4'd0, addr);
        end
    endtask

    // ------------------------------------------------------------------------
    // r0 is a normal register. Logic, arithmetic, and immediates.
    // ------------------------------------------------------------------------
    task test_alu_arith;
        integer before;
        integer halt_at;
        begin
            before = errors;
            $display("--- ALU arithmetic and immediates ---");
            clear_dmem();
            reset_prog();
            emit(OP_LOAD_IMM, 4'd0,  4'd0, 4'd0, 12'h123);
            emit(OP_LOAD_IMM, 4'd1,  4'd0, 4'd0, 12'h0F0);
            emit(OP_LOAD_IMM, 4'd2,  4'd0, 4'd0, 12'd4);
            emit(OP_NOP,      4'd0,  4'd0, 4'd0, 12'd0);
            emit(OP_ADD,      4'd3,  4'd1, 4'd2, 12'd0);
            emit(OP_SUB,      4'd4,  4'd1, 4'd2, 12'd0);
            emit(OP_AND,      4'd5,  4'd1, 4'd2, 12'd0);
            emit(OP_OR,       4'd6,  4'd1, 4'd2, 12'd0);
            emit(OP_XOR,      4'd7,  4'd1, 4'd2, 12'd0);
            emit(OP_NOT,      4'd8,  4'd1, 4'd0, 12'd0);
            emit(OP_MOV,      4'd9,  4'd1, 4'd0, 12'd0);
            emit(OP_ADDI,     4'd10, 4'd1, 4'd0, 12'hFFF); // 0xF0 + (-1)
            emit(OP_SUBI,     4'd11, 4'd1, 4'd0, 12'd1);
            emit(OP_ANDI,     4'd12, 4'd1, 4'd0, 12'h0FF);
            emit(OP_ORI,      4'd13, 4'd1, 4'd0, 12'h00F);
            emit(OP_XORI,     4'd14, 4'd1, 4'd0, 12'h0FF);
            emit(OP_LUI,      4'd15, 4'd0, 4'd0, 12'hABC);
            halt_at = npc;
            emit(OP_HALT, 4'd0, 4'd0, 4'd0, 12'd0);
            launch(2000);
            if (halted === 1'b1) begin
                `CHECK(illegal, 1'b0, "arith illegal")
                `CHECK(pc_now(0), halt_at, "arith halt pc")
                `CHECK(gpr(0),  32'h0000_0123, "R0 writable")
                `CHECK(gpr(1),  32'h0000_00F0, "LOAD_IMM")
                `CHECK(gpr(2),  32'h0000_0004, "LOAD_IMM r2")
                `CHECK(gpr(3),  32'h0000_00F4, "ADD")
                `CHECK(gpr(4),  32'h0000_00EC, "SUB")
                `CHECK(gpr(5),  32'h0000_0000, "AND")
                `CHECK(gpr(6),  32'h0000_00F4, "OR")
                `CHECK(gpr(7),  32'h0000_00F4, "XOR")
                `CHECK(gpr(8),  32'hFFFF_FF0F, "NOT")
                `CHECK(gpr(9),  32'h0000_00F0, "MOV")
                `CHECK(gpr(10), 32'h0000_00EF, "ADDI sext")
                `CHECK(gpr(11), 32'h0000_00EF, "SUBI")
                `CHECK(gpr(12), 32'h0000_00F0, "ANDI")
                `CHECK(gpr(13), 32'h0000_00FF, "ORI")
                `CHECK(gpr(14), 32'h0000_000F, "XORI")
                `CHECK(gpr(15), 32'hABC0_0000, "LUI")
            end
            if (errors == before)
                $display("PASS ALU arithmetic and immediates");
        end
    endtask

    // Shifts, rotates, multiply, and EQ register results.
    task test_shift_mul;
        integer before;
        begin
            before = errors;
            $display("--- shifts, rotates, MUL, EQ ---");
            clear_dmem();
            reset_prog();
            emit(OP_LUI,      4'd1,  4'd0,  4'd0, 12'h800);
            emit(OP_ORI,      4'd1,  4'd1,  4'd0, 12'h00F); // 0x8000000F
            emit(OP_LOAD_IMM, 4'd2,  4'd0,  4'd0, 12'd4);
            emit(OP_SHL,      4'd3,  4'd1,  4'd2, 12'd0);
            emit(OP_SHR,      4'd4,  4'd1,  4'd2, 12'd0);
            emit(OP_SAR,      4'd5,  4'd1,  4'd2, 12'd0);
            emit(OP_ROL,      4'd6,  4'd1,  4'd2, 12'd0);
            emit(OP_ROR,      4'd7,  4'd1,  4'd2, 12'd0);
            emit(OP_LOAD_IMM, 4'd8,  4'd0,  4'd0, 12'd0);
            emit(OP_SHL,      4'd9,  4'd1,  4'd8, 12'd0);   // shift by 0
            emit(OP_LOAD_IMM, 4'd10, 4'd0,  4'd0, 12'd200);
            emit(OP_LOAD_IMM, 4'd11, 4'd0,  4'd0, 12'd250);
            emit(OP_MUL,      4'd12, 4'd10, 4'd11, 12'd0);
            emit(OP_EQ,       4'd13, 4'd10, 4'd10, 12'd0);
            emit(OP_EQ,       4'd14, 4'd10, 4'd11, 12'd0);
            emit(OP_HALT,     4'd0,  4'd0,  4'd0, 12'd0);
            launch(2000);
            if (halted === 1'b1) begin
                `CHECK(gpr(1),  32'h8000_000F, "shift operand")
                `CHECK(gpr(3),  32'h0000_00F0, "SHL")
                `CHECK(gpr(4),  32'h0800_0000, "SHR")
                `CHECK(gpr(5),  32'hF800_0000, "SAR")
                `CHECK(gpr(6),  32'h0000_00F8, "ROL")
                `CHECK(gpr(7),  32'hF800_0000, "ROR")
                `CHECK(gpr(9),  32'h8000_000F, "SHL by 0")
                `CHECK(gpr(12), 32'h0000_C350, "MUL 200*250")
                `CHECK(gpr(13), 32'h0000_0001, "EQ true")
                `CHECK(gpr(14), 32'h0000_0000, "EQ false")
            end
            if (errors == before)
                $display("PASS shifts, rotates, MUL, EQ");
        end
    endtask

    // SLT / SLTU, CMP does not write rd, signed multiply.
    task test_compare;
        integer before;
        begin
            before = errors;
            $display("--- SLT, SLTU, CMP, signed MUL ---");
            clear_dmem();
            reset_prog();
            emit(OP_LOAD_IMM, 4'd1,  4'd0,  4'd0, 12'd5);
            emit(OP_LOAD_IMM, 4'd2,  4'd0,  4'd0, 12'd9);
            emit(OP_EQ,       4'd3,  4'd1,  4'd1, 12'd0);
            emit(OP_EQ,       4'd4,  4'd1,  4'd2, 12'd0);
            emit(OP_SLT,      4'd5,  4'd1,  4'd2, 12'd0);
            emit(OP_SLT,      4'd6,  4'd2,  4'd1, 12'd0);
            emit(OP_LOAD_IMM, 4'd7,  4'd0,  4'd0, 12'd0);
            emit(OP_NOT,      4'd7,  4'd7,  4'd0, 12'd0);   // -1
            emit(OP_LOAD_IMM, 4'd8,  4'd0,  4'd0, 12'd1);
            emit(OP_SLT,      4'd9,  4'd7,  4'd8, 12'd0);   // -1 < 1
            emit(OP_SLTU,     4'd10, 4'd7,  4'd8, 12'd0);   // unsigned false
            emit(OP_SLT,      4'd11, 4'd8,  4'd7, 12'd0);   // 1 < -1
            emit(OP_SLTU,     4'd12, 4'd8,  4'd7, 12'd0);   // 1 < 0xFFFFFFFF
            emit(OP_LOAD_IMM, 4'd13, 4'd0,  4'd0, 12'h055);
            emit(OP_CMP,      4'd13, 4'd1,  4'd2, 12'd0);   // must not write r13
            emit(OP_LOAD_IMM, 4'd14, 4'd0,  4'd0, 12'd0);
            emit(OP_NOT,      4'd14, 4'd14, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd15, 4'd0,  4'd0, 12'd5);
            emit(OP_MUL,      4'd15, 4'd14, 4'd15, 12'd0);  // -1 * 5
            emit(OP_HALT,     4'd0,  4'd0,  4'd0, 12'd0);
            launch(2000);
            if (halted === 1'b1) begin
                `CHECK(gpr(3),  32'd1,          "EQ equal")
                `CHECK(gpr(4),  32'd0,          "EQ differ")
                `CHECK(gpr(5),  32'd1,          "SLT 5<9")
                `CHECK(gpr(6),  32'd0,          "SLT 9<5")
                `CHECK(gpr(7),  32'hFFFF_FFFF,  "NOT zero")
                `CHECK(gpr(9),  32'd1,          "SLT -1<1")
                `CHECK(gpr(10), 32'd0,          "SLTU -1<1")
                `CHECK(gpr(11), 32'd0,          "SLT 1<-1")
                `CHECK(gpr(12), 32'd1,          "SLTU 1<max")
                `CHECK(gpr(13), 32'h0000_0055,  "CMP no write")
                `CHECK(gpr(15), 32'hFFFF_FFFB,  "MUL -1*5")
            end
            if (errors == before)
                $display("PASS SLT, SLTU, CMP, signed MUL");
        end
    endtask

    // Every branch / jump, plus flag side effects observed through branches.
    task test_branches;
        integer before;
        integer s_li;
        integer s_jmp;
        integer l_ok;
        begin
            before = errors;
            $display("--- branches, jumps, flag side effects ---");
            clear_dmem();
            reset_prog();

            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'd5);
            emit(OP_LOAD_IMM, 4'd2, 4'd0, 4'd0, 12'd5);
            emit(OP_LOAD_IMM, 4'd3, 4'd0, 4'd0, 12'd3);
            emit(OP_LOAD_IMM, 4'd4, 4'd0, 4'd0, 12'd9);

            emit(OP_CMP, 4'd0, 4'd1, 4'd2, 12'd0);
            branch_taken(OP_BEQ, 4'd0, 12'h010);
            emit(OP_CMP, 4'd0, 4'd1, 4'd3, 12'd0);
            branch_not_taken(OP_BEQ, 4'd0, 12'h011);
            emit(OP_CMP, 4'd0, 4'd1, 4'd3, 12'd0);
            branch_taken(OP_BNE, 4'd0, 12'h012);
            emit(OP_CMP, 4'd0, 4'd1, 4'd2, 12'd0);
            branch_not_taken(OP_BNE, 4'd0, 12'h013);

            emit(OP_CMP, 4'd0, 4'd3, 4'd1, 12'd0); // 3 < 5
            branch_taken(OP_BLT, 4'd0, 12'h014);
            emit(OP_CMP, 4'd0, 4'd1, 4'd3, 12'd0);
            branch_not_taken(OP_BLT, 4'd0, 12'h015);
            emit(OP_CMP, 4'd0, 4'd1, 4'd3, 12'd0); // 5 >= 3
            branch_taken(OP_BGE, 4'd0, 12'h016);
            emit(OP_CMP, 4'd0, 4'd3, 4'd1, 12'd0);
            branch_not_taken(OP_BGE, 4'd0, 12'h017);

            emit(OP_CMP, 4'd0, 4'd3, 4'd1, 12'd0); // unsigned 3 < 5, C=0
            branch_taken(OP_BLTU, 4'd0, 12'h018);
            emit(OP_CMP, 4'd0, 4'd1, 4'd3, 12'd0);
            branch_not_taken(OP_BLTU, 4'd0, 12'h019);
            emit(OP_CMP, 4'd0, 4'd1, 4'd3, 12'd0); // C=1
            branch_taken(OP_BGEU, 4'd0, 12'h01A);
            emit(OP_CMP, 4'd0, 4'd3, 4'd1, 12'd0);
            branch_not_taken(OP_BGEU, 4'd0, 12'h01B);

            branch_taken(OP_JMP, 4'd0, 12'h01C);
            branch_taken(OP_JMP_IF, 4'd1, 12'h01D); // r1 = 5
            branch_not_taken(OP_JMP_IF, 4'd0, 12'h01E); // r0 = 0

            // JMP_REG to the pass load-immediate.
            s_li = npc;
            emit(OP_LOAD_IMM, 4'd9, 4'd0, 4'd0, 12'd0);
            emit(OP_JMP_REG,  4'd0, 4'd9, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd8, 4'd0, 4'd0, 12'd0);
            s_jmp = npc;
            emit(OP_JMP, 4'd0, 4'd0, 4'd0, 12'd0);
            l_ok = npc;
            emit(OP_LOAD_IMM, 4'd8, 4'd0, 4'd0, 12'd1);
            set_target(s_li, l_ok);
            set_target(s_jmp, npc);
            emit(OP_STORE, 4'd8, 4'd0, 4'd0, 12'h01F);

            // -1 < 1 signed, no overflow. BLT taken.
            emit(OP_LOAD_IMM, 4'd5, 4'd0, 4'd0, 12'd0);
            emit(OP_NOT,      4'd5, 4'd5, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd6, 4'd0, 4'd0, 12'd1);
            emit(OP_CMP,      4'd0, 4'd5, 4'd6, 12'd0);
            branch_taken(OP_BLT, 4'd0, 12'h000);

            // NOP must leave Z set by CMP.
            emit(OP_LOAD_IMM, 4'd5, 4'd0, 4'd0, 12'd8);
            emit(OP_LOAD_IMM, 4'd6, 4'd0, 4'd0, 12'd8);
            emit(OP_CMP,      4'd0, 4'd5, 4'd6, 12'd0);
            emit(OP_NOP,      4'd0, 4'd0, 4'd0, 12'd0);
            branch_taken(OP_BEQ, 4'd0, 12'h001);

            // SUB writes Z/N only, so C from the previous ADD stays 1.
            emit(OP_LOAD_IMM, 4'd5, 4'd0, 4'd0, 12'd0);
            emit(OP_NOT,      4'd5, 4'd5, 4'd0, 12'd0);
            emit(OP_ADD,      4'd5, 4'd5, 4'd5, 12'd0); // -1 + -1, C=1
            emit(OP_LOAD_IMM, 4'd6, 4'd0, 4'd0, 12'd1);
            emit(OP_LOAD_IMM, 4'd7, 4'd0, 4'd0, 12'd2);
            emit(OP_SUB,      4'd6, 4'd6, 4'd7, 12'd0);   // 1 - 2
            branch_taken(OP_BGEU, 4'd0, 12'h022);

            // ADDI result 0 sets Z.
            emit(OP_LOAD_IMM, 4'd5, 4'd0, 4'd0, 12'd2);
            emit(OP_ADDI,     4'd5, 4'd5, 4'd0, 12'hFFE); // 2 + (-2)
            branch_taken(OP_BEQ, 4'd0, 12'h023);

            // EQ true writes Z = 0, so BEQ is not taken.
            emit(OP_LOAD_IMM, 4'd5, 4'd0, 4'd0, 12'd3);
            emit(OP_EQ,       4'd6, 4'd5, 4'd5, 12'd0);
            branch_not_taken(OP_BEQ, 4'd0, 12'h026);

            // MUL 0 sets Z, so BEQ is taken.
            emit(OP_LOAD_IMM, 4'd5, 4'd0, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd6, 4'd0, 4'd0, 12'd4);
            emit(OP_MUL,      4'd7, 4'd5, 4'd6, 12'd0);
            branch_taken(OP_BEQ, 4'd0, 12'h027);

            // 0x7FFFFFFF compared with -1 overflows. N^V = 0, so BGE is taken.
            emit(OP_LUI,      4'd6, 4'd0, 4'd0, 12'h7FF);
            emit(OP_ORI,      4'd6, 4'd6, 4'd0, 12'hFFF);
            emit(OP_LOAD_IMM, 4'd7, 4'd0, 4'd0, 12'd0);
            emit(OP_NOT,      4'd7, 4'd7, 4'd0, 12'd0);
            emit(OP_CMP,      4'd0, 4'd6, 4'd7, 12'd0);
            branch_taken(OP_BGE, 4'd0, 12'h025);

            // ADD overflow sets V. N^V = 0, so the following BLT is not taken.
            emit(OP_LOAD_IMM, 4'd5, 4'd0, 4'd0, 12'd1);
            emit(OP_CMP,      4'd0, 4'd5, 4'd5, 12'd0);   // V = 0 first
            emit(OP_LUI,      4'd6, 4'd0, 4'd0, 12'h7FF);
            emit(OP_ORI,      4'd6, 4'd6, 4'd0, 12'hFFF);
            emit(OP_LOAD_IMM, 4'd7, 4'd0, 4'd0, 12'd1);
            emit(OP_ADD,      4'd6, 4'd6, 4'd7, 12'd0);   // 0x80000000
            emit(OP_STORE,    4'd6, 4'd0, 4'd0, 12'h021);
            branch_not_taken(OP_BLT, 4'd0, 12'h024);

            emit(OP_HALT, 4'd0, 4'd0, 4'd0, 12'd0);
            launch(20000);
            if (halted === 1'b1) begin
                `CHECK(illegal, 1'b0, "branch illegal")
                `CHECK(dmem(12'h000), 32'd1, "BLT -1<1")
                `CHECK(dmem(12'h001), 32'd1, "NOP keeps Z")
                `CHECK(dmem(12'h010), 32'd1, "BEQ taken")
                `CHECK(dmem(12'h011), 32'd1, "BEQ not taken")
                `CHECK(dmem(12'h012), 32'd1, "BNE taken")
                `CHECK(dmem(12'h013), 32'd1, "BNE not taken")
                `CHECK(dmem(12'h014), 32'd1, "BLT taken")
                `CHECK(dmem(12'h015), 32'd1, "BLT not taken")
                `CHECK(dmem(12'h016), 32'd1, "BGE taken")
                `CHECK(dmem(12'h017), 32'd1, "BGE not taken")
                `CHECK(dmem(12'h018), 32'd1, "BLTU taken")
                `CHECK(dmem(12'h019), 32'd1, "BLTU not taken")
                `CHECK(dmem(12'h01A), 32'd1, "BGEU taken")
                `CHECK(dmem(12'h01B), 32'd1, "BGEU not taken")
                `CHECK(dmem(12'h01C), 32'd1, "JMP")
                `CHECK(dmem(12'h01D), 32'd1, "JMP_IF taken")
                `CHECK(dmem(12'h01E), 32'd1, "JMP_IF not taken")
                `CHECK(dmem(12'h01F), 32'd1, "JMP_REG")
                `CHECK(dmem(12'h021), 32'h8000_0000, "ADD overflow result")
                `CHECK(dmem(12'h022), 32'd1, "SUB leaves C")
                `CHECK(dmem(12'h023), 32'd1, "ADDI sets Z")
                `CHECK(dmem(12'h024), 32'd1, "ADD sets V")
                `CHECK(dmem(12'h025), 32'd1, "CMP overflow BGE")
                `CHECK(dmem(12'h026), 32'd1, "EQ clears Z")
                `CHECK(dmem(12'h027), 32'd1, "MUL sets Z")
            end
            if (errors == before)
                $display("PASS branches, jumps, flag side effects");
        end
    endtask

    // Hit, miss, store hit, store miss, indirect, and a tag conflict.
    task test_load_store;
        integer before;
        begin
            before = errors;
            $display("--- load, store, cache ---");
            clear_dmem();
            dut.u_mem_subsys.u_data_mem.mem[0]       = 32'h1111_0000;
            dut.u_mem_subsys.u_data_mem.mem[1]       = 32'h2222_0001;
            dut.u_mem_subsys.u_data_mem.mem[2]       = 32'h3333_0002;
            dut.u_mem_subsys.u_data_mem.mem[3]       = 32'h4444_0003;
            dut.u_mem_subsys.u_data_mem.mem[4]       = 32'h5555_0004;
            dut.u_mem_subsys.u_data_mem.mem[14'h028] = 32'hAAAA_0000;
            dut.u_mem_subsys.u_data_mem.mem[14'h029] = 32'hAAAA_0001;
            dut.u_mem_subsys.u_data_mem.mem[14'h02A] = 32'hAAAA_0002;
            dut.u_mem_subsys.u_data_mem.mem[14'h02B] = 32'hAAAA_0003;

            reset_prog();
            emit(OP_LOAD,     4'd1,  4'd0, 4'd0, 12'h000); // miss, fill line
            emit(OP_LOAD,     4'd2,  4'd0, 4'd0, 12'h001); // hit
            emit(OP_LOAD,     4'd3,  4'd0, 4'd0, 12'h002); // hit
            emit(OP_LOAD,     4'd4,  4'd0, 4'd0, 12'h003); // hit
            emit(OP_LOAD_IMM, 4'd5,  4'd0, 4'd0, 12'h004);
            emit(OP_LOAD_IND, 4'd6,  4'd5, 4'd0, 12'h000); // mem[4]
            emit(OP_LOAD_IMM, 4'd7,  4'd0, 4'd0, 12'hABC);
            emit(OP_STORE,    4'd7,  4'd0, 4'd0, 12'h001); // store hit
            emit(OP_LOAD,     4'd8,  4'd0, 4'd0, 12'h001); // hit readback
            emit(OP_LOAD_IMM, 4'd9,  4'd0, 4'd0, 12'h020);
            emit(OP_STORE_IND,4'd1,  4'd0, 4'd9, 12'h000); // store miss
            emit(OP_LOAD,     4'd10, 4'd0, 4'd0, 12'h020); // miss readback
            emit(OP_LOAD,     4'd11, 4'd0, 4'd0, 12'h028); // conflict miss, same index as word 0
            emit(OP_LOAD,     4'd12, 4'd0, 4'd0, 12'h029); // hit on new line
            emit(OP_LOAD,     4'd13, 4'd0, 4'd0, 12'h001); // refill, write-through
            emit(OP_HALT,     4'd0,  4'd0, 4'd0, 12'd0);
            launch(20000);
            if (halted === 1'b1) begin
                `CHECK(gpr(1),  32'h1111_0000, "LOAD miss")
                `CHECK(gpr(2),  32'h2222_0001, "LOAD hit")
                `CHECK(gpr(3),  32'h3333_0002, "LOAD same line")
                `CHECK(gpr(4),  32'h4444_0003, "LOAD line tail")
                `CHECK(gpr(6),  32'h5555_0004, "LOAD_IND")
                `CHECK(gpr(8),  32'h0000_0ABC, "store hit readback")
                `CHECK(gpr(10), 32'h1111_0000, "STORE_IND readback")
                `CHECK(gpr(11), 32'hAAAA_0000, "conflict miss")
                `CHECK(gpr(12), 32'hAAAA_0001, "hit after fill")
                `CHECK(gpr(13), 32'h0000_0ABC, "write-through reload")
                `CHECK(dmem(1),    32'h0000_0ABC, "mem store hit")
                `CHECK(dmem(12'h020), 32'h1111_0000, "mem store miss")
                `CHECK(dmem(0),    32'h1111_0000, "untouched word 0")
                `CHECK(dmem(2),    32'h3333_0002, "untouched word 2")
            end
            if (errors == before)
                $display("PASS load, store, cache");
        end
    endtask

    // Sum of words 0..9 (values 1..10) is 55, stored at word 0x20.
    task test_sum_loop;
        integer before;
        integer i;
        integer loop;
        begin
            before = errors;
            $display("--- sum loop ---");
            clear_dmem();
            for (i = 0; i < 10; i = i + 1)
                dut.u_mem_subsys.u_data_mem.mem[i] = i + 1;

            reset_prog();
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'd0);  // sum
            emit(OP_LOAD_IMM, 4'd2, 4'd0, 4'd0, 12'd0);  // pointer
            emit(OP_LOAD_IMM, 4'd3, 4'd0, 4'd0, 12'd10); // count
            emit(OP_LOAD_IMM, 4'd4, 4'd0, 4'd0, 12'd1);
            emit(OP_LOAD_IMM, 4'd6, 4'd0, 4'd0, 12'd0);
            loop = npc;
            emit(OP_LOAD_IND, 4'd5, 4'd2, 4'd0, 12'd0);
            emit(OP_ADD,      4'd1, 4'd1, 4'd5, 12'd0);
            emit(OP_ADDI,     4'd2, 4'd2, 4'd0, 12'd1);
            emit(OP_SUB,      4'd3, 4'd3, 4'd4, 12'd0);
            emit(OP_CMP,      4'd0, 4'd3, 4'd6, 12'd0);
            emit(OP_BNE,      4'd0, 4'd0, 4'd0, loop[11:0]);
            emit(OP_STORE,    4'd1, 4'd0, 4'd0, 12'h020);
            emit(OP_HALT,     4'd0, 4'd0, 4'd0, 12'd0);
            launch(20000);
            if (halted === 1'b1) begin
                `CHECK(gpr(1), 32'd55, "sum in r1")
                `CHECK(gpr(2), 32'd10, "pointer end")
                `CHECK(gpr(3), 32'd0,  "count end")
                `CHECK(dmem(12'h020), 32'd55, "sum stored")
            end
            if (errors == before)
                $display("PASS sum loop");
        end
    endtask

    task test_call_ret;
        integer before;
        integer s0;
        integer s1;
        integer la;
        integer lb;
        integer l_outer;
        integer l_inner;
        begin
            before = errors;
            $display("--- CALL and RET ---");
            clear_dmem();

            // Two calls in sequence. Each returns, then HALT.
            reset_prog();
            s0 = npc;
            emit(OP_CALL, 4'd0, 4'd0, 4'd0, 12'd0);
            s1 = npc;
            emit(OP_CALL, 4'd0, 4'd0, 4'd0, 12'd0);
            emit(OP_HALT, 4'd0, 4'd0, 4'd0, 12'd0);
            la = npc;
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'h011);
            emit(OP_RET, 4'd0, 4'd0, 4'd0, 12'd0);
            lb = npc;
            emit(OP_LOAD_IMM, 4'd2, 4'd0, 4'd0, 12'h022);
            emit(OP_ADD, 4'd3, 4'd1, 4'd2, 12'd0);
            emit(OP_RET, 4'd0, 4'd0, 4'd0, 12'd0);
            set_target(s0, la);
            set_target(s1, lb);
            launch(4000);
            if (halted === 1'b1) begin
                `CHECK(illegal, 1'b0, "call illegal")
                `CHECK(pc_now(0), 32'd2, "halt after calls")
                `CHECK(gpr(1), 32'h0000_0011, "first callee")
                `CHECK(gpr(2), 32'h0000_0022, "second callee")
                `CHECK(gpr(3), 32'h0000_0033, "add after both calls")
                `CHECK(sp_now(0), 32'd0, "stack empty after RET")
            end

            // Nested call: outer calls inner, inner returns to outer, outer returns.
            reset_prog();
            s0 = npc;
            emit(OP_CALL, 4'd0, 4'd0, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'h021);
            emit(OP_HALT, 4'd0, 4'd0, 4'd0, 12'd0);
            l_outer = npc;
            emit(OP_CALL, 4'd0, 4'd0, 4'd0, 12'd0);
            emit(OP_RET, 4'd0, 4'd0, 4'd0, 12'd0);
            l_inner = npc;
            emit(OP_LOAD_IMM, 4'd2, 4'd0, 4'd0, 12'h022);
            emit(OP_RET, 4'd0, 4'd0, 4'd0, 12'd0);
            set_target(s0, l_outer);
            set_target(l_outer, l_inner);
            launch(4000);
            if (halted === 1'b1) begin
                `CHECK(pc_now(0), 32'd2, "nested halt pc")
                `CHECK(gpr(1), 32'h0000_0021, "after outer return")
                `CHECK(gpr(2), 32'h0000_0022, "inner body")
                `CHECK(sp_now(0), 32'd0, "stack empty after nest")
            end

            // RET with an empty stack halts and does not run the next instruction.
            reset_prog();
            emit(OP_RET, 4'd0, 4'd0, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'h0EE);
            launch(200);
            if (halted === 1'b1) begin
                `CHECK(illegal, 1'b0, "empty RET illegal")
                `CHECK(pc_now(0), 32'd0, "empty RET pc")
                `CHECK(gpr(1), 32'd0, "empty RET no fallthrough")
                `CHECK(sp_now(0), 32'd0, "empty RET sp")
            end

            // The 17th nested CALL halts with the stack still full.
            reset_prog();
            emit(OP_CALL, 4'd0, 4'd0, 4'd0, 12'd0);
            launch(2000);
            if (halted === 1'b1) begin
                `CHECK(illegal, 1'b0, "full CALL illegal")
                `CHECK(pc_now(0), 32'd0, "full CALL pc")
                `CHECK(sp_now(0), 32'd16, "full CALL depth")
            end

            if (errors == before)
                $display("PASS CALL and RET");
        end
    endtask

    task test_halt_illegal;
        integer before;
        begin
            before = errors;
            $display("--- HALT and illegal opcode ---");
            clear_dmem();

            reset_prog();
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'd1);
            emit(OP_HALT,     4'd0, 4'd0, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'd2);
            launch(500);
            if (halted === 1'b1) begin
                `CHECK(illegal, 1'b0, "HALT not illegal")
                `CHECK(pc_now(0), 32'd1, "HALT pc")
                `CHECK(gpr(1), 32'd1, "HALT stops fetch")
            end

            reset_prog();
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'd1);
            emit(8'h1F,       4'd0, 4'd0, 4'd0, 12'd0);
            emit(OP_LOAD_IMM, 4'd1, 4'd0, 4'd0, 12'd2);
            launch(500);
            if (halted === 1'b1) begin
                `CHECK(illegal, 1'b1, "illegal opcode")
                `CHECK(pc_now(0), 32'd1, "illegal pc")
                `CHECK(gpr(1), 32'd1, "illegal stops fetch")
            end

            if (errors == before)
                $display("PASS HALT and illegal opcode");
        end
    endtask

    initial begin
        errors    = 0;
        rst_cpu_n = 1'b0;
        rst_mem_n = 1'b0;
        npc       = 0;
        #1;

        test_alu_arith();
        test_shift_mul();
        test_compare();
        test_branches();
        test_load_store();
        test_sum_loop();
        test_call_ret();
        test_halt_illegal();

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECKS FAILED", errors);
        $finish;
    end
endmodule

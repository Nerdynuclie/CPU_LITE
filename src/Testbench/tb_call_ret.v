// CALL / RET checks against cpu_top.
// CALL pushes PC+1 and jumps to imm. RET pops that address.
// An empty RET or a 17th nested CALL halts without illegal_out.
`timescale 1ns/1ps

module tb_call_ret;
    reg clk_cpu;
    reg rst_cpu_n;
    reg clk_mem;
    reg rst_mem_n;

    wire halted;
    wire illegal;

    integer errors;
    integer cycles;

    cpu_top dut (
        .clk_cpu    (clk_cpu),
        .rst_cpu_n  (rst_cpu_n),
        .clk_mem    (clk_mem),
        .rst_mem_n  (rst_mem_n),
        .halted_out (halted),
        .illegal_out(illegal)
    );

    initial clk_cpu = 1'b0;
    always #5 clk_cpu = ~clk_cpu;

    initial clk_mem = 1'b0;
    always #7.5 clk_mem = ~clk_mem;

    function [31:0] enc;
        input [7:0] op;
        input [3:0] rd;
        input [11:0] imm;
        begin
            enc = {op, rd, 4'd0, 4'd0, imm};
        end
    endfunction

    // Write data memory before any program image. Called after time 0 so
    // this overrides the zeros in data_memory's initial block.
    task load_dmem;
        integer a;
        begin
            for (a = 0; a < 16; a = a + 1)
                dut.u_mem_subsys.u_data_mem.mem[a] = 32'h0000_0010 + a;
        end
    endtask

    task clear_imem;
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                dut.u_program_memory.mem[i] = 32'd0;
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

    task run_until_halt;
        begin
            cycles = 0;
            while (halted !== 1'b1 && cycles < 400) begin
                @(posedge clk_cpu);
                cycles = cycles + 1;
            end
        end
    endtask

    task check;
        input [8*48-1:0] name;
        input cond;
        begin
            if (!cond) begin
                $display("FAIL %0s  pc=%0d r1=%h r2=%h sp=%0d illegal=%b cycles=%0d",
                    name,
                    dut.u_cpu_core.u_pc_unit.pc_q,
                    dut.u_cpu_core.u_regfile.reg_mem[1],
                    dut.u_cpu_core.u_regfile.reg_mem[2],
                    dut.u_cpu_core.u_return_stack.sp_q,
                    illegal, cycles);
                errors = errors + 1;
            end
            else
                $display("PASS %0s", name);
        end
    endtask

    initial begin
        errors    = 0;
        rst_cpu_n = 1'b0;
        rst_mem_n = 1'b0;
        #1;

        // Return to the instruction after CALL, then halt.
        load_dmem();
        clear_imem();
        dut.u_program_memory.mem[0] = enc(8'h27, 4'd0, 12'd3); // CALL 3
        dut.u_program_memory.mem[1] = enc(8'h03, 4'd1, 12'h011); // LOAD_IMM r1, 0x11
        dut.u_program_memory.mem[2] = enc(8'hFF, 4'd0, 12'd0); // HALT
        dut.u_program_memory.mem[3] = enc(8'h28, 4'd0, 12'd0); // RET
        apply_reset();
        run_until_halt();
        check("call-ret writes r1 and halts at 2",
            halted === 1'b1 && illegal === 1'b0 &&
            dut.u_cpu_core.u_pc_unit.pc_q == 12'd2 &&
            dut.u_cpu_core.u_regfile.reg_mem[1] == 32'h0000_0011 &&
            dut.u_cpu_core.u_return_stack.sp_q == 5'd0);

        // Inner call returns to the outer subroutine, then to the caller.
        load_dmem();
        clear_imem();
        dut.u_program_memory.mem[0] = enc(8'h27, 4'd0, 12'd4); // CALL 4
        dut.u_program_memory.mem[1] = enc(8'h03, 4'd1, 12'h021); // LOAD_IMM r1, 0x21
        dut.u_program_memory.mem[2] = enc(8'hFF, 4'd0, 12'd0); // HALT
        dut.u_program_memory.mem[4] = enc(8'h27, 4'd0, 12'd6); // CALL 6
        dut.u_program_memory.mem[5] = enc(8'h28, 4'd0, 12'd0); // RET -> 1
        dut.u_program_memory.mem[6] = enc(8'h03, 4'd2, 12'h022); // LOAD_IMM r2, 0x22
        dut.u_program_memory.mem[7] = enc(8'h28, 4'd0, 12'd0); // RET -> 5
        apply_reset();
        run_until_halt();
        check("nested call returns in order",
            halted === 1'b1 && illegal === 1'b0 &&
            dut.u_cpu_core.u_pc_unit.pc_q == 12'd2 &&
            dut.u_cpu_core.u_regfile.reg_mem[1] == 32'h0000_0021 &&
            dut.u_cpu_core.u_regfile.reg_mem[2] == 32'h0000_0022 &&
            dut.u_cpu_core.u_return_stack.sp_q == 5'd0);

        // JMP must still skip the following instruction.
        load_dmem();
        clear_imem();
        dut.u_program_memory.mem[0] = enc(8'h0E, 4'd0, 12'd2); // JMP 2
        dut.u_program_memory.mem[1] = enc(8'h03, 4'd1, 12'h001); // LOAD_IMM r1, 1
        dut.u_program_memory.mem[2] = enc(8'hFF, 4'd0, 12'd0); // HALT
        apply_reset();
        run_until_halt();
        check("jmp still skips",
            halted === 1'b1 &&
            dut.u_cpu_core.u_pc_unit.pc_q == 12'd2 &&
            dut.u_cpu_core.u_regfile.reg_mem[1] == 32'd0);

        // RET on an empty stack halts at the RET itself.
        load_dmem();
        clear_imem();
        dut.u_program_memory.mem[0] = enc(8'h28, 4'd0, 12'd0); // RET
        dut.u_program_memory.mem[1] = enc(8'h03, 4'd1, 12'h0EE); // must not run
        apply_reset();
        run_until_halt();
        check("empty ret halts",
            halted === 1'b1 && illegal === 1'b0 &&
            dut.u_cpu_core.u_pc_unit.pc_q == 12'd0 &&
            dut.u_cpu_core.u_regfile.reg_mem[1] == 32'd0 &&
            dut.u_cpu_core.u_return_stack.sp_q == 5'd0 &&
            cycles < 20);

        // Sixteen self-calls fill the stack; the next one halts at PC 0.
        load_dmem();
        clear_imem();
        dut.u_program_memory.mem[0] = enc(8'h27, 4'd0, 12'd0); // CALL 0
        apply_reset();
        run_until_halt();
        check("full call halts",
            halted === 1'b1 && illegal === 1'b0 &&
            dut.u_cpu_core.u_pc_unit.pc_q == 12'd0 &&
            dut.u_cpu_core.u_return_stack.sp_q == 5'd16 &&
            cycles > 70 && cycles < 120);

        if (errors == 0)
            $display("ALL CALL/RET TESTS PASSED");
        else
            $display("%0d CALL/RET TESTS FAILED", errors);
        $finish;
    end
endmodule

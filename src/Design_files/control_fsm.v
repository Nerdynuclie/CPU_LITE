`default_nettype none
// control_fsm.v
// Memory handshake contract (matches mem_subsys_top.v):
//   mem_req_o     : asserted while the FSM wants the cache to accept a
//                   request. Held until the cache actually samples it.
//   mem_wr_en_o      : 1 for STORE, 0 for LOAD.
//   mem_ready_i   : level. 1 => cache can latch a request THIS cycle.
//                   Only meaningful when mem_req_o is also 1: on that cycle,
//                   the cache has taken the transaction.
//   mem_done_i    : one-cycle pulse. 1 => the current transaction has just
//                   retired (loads AND stores). Wired to l1_dcache.xact_done_o.
//                   The FSM waits on this in S_MEM before advancing to WB.

module control_fsm
(
    input  wire         clk_cpu,
    input  wire         rst_cpu_n,

    // From program memory
    input  wire         imem_rd_data_vld_in,

    // From decoder
    input  wire         is_load_in,
    input  wire         is_store_in,
    input  wire         is_mul_in,
    input  wire         is_halt_in,
    input  wire         illegal_in,
    input  wire         unimpl_in,
    input  wire         stack_fault_in, // CALL when return stack is full, or RET when empty

    // From alu
    input  wire         mul_done_in,

    // From data-memory / cache subsystem
    input  wire         mem_ready_in,   // level: cache can accept a req
    input  wire         mem_done_in,    // pulse: current transaction retired

    // To pc_unit
    output reg          pc_wr_en_out,

    // To instruction memory
    output reg          imem_req_out,

    // To alu
    output reg          mul_start_out,

    // To data-memory / cache subsystem
    output reg          mem_req_out,
    output reg          mem_wr_en_out,

    // To pipeline regs / register file
    output reg          ir_wr_en_out,       // latch fetched instruction into IR
    output reg          reg_wr_en_out,      // gate decoder.wr_rd_o into the actual RF write
    output reg          flags_wr_en_out,    // gate decoder.flag_wr_en_mask_o into PSR updates

    output wire         halted_out,
    output wire         illegal_out
);

    //--------------------------------------------------
    // States
    //--------------------------------------------------
    localparam [2:0] S_FETCH  = 3'd0,
                     S_DECODE = 3'd1,
                     S_EXEC   = 3'd2,
                     S_MEM    = 3'd3,   // request already accepted; waiting for mem_done_i
                     S_WB     = 3'd4,
                     S_HALT   = 3'd5;

    reg [2:0] current_state, next_state;

    assign halted_out  = (current_state == S_HALT);
    assign illegal_out = illegal_in;

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n) current_state <= S_FETCH;
        else            current_state <= next_state;
    end

    //--------------------------------------------------
    // Next-state + output logic
    //--------------------------------------------------
    always @(*) begin
        // Defaults - everything idle unless a state below turns it on.
        pc_wr_en_out     = 1'b0;
        imem_req_out  = 1'b0;
        mul_start_out = 1'b0;
        mem_req_out   = 1'b0;
        mem_wr_en_out    = 1'b0;
        ir_wr_en_out     = 1'b0;
        reg_wr_en_out    = 1'b0;
        flags_wr_en_out  = 1'b0;
        next_state     = current_state;

        case (current_state)

            //---------------------------------------------------------
            S_FETCH: begin
                imem_req_out = 1'b1;
                if (imem_rd_data_vld_in) begin
                    ir_wr_en_out = 1'b1;
                    next_state = S_DECODE;
                end
            end

            //---------------------------------------------------------
            S_DECODE: begin
                // decoder is combinational off the IR captured above - one
                // cycle here lets downstream muxes (imm_gen, addr_gen,
                // branch_unit, RF read) settle before EXEC reads them.
                next_state = S_EXEC;
            end

            //---------------------------------------------------------
            S_EXEC: begin
                if (illegal_in || unimpl_in) begin
                    next_state = S_HALT;    // visible stop instead of silently
                end                      // running past an unhandled op
                else if (is_halt_in) begin
                    next_state = S_HALT;
                end
                else if (is_mul_in) begin
                    // Assert start every cycle wr_en're waiting - the ALU has a
                    // (mul_start_i && !mul_done_o) guard that prevents a
                    // ghost restart on the completion cycle, so this is safe.
                    mul_start_out = 1'b1;

                    // HOLD flags_wr_en_o high for the ENTIRE multiply.
                    //
                    // Rationale: the ALU only writes PSR on its mul_last_cyc
                    // edge (see alu.v). That edge is the SAME edge that
                    // clears mul_busy_q and pulses mul_done_o - i.e. it
                    // happens BEFORE the FSM observes mul_done_i=1 one
                    // cycle later. So if flags_wr_en_o wr_enre only raised on the
                    // mul_done_i cycle the gate would already be closed by
                    // the time the PSR write fired, and Z/N would silently
                    // stay at their previous value (contradicting spec 3.2).
                    // Holding the gate open across every multiplier cycle
                    // costs nothing (the ALU only actually writes PSR on
                    // one specific cycle) and puts the write in the clear.
                    flags_wr_en_out = 1'b1;

                    if (mul_done_in)
                        next_state = S_WB;
                end
                else if (stack_fault_in) begin
                    // CALL/RET cannot complete: do not write the PC.
                    next_state = S_HALT;
                end
                else if (is_load_in || is_store_in) begin
                    // Two-phase handshake: assert mem_req_o and wait until
                    // the cache actually latches it (mem_ready_i level).
                    // Once accepted, transition to S_MEM where mem_req_o is
                    // deasserted so the cache does not re-latch a duplicate.
                    mem_req_out = 1'b1;
                    mem_wr_en_out  = is_store_in;
                    if (mem_ready_in)
                        next_state = S_MEM;
                end
                else begin
                    // Pure ALU op: PSR updates this cycle via flags_wr_en_o
                    // gate; the ALU already registered its result last
                    // cycle, so S_WB just clocks the RF and PC.
                    flags_wr_en_out = 1'b1;
                    next_state    = S_WB;
                end
            end

            //---------------------------------------------------------
            S_MEM: begin
                // Request already accepted in S_EXEC; do NOT re-assert
                // mem_req_o - that was the source of the duplicate-issue
                // bug in the previous revision.
                //
                // Simply wait for the completion pulse.
                if (mem_done_in)
                    next_state = S_WB;
            end

            //---------------------------------------------------------
            S_WB: begin
                reg_wr_en_out = 1'b1;   // gated by decoder.wr_rd_o at the top level
                pc_wr_en_out  = 1'b1;   // branch_unit picks target vs pc+1
                next_state  = S_FETCH;
            end

            //---------------------------------------------------------
            S_HALT: begin
                next_state = S_HALT;   // parked; needs external reset to leave
            end

            default: next_state = S_FETCH;

        endcase
    end

endmodule

`default_nettype wire

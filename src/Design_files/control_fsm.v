`default_nettype none
// control_fsm.v
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

    // States
    localparam [2:0] FETCH  = 3'd0,
                     DECODE = 3'd1,
                     EXEC   = 3'd2,
                     MEM    = 3'd3,   // request already accepted; waiting for mem_done_i
                     WB     = 3'd4,
                     HALT   = 3'd5;

    reg [2:0] current_state, next_state;

    assign halted_out  = (current_state == HALT);
    assign illegal_out = illegal_in;

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n) current_state <= FETCH;
        else            current_state <= next_state;
    end

    // Next-state + output logic
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
            FETCH: begin
                imem_req_out = 1'b1;
                if (imem_rd_data_vld_in) begin
                    ir_wr_en_out = 1'b1;
                    next_state = DECODE;
                end
            end

            DECODE: begin
                // decoder is combinational module
                next_state = EXEC;
            end

            EXEC: begin
                if (illegal_in || unimpl_in) begin
                    next_state = HALT;    // visible stop instead of silently
                end                     
                else if (is_halt_in) begin
                    next_state = HALT;
                end
                else if (is_mul_in) begin
                    mul_start_out = 1'b1;
                    flags_wr_en_out = 1'b1;

                    if (mul_done_in)
                        next_state = WB;
                end
                else if (stack_fault_in) begin
                    next_state = HALT;
                end
                else if (is_load_in || is_store_in) begin
                    mem_req_out = 1'b1;
                    mem_wr_en_out  = is_store_in;
                    if (mem_ready_in)
                        next_state = MEM;
                end
                else begin
                    flags_wr_en_out = 1'b1;
                    next_state    = WB;
                end
            end

            
            MEM: begin
                if (mem_done_in)
                    next_state = WB;
            end

            
            WB: begin
                reg_wr_en_out = 1'b1;   // gated by decoder.wr_rd_o at the top level
                pc_wr_en_out  = 1'b1;   // branch_unit picks target vs pc+1
                next_state  = FETCH;
            end

            
            HALT: begin
                next_state = HALT;   // parked; needs external reset to leave
            end

            default: next_state = FETCH;

        endcase
    end

endmodule
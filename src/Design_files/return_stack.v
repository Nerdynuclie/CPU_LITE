// stack for CALL / RET.
// DEPTH entries of PC_WIDTH. DEPTH must be a power of two.
// sp counts occupied entries (0 = empty, DEPTH = full).
// top_out is the newest return address and is valid while !empty.
// Push and pop are mutually exclusive; both are ignored when they
// would overflow or underflow.

`default_nettype none

module return_stack #(
    parameter PC_WIDTH = 12,
    parameter DEPTH    = 16,
    parameter SP_WIDTH     = 5
) (
    input  wire                     clk_cpu,
    input  wire                     rst_cpu_n,

    input  wire                     push_en_in,
    input  wire                     pop_en_in,
    input  wire [PC_WIDTH-1:0]      push_data_in,

    output wire [PC_WIDTH-1:0]      top_out,
    output wire                     empty_out,
    output wire                     full_out
);

    reg [PC_WIDTH-1:0] mem [0:DEPTH-1];
    reg [SP_WIDTH-1:0]     sp_reg;

    integer i;

    assign empty_out = (sp_reg == {SP_WIDTH{1'b0}});
    assign full_out  = (sp_reg == DEPTH);
    // Entry index is SP_WIDTH-1 bits. When the stack is full, sp_reg == DEPTH
    // and the low bits are 0, so subtracting 1 wraps to the last entry.
    assign top_out   = mem[sp_reg[SP_WIDTH-2:0] - 1'b1];

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n) begin
            sp_reg <= {SP_WIDTH{1'b0}};
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {PC_WIDTH{1'b0}};
        end
        else if (push_en_in && !full_out) begin
            mem[sp_reg[SP_WIDTH-2:0]] <= push_data_in;
            sp_reg <= sp_reg + 1'b1;
        end
        else if (pop_en_in && !empty_out) begin
            sp_reg <= sp_reg - 1'b1;
        end
    end

endmodule

`default_nettype wire

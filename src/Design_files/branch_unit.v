//branch statement executer

`default_nettype none

module branch_unit #(
    parameter PC_WIDTH = 12
)(
    input   wire [3:0]          branch_type_in,
    input   wire [3:0]          psr_i,
    input   wire [31:0]         rs1_data_in,        //for JMP_IF/ JMP_REG

    input   wire [PC_WIDTH-1:0] branch_target_in,
    input   wire [PC_WIDTH-1:0] pc_plus1_in,
    input   wire [PC_WIDTH-1:0] ret_addr_in,        // return-stack top, for RET

    output  reg [PC_WIDTH-1:0]  next_pc_out
);

    reg branch_taken;

    localparam [3:0] BR_NONE    = 4'd0;
    localparam [3:0] BR_JMP     = 4'd1;
    localparam [3:0] BR_JMP_IF  = 4'd2;
    localparam [3:0] BR_BEQ     = 4'd3;
    localparam [3:0] BR_BNE     = 4'd4;
    localparam [3:0] BR_BLT     = 4'd5;
    localparam [3:0] BR_BGE     = 4'd6;
    localparam [3:0] BR_BLTU    = 4'd7;
    localparam [3:0] BR_BGEU    = 4'd8;
    localparam [3:0] BR_JMP_REG = 4'd9;
    localparam [3:0] BR_CALL    = 4'd10;
    localparam [3:0] BR_RET     = 4'd11;

    //flags
    localparam Z = 0;
    localparam N = 1;
    localparam C = 2;
    localparam V = 3;

    wire rs1_nonzero = |rs1_data_in;

    //branch conditions

    always @ (*) begin
        case (branch_type_in)
            BR_NONE:    branch_taken = 1'b0;
            BR_JMP:     branch_taken = 1'b1;
            BR_JMP_IF:  branch_taken = rs1_nonzero;
            BR_BEQ:     branch_taken = psr_i[Z];
            BR_BNE:     branch_taken = ~psr_i[Z];
            BR_BLT:     branch_taken = psr_i[N] ^ psr_i[V];
            BR_BGE:     branch_taken = ~(psr_i[N] ^ psr_i[V]);
            BR_BLTU:    branch_taken = ~psr_i[C];
            BR_BGEU:    branch_taken = psr_i[C];
            BR_JMP_REG: branch_taken = 1'b1;
            BR_CALL:    branch_taken = 1'b1;
            BR_RET:     branch_taken = 1'b1;
            default:    branch_taken = 1'b0;
        endcase
    end

    //next pc select
    always @(*) begin
        if(branch_taken) begin
                if(branch_type_in == BR_JMP_REG)
                    next_pc_out = rs1_data_in [PC_WIDTH-1:0];
                else if(branch_type_in == BR_RET)
                    next_pc_out = ret_addr_in;
                else
                    next_pc_out = branch_target_in;
        end    

        else begin
            next_pc_out = pc_plus1_in;
        end
    end
endmodule
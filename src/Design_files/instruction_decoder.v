//instruction decoder
`default_nettype none
module instruction_decoder #(
    parameter inst_width = 32
) (
    input  wire [inst_width-1:0]  inst_in,

    output wire [7:0]   opcode_out,
    output wire [3:0]   rd_out,
    output wire [3:0]   rs1_out,
    output wire [3:0]   rs2_out,
    output wire [11:0]  imm_out,

    //register file control signals
    output reg          ra1_is_rd_out,    //read control 1:read port A addr =rd 0:read port A addr rs1
    output reg          wr_rd_out,        //write control 1: write enable
    output reg [1:0]    wb_sel_out,       //00-ALU result, 01- load data, 10 - imm_ext

    //ALU Cntrl signals
    output reg [3:0]    alu_op_out,
    output reg          op_b_is_imm_out,  //if 1 OPB is IMM
    output reg [1:0]    imm_mode_out,     //i/p to imm_gen 00-zero ext 01 - sign_ext 10 - imm_ext
    output reg [3:0]    flag_we_mask_out, //{V, C, N, Z} Pre flag write enable for flag
    //multiply
    output reg          is_mul_out,

    //Load and Store cntrl
    output reg          is_load_out,
    output reg          is_store_out,
    output reg [1:0]    addr_sel_out,   //00-direct addr(IMM), 01- RS1, 10- RS2

    //branch flow
    output reg [3:0]    branch_type_out,
    output reg          is_call_out,
    output reg          is_ret_out,

    //halt and not implemebted CMD or illegal signals 
    output reg          is_nop_out,
    output reg          is_halt_out,
    output reg          illegal_out,    //opcode which are not defined
    output reg          is_unimpl_out  //opcode which are not yet implemented

);

//OPCODES
    localparam [7:0] OP_NOP       = 8'h00;
    localparam [7:0] OP_LOAD      = 8'h01;
    localparam [7:0] OP_LOAD_IND  = 8'h02;
    localparam [7:0] OP_LOAD_IMM  = 8'h03;
    localparam [7:0] OP_STORE     = 8'h04;
    localparam [7:0] OP_STORE_IND = 8'h05;
    localparam [7:0] OP_ADD       = 8'h06;
    localparam [7:0] OP_SUB       = 8'h07;
    localparam [7:0] OP_MUL       = 8'h08;
    localparam [7:0] OP_AND       = 8'h09;
    localparam [7:0] OP_OR        = 8'h0A;
    localparam [7:0] OP_NOT       = 8'h0B;
    localparam [7:0] OP_CMP       = 8'h0C;
    localparam [7:0] OP_EQ        = 8'h0D;
    localparam [7:0] OP_JMP       = 8'h0E;
    localparam [7:0] OP_JMP_IF    = 8'h0F;
    localparam [7:0] OP_XOR       = 8'h10;
    localparam [7:0] OP_SHL       = 8'h11;
    localparam [7:0] OP_SHR       = 8'h12;
    localparam [7:0] OP_SAR       = 8'h13;
    localparam [7:0] OP_ROL       = 8'h14;
    localparam [7:0] OP_ROR       = 8'h15;
    localparam [7:0] OP_ADDI      = 8'h16;
    localparam [7:0] OP_SUBI      = 8'h17;
    localparam [7:0] OP_ANDI      = 8'h18;
    localparam [7:0] OP_ORI       = 8'h19;
    localparam [7:0] OP_XORI      = 8'h1A;
    localparam [7:0] OP_MOV       = 8'h1B;
    localparam [7:0] OP_SLT       = 8'h1C;
    localparam [7:0] OP_SLTU      = 8'h1D;
    localparam [7:0] OP_LUI       = 8'h1E;
    localparam [7:0] OP_BEQ       = 8'h20;
    localparam [7:0] OP_BNE       = 8'h21;
    localparam [7:0] OP_BLT       = 8'h22;
    localparam [7:0] OP_BGE       = 8'h23;
    localparam [7:0] OP_BLTU      = 8'h24;
    localparam [7:0] OP_BGEU      = 8'h25;
    localparam [7:0] OP_JMP_REG   = 8'h26;
    localparam [7:0] OP_CALL      = 8'h27;
    localparam [7:0] OP_RET       = 8'h28;
    localparam [7:0] OP_HALT      = 8'hFF;

//ALU OPCODES
    localparam [3:0] ALU_ADD  = 4'd0;
    localparam [3:0] ALU_SUB  = 4'd1;   // also used for CMP
    localparam [3:0] ALU_AND  = 4'd2;
    localparam [3:0] ALU_OR   = 4'd3;
    localparam [3:0] ALU_XOR  = 4'd4;
    localparam [3:0] ALU_NOT  = 4'd5;
    localparam [3:0] ALU_SHL  = 4'd6;
    localparam [3:0] ALU_SHR  = 4'd7;
    localparam [3:0] ALU_SAR  = 4'd8;
    localparam [3:0] ALU_ROL  = 4'd9;
    localparam [3:0] ALU_ROR  = 4'd10;
    localparam [3:0] ALU_EQ   = 4'd11;
    localparam [3:0] ALU_SLT  = 4'd12;
    localparam [3:0] ALU_SLTU = 4'd13;
    localparam [3:0] ALU_MOV  = 4'd14;  // Rd <- Rs1 (MOV)
    localparam [3:0] ALU_MUL  = 4'd15;

//Branch/Jump Types
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


//Extracting the Instruction and Separating it

    assign opcode_out   = inst_in [31:24];      //first 8 bits of inst are opcode (from MSB)
    assign rd_out       = inst_in [23:20];      //Destination regitsers store the alu result and in store operation the value in rd is stored in reg file
    assign rs1_out      = inst_in [19:16];      //OP A
    assign rs2_out      = inst_in [15:12];      //OP B
    assign imm_out      = inst_in [11:0];       //IMM

//decoder
    always @ (*) begin
        //Default values
        ra1_is_rd_out       = 1'b0;
        alu_op_out          = ALU_ADD;
        op_b_is_imm_out     = 1'b0;
        imm_mode_out        = 2'b00;
        flag_we_mask_out    = 4'd0;
        wr_rd_out           = 1'b0;
        wb_sel_out          = 2'b00;
        is_load_out         = 1'b0;
        is_store_out        = 1'b0;
        addr_sel_out        = 2'b00;
        is_unimpl_out       = 1'b0;
        branch_type_out     = BR_NONE;
        is_call_out         = 1'b0;
        is_ret_out          = 1'b0;
        is_nop_out          = 1'b0;
        is_halt_out         = 1'b0;
        illegal_out         = 1'b0;
        is_unimpl_out       = 1'b0;
        is_mul_out          = 1'b0;

        case (opcode_out) 
            OP_NOP:begin
                is_nop_out = 1'b1;
            end

            OP_LOAD:begin
                is_load_out  = 1'b1;
                addr_sel_out = 2'b00;      // direct ADDR
                wr_rd_out    = 1'b1;
                wb_sel_out   = 2'b01;      // load data
            end

            OP_LOAD_IMM:begin
                wr_rd_out    = 1'b1;
                wb_sel_out   = 2'b10;      // immediate path
                imm_mode_out = 2'b00;      // zero-extend               
            end

            OP_LOAD_IND:begin
                is_load_out     = 1'b1;
                addr_sel_out    = 2'b01;      // Rs1
                wr_rd_out       = 1'b1;
                wb_sel_out      = 2'b01;
            end

            OP_STORE: begin
                is_store_out        = 1'b1;
                addr_sel_out        = 2'b00;
                ra1_is_rd_out       = 1'b1;        //READ PORT A
            end

            OP_STORE_IND:begin
                is_store_out        = 1'b1;
                addr_sel_out        = 2'b10;        //read port A = RS1
                ra1_is_rd_out       = 1'b1;
            end

            OP_ADD:begin
                alu_op_out          = ALU_ADD;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b1111;
            end

            OP_SUB:begin
                alu_op_out          = ALU_SUB;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_MUL:begin
                alu_op_out          = ALU_MUL;
                is_mul_out          = 1'b1;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_AND: begin
                alu_op_out          = ALU_AND;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_OR:begin
                alu_op_out          = ALU_OR;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_NOT:begin
                alu_op_out          = ALU_NOT;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_CMP:begin
                alu_op_out          = ALU_SUB;
                flag_we_mask_out    = 4'b1111;
            end

            OP_EQ:begin
                alu_op_out          = ALU_EQ;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0001; //Z only
            end

            OP_JMP:begin
                branch_type_out = BR_JMP;
            end

            OP_JMP_IF:begin
                branch_type_out = BR_JMP_IF;
            end

            OP_XOR:begin
                alu_op_out          = ALU_XOR;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_SHL:begin
                alu_op_out          = ALU_SHL;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;                
            end

            OP_SHR:begin
                alu_op_out          = ALU_SHR;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;            
            end

            OP_SAR:begin
                alu_op_out          = ALU_SAR;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_ROL:begin
                alu_op_out          = ALU_ROL;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;               
            end

            OP_ROR: begin
                alu_op_out          = ALU_ROR;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_ADDI: begin
                alu_op_out          = ALU_ADD;
                op_b_is_imm_out     = 1'b1;
                imm_mode_out        = 2'b01;        //SIGN EXT
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_SUBI:begin
                alu_op_out          = ALU_SUB;
                op_b_is_imm_out     = 1'b1;
                imm_mode_out        = 2'b01;        //SIGN EXT
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_ANDI: begin
                alu_op_out          = ALU_AND;
                op_b_is_imm_out     = 1'b1;
                imm_mode_out        = 2'b00;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;                     
            end

            OP_ORI: begin
                alu_op_out          = ALU_OR;
                op_b_is_imm_out     = 1'b1;
                imm_mode_out        = 2'b00;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;     
            end

            OP_XORI: begin
                alu_op_out          = ALU_XOR;
                op_b_is_imm_out     = 1'b1;
                imm_mode_out        = 2'b00;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0011;
            end

            OP_MOV: begin
                alu_op_out  = ALU_MOV;
                wr_rd_out   = 1'b1;
            end

            OP_SLT: begin
                alu_op_out          = ALU_SLT;
                wr_rd_out           = 1'b1;
                flag_we_mask_out    = 4'b0001;
            end

            OP_SLTU: begin
                alu_op_out          = ALU_SLTU;
                wr_rd_out           = 1'b1;     //reg write en
                flag_we_mask_out    = 4'b0001;  //enable zero flag signal updation
            end

            OP_LUI: begin   //limit upper immediate
                wr_rd_out       = 1'b1;   //reg write enable 
                wb_sel_out      = 2'b10;  //immediate Value
                imm_mode_out    = 2'b10;  //LUI mode
            end

            OP_BEQ: begin
                branch_type_out = BR_BEQ;
            end

            OP_BNE: begin
                branch_type_out = BR_BNE;
            end

            OP_BLT: begin
                branch_type_out = BR_BLT;
            end

            OP_BGE: begin
                branch_type_out = BR_BGE;
            end

            OP_BLTU: begin
                branch_type_out = BR_BLTU;
            end

            OP_BGEU: begin
                branch_type_out = BR_BGEU;
            end
            
            OP_JMP_REG: begin
                branch_type_out = BR_JMP_REG;
            end
            // CALL imm: push PC+1, PC = imm
            OP_CALL: begin
                branch_type_out = BR_CALL;
                is_call_out     = 1'b1;
            end

            // RET: PC = pop(return stack)
            OP_RET: begin
                branch_type_out = BR_RET;
                is_ret_out      = 1'b1;
            end

            OP_HALT: begin
                is_halt_out = 1'b1;
            end

            default: begin
                illegal_out = 1'b1;
            end
        endcase

    end

endmodule
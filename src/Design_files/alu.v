//alu unit

`default_nettype none

module alu (
    input  wire         clk_cpu,
    input  wire         rst_cpu_n,

    //OPERANDS
    input  wire [31:0]  A,
    input  wire [31:0]  B,

    //OPERATOR
    input  wire [3:0]   alu_op_in,  //ALU OPCODE from decoder

    //Flag enable signal
    input  wire [3:0]   flag_we_mask_in,

    //Multiplication
    input  wire         mul_start_in,       //one cycle enable signal from control fsm
    output reg          mul_done_out,       //one cycle done flag for control fsm
    
    //flags  PSR [0]-->Z [1] --->N (result[31]) [2]--> C (carry)  [3]--> V (overflow)
    output reg [3:0]    PSR,                //Program status register (FLAG)

    //ALU result
    output reg [31:0]   alu_result
);

//opcode
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
    
//COMBINATIONAL BLOCKS FOR ONE CYCLE OPERATIONS

    wire [32:0] add_33bit = {1'b0, A} + {1'b0, B};       //ADDITION
    wire [32:0] sub_33bit = {1'b0, A} + {1'b0, ~B} + 33'd1; //Subtraction


//overflow logic
    wire add_v = (A[31] == B[31]) && (add_33bit[31] != A[31]);  //Signed overflow happens when i/p have same sign but o/p doesnt match the i/p sign
    wire sub_v = (A[31] != B[31]) && (sub_33bit[31] != A[31]);  //vuce versa

//shift operation
    wire [4:0] shift_amt     = B[4:0];
    wire [5:0] inv_shift_sum = 6'd32 - {1'b0, shift_amt};
    wire [4:0] inv_shift_amt = inv_shift_sum[4:0];
    wire [31:0] shl_res = A << shift_amt;
    wire [31:0] shr_res = A >> shift_amt;
    wire [31:0] sar_res = $signed(A) >>> shift_amt;
    wire [31:0] rol_res = (A << shift_amt) | (A >> inv_shift_amt);
    wire [31:0] ror_res = (A >> shift_amt) | (A << inv_shift_amt);

//logical operation
    wire [31:0] and_res = A & B;
    wire [31:0] or_res  = A | B;
    wire [31:0] not_res = ~ A;
    wire [31:0] xor_res = A ^ B;

//comparator (EQ, SLT (A<B)(signed), SLTU (A<B)(unsignes) )
    wire        eq_bool     = (A == B);
    wire signed [31:0] As   = A;
    wire signed [31:0] Bs   = B;
    //signed comparision
    wire        slt_bool    = (As < Bs);
    //unsigned comparision
    wire        sltu_bool   = (A < B);

//Multiplication 
    reg         mul_busy_reg;
    reg [31:0]  mcand_reg;      //copies OP A
    reg [31:0]  mplier_reg;     //copies OP B

    wire [31:0] mul_res         = mcand_reg * mplier_reg;

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if(!rst_cpu_n) begin
            PSR         <= 4'd0;
            alu_result  <= 32'd0;
            mul_busy_reg  <= 1'b0;
            mcand_reg     <= 32'd0;
            mplier_reg    <= 32'd0;
            mul_done_out  <= 1'b0;
        end

        else begin
            mul_done_out <= 1'b0;
            //initailizing all multiplication registers
            if (mul_start_in && !mul_busy_reg && !mul_done_out) begin
                mcand_reg     <= A;
                mplier_reg    <= B;
                mul_busy_reg  <= 1'b1;
                
            end

            else if(mul_busy_reg) begin
                mul_busy_reg <= 1'b0;
                mul_done_out <= 1'b1;
                alu_result   <= mul_res;
                if(flag_we_mask_in[0])
                    PSR[0]  <= (mul_res == 32'd0);
                if(flag_we_mask_in[1])
                    PSR[1]  <= mul_res[31];
            end

            //other ALU operation assigning to o/p ports 
            else begin
                case (alu_op_in)

                    ALU_ADD: begin
                        alu_result  <= add_33bit[31:0];
                        if (flag_we_mask_in[0]) PSR[0] <= (add_33bit[31:0] == 32'd0);    // Z
                        if (flag_we_mask_in[1]) PSR[1] <= add_33bit[31];                 // N
                        if (flag_we_mask_in[2]) PSR[2] <= add_33bit[32];                 // C (carry-out)
                        if (flag_we_mask_in[3]) PSR[3] <= add_v;                         // V
                    end
                    ALU_SUB: begin
                        alu_result  <= sub_33bit[31:0];
                        if (flag_we_mask_in[0]) PSR[0] <= (sub_33bit[31:0] == 32'd0);    // Z
                        if (flag_we_mask_in[1]) PSR[1] <= sub_33bit[31];                 // N
                        if (flag_we_mask_in[2]) PSR[2] <= sub_33bit[32];                 // C (carry-out)
                        if (flag_we_mask_in[3]) PSR[3] <= sub_v;                         // V
                    end
                    ALU_OR: begin
                        alu_result <= or_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (or_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= or_res[31];
                    end
                    ALU_AND: begin
                        alu_result <= and_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (and_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= and_res[31];
                    end

                    ALU_XOR: begin
                        alu_result <= xor_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (xor_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= xor_res[31];
                    end

                    ALU_NOT: begin
                        alu_result <= not_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (not_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= not_res[31];
                    end

                    ALU_SHL: begin
                        alu_result <= shl_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (shl_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= shl_res[31];
                    end

                    ALU_SHR: begin
                        alu_result <= shr_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (shr_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= shr_res[31];
                    end

                    ALU_SAR: begin
                        alu_result <= sar_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (sar_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= sar_res[31];
                    end

                    ALU_ROL: begin
                        alu_result <= rol_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (rol_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= rol_res[31];
                    end

                    ALU_ROR: begin
                        alu_result <= ror_res;
                        if  (flag_we_mask_in[0]) PSR [0] <= (ror_res == 32'd0);
                        if  (flag_we_mask_in[1]) PSR [1] <= ror_res[31];
                    end

                    ALU_EQ: begin
                        alu_result <= eq_bool ? 32'd1 : 32'd0;
                        if (flag_we_mask_in[0]) PSR [0] <= ~eq_bool;
                    end

                    ALU_SLT: begin
                        alu_result <= slt_bool ? 32'd1 : 32'd0;
                        if (flag_we_mask_in [0]) PSR [0] <= ~slt_bool;
                    end

                    ALU_SLTU: begin
                        alu_result <= sltu_bool ? 32'd1 : 32'd0;
                        if (flag_we_mask_in [0]) PSR[0] <= ~sltu_bool;
                    end

                    ALU_MOV: begin
                        alu_result <= A;
                    end

                    default: begin
                        
                    end
                endcase
            end
        end
    end
endmodule
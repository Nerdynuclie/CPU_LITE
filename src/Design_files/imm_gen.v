//immediate vlaue formating
//zero extended, sign_extended, LUI - load upper immediate

`default_nettype none
module imm_gen
#(
    parameter PC_WIDTH = 12
)
(
    input  wire [11:0]          imm_in,
    input  wire [1:0]           imm_mode_in,

    output reg  [31:0]          imm_ext_out,
    output wire [PC_WIDTH-1:0]  branch_target_out
);
    localparam ZERO_EXT = 2'b00;
    localparam SIGN_EXT = 2'b01;
    localparam LUI      = 2'b10;

    always @ (*) begin
        case(imm_mode_in)
        ZERO_EXT:begin
            imm_ext_out = {20'd0, imm_in};              //normal immediate value extended with zeros
        end

        SIGN_EXT: begin
            imm_ext_out = {{20{imm_in[11]}}, imm_in};    //extended sign 
        end

        LUI: begin
            imm_ext_out = {imm_in,20'd0};                //IMMEDIATE In MSB
        end

        default: begin
            imm_ext_out = {20'd0 , imm_in};
        end
        endcase
    end

    assign branch_target_out = imm_in[PC_WIDTH-1:0];

endmodule
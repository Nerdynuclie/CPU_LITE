//address generator for load/store to access l1_cache or data memory 
`default_nettype none
module addr_gen
#(
    parameter ADDR_WIDTH = 14
)
(
    input  wire [1:0]               addr_sel_in,     //00-Direct addr, 01- RS1 , 10 - Rs2
    input  wire [11:0]              imm_in,
    input  wire [ADDR_WIDTH-1:0]    rs1_data_in,
    input  wire [ADDR_WIDTH-1:0]    rs2_data_in,

    output reg [ADDR_WIDTH-1:0]     mem_addr_out
);

localparam ADDR_DIRECT  = 2'b00;
localparam ADDR_RS1     = 2'b01;
localparam ADDR_RS2     = 2'b10;

always @ (*) begin
    case(addr_sel_in)
        ADDR_DIRECT: begin
            mem_addr_out = {{(ADDR_WIDTH-4'd12){1'b0}},imm_in}; //padding with zero for rest of the bits
        end

        ADDR_RS1: begin
            mem_addr_out = rs1_data_in;
        end

        ADDR_RS2: begin
            mem_addr_out = rs2_data_in;
        end
        
        default: begin
            mem_addr_out = {{(ADDR_WIDTH-4'd12){1'b0}},imm_in};
        end
    endcase
end
endmodule
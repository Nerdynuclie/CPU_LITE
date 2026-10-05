//program counter module
`default_nettype none
module pc_unit
# (
    parameter PC_WIDTH = 12    //4096 Program memory 
)
(
    input  wire                 cpu_clk,
    input  wire                 rst_cpu_n,

    input  wire                 pc_en_in,        //Enable signal from control unit
    input  wire [PC_WIDTH-1:0]  next_pc_in,        //next PC value from branch unit

    output wire [PC_WIDTH-1:0]  pc_out,
    output wire [PC_WIDTH-1:0]  pc_plus1_out    //fed to branch unit 
);

reg [PC_WIDTH-1:0]  pc_q;   //registers next pc value given from branch unit

always @(posedge cpu_clk or negedge rst_cpu_n) begin
    if(!rst_cpu_n) begin
        pc_q <= {PC_WIDTH{1'b0}};
    end
    else if (pc_en_in) begin
        pc_q <= next_pc_in;
    end
end

//assigning new pc 
assign pc_out       = pc_q;
assign pc_plus1_out = pc_q + 1'b1;

endmodule
//register bank 16 register of 32 bit each
`default_nettype none

module reg_file #(
    parameter DATA_WIDTH    = 32,
    parameter ADDR_WIDTH    = 4,
    parameter DEPTH         = 16
) (
    input  wire             clk_cpu,
    input  wire             rst_cpu_n,

    //READ PORT A
    input  wire  [ADDR_WIDTH-1:0] ra_a,     //Read address for PORT A
    output wire  [DATA_WIDTH-1:0] rd_a,     // Data O/P from PORT A

    //READ PORT B
    input  wire [ADDR_WIDTH-1:0]  ra_b,     //Read address for PORT B
    output wire [DATA_WIDTH-1:0]  rd_b,     //Data O/P From PORT B

    //Write Port
    input  wire                   wr_en,       //write enable
    input  wire [ADDR_WIDTH-1:0]  w_addr,   //write address
    input  wire [DATA_WIDTH-1:0]  w_data    //write data

);

    reg [DATA_WIDTH-1:0]  reg_mem [0:DEPTH-1];

    integer  i;
    always @ (posedge clk_cpu or negedge rst_cpu_n) begin
        if(!rst_cpu_n) begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                reg_mem[i] <= {DATA_WIDTH{1'b0}};
            end
        end

        else if(wr_en) begin
            reg_mem[w_addr] <= w_data;
        end
    end
    //assigning the o/p data for read/load
    assign rd_a  = reg_mem[ra_a];
    assign rd_b  = reg_mem[ra_b];

endmodule
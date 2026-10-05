//data memory of 16K x 32 sync ,single port 
//interface
//-addr_in - Word_Address 14-bit word index (0-->16383)
//-req_in  - starts Transcation
//wr_en_in    - selects raed (0) or write (1)
//read latency - 1cycle rdata_vld_out pulses after one cycle aftera a read req_in
//write is done in one cycle
module data_memory
#(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 14,
    parameter DEPTH      = (1 << ADDR_WIDTH)    //16384
)
(
    input  wire                     clk_mem,
    input  wire                     rst_mem_n,

    input  wire                     req_in,
    input  wire                     wr_en_in,
    input  wire [ADDR_WIDTH-1:0]    addr_in,
    input  wire [DATA_WIDTH-1:0]    wr_data_in,

    output reg  [DATA_WIDTH-1:0]    rd_data_out,
    output reg                      rd_data_vld_out
);

reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

//read valid output logic
always @(posedge clk_mem or negedge rst_mem_n) begin
    if(!rst_mem_n) begin
        rd_data_vld_out <= 1'b0;
    end
    else begin
        rd_data_vld_out <= (req_in && !wr_en_in);
    end
end

//BRAM + raed_reg no reset
always @(posedge clk_mem ) begin
    if(req_in) begin
        if(wr_en_in) begin
            mem[addr_in] <= wr_data_in;
        end
        else begin
            rd_data_out <= mem[addr_in];
        end
    end
end

integer k;
initial begin
    for (k = 0; k < DEPTH; k = k + 1)
        mem[k] = {DATA_WIDTH{1'b0}};
    for (k = 0; k < 10; k = k + 1)
        mem[14'h100 + k] = k + 1;
end
endmodule

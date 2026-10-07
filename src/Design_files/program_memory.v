// Program memory, 4K x 32, synchronous read.
// Contents are written by the testbench through dut.u_program_memory.mem[].
// Read latency is one clk_cpu cycle: data and valid are registered on the
// edge after imem_req_in is seen.

module program_memory #(
    parameter PC_WIDTH = 12,
    parameter DEPTH    = (1 << PC_WIDTH)
) (
    input  wire                 clk_cpu,
    input  wire                 rst_cpu_n,

    input  wire [PC_WIDTH-1:0]  imem_addr_in,           //from pc unit
    input  wire                 imem_req_in,            //from control fsm 
    output reg  [31:0]          imem_rd_data_out,       //to instruction decoder
    output reg                  imem_rd_data_vld_out    //to control fsm 
);

    reg [31:0] mem [0:DEPTH-1];

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n) begin
            imem_rd_data_out     <= 32'h0000_0000;
            imem_rd_data_vld_out <= 1'b0;
        end
        else begin
            imem_rd_data_vld_out <= imem_req_in;
            if (imem_req_in)
                imem_rd_data_out <= mem[imem_addr_in];
        end
    end

endmodule

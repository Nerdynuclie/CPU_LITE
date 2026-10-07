module cpu_top #(
    parameter PC_WIDTH           = 12,
    parameter DMEM_ADDR_WIDTH    = 14,
    parameter DATA_WIDTH         = 32,
    parameter NUM_LINES          = 10,
    parameter WORDS_PER_LINE     = 4,
    parameter TX_FIFO_DEPTH_LOG2 = 3,
    parameter RX_FIFO_DEPTH_LOG2 = 3
) (
    input  wire                         clk_cpu,
    input  wire                         rst_cpu_n,
    input  wire                         clk_mem,
    input  wire                         rst_mem_n,
    output wire                         halted_out,
    output wire                         illegal_out
);

    wire [DATA_WIDTH-1:0]               imem_rd_data;
    wire                                imem_rd_data_vld;
    wire                                imem_req;
    wire [PC_WIDTH-1:0]                 imem_addr;

    wire                                dmem_ready;
    wire [DATA_WIDTH-1:0]               dmem_rd_data;
    wire                                dmem_rd_data_valid;
    wire                                dmem_xact_done;
    wire                                dmem_req;
    wire                                dmem_wr_en;
    wire [DMEM_ADDR_WIDTH-1:0]          dmem_addr;
    wire [DATA_WIDTH-1:0]               dmem_wr_data;

    cpu_core #(
        .PC_WIDTH        (PC_WIDTH),
        .DMEM_ADDR_WIDTH (DMEM_ADDR_WIDTH)
    ) u_cpu_core (
        .clk_cpu               (clk_cpu),
        .rst_cpu_n             (rst_cpu_n),
        .imem_rd_data_in       (imem_rd_data),
        .imem_rd_data_vld_in   (imem_rd_data_vld),
        .imem_req_out          (imem_req),
        .imem_addr_out         (imem_addr),
        .dmem_ready_in         (dmem_ready),
        .dmem_rd_data_in       (dmem_rd_data),
        .dmem_rd_data_valid_in (dmem_rd_data_valid),
        .dmem_xact_done_in     (dmem_xact_done),
        .dmem_req_out          (dmem_req),
        .dmem_wr_en_out        (dmem_wr_en),
        .dmem_addr_out         (dmem_addr),
        .dmem_wr_data_out      (dmem_wr_data),
        .halted_out            (halted_out),
        .illegal_out           (illegal_out)
    );

    program_memory #(
        .PC_WIDTH (PC_WIDTH)
    ) u_program_memory (
        .clk_cpu              (clk_cpu),
        .rst_cpu_n            (rst_cpu_n),
        .imem_addr_in         (imem_addr),
        .imem_req_in          (imem_req),
        .imem_rd_data_out     (imem_rd_data),
        .imem_rd_data_vld_out (imem_rd_data_vld)
    );

    mem_subsys_top #(
        .DATA_WIDTH         (DATA_WIDTH),
        .ADDR_WIDTH         (DMEM_ADDR_WIDTH),
        .NUM_LINES          (NUM_LINES),
        .WORDS_PER_LINE     (WORDS_PER_LINE),
        .TX_FIFO_DEPTH_LOG2 (TX_FIFO_DEPTH_LOG2),
        .RX_FIFO_DEPTH_LOG2 (RX_FIFO_DEPTH_LOG2)
    ) u_mem_subsys (
        .clk_cpu         (clk_cpu),
        .rst_cpu_n       (rst_cpu_n),
        .req_in          (dmem_req),
        .wr_en_in        (dmem_wr_en),
        .addr_in         (dmem_addr),
        .wr_data_in      (dmem_wr_data),
        .ready_out       (dmem_ready),
        .rd_data_vld_out (dmem_rd_data_valid),
        .rd_data_out     (dmem_rd_data),
        .xact_done_out   (dmem_xact_done),
        .clk_mem         (clk_mem),
        .rst_mem_n       (rst_mem_n)
    );

endmodule

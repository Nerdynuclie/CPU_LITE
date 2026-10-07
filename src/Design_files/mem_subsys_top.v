//memory connections top
// l1_cache         (fast, clk_cpu)     -- direct_mapped L1
// cdc_bridge       (Both domain)       -- 2x async_fifo 
// mem_ctrl_slow    (slow, clk_mem)     -- SP RAM Controller
// data_mem         (slow, clk_mem)     -- 16K x 32 SP RAM

module mem_subsys_top
#(
    parameter DATA_WIDTH            = 32,
    parameter ADDR_WIDTH            = 14,
    parameter NUM_LINES             = 10,
    parameter WORDS_PER_LINE        = 4,
    parameter TX_FIFO_DEPTH_LOG2    = 3,
    parameter RX_FIFO_DEPTH_LOG2    = 3  
)
(
    //fast domain (clk_cpu)
    input  wire                     clk_cpu,
    input  wire                     rst_cpu_n,

    input  wire                     req_in,
    input  wire                     wr_en_in,
    input  wire [ADDR_WIDTH-1:0]    addr_in,
    input  wire [DATA_WIDTH-1:0]    wr_data_in,
    output wire                     ready_out,
    output wire                     rd_data_vld_out,
    output wire [DATA_WIDTH-1:0]    rd_data_out,
    output wire                     xact_done_out,


    //slow domain (clk_mem)
    input  wire                     clk_mem,
    input  wire                     rst_mem_n
);


//L1 Cache <--> cdc_bridge

wire                                cache_tx_fifo_push;
wire                                cache_tx_fifo_wr_en;
wire [ADDR_WIDTH-1:0]               cache_tx_fifo_addr;
wire [DATA_WIDTH-1:0]               cache_tx_fifo_wr_data;
wire                                cache_tx_fifo_full;

wire                                cache_rx_fifo_pop;
wire [DATA_WIDTH-1:0]               cache_rx_fifo_rd_data;
wire                                cache_rx_fifo_empty;

//cdc bridge <--> mem_ctrl_slow 
wire                                ctrl_tx_fifo_pop;
wire                                ctrl_tx_fifo_wr_en;
wire [DATA_WIDTH-1:0]               ctrl_tx_fifo_wr_data;
wire [ADDR_WIDTH-1:0]               ctrl_tx_fifo_addr;
wire                                ctrl_tx_fifo_empty;

wire                                ctrl_rx_fifo_push;
wire [DATA_WIDTH-1:0]               ctrl_rx_fifo_data;
wire                                ctrl_rx_fifo_full;

//mem_ctrl_slow <--> data_mem
wire                                mem_req;
wire                                mem_wr_en;
wire [ADDR_WIDTH-1:0]               mem_addr;
wire [DATA_WIDTH-1:0]               mem_wr_data;
wire                                mem_rd_vld;
wire [DATA_WIDTH-1:0]               mem_rd_data;

//L1 cache 
l1_cache #(
    .DATA_WIDTH     (DATA_WIDTH),
    .ADDR_WIDTH     (ADDR_WIDTH),
    .NUM_LINES      (NUM_LINES),
    .WORDS_PER_LINE (WORDS_PER_LINE)
)
u1_l1_cache(
    .clk_cpu                    (clk_cpu),
    .rst_cpu_n                  (rst_cpu_n),

    .req_in                     (req_in),
    .wr_en_in                   (wr_en_in),
    .addr_in                    (addr_in),
    .wr_data_in                 (wr_data_in),
    .ready_out                  (ready_out),
    .rd_data_vld_out            (rd_data_vld_out),
    .rd_data_out                (rd_data_out),
    .xact_done_out              (xact_done_out),

    .mem_tx_fifo_full_in        (cache_tx_fifo_full),
    .mem_tx_fifo_push_out       (cache_tx_fifo_push),
    .mem_tx_fifo_wr_en_out      (cache_tx_fifo_wr_en),
    .mem_tx_fifo_addr_out       (cache_tx_fifo_addr),
    .mem_tx_fifo_wr_data_out    (cache_tx_fifo_wr_data),

    .mem_rx_fifo_empty_in       (cache_rx_fifo_empty),
    .mem_rx_rd_data_in          (cache_rx_fifo_rd_data),
    .mem_rx_fifo_pop_out        (cache_rx_fifo_pop)
);


//cdc_bridge

cdc_bridge #(
    .ADDR_WIDTH         (ADDR_WIDTH),
    .DATA_WIDTH         (DATA_WIDTH),
    .TX_FIFO_DEPTH_LOG2 (TX_FIFO_DEPTH_LOG2),
    .RX_FIFO_DEPTH_LOG2 (RX_FIFO_DEPTH_LOG2)
)
u_cdc_bridge(
    .clk_cpu                (clk_cpu),
    .rst_cpu_n              (rst_cpu_n),

    .tx_fifo_push_in        (cache_tx_fifo_push),
    .tx_fifo_wr_en_in       (cache_tx_fifo_wr_en),
    .tx_fifo_addr_in        (cache_tx_fifo_addr),
    .tx_fifo_wr_data_in     (cache_tx_fifo_wr_data),
    .tx_fifo_full_out       (cache_tx_fifo_full),

    .rx_fifo_pop_in         (cache_rx_fifo_pop),
    .rx_fifo_rd_data_out    (cache_rx_fifo_rd_data),
    .rx_fifo_empty_out      (cache_rx_fifo_empty),

    .clk_mem                (clk_mem),
    .rst_mem_n              (rst_mem_n),

    .tx_fifo_pop_in         (ctrl_tx_fifo_pop),
    .tx_fifo_wr_en_out      (ctrl_tx_fifo_wr_en),
    .tx_fifo_addr_out       (ctrl_tx_fifo_addr),
    .tx_fifo_wr_data_out    (ctrl_tx_fifo_wr_data),
    .tx_fifo_empty_out      (ctrl_tx_fifo_empty),

    .rx_fifo_push_in        (ctrl_rx_fifo_push),
    .rx_fifo_rd_data_in     (ctrl_rx_fifo_data),
    .rx_fifo_full_out       (ctrl_rx_fifo_full)
);

//mem controler
data_mem_control #(
    .ADDR_WIDTH     (ADDR_WIDTH),
    .DATA_WIDTH     (DATA_WIDTH)
) u_data_mem_control (
    .clk_mem                (clk_mem),
    .rst_mem_n              (rst_mem_n),

    .tx_fifo_empty_in       (ctrl_tx_fifo_empty),
    .tx_fifo_wr_en_in       (ctrl_tx_fifo_wr_en),
    .tx_fifo_addr_in        (ctrl_tx_fifo_addr),
    .tx_fifo_wr_data_in          (ctrl_tx_fifo_wr_data),
    .tx_fifo_pop_out        (ctrl_tx_fifo_pop),

    .rx_fifo_full_in        (ctrl_rx_fifo_full),
    .rx_fifo_push_out       (ctrl_rx_fifo_push),
    .rx_fifo_data_out       (ctrl_rx_fifo_data),

    .mem_req_out            (mem_req),
    .mem_wr_en_out          (mem_wr_en),
    .mem_addr_out           (mem_addr),
    .mem_wr_data_out        (mem_wr_data),
    .mem_rd_data_in         (mem_rd_data),
    .mem_rd_vld_in          (mem_rd_vld)
);

//data memeory
data_memory   #(
    .DATA_WIDTH     (DATA_WIDTH),
    .ADDR_WIDTH     (ADDR_WIDTH)
) u_data_mem    (
    .clk_mem        (clk_mem),
    .rst_mem_n      (rst_mem_n),

    .req_in         (mem_req),
    .wr_en_in       (mem_wr_en),
    .addr_in        (mem_addr),
    .wr_data_in     (mem_wr_data),

    .rd_data_out        (mem_rd_data),
    .rd_data_vld_out    (mem_rd_vld)
);

endmodule
//cdc bridge is the module connecting data memory to cpu core 
//using two ff 
//tx fifo : fast -> slow (cache     --> data_mem)
//rx_fifo : slow -> fast (data_mem  --> cache)
//both fifo uses async_fifo.v

module cdc_bridge
#(
    parameter   ADDR_WIDTH              = 14,
    parameter   DATA_WIDTH              = 32,
    parameter   TX_FIFO_DEPTH_LOG2      = 3,
    parameter   RX_FIFO_DEPTH_LOG2      = 3
)(
    //cpu clk domain (fast clk domain)
    input  wire                     clk_cpu,
    input  wire                     rst_cpu_n,

    //cache --> bridge (push tx_FIFO)
    input  wire                     tx_fifo_push_in,
    input  wire                     tx_fifo_wr_en_in,
    input  wire [ADDR_WIDTH-1:0]    tx_fifo_addr_in,
    input  wire [DATA_WIDTH-1:0]    tx_fifo_wr_data_in,
    output wire                     tx_fifo_full_out,

    //bridge ---> cache (poP rx_fifo)
    input  wire                     rx_fifo_pop_in,
    output wire [DATA_WIDTH-1:0]    rx_fifo_rd_data_out,
    output wire                     rx_fifo_empty_out,

    //data mem domain (slow clk domain)
    input  wire                     clk_mem,
    input  wire                     rst_mem_n,

    //bridge --> data_mem (pop tx_fifo) 
    input  wire                      tx_fifo_pop_in,
    output wire                      tx_fifo_wr_en_out,
    output wire [ADDR_WIDTH-1:0]     tx_fifo_addr_out,
    output wire [DATA_WIDTH-1:0]     tx_fifo_wr_data_out,
    output wire                      tx_fifo_empty_out,

    //data_mem_control --> bridge (push rx_fifo)
    input  wire                     rx_fifo_push_in,
    input  wire [DATA_WIDTH-1:0]    rx_fifo_rd_data_in,
    output wire                     rx_fifo_full_out
);

localparam   TX_FIFO_WIDTH   = 1 + ADDR_WIDTH + DATA_WIDTH;
// Pack / unpack tx_fifo payload

wire [TX_FIFO_WIDTH-1:0]    tx_fifo_word_in;
wire [TX_FIFO_WIDTH-1:0]    tx_fifo_word_out;

assign tx_fifo_word_in      = { tx_fifo_wr_data_in , tx_fifo_addr_in , tx_fifo_wr_en_in};

assign tx_fifo_wr_en_out    = tx_fifo_word_out [0];
assign tx_fifo_addr_out     = tx_fifo_word_out [1+: ADDR_WIDTH];

assign tx_fifo_wr_data_out  = tx_fifo_word_out[1+ADDR_WIDTH +: DATA_WIDTH];

//TX FIFO
async_fifo #(
    .DATA_WIDTH     (TX_FIFO_WIDTH),
    .DEPTH_LOG2     (TX_FIFO_DEPTH_LOG2)
)
u_tx_fifo (
    .wr_clk         (clk_cpu),
    .wr_rst_n       (rst_cpu_n),
    .wr_en          (tx_fifo_push_in),
    .wr_data        (tx_fifo_word_in),
    .fifo_full      (tx_fifo_full_out),

    .rd_clk         (clk_mem),
    .rd_rst_n       (rst_mem_n),
    .rd_en          (tx_fifo_pop_in),
    .rd_data        (tx_fifo_word_out),
    .fifo_empty     (tx_fifo_empty_out)
);

//RX FIFO 
async_fifo #(
    .DATA_WIDTH     (DATA_WIDTH),
    .DEPTH_LOG2     (RX_FIFO_DEPTH_LOG2)
)
u_rx_fifo (
    .wr_clk         (clk_mem),
    .wr_rst_n       (rst_mem_n),
    .wr_en          (rx_fifo_push_in),
    .wr_data        (rx_fifo_rd_data_in),
    .fifo_full      (rx_fifo_full_out),

    .rd_clk         (clk_cpu),
    .rd_rst_n       (rst_cpu_n),
    .rd_en          (rx_fifo_pop_in),
    .rd_data        (rx_fifo_rd_data_out),
    .fifo_empty     (rx_fifo_empty_out)
);

endmodule

//data memory control module
//pops cmds form tx_fifo
//and takes data from the data memory

//fsm (3 states)
//IDLE : if ! cmd_empty && !resp_full then pop
//      - store:assert wr_en_in to data mem this cycle goes to WRITE_ACK
//      - LOAD : asserts read enable (req_in , !wr_ne_in); goes to READ_WAIT
//READ_WAIT: data mem.read_vld_out is 1 this cycle --> pushes response
//WRITE_ACK: push a zero-data resp --> back to idle

`default_nettype none

module data_mem_control #(
    parameter ADDR_WIDTH = 14,
    parameter DATA_WIDTH = 32
) (
    input  wire                 clk_mem,
    input  wire                 rst_mem_n,

    // cdc_brodge 

    input  wire                  tx_fifo_empty_in,
    input  wire                  tx_fifo_wr_en_in,
    input  wire [ADDR_WIDTH-1:0] tx_fifo_addr_in,
    input  wire [DATA_WIDTH-1:0] tx_fifo_wr_data_in,
    output reg                   tx_fifo_pop_out,

    // cdc 
    input  wire                  rx_fifo_full_in,
    output reg                   rx_fifo_push_out,
    output reg [DATA_WIDTH-1:0]  rx_fifo_data_out,

    //to and from data mem

    input  wire [DATA_WIDTH-1:0]    mem_rd_data_in,
    input  wire                     mem_rd_vld_in,
    output reg                      mem_req_out,
    output reg                      mem_wr_en_out,
    output reg [ADDR_WIDTH-1:0]     mem_addr_out,
    output reg [DATA_WIDTH-1:0]     mem_wr_data_out    
);

//FSM STATES

localparam IDLE         = 2'd0;
localparam READ_WAIT    = 2'd1;
localparam WRITE_ACK    = 2'd2;

reg [1:0] current_state;
reg [1:0] next_state;

always @ (posedge clk_mem or negedge rst_mem_n) begin
    if(!rst_mem_n) begin
        current_state <= IDLE;
    end
    else begin
        current_state <= next_state;
    end
end

//FSM LOGIC

always @ (*) begin
    
//default

next_state          = current_state;
tx_fifo_pop_out     = 1'b0;
rx_fifo_push_out    = 1'b0;
rx_fifo_data_out    = {DATA_WIDTH{1'b0}};

mem_req_out         = 1'b0;
mem_wr_en_out       = 1'b0;
mem_addr_out        = {ADDR_WIDTH{1'b0}};
mem_wr_data_out     = {DATA_WIDTH{1'b0}};

case(current_state)
    IDLE: begin
        if(!tx_fifo_empty_in && !rx_fifo_full_in) begin
            tx_fifo_pop_out = 1'b1;
            mem_req_out     = 1'b1;
            mem_wr_en_out   = tx_fifo_wr_en_in;
            mem_addr_out    = tx_fifo_addr_in;
            mem_wr_data_out = tx_fifo_wr_data_in;
            next_state      = tx_fifo_wr_en_in ? WRITE_ACK : READ_WAIT;
        end
    end

    READ_WAIT: begin
        if(mem_rd_vld_in) begin
            rx_fifo_push_out    = 1'b1;
            rx_fifo_data_out    = mem_rd_data_in;
            next_state          = IDLE;
        end
    end

    WRITE_ACK: begin
        rx_fifo_push_out    = 1'b1;
        rx_fifo_data_out    = {DATA_WIDTH{1'b0}};
        next_state          = IDLE;
    end

    default: next_state = IDLE;
endcase

end
endmodule
//async fifo

module async_fifo #(
    parameter DATA_WIDTH    = 32,
    parameter DEPTH_LOG2    = 3,               //default 8 Depth
    parameter DEPTH         = (1 << DEPTH_LOG2)
) (
    //Write domain
    input  wire                         wr_clk,
    input  wire                         wr_rst_n,
    input  wire                         wr_en,
    input  wire [DATA_WIDTH-1:0]        wr_data,
    output wire                         fifo_full,

    //Read Domain
    input  wire                         rd_clk,
    input  wire                         rd_rst_n,
    input  wire                         rd_en,
    output wire [DATA_WIDTH-1:0]        rd_data,
    output wire                         fifo_empty
);

//Initailizing Adrress width and pointer width
    localparam ADDR_WIDTH = DEPTH_LOG2;
    localparam PTR_WIDTH  = DEPTH_LOG2 + 1;
    
//FIFO MEMORY
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

//pointer registers(o/p of combo to be registered)
    reg [PTR_WIDTH-1:0] wr_ptr_bin_reg;
    reg [PTR_WIDTH-1:0] wr_ptr_gray_reg;
    reg [PTR_WIDTH-1:0] rd_ptr_bin_reg;
    reg [PTR_WIDTH-1:0] rd_ptr_gray_reg;

//2-ff sync o/p
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync_1;
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync_2;
    
    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync_1;
    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync_2;

    reg                 fifo_full_reg;
    reg                 rd_valid;
    reg                 capture;
    reg [DATA_WIDTH-1:0] rd_data_reg;

//wrte domain gray to bin converstion
//gray to bin 
    wire [PTR_WIDTH:0]   wr_ptr_bin_sum     = {1'b0, wr_ptr_bin_reg} + {{PTR_WIDTH{1'b0}}, (wr_en & ~fifo_full)};
    wire [PTR_WIDTH-1:0] wr_ptr_bin_next    = wr_ptr_bin_sum[PTR_WIDTH-1:0];
//bin to gray

    wire [PTR_WIDTH-1:0] wr_ptr_gray_next   = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;

    always @ (posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            wr_ptr_bin_reg  <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_reg <= {PTR_WIDTH{1'b0}};
        end

        else begin
            wr_ptr_bin_reg  <= wr_ptr_bin_next;
            wr_ptr_gray_reg <= wr_ptr_gray_next;
        end
    end 

//read domain
    // RAM has an unread word when the gray pointers differ
    wire ram_empty = (rd_ptr_gray_reg == wr_ptr_gray_sync_2);
    wire [PTR_WIDTH:0]   rd_ptr_bin_sum   = {1'b0, rd_ptr_bin_reg} + {{PTR_WIDTH{1'b0}}, capture};
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next  = rd_ptr_bin_sum[PTR_WIDTH-1:0];
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    wire [DATA_WIDTH-1:0] mem_word = mem[rd_ptr_bin_reg[ADDR_WIDTH-1:0]];
    wire [DATA_WIDTH-1:0] rd_data_next = capture ? mem_word : rd_data_reg;

    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin_reg  <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_reg <= {PTR_WIDTH{1'b0}};
            rd_valid        <= 1'b0;
            capture         <= 1'b0;
            rd_data_reg     <= {DATA_WIDTH{1'b0}};
        end else begin
            capture <= (!ram_empty) && (rd_en || !rd_valid) && (!capture);
            rd_data_reg <= rd_data_next;
            if (capture) begin
                rd_ptr_bin_reg  <= rd_ptr_bin_next;
                rd_ptr_gray_reg <= rd_ptr_gray_next;
                rd_valid        <= 1'b1;
            end else if (rd_en) begin
                rd_valid <= 1'b0;
            end
        end
    end

//sync rd_ptr into wr_clk

    always @ (posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            rd_ptr_gray_sync_1 <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_sync_2 <= {PTR_WIDTH{1'b0}};
        end
        else begin
            rd_ptr_gray_sync_1 <= rd_ptr_gray_reg;
            rd_ptr_gray_sync_2 <= rd_ptr_gray_sync_1;
        end
    end 

//full condition logic
    wire fifo_full_next = (wr_ptr_gray_next == {~rd_ptr_gray_sync_2[PTR_WIDTH-1:PTR_WIDTH-2],
                                                 rd_ptr_gray_sync_2[PTR_WIDTH-3:0]});
    always @ (posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n)
            fifo_full_reg <= 1'b0;
        else 
            fifo_full_reg <= fifo_full_next;
    end

    assign fifo_full = fifo_full_reg;

 //sync wr_ptr in rd_clk domain

    always @ (posedge rd_clk or negedge rd_rst_n) begin
        if(!rd_rst_n) begin
            wr_ptr_gray_sync_1 <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_sync_2 <= {PTR_WIDTH{1'b0}};
        end

        else begin
            wr_ptr_gray_sync_1 <= wr_ptr_gray_reg;
            wr_ptr_gray_sync_2 <= wr_ptr_gray_sync_1;
        end
    end

    assign fifo_empty = !rd_valid;

//read and write operations

    //WRITE 
    integer j;
    always @ (posedge wr_clk or negedge wr_rst_n) begin
        if(!wr_rst_n) begin
            for (j = 0; j < DEPTH; j = j + 1)
                mem[j] <= {DATA_WIDTH{1'b0}};
        end
        else if(wr_en && !fifo_full) begin
            mem[wr_ptr_bin_reg[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end

    //READ
    assign rd_data = rd_data_reg;

endmodule
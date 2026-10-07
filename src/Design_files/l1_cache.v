
// L1 Cache
// Level-1 cache, direct mapped, 4-word lines, write-through,
// no-write-allocate. Works in the fast clock domain (clk_cpu) and connects
// to data memory (slow clock) through the CDC FIFOs.
//
// Address map (NUM_LINES need not be a power of two):
//     line   = addr_in[ADDR_WIDTH-1 : OFFSET_WIDTH]
//     index  = line % NUM_LINES          (0 .. NUM_LINES-1)
//     tag    = line / NUM_LINES
//     offset = addr_in[OFFSET_WIDTH-1:0] (word in the line)
// Line size = 4 words. A 10-line cache uses a 4-bit index.
//
// FSM
//   IDLE, ready_out = 1. On a request:
//     load hit   : register rd_data, pulse rd_data_vld_out and xact_done_out
//                  on the next clock, stay in IDLE.
//     store hit  : update that word this cycle, push a write command
//                  into the TX FIFO, go to WAIT_RESP.
//     load miss  : push one read per word of the line, then WAIT_RESP.
//                  On the last response, fill the line and forward the
//                  requested word to the core.
//     store miss : push a write command (no allocate), go to WAIT_RESP.
//                  On the response, the transaction is done.
//   PUSH, ready_out = 0 while the remaining memory commands are sent.
//   WAIT_RESP, ready_out = 0 until the last response arrives.
//
// rd_data_vld_out and xact_done_out are registered. The control FSM samples
// xact_done_out only after it has moved to S_MEM, which is the cycle after
// it saw ready_out. A combinational pulse would already be gone by then.
`default_nettype none
module l1_cache
#(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 14,
    parameter NUM_LINES      = 10,
    parameter WORDS_PER_LINE = 4
)
(
    input  wire                      clk_cpu,
    input  wire                      rst_cpu_n,

    // Core interface
    input  wire                      req_in,              // 1 = valid request
    input  wire                      wr_en_in,            // 1 = store, 0 = load
    input  wire [ADDR_WIDTH-1:0]     addr_in,             // word address
    input  wire [DATA_WIDTH-1:0]     wr_data_in,          // store data
    output wire                      ready_out,           // cache can accept a new req
    output reg                       rd_data_vld_out,     // load data valid, 1-cycle pulse
    output reg  [DATA_WIDTH-1:0]     rd_data_out,         // load data
    output reg                       xact_done_out,       // 1-cycle pulse, load and store

    // Data-memory interface (CDC bridge)
    // TX FIFO : cache -> slow memory
    input  wire                      mem_tx_fifo_full_in,
    output reg                       mem_tx_fifo_push_out,
    output reg                       mem_tx_fifo_wr_en_out,
    output reg  [ADDR_WIDTH-1:0]     mem_tx_fifo_addr_out,
    output reg  [DATA_WIDTH-1:0]     mem_tx_fifo_wr_data_out,

    // RX FIFO : slow memory -> cache
    input  wire                      mem_rx_fifo_empty_in,
    input  wire [DATA_WIDTH-1:0]     mem_rx_rd_data_in,
    output reg                       mem_rx_fifo_pop_out
);

    localparam OFFSET_WIDTH = $clog2(WORDS_PER_LINE);
    localparam LINE_ADDR_W  = ADDR_WIDTH - OFFSET_WIDTH;
    // Width of an index that can hold 0 .. NUM_LINES-1. For 10 lines this is 4.
    localparam INDEX_W      = (NUM_LINES <= 2) ? 1 : $clog2(NUM_LINES);
    localparam MAX_TAG      = ((1 << LINE_ADDR_W) - 1) / NUM_LINES;
    localparam TAG_WIDTH    = (MAX_TAG < 2) ? 1 : $clog2(MAX_TAG + 1);
    localparam [OFFSET_WIDTH-1:0] LINE_LAST = WORDS_PER_LINE - 1;

    // Storage, direct mapped. One line holds WORDS_PER_LINE words.
    reg                           valid_arr [0:NUM_LINES-1];
    reg [TAG_WIDTH-1:0]           tag_arr   [0:NUM_LINES-1];
    reg [DATA_WIDTH-1:0]          data_arr  [0:NUM_LINES-1][0:WORDS_PER_LINE-1];

    // valid_arr, tag_arr and data_arr are all reset to a safe empty state.
    // A line is never read while valid is 0.
    integer i;
    integer w;
    reg                           wr_valid_wr_en;
    reg                           wr_line_en;
    reg [INDEX_W-1:0]             wr_index;
    reg [TAG_WIDTH-1:0]           wr_tag;
    reg [OFFSET_WIDTH-1:0]        wr_off;
    reg [DATA_WIDTH-1:0]          wr_data;

    // Words collected while a load-miss line fill is in flight.
    reg [DATA_WIDTH-1:0]          fill_buf [0:WORDS_PER_LINE-1];
    reg [OFFSET_WIDTH-1:0]        beat_reg;
    reg [OFFSET_WIDTH-1:0]        resp_reg;

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n) begin
            for (i = 0; i < NUM_LINES; i = i + 1)
                valid_arr[i] <= 1'b0;
        end
        else if (wr_valid_wr_en)
            valid_arr[wr_index] <= 1'b1;
    end

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n) begin
            for (i = 0; i < NUM_LINES; i = i + 1) begin
                tag_arr[i] <= {TAG_WIDTH{1'b0}};
                for (w = 0; w < WORDS_PER_LINE; w = w + 1)
                    data_arr[i][w] <= {DATA_WIDTH{1'b0}};
            end
        end
        else if (wr_valid_wr_en) begin
            tag_arr[wr_index] <= wr_tag;
            if (wr_line_en) begin
                for (w = 0; w < WORDS_PER_LINE; w = w + 1) begin
                    if ((w == resp_reg) && !mem_rx_fifo_empty_in)
                        data_arr[wr_index][w] <= mem_rx_rd_data_in;
                    else
                        data_arr[wr_index][w] <= fill_buf[w];
                end
            end
            else
                data_arr[wr_index][wr_off] <= wr_data;
        end
    end

    // Latched request, captured on the cycle it is accepted
    reg                        pending_wr_en_reg;
    reg [ADDR_WIDTH-1:0]       pending_addr_reg;
    reg [DATA_WIDTH-1:0]       pending_wr_data_reg;
    reg                        pending_was_hit_reg;   // skip fill on store hit and store miss

    wire [OFFSET_WIDTH-1:0]    pending_off   = pending_addr_reg[OFFSET_WIDTH-1:0];
    wire [LINE_ADDR_W-1:0]     pending_line  = pending_addr_reg[ADDR_WIDTH-1:OFFSET_WIDTH];
    wire [INDEX_W-1:0]         pending_index = pending_line % NUM_LINES;
    wire [TAG_WIDTH-1:0]       pending_tag   = pending_line / NUM_LINES;

    // Combinational tag lookup on the incoming request.
    // Index is always 0 .. NUM_LINES-1, so it matches the array bounds.
    wire [OFFSET_WIDTH-1:0]    in_off   = addr_in[OFFSET_WIDTH-1:0];
    wire [LINE_ADDR_W-1:0]     in_line  = addr_in[ADDR_WIDTH-1:OFFSET_WIDTH];
    wire [INDEX_W-1:0]         in_index = in_line % NUM_LINES;
    wire [TAG_WIDTH-1:0]       in_tag   = in_line / NUM_LINES;

    wire                       lookup_valid = valid_arr[in_index];
    wire [TAG_WIDTH-1:0]       lookup_tag   = tag_arr  [in_index];
    wire [DATA_WIDTH-1:0]      lookup_data  = data_arr [in_index][in_off];

    wire                       hit_now = lookup_valid && (lookup_tag == in_tag);

    // FSM
    localparam [1:0] IDLE      = 2'd0;
    localparam [1:0] PUSH      = 2'd1;
    localparam [1:0] WAIT_RESP = 2'd2;

    reg [1:0] current_state;
    reg [1:0] next_state;
    reg latch_req;
    reg rd_data_vld_next;
    reg xact_done_next;
    reg [DATA_WIDTH-1:0] rd_data_next;

    assign ready_out = (current_state == IDLE);

    // Next state and combinational outputs (FIFO push/pop, cache write)
    always @(*) begin
        next_state              = current_state;
        latch_req               = 1'b0;

        rd_data_vld_next        = 1'b0;
        xact_done_next          = 1'b0;
        rd_data_next            = rd_data_out;

        mem_tx_fifo_push_out    = 1'b0;
        mem_tx_fifo_wr_en_out   = 1'b0;
        mem_tx_fifo_addr_out    = {ADDR_WIDTH{1'b0}};
        mem_tx_fifo_wr_data_out = {DATA_WIDTH{1'b0}};
        mem_rx_fifo_pop_out     = 1'b0;

        wr_valid_wr_en          = 1'b0;
        wr_line_en              = 1'b0;
        wr_index                = {INDEX_W{1'b0}};
        wr_tag                  = {TAG_WIDTH{1'b0}};
        wr_off                  = {OFFSET_WIDTH{1'b0}};
        wr_data                 = {DATA_WIDTH{1'b0}};

        case (current_state)

            IDLE: begin
                if (req_in) begin
                    latch_req = 1'b1;

                    // Load hit: retire on the next clock, stay in IDLE.
                    if (!wr_en_in && hit_now) begin
                        rd_data_vld_next = 1'b1;
                        rd_data_next     = lookup_data;
                        xact_done_next   = 1'b1;
                        next_state       = IDLE;
                    end
                    else begin
                        // Store hit: write-through. Update that word now and
                        // send the same write to memory. The line and memory
                        // are both updated before the next request is accepted.
                        if (wr_en_in && hit_now) begin
                            wr_valid_wr_en = 1'b1;
                            wr_index       = in_index;
                            wr_tag         = in_tag;
                            wr_off         = in_off;
                            wr_data        = wr_data_in;
                        end

                        if (!mem_tx_fifo_full_in) begin
                            mem_tx_fifo_push_out    = 1'b1;
                            mem_tx_fifo_wr_en_out   = wr_en_in;
                            mem_tx_fifo_wr_data_out = wr_data_in;
                            if (wr_en_in) begin
                                mem_tx_fifo_addr_out = addr_in;
                                next_state           = WAIT_RESP;
                            end
                            else begin
                                mem_tx_fifo_addr_out = {in_line, {OFFSET_WIDTH{1'b0}}};
                                next_state           = (WORDS_PER_LINE == 1) ? WAIT_RESP : PUSH;
                            end
                        end
                        else
                            next_state = PUSH;
                    end
                end
            end

            PUSH: begin
                if (!mem_tx_fifo_full_in) begin
                    mem_tx_fifo_push_out = 1'b1;
                    if (pending_wr_en_reg) begin
                        mem_tx_fifo_wr_en_out   = 1'b1;
                        mem_tx_fifo_addr_out    = pending_addr_reg;
                        mem_tx_fifo_wr_data_out = pending_wr_data_reg;
                        next_state              = WAIT_RESP;
                    end
                    else begin
                        mem_tx_fifo_wr_en_out   = 1'b0;
                        mem_tx_fifo_addr_out    = {pending_line, beat_reg};
                        mem_tx_fifo_wr_data_out = {DATA_WIDTH{1'b0}};
                        if (beat_reg == LINE_LAST)
                            next_state = WAIT_RESP;
                    end
                end
            end

            WAIT_RESP: begin
                if (!mem_rx_fifo_empty_in) begin
                    mem_rx_fifo_pop_out = 1'b1;

                    // Stores complete on the single response. A load miss
                    // completes on the last word of the line.
                    if (pending_wr_en_reg || (resp_reg == LINE_LAST)) begin
                        xact_done_next = 1'b1;
                        next_state     = IDLE;

                        if (!pending_wr_en_reg) begin
                            rd_data_vld_next = 1'b1;
                            rd_data_next     = (pending_off == resp_reg) ? mem_rx_rd_data_in
                                                                       : fill_buf[pending_off];
                        end

                        // Load miss only: install the line.
                        // Store hit was written in IDLE. Store miss does not allocate.
                        if (!pending_wr_en_reg && !pending_was_hit_reg) begin
                            wr_valid_wr_en = 1'b1;
                            wr_line_en     = 1'b1;
                            wr_index       = pending_index;
                            wr_tag         = pending_tag;
                        end
                    end
                end
            end

            default: next_state = IDLE;

        endcase
    end

    // State, pending request, and the registered pulses to the core
    integer f;
    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n) begin
            current_state       <= IDLE;
            pending_wr_en_reg   <= 1'b0;
            pending_addr_reg    <= {ADDR_WIDTH{1'b0}};
            pending_wr_data_reg <= {DATA_WIDTH{1'b0}};
            pending_was_hit_reg <= 1'b0;
            beat_reg              <= {OFFSET_WIDTH{1'b0}};
            for (f = 0; f < WORDS_PER_LINE; f = f + 1)
                fill_buf[f] <= {DATA_WIDTH{1'b0}};
            rd_data_vld_out     <= 1'b0;
            rd_data_out         <= {DATA_WIDTH{1'b0}};
            xact_done_out       <= 1'b0;
        end
        else begin
            current_state   <= next_state;
            rd_data_vld_out <= rd_data_vld_next;
            rd_data_out     <= rd_data_next;
            xact_done_out   <= xact_done_next;

            if (latch_req) begin
                pending_wr_en_reg   <= wr_en_in;
                pending_addr_reg    <= addr_in;
                pending_wr_data_reg <= wr_data_in;
                pending_was_hit_reg <= hit_now;
                if (!wr_en_in && hit_now)
                    beat_reg <= {OFFSET_WIDTH{1'b0}};
                else if (!mem_tx_fifo_full_in)
                    beat_reg <= {{(OFFSET_WIDTH-1){1'b0}}, 1'b1};
                else
                    beat_reg <= {OFFSET_WIDTH{1'b0}};
            end
            else if ((current_state == PUSH) && !mem_tx_fifo_full_in)
                beat_reg <= beat_reg + 1'b1;

            if ((current_state == WAIT_RESP) && !mem_rx_fifo_empty_in)
                fill_buf[resp_reg] <= mem_rx_rd_data_in;
        end
    end

    always @(posedge clk_cpu or negedge rst_cpu_n) begin
        if (!rst_cpu_n)
            resp_reg <= {OFFSET_WIDTH{1'b0}};
        else if (latch_req)
            resp_reg <= {OFFSET_WIDTH{1'b0}};
        else if ((current_state == WAIT_RESP) && !mem_rx_fifo_empty_in)
            resp_reg <= resp_reg + 1'b1;
    end

endmodule


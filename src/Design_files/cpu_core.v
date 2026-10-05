//cpu_core.v

module cpu_core #(
    parameter PC_WIDTH          = 12,
    parameter DMEM_ADDR_WIDTH  = 14
) (
    input  wire                 clk_cpu,
    input  wire                 rst_cpu_n,

    //Program memory
    input  wire  [31:0]         imem_rd_data_in,
    input  wire                 imem_rd_data_vld_in,
    output wire                 imem_req_out,
    output wire [PC_WIDTH-1:0]  imem_addr_out,

    // mem_subsys
    input  wire                         dmem_ready_in,
    input  wire [31:0]                  dmem_rd_data_in,
    input  wire                         dmem_rd_data_valid_in,
    input  wire                         dmem_xact_done_in,

    output wire                         dmem_req_out,
    output wire                         dmem_wr_en_out,
    output wire [DMEM_ADDR_WIDTH-1:0]   dmem_addr_out,
    output wire [31:0]                  dmem_wr_data_out,

    //status 
    output wire                         halted_out,
    output wire                         illegal_out
);
    
// instruction register (latched at FETCH STATE --> DECODE STATE)
wire        ir_wr_en;
reg [31:0]  ir_reg;

always @ (posedge clk_cpu or negedge rst_cpu_n) begin
    if(!rst_cpu_n) begin
        ir_reg <= 32'd0;
    end
    else if (ir_wr_en) begin
        ir_reg <= imem_rd_data_in;
    end
end

//decoder combo
wire [3:0]      dec_rd, dec_rs1, dec_rs2;
wire [11:0]     dec_imm;
wire            dec_ra1_is_rd;
wire [3:0]      dec_alu_op;
wire            dec_op_b_is_imm;
wire [1:0]      dec_imm_mode;
wire [3:0]      dec_flag_wr_en_mask;
wire            dec_wr_rd;
wire [1:0]      dec_wb_sel;     //write back select
wire            dec_is_load, dec_is_store;
wire [1:0]      dec_addr_sel;
wire            dec_is_mul;
wire [3:0]      dec_branch_type;
wire            dec_is_call, dec_is_ret;
wire            dec_is_halt, dec_is_illegal, dec_unimpl;

instruction_decoder u_decoder(
    .inst_in            (ir_reg),
    .opcode_out          (),
    .rd_out             (dec_rd),
    .rs1_out            (dec_rs1),
    .rs2_out            (dec_rs2),
    .imm_out            (dec_imm),
    .ra1_is_rd_out      (dec_ra1_is_rd),
    .alu_op_out         (dec_alu_op),
    .op_b_is_imm_out    (dec_op_b_is_imm),
    .imm_mode_out       (dec_imm_mode),
    .flag_we_mask_out   (dec_flag_wr_en_mask),
    .wr_rd_out          (dec_wr_rd),
    .wb_sel_out         (dec_wb_sel),
    .is_load_out        (dec_is_load),
    .is_store_out       (dec_is_store),
    .addr_sel_out       (dec_addr_sel),
    .is_mul_out         (dec_is_mul),
    .branch_type_out    (dec_branch_type),
    .is_call_out        (dec_is_call),
    .is_ret_out         (dec_is_ret),
    .is_nop_out         (),
    .is_halt_out        (dec_is_halt),
    .illegal_out        (dec_is_illegal),
    .is_unimpl_out      (dec_unimpl)
);

//register file
//PORT A serves dual purpose:
//  ra1_is_rd = 0 -> read rs1
//  ra1_is_rd = 1 -> read rd
//PORT B is always rs2

wire [3:0]  ra_a_addr = dec_ra1_is_rd ? dec_rd : dec_rs1;

wire [31:0] rf_rd_a;
wire [31:0] rf_rd_b;

wire        rf_wr_en;
wire [31:0] wb_data;    //write back data

reg_file u_regfile(
    .clk_cpu        (clk_cpu),
    .rst_cpu_n      (rst_cpu_n),
    .ra_a           (ra_a_addr),
    .rd_a           (rf_rd_a),
    .ra_b           (dec_rs2),
    .rd_b           (rf_rd_b),
    .wr_en          (rf_wr_en),
    .w_addr         (dec_rd),
    .w_data         (wb_data)
);

//Immediate + brnach target
wire [31:0]             imm_ext;
wire [PC_WIDTH-1:0]     branch_target;

imm_gen #(.PC_WIDTH (PC_WIDTH)) u_imm_gen (
    .imm_in             (dec_imm),
    .imm_mode_in        (dec_imm_mode),
    .imm_ext_out        (imm_ext),
    .branch_target_out  (branch_target)
);

//addr_gen
//effective load/store address

wire [DMEM_ADDR_WIDTH-1:0] mem_ea;

addr_gen #(
    .ADDR_WIDTH (DMEM_ADDR_WIDTH)
) u_addr_gen
(
    .addr_sel_in        (dec_addr_sel),
    .imm_in             (dec_imm),
    .rs1_data_in        (rf_rd_a [DMEM_ADDR_WIDTH-1:0]),    //used for load_IND
    .rs2_data_in        (rf_rd_b [DMEM_ADDR_WIDTH-1:0]),    //used for store IND
    .mem_addr_out       (mem_ea)
);


//ALU

wire [31:0] alu_op_a = rf_rd_a;
wire [31:0] alu_op_b = dec_op_b_is_imm ? imm_ext : rf_rd_b;

wire        fsm_flags_wr_en;
wire [3:0]  alu_flag_mask_gated = dec_flag_wr_en_mask & {4{fsm_flags_wr_en}};

wire        mul_start;
wire        mul_done;
wire [3:0]  psr;
wire [31:0] alu_result;

alu u_alu(
    .clk_cpu            (clk_cpu),
    .rst_cpu_n          (rst_cpu_n),
    .A                  (alu_op_a),
    .B                  (alu_op_b),
    .alu_op_in          (dec_alu_op),
    .flag_we_mask_in    (alu_flag_mask_gated),
    .mul_start_in       (mul_start),
    .mul_done_out       (mul_done),
    .PSR                (psr),
    .alu_result         (alu_result)
);

//branch unit
wire [PC_WIDTH-1:0] pc;
wire [PC_WIDTH-1:0] pc_plus1;
wire [PC_WIDTH-1:0] next_pc;
wire                pc_wr_en;

//return stack: CALL pushes PC+1 in WB, RET pops the same edge the PC takes it
wire [PC_WIDTH-1:0] ret_addr;
wire                stack_empty;
wire                stack_full;
wire                stack_fault = (dec_is_call & stack_full) | (dec_is_ret & stack_empty);

return_stack #(
    .PC_WIDTH (PC_WIDTH)
) u_return_stack (
    .clk_cpu        (clk_cpu),
    .rst_cpu_n      (rst_cpu_n),
    .push_en_in     (pc_wr_en & dec_is_call),
    .pop_en_in      (pc_wr_en & dec_is_ret),
    .push_data_in   (pc_plus1),
    .top_out        (ret_addr),
    .empty_out      (stack_empty),
    .full_out       (stack_full)
);

branch_unit #(.PC_WIDTH (PC_WIDTH)) u_brnach_unit(
    .branch_type_in         (dec_branch_type),
    .psr_i                  (psr),
    .rs1_data_in            (rf_rd_a),
    .branch_target_in       (branch_target),
    .pc_plus1_in            (pc_plus1),
    .ret_addr_in            (ret_addr),
    .next_pc_out            (next_pc)
);

pc_unit #(.PC_WIDTH (PC_WIDTH)) u_pc_unit (
    .cpu_clk        (clk_cpu),
    .rst_cpu_n      (rst_cpu_n),
    .pc_en_in       (pc_wr_en),
    .next_pc_in     (next_pc),
    .pc_out         (pc),
    .pc_plus1_out   (pc_plus1)
);

//load_data latch (holds cache rd_data stable from S_mem into S_WB)

reg [31:0] load_data_reg;
always @ (posedge clk_cpu   or negedge rst_cpu_n) begin
    if(!rst_cpu_n) begin
        load_data_reg <= 32'd0;
    end
    else if (dmem_rd_data_valid_in) begin
        load_data_reg <= dmem_rd_data_in;
    end
end


//write back mux
//wb_sel = 00 -> alu_result
//wb_sel = 01 -> laod_data  (load / load ind)
//wb_sel = 10 -> immediate  (load_IMM, LUI)
reg [31:0] wb_data_r;
always @ (*) begin
    case (dec_wb_sel)
        2'b00 :     wb_data_r = alu_result;
        2'b01 :     wb_data_r = load_data_reg;
        2'b10 :     wb_data_r = imm_ext;
        default:    wb_data_r = alu_result;
    endcase
end

assign wb_data = wb_data_r;

wire fsm_reg_wr_en;

control_fsm u_ctrl_fsm(
    .clk_cpu                (clk_cpu),
    .rst_cpu_n              (rst_cpu_n),
    .imem_rd_data_vld_in    (imem_rd_data_vld_in),

    .is_load_in             (dec_is_load),
    .is_store_in            (dec_is_store),
    .is_mul_in              (dec_is_mul),
    .is_halt_in             (dec_is_halt),
    .illegal_in             (dec_is_illegal),
    .unimpl_in              (dec_unimpl),
    .stack_fault_in         (stack_fault),

    .mul_done_in            (mul_done),

    .mem_ready_in           (dmem_ready_in),
    .mem_done_in            (dmem_xact_done_in),
    .pc_wr_en_out           (pc_wr_en),
    .imem_req_out           (imem_req_out),
    .mul_start_out          (mul_start),
    .mem_req_out            (dmem_req_out),
    .mem_wr_en_out          (dmem_wr_en_out),
    .ir_wr_en_out           (ir_wr_en),
    .reg_wr_en_out          (fsm_reg_wr_en),
    .flags_wr_en_out        (fsm_flags_wr_en),
    .halted_out             (halted_out),
    .illegal_out            (illegal_out)
);

//final gates 
// imem address is just pc (12 bits)
assign imem_addr_out = pc;

//rf writes enable : both fsm says "its wb" and decoder says "this instruction wiries rd".
//stores, brnaches, CMP, NOP, HALT etx 
assign rf_wr_en    = fsm_reg_wr_en  & dec_wr_rd;

//DMEM address:take the low 14 bits of effectuve address 
//uses indirectly are silently ifnore 
assign dmem_addr_out = mem_ea;

//dmem write data : for stores, decoder sets ra1_is_rd -> prt A reads rd -> rf_rd_a already IS the data to write
assign dmem_wr_data_out = rf_rd_a;

endmodule
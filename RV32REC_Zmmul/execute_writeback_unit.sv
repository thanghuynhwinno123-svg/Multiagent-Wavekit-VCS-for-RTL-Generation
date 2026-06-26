`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module execute_writeback_unit (
  input  logic                             clk,
  input  logic                             rst_n,
  input  logic [RV32EC_ZMMUL_PC_W-1:0]     pc_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]     rs1_data_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]     rs2_data_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]     imm_i,
  input  logic [RV32EC_ZMMUL_ARCH_REG_ENC_W-1:0] rd_idx_i,
  input  logic [RV32EC_ZMMUL_ALU_OP_W-1:0] alu_op_i,
  input  logic [RV32EC_ZMMUL_BRANCH_OP_W-1:0] branch_op_i,
  input  logic                             mul_en_i,
  input  logic                             mem_req_i,
  input  logic                             mem_we_i,
  input  logic                             csr_en_i,
  input  logic                             mret_i,
  input  logic                             illegal_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]     load_data_i,
  input  logic                             load_ready_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]     mul_result_i,
  input  logic                             mul_done_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]     csr_rdata_i,
  output logic                             branch_taken_o,
  output logic [RV32EC_ZMMUL_PC_W-1:0]     branch_target_o,
  output logic                             wb_en_o,
  output logic [RV32EC_ZMMUL_ARCH_REG_ENC_W-1:0] wb_rd_idx_o,
  output logic [RV32EC_ZMMUL_XLEN-1:0]     wb_data_o,
  output logic [RV32EC_ZMMUL_XLEN-1:0]     mem_addr_o,
  output logic [RV32EC_ZMMUL_XLEN-1:0]     mem_wdata_o,
  output logic                             mem_req_o,
  output logic                             mem_we_o,
  output logic                             trap_req_o,
  output logic [RV32EC_ZMMUL_TRAP_CAUSE_W-1:0] trap_cause_o,
  output logic                             mret_req_o,
  output logic                             stall_o
);

  localparam logic [RV32EC_ZMMUL_BRANCH_OP_W-1:0] BRANCH_NONE = 3'd0;
  localparam logic [RV32EC_ZMMUL_BRANCH_OP_W-1:0] BRANCH_JAL  = 3'd6;
  localparam logic [RV32EC_ZMMUL_BRANCH_OP_W-1:0] BRANCH_JALR = 3'd7;
  localparam logic [RV32EC_ZMMUL_TRAP_CAUSE_W-1:0] TRAP_CAUSE_ILLEGAL = 4'd2;

  typedef enum logic [1:0] {
    PENDING_NONE = 2'd0,
    PENDING_MEM  = 2'd1,
    PENDING_MUL  = 2'd2
  } pending_kind_t;

  pending_kind_t pending_kind_q;

  logic [RV32EC_ZMMUL_ARCH_REG_ENC_W-1:0] pending_rd_idx_q;
  logic [RV32EC_ZMMUL_XLEN-1:0]           pending_mem_addr_q;
  logic [RV32EC_ZMMUL_XLEN-1:0]           pending_mem_wdata_q;

  logic [RV32EC_ZMMUL_XLEN-1:0]           alu_result;
  logic                                   alu_branch_taken;
  logic [RV32EC_ZMMUL_PC_W-1:0]           alu_branch_target;
  logic [RV32EC_ZMMUL_XLEN-1:0]           mem_addr_calc;
  logic                                   is_jump;

  assign mem_addr_calc = rs1_data_i + imm_i;
  assign is_jump       = (branch_op_i == BRANCH_JAL) || (branch_op_i == BRANCH_JALR);

  alu32_branch_unit u_alu32_branch_unit (
    .op_a_i          (rs1_data_i),
    .op_b_i          (rs2_data_i),
    .pc_i            (pc_i),
    .imm_i           (imm_i),
    .alu_op_i        (alu_op_i),
    .branch_op_i     (branch_op_i),
    .result_o        (alu_result),
    .branch_taken_o  (alu_branch_taken),
    .branch_target_o (alu_branch_target)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending_kind_q      <= PENDING_NONE;
      pending_rd_idx_q    <= '0;
      pending_mem_addr_q  <= '0;
      pending_mem_wdata_q <= '0;
    end else begin
      case (pending_kind_q)
        PENDING_NONE: begin
          if (illegal_i || mret_i) begin
            pending_kind_q <= PENDING_NONE;
          end else if (mem_req_i && !mem_we_i && !load_ready_i) begin
            pending_kind_q      <= PENDING_MEM;
            pending_rd_idx_q    <= rd_idx_i;
            pending_mem_addr_q  <= mem_addr_calc;
            pending_mem_wdata_q <= rs2_data_i;
          end else if (mul_en_i && !mul_done_i) begin
            pending_kind_q      <= PENDING_MUL;
            pending_rd_idx_q    <= rd_idx_i;
            pending_mem_addr_q  <= '0;
            pending_mem_wdata_q <= '0;
          end else begin
            pending_kind_q <= PENDING_NONE;
          end
        end

        PENDING_MEM: begin
          if (load_ready_i) begin
            pending_kind_q <= PENDING_NONE;
          end
        end

        PENDING_MUL: begin
          if (mul_done_i) begin
            pending_kind_q <= PENDING_NONE;
          end
        end

        default: begin
          pending_kind_q <= PENDING_NONE;
        end
      endcase
    end
  end

  always_comb begin
    branch_taken_o  = 1'b0;
    branch_target_o = '0;
    wb_en_o         = 1'b0;
    wb_rd_idx_o     = '0;
    wb_data_o       = '0;
    mem_addr_o      = '0;
    mem_wdata_o     = '0;
    mem_req_o       = 1'b0;
    mem_we_o        = 1'b0;
    trap_req_o      = 1'b0;
    trap_cause_o    = '0;
    mret_req_o      = 1'b0;
    stall_o         = 1'b0;

    if (!rst_n) begin
      branch_taken_o  = 1'b0;
      branch_target_o = '0;
      wb_en_o         = 1'b0;
      wb_rd_idx_o     = '0;
      wb_data_o       = '0;
      mem_addr_o      = '0;
      mem_wdata_o     = '0;
      mem_req_o       = 1'b0;
      mem_we_o        = 1'b0;
      trap_req_o      = 1'b0;
      trap_cause_o    = '0;
      mret_req_o      = 1'b0;
      stall_o         = 1'b0;
    end else if (pending_kind_q == PENDING_MEM) begin
      mem_addr_o  = pending_mem_addr_q;
      mem_wdata_o = pending_mem_wdata_q;
      mem_req_o   = 1'b1;
      mem_we_o    = 1'b0;
      stall_o     = ~load_ready_i;

      if (load_ready_i) begin
        wb_en_o     = 1'b1;
        wb_rd_idx_o = pending_rd_idx_q;
        wb_data_o   = load_data_i;
      end
    end else if (pending_kind_q == PENDING_MUL) begin
      stall_o = ~mul_done_i;

      if (mul_done_i) begin
        wb_en_o     = 1'b1;
        wb_rd_idx_o = pending_rd_idx_q;
        wb_data_o   = mul_result_i;
      end
    end else if (illegal_i) begin
      trap_req_o   = 1'b1;
      trap_cause_o = TRAP_CAUSE_ILLEGAL;
    end else if (mret_i) begin
      mret_req_o = 1'b1;
    end else if (mem_req_i) begin
      mem_addr_o  = mem_addr_calc;
      mem_wdata_o = rs2_data_i;
      mem_req_o   = 1'b1;
      mem_we_o    = mem_we_i;

      if (mem_we_i) begin
        wb_en_o = 1'b0;
      end else begin
        stall_o = ~load_ready_i;
        if (load_ready_i) begin
          wb_en_o     = 1'b1;
          wb_rd_idx_o = rd_idx_i;
          wb_data_o   = load_data_i;
        end
      end
    end else if (mul_en_i) begin
      stall_o = ~mul_done_i;

      if (mul_done_i) begin
        wb_en_o     = 1'b1;
        wb_rd_idx_o = rd_idx_i;
        wb_data_o   = mul_result_i;
      end
    end else if (csr_en_i) begin
      wb_en_o     = 1'b1;
      wb_rd_idx_o = rd_idx_i;
      wb_data_o   = csr_rdata_i;
    end else if (branch_op_i != BRANCH_NONE) begin
      branch_taken_o  = alu_branch_taken;
      branch_target_o = alu_branch_target;

      if (is_jump) begin
        wb_en_o     = 1'b1;
        wb_rd_idx_o = rd_idx_i;
        wb_data_o   = pc_i + 32'd4;
      end
    end else begin
      wb_en_o     = 1'b1;
      wb_rd_idx_o = rd_idx_i;
      wb_data_o   = alu_result;
    end
  end

endmodule
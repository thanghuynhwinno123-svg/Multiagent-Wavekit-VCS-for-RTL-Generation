`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_execute_writeback_unit;

  logic                             clk;
  logic                             rst_n;
  logic [RV32EC_ZMMUL_PC_W-1:0]     pc_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     rs1_data_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     rs2_data_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     imm_i;
  logic [RV32EC_ZMMUL_ARCH_REG_ENC_W-1:0] rd_idx_i;
  logic [RV32EC_ZMMUL_ALU_OP_W-1:0] alu_op_i;
  logic [RV32EC_ZMMUL_BRANCH_OP_W-1:0] branch_op_i;
  logic                             mul_en_i;
  logic                             mem_req_i;
  logic                             mem_we_i;
  logic                             csr_en_i;
  logic                             mret_i;
  logic                             illegal_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     load_data_i;
  logic                             load_ready_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     mul_result_i;
  logic                             mul_done_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     csr_rdata_i;

  logic                             branch_taken_o;
  logic [RV32EC_ZMMUL_PC_W-1:0]     branch_target_o;
  logic                             wb_en_o;
  logic [RV32EC_ZMMUL_ARCH_REG_ENC_W-1:0] wb_rd_idx_o;
  logic [RV32EC_ZMMUL_XLEN-1:0]     wb_data_o;
  logic [RV32EC_ZMMUL_XLEN-1:0]     mem_addr_o;
  logic [RV32EC_ZMMUL_XLEN-1:0]     mem_wdata_o;
  logic                             mem_req_o;
  logic                             mem_we_o;
  logic                             trap_req_o;
  logic [RV32EC_ZMMUL_TRAP_CAUSE_W-1:0] trap_cause_o;
  logic                             mret_req_o;
  logic                             stall_o;

  execute_writeback_unit u_dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .pc_i           (pc_i),
    .rs1_data_i     (rs1_data_i),
    .rs2_data_i     (rs2_data_i),
    .imm_i          (imm_i),
    .rd_idx_i       (rd_idx_i),
    .alu_op_i       (alu_op_i),
    .branch_op_i    (branch_op_i),
    .mul_en_i       (mul_en_i),
    .mem_req_i      (mem_req_i),
    .mem_we_i       (mem_we_i),
    .csr_en_i       (csr_en_i),
    .mret_i         (mret_i),
    .illegal_i      (illegal_i),
    .load_data_i    (load_data_i),
    .load_ready_i   (load_ready_i),
    .mul_result_i   (mul_result_i),
    .mul_done_i     (mul_done_i),
    .csr_rdata_i    (csr_rdata_i),
    .branch_taken_o (branch_taken_o),
    .branch_target_o(branch_target_o),
    .wb_en_o        (wb_en_o),
    .wb_rd_idx_o    (wb_rd_idx_o),
    .wb_data_o      (wb_data_o),
    .mem_addr_o     (mem_addr_o),
    .mem_wdata_o    (mem_wdata_o),
    .mem_req_o      (mem_req_o),
    .mem_we_o       (mem_we_o),
    .trap_req_o     (trap_req_o),
    .trap_cause_o   (trap_cause_o),
    .mret_req_o     (mret_req_o),
    .stall_o        (stall_o)
  );

  tb_execute_writeback_unit u_tb (
    .clk            (clk),
    .rst_n          (rst_n),
    .pc_i           (pc_i),
    .rs1_data_i     (rs1_data_i),
    .rs2_data_i     (rs2_data_i),
    .imm_i          (imm_i),
    .rd_idx_i       (rd_idx_i),
    .alu_op_i       (alu_op_i),
    .branch_op_i    (branch_op_i),
    .mul_en_i       (mul_en_i),
    .mem_req_i      (mem_req_i),
    .mem_we_i       (mem_we_i),
    .csr_en_i       (csr_en_i),
    .mret_i         (mret_i),
    .illegal_i      (illegal_i),
    .load_data_i    (load_data_i),
    .load_ready_i   (load_ready_i),
    .mul_result_i   (mul_result_i),
    .mul_done_i     (mul_done_i),
    .csr_rdata_i    (csr_rdata_i),
    .branch_taken_o (branch_taken_o),
    .branch_target_o(branch_target_o),
    .wb_en_o        (wb_en_o),
    .wb_rd_idx_o    (wb_rd_idx_o),
    .wb_data_o      (wb_data_o),
    .mem_addr_o     (mem_addr_o),
    .mem_wdata_o    (mem_wdata_o),
    .mem_req_o      (mem_req_o),
    .mem_we_o       (mem_we_o),
    .trap_req_o     (trap_req_o),
    .trap_cause_o   (trap_cause_o),
    .mret_req_o     (mret_req_o),
    .stall_o        (stall_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_execute_writeback_unit);
  end

endmodule
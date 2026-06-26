`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_decode_control_unit;

  logic [31:0] instr_i;
  logic [31:0] pc_i;
  logic [4:0]  rs1_idx_o;
  logic [4:0]  rs2_idx_o;
  logic [4:0]  rd_idx_o;
  logic [31:0] imm_o;
  logic [3:0]  alu_op_o;
  logic [2:0]  branch_op_o;
  logic        mul_en_o;
  logic        mem_req_o;
  logic        mem_we_o;
  logic        csr_en_o;
  logic        mret_o;
  logic        ebreak_o;
  logic        illegal_o;
  logic        is_compressed_o;
  logic        wb_en_o;

  decode_control_unit dut (
    .instr_i          (instr_i),
    .pc_i             (pc_i),
    .rs1_idx_o        (rs1_idx_o),
    .rs2_idx_o        (rs2_idx_o),
    .rd_idx_o         (rd_idx_o),
    .imm_o            (imm_o),
    .alu_op_o         (alu_op_o),
    .branch_op_o      (branch_op_o),
    .mul_en_o         (mul_en_o),
    .mem_req_o        (mem_req_o),
    .mem_we_o         (mem_we_o),
    .csr_en_o         (csr_en_o),
    .mret_o           (mret_o),
    .ebreak_o         (ebreak_o),
    .illegal_o        (illegal_o),
    .is_compressed_o  (is_compressed_o),
    .wb_en_o          (wb_en_o)
  );

  tb_decode_control_unit tb (
    .instr_i          (instr_i),
    .pc_i             (pc_i),
    .rs1_idx_o        (rs1_idx_o),
    .rs2_idx_o        (rs2_idx_o),
    .rd_idx_o         (rd_idx_o),
    .imm_o            (imm_o),
    .alu_op_o         (alu_op_o),
    .branch_op_o      (branch_op_o),
    .mul_en_o         (mul_en_o),
    .mem_req_o        (mem_req_o),
    .mem_we_o         (mem_we_o),
    .csr_en_o         (csr_en_o),
    .mret_o           (mret_o),
    .ebreak_o         (ebreak_o),
    .illegal_o        (illegal_o),
    .is_compressed_o  (is_compressed_o),
    .wb_en_o          (wb_en_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_decode_control_unit);
  end

endmodule
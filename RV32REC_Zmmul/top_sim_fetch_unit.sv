`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_fetch_unit;

  logic [RV32EC_ZMMUL_XLEN-1:0]  reset_vector_i;
  logic                          clk;
  logic                          rst_n;
  logic                          stall_i;
  logic                          flush_i;
  logic                          trap_redirect_valid_i;
  logic [RV32EC_ZMMUL_PC_W-1:0]  trap_redirect_pc_i;
  logic                          mret_redirect_valid_i;
  logic [RV32EC_ZMMUL_PC_W-1:0]  mret_redirect_pc_i;
  logic                          branch_redirect_valid_i;
  logic [RV32EC_ZMMUL_PC_W-1:0]  branch_redirect_pc_i;
  logic                          instr_ready_i;
  logic [RV32EC_ZMMUL_INSTR_W-1:0] instr_rdata_i;
  logic                          is_compressed_i;
  logic                          instr_req_o;
  logic [RV32EC_ZMMUL_PC_W-1:0]  instr_addr_o;
  logic [RV32EC_ZMMUL_PC_W-1:0]  pc_o;
  logic                          instr_valid_o;
  logic [RV32EC_ZMMUL_INSTR_W-1:0] instr_o;

  fetch_unit dut (
    .reset_vector_i          (reset_vector_i),
    .clk                     (clk),
    .rst_n                   (rst_n),
    .stall_i                 (stall_i),
    .flush_i                 (flush_i),
    .trap_redirect_valid_i   (trap_redirect_valid_i),
    .trap_redirect_pc_i      (trap_redirect_pc_i),
    .mret_redirect_valid_i   (mret_redirect_valid_i),
    .mret_redirect_pc_i      (mret_redirect_pc_i),
    .branch_redirect_valid_i (branch_redirect_valid_i),
    .branch_redirect_pc_i    (branch_redirect_pc_i),
    .instr_ready_i           (instr_ready_i),
    .instr_rdata_i           (instr_rdata_i),
    .is_compressed_i         (is_compressed_i),
    .instr_req_o             (instr_req_o),
    .instr_addr_o            (instr_addr_o),
    .pc_o                    (pc_o),
    .instr_valid_o           (instr_valid_o),
    .instr_o                 (instr_o)
  );

  tb_fetch_unit tb (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .stall_i                 (stall_i),
    .flush_i                 (flush_i),
    .trap_redirect_valid_i   (trap_redirect_valid_i),
    .trap_redirect_pc_i      (trap_redirect_pc_i),
    .mret_redirect_valid_i   (mret_redirect_valid_i),
    .mret_redirect_pc_i      (mret_redirect_pc_i),
    .branch_redirect_valid_i (branch_redirect_valid_i),
    .branch_redirect_pc_i    (branch_redirect_pc_i),
    .instr_ready_i           (instr_ready_i),
    .instr_rdata_i           (instr_rdata_i),
    .is_compressed_i         (is_compressed_i),
    .reset_vector_i          (reset_vector_i),
    .instr_req_o             (instr_req_o),
    .instr_addr_o            (instr_addr_o),
    .pc_o                    (pc_o),
    .instr_valid_o           (instr_valid_o),
    .instr_o                 (instr_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_fetch_unit);
  end

endmodule
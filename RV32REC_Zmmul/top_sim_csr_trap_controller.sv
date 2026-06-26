`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_csr_trap_controller;

  logic                             clk;
  logic                             rst_n;
  logic                             csr_en_i;
  logic                             csr_we_i;
  logic [RV32EC_ZMMUL_CSR_ADDR_W-1:0] csr_addr_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     csr_wdata_i;
  logic                             trap_req_i;
  logic [RV32EC_ZMMUL_TRAP_CAUSE_W-1:0] trap_cause_i;
  logic [RV32EC_ZMMUL_PC_W-1:0]     trap_pc_i;
  logic                             ext_irq_i;
  logic                             mret_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]     csr_rdata_o;
  logic                             trap_redirect_valid_o;
  logic [RV32EC_ZMMUL_PC_W-1:0]     trap_redirect_pc_o;
  logic                             mret_redirect_valid_o;
  logic [RV32EC_ZMMUL_PC_W-1:0]     mret_redirect_pc_o;

  csr_trap_controller dut (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .csr_en_i              (csr_en_i),
    .csr_we_i              (csr_we_i),
    .csr_addr_i            (csr_addr_i),
    .csr_wdata_i           (csr_wdata_i),
    .trap_req_i            (trap_req_i),
    .trap_cause_i          (trap_cause_i),
    .trap_pc_i             (trap_pc_i),
    .ext_irq_i             (ext_irq_i),
    .mret_i                (mret_i),
    .csr_rdata_o           (csr_rdata_o),
    .trap_redirect_valid_o (trap_redirect_valid_o),
    .trap_redirect_pc_o    (trap_redirect_pc_o),
    .mret_redirect_valid_o (mret_redirect_valid_o),
    .mret_redirect_pc_o    (mret_redirect_pc_o)
  );

  tb_csr_trap_controller tb (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .csr_en_i              (csr_en_i),
    .csr_we_i              (csr_we_i),
    .csr_addr_i            (csr_addr_i),
    .csr_wdata_i           (csr_wdata_i),
    .trap_req_i            (trap_req_i),
    .trap_cause_i          (trap_cause_i),
    .trap_pc_i             (trap_pc_i),
    .ext_irq_i             (ext_irq_i),
    .mret_i                (mret_i),
    .csr_rdata_o           (csr_rdata_o),
    .trap_redirect_valid_o (trap_redirect_valid_o),
    .trap_redirect_pc_o    (trap_redirect_pc_o),
    .mret_redirect_valid_o (mret_redirect_valid_o),
    .mret_redirect_pc_o    (mret_redirect_pc_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_csr_trap_controller);
  end

endmodule
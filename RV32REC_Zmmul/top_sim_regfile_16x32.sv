`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_regfile_16x32;

  logic                              clk;
  logic                              rst_n;
  logic [RV32EC_ZMMUL_REG_ADDR_W-1:0] raddr1_i;
  logic [RV32EC_ZMMUL_REG_ADDR_W-1:0] raddr2_i;
  logic                              we_i;
  logic [RV32EC_ZMMUL_REG_ADDR_W-1:0] waddr_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]      wdata_i;
  logic [RV32EC_ZMMUL_XLEN-1:0]      rdata1_o;
  logic [RV32EC_ZMMUL_XLEN-1:0]      rdata2_o;

  regfile_16x32 dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .raddr1_i (raddr1_i),
    .raddr2_i (raddr2_i),
    .we_i     (we_i),
    .waddr_i  (waddr_i),
    .wdata_i  (wdata_i),
    .rdata1_o (rdata1_o),
    .rdata2_o (rdata2_o)
  );

  tb_regfile_16x32 tb (
    .clk      (clk),
    .rst_n    (rst_n),
    .raddr1_i (raddr1_i),
    .raddr2_i (raddr2_i),
    .we_i     (we_i),
    .waddr_i  (waddr_i),
    .wdata_i  (wdata_i),
    .rdata1_o (rdata1_o),
    .rdata2_o (rdata2_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_regfile_16x32);
  end

endmodule
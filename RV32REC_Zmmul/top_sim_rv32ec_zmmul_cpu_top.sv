`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_rv32ec_zmmul_cpu_top;

  logic        clk;
  logic        rst_n;
  logic        boot_mode_spi;
  logic        ext_irq;
  logic        instr_ready;
  logic [31:0] instr_rdata;
  logic        data_ready;
  logic [31:0] data_rdata;
  logic        spi_ready;
  logic [31:0] spi_rdata;
  logic        instr_req;
  logic [31:0] instr_addr;
  logic        data_req;
  logic        data_we;
  logic [3:0]  data_be;
  logic [31:0] data_addr;
  logic [31:0] data_wdata;
  logic        spi_req;
  logic [31:0] spi_addr;
  logic        fail_stop;

  rv32ec_zmmul_cpu_top u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .boot_mode_spi (boot_mode_spi),
    .ext_irq       (ext_irq),
    .instr_ready   (instr_ready),
    .instr_rdata   (instr_rdata),
    .data_ready    (data_ready),
    .data_rdata    (data_rdata),
    .spi_ready     (spi_ready),
    .spi_rdata     (spi_rdata),
    .instr_req     (instr_req),
    .instr_addr    (instr_addr),
    .data_req      (data_req),
    .data_we       (data_we),
    .data_be       (data_be),
    .data_addr     (data_addr),
    .data_wdata    (data_wdata),
    .spi_req       (spi_req),
    .spi_addr      (spi_addr),
    .fail_stop     (fail_stop)
  );

  tb_rv32ec_zmmul_cpu_top u_tb (
    .clk           (clk),
    .rst_n         (rst_n),
    .boot_mode_spi (boot_mode_spi),
    .ext_irq       (ext_irq),
    .instr_ready   (instr_ready),
    .instr_rdata   (instr_rdata),
    .data_ready    (data_ready),
    .data_rdata    (data_rdata),
    .spi_ready     (spi_ready),
    .spi_rdata     (spi_rdata),
    .instr_req     (instr_req),
    .instr_addr    (instr_addr),
    .data_req      (data_req),
    .data_we       (data_we),
    .data_be       (data_be),
    .data_addr     (data_addr),
    .data_wdata    (data_wdata),
    .spi_req       (spi_req),
    .spi_addr      (spi_addr),
    .fail_stop     (fail_stop)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_rv32ec_zmmul_cpu_top);
  end

endmodule
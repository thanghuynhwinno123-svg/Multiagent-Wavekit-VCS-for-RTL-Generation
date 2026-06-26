`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_boot_rom_loader;

  logic        clk;
  logic        rst_n;
  logic        start_i;
  logic        spi_ready_i;
  logic [31:0] spi_rdata_i;
  logic        iram_ready_i;
  logic        validation_enable_i;
  logic        spi_req_o;
  logic [31:0] spi_addr_o;
  logic        iram_we_o;
  logic [31:0] iram_addr_o;
  logic [31:0] iram_wdata_o;
  logic        done_o;
  logic [31:0] boot_pc_o;
  logic        fail_stop_o;

  boot_rom_loader dut (
    .clk                 (clk),
    .rst_n               (rst_n),
    .start_i             (start_i),
    .spi_ready_i         (spi_ready_i),
    .spi_rdata_i         (spi_rdata_i),
    .iram_ready_i        (iram_ready_i),
    .validation_enable_i (validation_enable_i),
    .spi_req_o           (spi_req_o),
    .spi_addr_o          (spi_addr_o),
    .iram_we_o           (iram_we_o),
    .iram_addr_o         (iram_addr_o),
    .iram_wdata_o        (iram_wdata_o),
    .done_o              (done_o),
    .boot_pc_o           (boot_pc_o),
    .fail_stop_o         (fail_stop_o)
  );

  tb_boot_rom_loader tb (
    .clk                 (clk),
    .rst_n               (rst_n),
    .start_i             (start_i),
    .spi_ready_i         (spi_ready_i),
    .spi_rdata_i         (spi_rdata_i),
    .iram_ready_i        (iram_ready_i),
    .validation_enable_i (validation_enable_i),
    .spi_req_o           (spi_req_o),
    .spi_addr_o          (spi_addr_o),
    .iram_we_o           (iram_we_o),
    .iram_addr_o         (iram_addr_o),
    .iram_wdata_o        (iram_wdata_o),
    .done_o              (done_o),
    .boot_pc_o           (boot_pc_o),
    .fail_stop_o         (fail_stop_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_boot_rom_loader);
  end

endmodule
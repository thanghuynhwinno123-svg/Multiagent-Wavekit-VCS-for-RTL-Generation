`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module top_sim_load_store_unit;

  logic        clk;
  logic        rst_n;
  logic        req_i;
  logic        we_i;
  logic [1:0]  size_i;
  logic        unsigned_i;
  logic [31:0] base_addr_i;
  logic [31:0] offset_i;
  logic [31:0] store_data_i;
  logic        mem_ready_i;
  logic [31:0] mem_rdata_i;
  logic        trap_on_misaligned_i;

  logic        mem_req_o;
  logic        mem_we_o;
  logic [3:0]  mem_be_o;
  logic [31:0] mem_addr_o;
  logic [31:0] mem_wdata_o;
  logic [31:0] load_data_o;
  logic        done_o;
  logic        stall_o;
  logic        misaligned_o;

  load_store_unit dut (
    .clk                  (clk),
    .rst_n                (rst_n),
    .req_i                (req_i),
    .we_i                 (we_i),
    .size_i               (size_i),
    .unsigned_i           (unsigned_i),
    .base_addr_i          (base_addr_i),
    .offset_i             (offset_i),
    .store_data_i         (store_data_i),
    .mem_ready_i          (mem_ready_i),
    .mem_rdata_i          (mem_rdata_i),
    .trap_on_misaligned_i (trap_on_misaligned_i),
    .mem_req_o            (mem_req_o),
    .mem_we_o             (mem_we_o),
    .mem_be_o             (mem_be_o),
    .mem_addr_o           (mem_addr_o),
    .mem_wdata_o          (mem_wdata_o),
    .load_data_o          (load_data_o),
    .done_o               (done_o),
    .stall_o              (stall_o),
    .misaligned_o         (misaligned_o)
  );

  tb_load_store_unit tb (
    .clk                  (clk),
    .rst_n                (rst_n),
    .req_i                (req_i),
    .we_i                 (we_i),
    .size_i               (size_i),
    .unsigned_i           (unsigned_i),
    .base_addr_i          (base_addr_i),
    .offset_i             (offset_i),
    .store_data_i         (store_data_i),
    .mem_ready_i          (mem_ready_i),
    .mem_rdata_i          (mem_rdata_i),
    .trap_on_misaligned_i (trap_on_misaligned_i),
    .mem_req_o            (mem_req_o),
    .mem_we_o             (mem_we_o),
    .mem_be_o             (mem_be_o),
    .mem_addr_o           (mem_addr_o),
    .mem_wdata_o          (mem_wdata_o),
    .load_data_o          (load_data_o),
    .done_o               (done_o),
    .stall_o              (stall_o),
    .misaligned_o         (misaligned_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_load_store_unit);
  end

endmodule
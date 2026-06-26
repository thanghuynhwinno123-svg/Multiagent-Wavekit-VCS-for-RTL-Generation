`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module regfile_16x32 (
  input  logic                              clk,
  input  logic                              rst_n,
  input  logic [RV32EC_ZMMUL_REG_ADDR_W-1:0] raddr1_i,
  input  logic [RV32EC_ZMMUL_REG_ADDR_W-1:0] raddr2_i,
  input  logic                              we_i,
  input  logic [RV32EC_ZMMUL_REG_ADDR_W-1:0] waddr_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]      wdata_i,
  output logic [RV32EC_ZMMUL_XLEN-1:0]      rdata1_o,
  output logic [RV32EC_ZMMUL_XLEN-1:0]      rdata2_o
);

  logic [RV32EC_ZMMUL_XLEN-1:0] regfile_q [0:RV32EC_ZMMUL_REG_COUNT-1];
  integer idx;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (idx = 0; idx < RV32EC_ZMMUL_REG_COUNT; idx = idx + 1) begin
        regfile_q[idx] <= '0;
      end
    end else begin
      if (we_i && (waddr_i != '0)) begin
        regfile_q[waddr_i] <= wdata_i;
      end
    end
  end

  always_comb begin
    if (raddr1_i == '0) begin
      rdata1_o = '0;
    end else begin
      rdata1_o = regfile_q[raddr1_i];
    end
  end

  always_comb begin
    if (raddr2_i == '0) begin
      rdata2_o = '0;
    end else begin
      rdata2_o = regfile_q[raddr2_i];
    end
  end

endmodule
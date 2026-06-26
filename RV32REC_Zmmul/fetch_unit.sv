`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module fetch_unit (
  input  logic [RV32EC_ZMMUL_XLEN-1:0] reset_vector_i,
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         stall_i,
  input  logic                         flush_i,
  input  logic                         trap_redirect_valid_i,
  input  logic [RV32EC_ZMMUL_PC_W-1:0] trap_redirect_pc_i,
  input  logic                         mret_redirect_valid_i,
  input  logic [RV32EC_ZMMUL_PC_W-1:0] mret_redirect_pc_i,
  input  logic                         branch_redirect_valid_i,
  input  logic [RV32EC_ZMMUL_PC_W-1:0] branch_redirect_pc_i,
  input  logic                         instr_ready_i,
  input  logic [RV32EC_ZMMUL_INSTR_W-1:0] instr_rdata_i,
  input  logic                         is_compressed_i,
  output logic                         instr_req_o,
  output logic [RV32EC_ZMMUL_PC_W-1:0] instr_addr_o,
  output logic [RV32EC_ZMMUL_PC_W-1:0] pc_o,
  output logic                         instr_valid_o,
  output logic [RV32EC_ZMMUL_INSTR_W-1:0] instr_o
);

  logic [RV32EC_ZMMUL_PC_W-1:0]    pc_q;
  logic [RV32EC_ZMMUL_PC_W-1:0]    pc_d;
  logic [RV32EC_ZMMUL_INSTR_W-1:0] instr_q;
  logic [RV32EC_ZMMUL_INSTR_W-1:0] instr_d;
  logic                            instr_valid_q;
  logic                            instr_valid_d;

  logic                            redirect_valid;
  logic [RV32EC_ZMMUL_PC_W-1:0]    redirect_pc;
  logic [RV32EC_ZMMUL_PC_W-1:0]    seq_next_pc;

  always_comb begin
    redirect_valid = 1'b0;
    redirect_pc    = pc_q;

    if (trap_redirect_valid_i) begin
      redirect_valid = 1'b1;
      redirect_pc    = trap_redirect_pc_i;
    end else if (mret_redirect_valid_i) begin
      redirect_valid = 1'b1;
      redirect_pc    = mret_redirect_pc_i;
    end else if (branch_redirect_valid_i) begin
      redirect_valid = 1'b1;
      redirect_pc    = branch_redirect_pc_i;
    end

    if (is_compressed_i) begin
      seq_next_pc = pc_q + 32'd2;
    end else begin
      seq_next_pc = pc_q + 32'd4;
    end
  end

  always_comb begin
    pc_d          = pc_q;
    instr_d       = instr_q;
    instr_valid_d = instr_valid_q;

    if (!stall_i) begin
      if (redirect_valid) begin
        pc_d          = redirect_pc;
        instr_valid_d = 1'b0;
      end else begin
        if (flush_i) begin
          instr_valid_d = 1'b0;
        end

        if (instr_ready_i) begin
          instr_d       = instr_rdata_i;
          instr_valid_d = 1'b1;
          pc_d          = seq_next_pc;
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_q          <= reset_vector_i;
      instr_q       <= '0;
      instr_valid_q <= 1'b0;
    end else begin
      pc_q          <= pc_d;
      instr_q       <= instr_d;
      instr_valid_q <= instr_valid_d;
    end
  end

  always_comb begin
    instr_req_o   = 1'b1;
    instr_addr_o  = pc_q;
    pc_o          = pc_q;
    instr_valid_o = instr_valid_q;
    instr_o       = instr_q;
  end

endmodule
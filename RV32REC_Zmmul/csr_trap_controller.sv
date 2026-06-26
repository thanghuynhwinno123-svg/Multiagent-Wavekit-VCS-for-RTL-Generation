`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module csr_trap_controller (
  input  logic                             clk,
  input  logic                             rst_n,
  input  logic                             csr_en_i,
  input  logic                             csr_we_i,
  input  logic [RV32EC_ZMMUL_CSR_ADDR_W-1:0] csr_addr_i,
  input  logic [RV32EC_ZMMUL_XLEN-1:0]     csr_wdata_i,
  input  logic                             trap_req_i,
  input  logic [RV32EC_ZMMUL_TRAP_CAUSE_W-1:0] trap_cause_i,
  input  logic [RV32EC_ZMMUL_PC_W-1:0]     trap_pc_i,
  input  logic                             ext_irq_i,
  input  logic                             mret_i,
  output logic [RV32EC_ZMMUL_XLEN-1:0]     csr_rdata_o,
  output logic                             trap_redirect_valid_o,
  output logic [RV32EC_ZMMUL_PC_W-1:0]     trap_redirect_pc_o,
  output logic                             mret_redirect_valid_o,
  output logic [RV32EC_ZMMUL_PC_W-1:0]     mret_redirect_pc_o
);

  localparam logic [11:0] CSR_ADDR_MSTATUS = 12'h300;
  localparam logic [11:0] CSR_ADDR_MTVEC   = 12'h305;
  localparam logic [11:0] CSR_ADDR_MEPC    = 12'h341;
  localparam logic [11:0] CSR_ADDR_MCAUSE  = 12'h342;

  localparam logic [31:0] MCAUSE_MEI       = 32'h8000_000B;

  logic [31:0] mstatus_q;
  logic [31:0] mtvec_q;
  logic [31:0] mepc_q;
  logic [31:0] mcause_q;

  logic        csr_write_fire;
  logic        irq_accept;
  logic        trap_accept;

  assign csr_write_fire = csr_en_i & csr_we_i;

  // External interrupt acceptance is intentionally ungated in this simplified controller.
  assign irq_accept  = ext_irq_i;
  assign trap_accept = trap_req_i | irq_accept;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mstatus_q              <= 32'h0000_0000;
      mtvec_q                <= RV32EC_ZMMUL_MTVEC_RESET;
      mepc_q                 <= 32'h0000_0000;
      mcause_q               <= 32'h0000_0000;
      trap_redirect_valid_o  <= 1'b0;
      trap_redirect_pc_o     <= 32'h0000_0000;
      mret_redirect_valid_o  <= 1'b0;
      mret_redirect_pc_o     <= 32'h0000_0000;
    end else begin
      trap_redirect_valid_o  <= 1'b0;
      mret_redirect_valid_o  <= 1'b0;

      if (trap_accept) begin
        mepc_q                <= trap_pc_i;
        mcause_q              <= irq_accept ? MCAUSE_MEI : {28'h0000_000, trap_cause_i};
        trap_redirect_valid_o <= 1'b1;
        trap_redirect_pc_o    <= mtvec_q;

        mstatus_q[7]          <= mstatus_q[3];
        mstatus_q[3]          <= 1'b0;
      end else if (mret_i) begin
        mret_redirect_valid_o <= 1'b1;
        mret_redirect_pc_o    <= mepc_q;

        mstatus_q[3]          <= mstatus_q[7];
        mstatus_q[7]          <= 1'b1;
      end else if (csr_write_fire) begin
        unique case (csr_addr_i)
          CSR_ADDR_MSTATUS: mstatus_q <= csr_wdata_i;
          CSR_ADDR_MTVEC:   mtvec_q   <= {csr_wdata_i[31:2], 2'b00};
          CSR_ADDR_MEPC:    mepc_q    <= csr_wdata_i;
          CSR_ADDR_MCAUSE:  mcause_q  <= csr_wdata_i;
          default: begin
          end
        endcase
      end
    end
  end

  always_comb begin
    csr_rdata_o = 32'h0000_0000;

    unique case (csr_addr_i)
      CSR_ADDR_MSTATUS: csr_rdata_o = mstatus_q;
      CSR_ADDR_MTVEC:   csr_rdata_o = mtvec_q;
      CSR_ADDR_MEPC:    csr_rdata_o = mepc_q;
      CSR_ADDR_MCAUSE:  csr_rdata_o = mcause_q;
      default:          csr_rdata_o = 32'h0000_0000;
    endcase
  end

endmodule
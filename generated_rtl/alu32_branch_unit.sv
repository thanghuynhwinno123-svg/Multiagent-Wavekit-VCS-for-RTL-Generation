`timescale 1ns/1ps

module alu32_branch_unit (
  input  logic [31:0] op_a_i,
  input  logic [31:0] op_b_i,
  input  logic [31:0] pc_i,
  input  logic [31:0] imm_i,
  input  logic [3:0]  alu_op_i,
  input  logic [2:0]  branch_op_i,
  output logic [31:0] result_o,
  output logic        branch_taken_o,
  output logic [31:0] branch_target_o
);

  import rv32ec_zmmul_core_pkg::*;

  logic        eq_cmp;
  logic        slt_signed_cmp;
  logic        slt_unsigned_cmp;
  logic [31:0] pc_plus_imm;
  logic [31:0] jalr_target;

  always_comb begin
    eq_cmp           = (op_a_i == op_b_i);
    slt_signed_cmp   = ($signed(op_a_i) < $signed(op_b_i));
    slt_unsigned_cmp = (op_a_i < op_b_i);
    pc_plus_imm      = pc_i + imm_i;
    jalr_target      = (op_a_i + imm_i) & 32'hFFFF_FFFE;

    result_o        = 32'h0000_0000;
    branch_taken_o  = 1'b0;
    branch_target_o = 32'h0000_0000;

    case (alu_op_i)
      4'd0: result_o = op_a_i + op_b_i;
      4'd1: result_o = op_a_i - op_b_i;
      4'd2: result_o = op_a_i & op_b_i;
      4'd3: result_o = op_a_i | op_b_i;
      4'd4: result_o = op_a_i ^ op_b_i;
      4'd5: result_o = op_a_i << op_b_i[4:0];
      4'd6: result_o = op_a_i >> op_b_i[4:0];
      4'd7: result_o = $signed(op_a_i) >>> op_b_i[4:0];
      4'd8: result_o = {31'd0, slt_signed_cmp};
      4'd9: result_o = {31'd0, slt_unsigned_cmp};
      default: result_o = 32'h0000_0000;
    endcase

    case (branch_op_i)
      3'd0: begin
        branch_taken_o  = 1'b0;
        branch_target_o = 32'h0000_0000;
      end
      3'd1: begin
        branch_taken_o  = eq_cmp;
        branch_target_o = pc_plus_imm;
      end
      3'd2: begin
        branch_taken_o  = ~eq_cmp;
        branch_target_o = pc_plus_imm;
      end
      3'd3: begin
        branch_taken_o  = slt_signed_cmp;
        branch_target_o = pc_plus_imm;
      end
      3'd4: begin
        branch_taken_o  = ~slt_unsigned_cmp;
        branch_target_o = pc_plus_imm;
      end
      3'd5: begin
        branch_taken_o  = slt_unsigned_cmp;
        branch_target_o = pc_plus_imm;
      end
      3'd6: begin
        branch_taken_o  = 1'b1;
        branch_target_o = pc_plus_imm;
      end
      3'd7: begin
        branch_taken_o  = 1'b1;
        branch_target_o = jalr_target;
      end
      default: begin
        branch_taken_o  = 1'b0;
        branch_target_o = 32'h0000_0000;
      end
    endcase
  end

endmodule
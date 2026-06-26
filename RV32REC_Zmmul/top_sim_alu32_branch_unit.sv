`timescale 1ns/1ps

module top_sim_alu32_branch_unit;

  import rv32ec_zmmul_core_pkg::*;

  logic [31:0] op_a_i;
  logic [31:0] op_b_i;
  logic [31:0] pc_i;
  logic [31:0] imm_i;
  logic [3:0]  alu_op_i;
  logic [2:0]  branch_op_i;
  logic [31:0] result_o;
  logic        branch_taken_o;
  logic [31:0] branch_target_o;

  alu32_branch_unit dut (
    .op_a_i(op_a_i),
    .op_b_i(op_b_i),
    .pc_i(pc_i),
    .imm_i(imm_i),
    .alu_op_i(alu_op_i),
    .branch_op_i(branch_op_i),
    .result_o(result_o),
    .branch_taken_o(branch_taken_o),
    .branch_target_o(branch_target_o)
  );

  tb_alu32_branch_unit tb (
    .op_a_i(op_a_i),
    .op_b_i(op_b_i),
    .pc_i(pc_i),
    .imm_i(imm_i),
    .alu_op_i(alu_op_i),
    .branch_op_i(branch_op_i),
    .result_o(result_o),
    .branch_taken_o(branch_taken_o),
    .branch_target_o(branch_target_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_alu32_branch_unit);
  end

endmodule
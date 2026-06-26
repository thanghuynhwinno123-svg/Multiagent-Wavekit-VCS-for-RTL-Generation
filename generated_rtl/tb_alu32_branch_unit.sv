`timescale 1ns/1ps

module tb_alu32_branch_unit (
  output logic [31:0] op_a_i,
  output logic [31:0] op_b_i,
  output logic [31:0] pc_i,
  output logic [31:0] imm_i,
  output logic [3:0]  alu_op_i,
  output logic [2:0]  branch_op_i,
  input  logic [31:0] result_o,
  input  logic        branch_taken_o,
  input  logic [31:0] branch_target_o
);

  integer cycle_count = 0;
  integer pass_count = 0;
  integer fail_count = 0;

  initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish;
  end

  task automatic golden_model(
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [31:0] pc,
    input  logic [31:0] imm,
    input  logic [3:0]  alu_op,
    input  logic [2:0]  branch_op,
    output logic [31:0] exp_result,
    output logic        exp_branch_taken,
    output logic [31:0] exp_branch_target
  );
    begin
      case (alu_op)
        4'd0: exp_result = a + b;
        4'd1: exp_result = a - b;
        4'd2: exp_result = a & b;
        4'd3: exp_result = a | b;
        4'd4: exp_result = a ^ b;
        4'd5: exp_result = a << b[4:0];
        4'd6: exp_result = a >> b[4:0];
        4'd7: exp_result = $signed(a) >>> b[4:0];
        4'd8: exp_result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
        4'd9: exp_result = (a < b) ? 32'd1 : 32'd0;
        default: exp_result = 32'd0;
      endcase

      exp_branch_taken  = 1'b0;
      exp_branch_target = 32'd0;

      case (branch_op)
        3'd0: begin
          exp_branch_taken  = 1'b0;
          exp_branch_target = 32'd0;
        end
        3'd1: begin
          exp_branch_taken  = (a == b);
          exp_branch_target = pc + imm;
        end
        3'd2: begin
          exp_branch_taken  = (a != b);
          exp_branch_target = pc + imm;
        end
        3'd3: begin
          exp_branch_taken  = ($signed(a) < $signed(b));
          exp_branch_target = pc + imm;
        end
        3'd4: begin
          exp_branch_taken  = (a >= b);
          exp_branch_target = pc + imm;
        end
        3'd5: begin
          exp_branch_taken  = ($signed(a) >= $signed(b));
          exp_branch_target = pc + imm;
        end
        3'd6: begin
          exp_branch_taken  = 1'b1;
          exp_branch_target = pc + imm;
        end
        3'd7: begin
          exp_branch_taken  = 1'b1;
          exp_branch_target = (a + imm) & 32'hFFFF_FFFE;
        end
        default: begin
          exp_branch_taken  = 1'b0;
          exp_branch_target = 32'd0;
        end
      endcase
    end
  endtask

  task automatic check_signal_32(
    input string tc_name,
    input string signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val,
    inout bit tc_fail
  );
    begin
      if (got_val !== exp_val) begin
        tc_fail = 1'b1;
        fail_count = fail_count + 1;
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
      end
    end
  endtask

  task automatic check_signal_1(
    input string tc_name,
    input string signal_name,
    input logic got_val,
    input logic exp_val,
    inout bit tc_fail
  );
    begin
      if (got_val !== exp_val) begin
        tc_fail = 1'b1;
        fail_count = fail_count + 1;
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
      end
    end
  endtask

  task automatic run_case(
    input string       tc_name,
    input logic [31:0] a,
    input logic [31:0] b,
    input logic [31:0] pc,
    input logic [31:0] imm,
    input logic [3:0]  alu_op,
    input logic [2:0]  branch_op,
    input bit          check_result
  );
    logic [31:0] exp_result;
    logic        exp_branch_taken;
    logic [31:0] exp_branch_target;
    bit          tc_fail;
    begin
      op_a_i      = a;
      op_b_i      = b;
      pc_i        = pc;
      imm_i       = imm;
      alu_op_i    = alu_op;
      branch_op_i = branch_op;

      #1;

      golden_model(a, b, pc, imm, alu_op, branch_op,
                   exp_result, exp_branch_taken, exp_branch_target);

      tc_fail = 1'b0;

      if (check_result) begin
        check_signal_32(tc_name, "result_o", result_o, exp_result, tc_fail);
      end
      check_signal_1(tc_name, "branch_taken_o", branch_taken_o, exp_branch_taken, tc_fail);
      check_signal_32(tc_name, "branch_target_o", branch_target_o, exp_branch_target, tc_fail);

      if (!tc_fail) begin
        pass_count = pass_count + 1;
        $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
      end
    end
  endtask

  initial begin
    op_a_i      = 32'd0;
    op_b_i      = 32'd0;
    pc_i        = 32'd0;
    imm_i       = 32'd0;
    alu_op_i    = 4'd0;
    branch_op_i = 3'd0;

    #1;

    run_case("TC001_ADD",            32'h0000_0005, 32'h0000_0003, 32'h0000_0000, 32'h0000_0000, 4'd0, 3'd0, 1'b1);
    run_case("TC002_SUB",            32'h0000_0005, 32'h0000_0003, 32'h0000_0000, 32'h0000_0000, 4'd1, 3'd0, 1'b1);
    run_case("TC003_AND",            32'h0000_00F0, 32'h0000_00CC, 32'h0000_0000, 32'h0000_0000, 4'd2, 3'd0, 1'b1);
    run_case("TC004_OR",             32'h0000_00F0, 32'h0000_000C, 32'h0000_0000, 32'h0000_0000, 4'd3, 3'd0, 1'b1);
    run_case("TC005_XOR",            32'h0000_00F0, 32'h0000_00CC, 32'h0000_0000, 32'h0000_0000, 4'd4, 3'd0, 1'b1);
    run_case("TC006_SLL",            32'h0000_0003, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 4'd5, 3'd0, 1'b1);
    run_case("TC007_SRL",            32'h8000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 4'd6, 3'd0, 1'b1);
    run_case("TC008_SRA",            32'h8000_0000, 32'h0000_0004, 32'h0000_0000, 32'h0000_0000, 4'd7, 3'd0, 1'b1);
    run_case("TC009_SLT_SIGNED",     32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0000, 32'h0000_0000, 4'd8, 3'd0, 1'b1);
    run_case("TC010_SLTU",           32'h0000_0001, 32'hFFFF_FFFF, 32'h0000_0000, 32'h0000_0000, 4'd9, 3'd0, 1'b1);
    run_case("TC011_BEQ_TAKEN",      32'h0000_0009, 32'h0000_0009, 32'h0000_0100, 32'h0000_0010, 4'd0, 3'd1, 1'b1);
    run_case("TC012_BNE_TAKEN",      32'h0000_0009, 32'h0000_0008, 32'h0000_0100, 32'h0000_0010, 4'd0, 3'd2, 1'b0);
    run_case("TC013_BLT_TAKEN",      32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0100, 32'h0000_0010, 4'd0, 3'd3, 1'b0);
    run_case("TC014_BGEU_TAKEN",     32'hFFFF_FFFF, 32'h0000_0001, 32'h0000_0100, 32'h0000_0010, 4'd0, 3'd4, 1'b0);
    run_case("TC015_JAL_TARGET",     32'h0000_0000, 32'h0000_0000, 32'h0000_0200, 32'h0000_0020, 4'd0, 3'd6, 1'b0);
    run_case("TC016_JALR_TARGET",    32'h0000_0301, 32'h0000_0000, 32'h0000_0000, 32'h0000_0008, 4'd0, 3'd7, 1'b0);

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
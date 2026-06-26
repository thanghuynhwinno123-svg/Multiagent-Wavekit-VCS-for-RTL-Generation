`timescale 1ns/1ps

module tb_multiplier_unit (
  output logic        clk,
  output logic        rst_n,
  output logic        start_i,
  output logic [31:0] op_a_i,
  output logic [31:0] op_b_i,
  input  logic        busy_o,
  input  logic        done_o,
  input  logic [31:0] result_o
);

  integer pass_count = 0;
  integer fail_count = 0;
  integer cycle_count = 0;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
  end

  initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish;
  end

  task automatic golden_mul(
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] exp_result
  );
    logic [63:0] full_product;
    begin
      full_product = a * b;
      exp_result   = full_product[31:0];
    end
  endtask

  task automatic check_value(
    input string       tc_name,
    input string       signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val,
    inout integer      tc_fail_local
  );
    begin
      if (got_val !== exp_val) begin
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
        fail_count    = fail_count + 1;
        tc_fail_local = tc_fail_local + 1;
      end
    end
  endtask

  task automatic finish_testcase(
    input string  tc_name,
    input integer tc_fail_local
  );
    begin
      if (tc_fail_local == 0) begin
        pass_count = pass_count + 1;
        $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
      end
    end
  endtask

  task automatic drive_idle;
    begin
      start_i = 1'b0;
      op_a_i  = 32'h00000000;
      op_b_i  = 32'h00000000;
    end
  endtask

  task automatic wait_for_idle;
    integer wait_cycles;
    begin
      wait_cycles = 0;
      while ((busy_o === 1'b1 || done_o === 1'b1) && (wait_cycles < 1000)) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
      end
    end
  endtask

  task automatic tc_reset_idle;
    string  tc_name;
    integer tc_fail_local;
    begin
      tc_name       = "TC001_RESET_IDLE";
      tc_fail_local = 0;

      drive_idle();
      rst_n = 1'b1;
      #1;
      rst_n = 1'b0;
      #1;

      check_value(tc_name, "busy_o",   {31'd0, busy_o},   32'h00000000, tc_fail_local);
      check_value(tc_name, "done_o",   {31'd0, done_o},   32'h00000000, tc_fail_local);
      check_value(tc_name, "result_o", result_o,          32'h00000000, tc_fail_local);

      @(posedge clk);
      #1;
      check_value(tc_name, "busy_o",   {31'd0, busy_o},   32'h00000000, tc_fail_local);
      check_value(tc_name, "done_o",   {31'd0, done_o},   32'h00000000, tc_fail_local);
      check_value(tc_name, "result_o", result_o,          32'h00000000, tc_fail_local);

      rst_n = 1'b1;
      @(posedge clk);
      #1;

      finish_testcase(tc_name, tc_fail_local);
    end
  endtask

  task automatic tc_run_multiply(
    input string       tc_name,
    input logic [31:0] a,
    input logic [31:0] b,
    input bit          check_busy_hold
  );
    logic [31:0] exp_result;
    integer      tc_fail_local;
    integer      wait_cycles;
    begin
      tc_fail_local = 0;
      golden_mul(a, b, exp_result);

      wait_for_idle();

      @(negedge clk);
      op_a_i   = a;
      op_b_i   = b;
      start_i  = 1'b1;
      rst_n    = 1'b1;

      @(posedge clk);
      #1;
      start_i = 1'b0;

      check_value(tc_name, "busy_o", {31'd0, busy_o}, 32'h00000001, tc_fail_local);

      wait_cycles = 0;
      while ((done_o !== 1'b1) && (wait_cycles < 1000)) begin
        if (check_busy_hold) begin
          check_value(tc_name, "busy_o", {31'd0, busy_o}, 32'h00000001, tc_fail_local);
        end
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
      end

      if (done_o !== 1'b1) begin
        $display("[TESTCASE_RESULT] FAIL: %0s.done_o | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, {31'd0, done_o}, 32'h00000001, cycle_count, $time);
        fail_count    = fail_count + 1;
        tc_fail_local = tc_fail_local + 1;
      end
      else begin
        check_value(tc_name, "done_o",   {31'd0, done_o}, 32'h00000001, tc_fail_local);
        check_value(tc_name, "result_o", result_o,        exp_result,   tc_fail_local);

        @(posedge clk);
        #1;
        check_value(tc_name, "done_o", {31'd0, done_o}, 32'h00000000, tc_fail_local);
      end

      finish_testcase(tc_name, tc_fail_local);
    end
  endtask

  initial begin
    rst_n   = 1'b1;
    start_i = 1'b0;
    op_a_i  = 32'h00000000;
    op_b_i  = 32'h00000000;

    tc_reset_idle();
    tc_run_multiply("TC002_MUL_POSITIVE",             32'h00000006, 32'h00000007, 1'b0);
    tc_run_multiply("TC003_MUL_BY_ZERO",              32'h12345678, 32'h00000000, 1'b0);
    tc_run_multiply("TC004_MUL_NEGATIVE_OPERAND_LOW32", 32'hFFFFFFFF, 32'h00000002, 1'b0);
    tc_run_multiply("TC005_MUL_OVERFLOW_LOW32",       32'h80000000, 32'h00000002, 1'b0);
    tc_run_multiply("TC006_BUSY_HOLDS_UNTIL_DONE",    32'h00000003, 32'h00000005, 1'b1);

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
`timescale 1ns/1ps

module tb_regfile_16x32 (
  output logic        clk,
  output logic        rst_n,
  output logic [3:0]  raddr1_i,
  output logic [3:0]  raddr2_i,
  output logic        we_i,
  output logic [3:0]  waddr_i,
  output logic [31:0] wdata_i,
  input  logic [31:0] rdata1_o,
  input  logic [31:0] rdata2_o
);

  logic [31:0] golden_regs [0:15];
  integer cycle_count = 0;
  integer pass_count = 0;
  integer fail_count = 0;

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

  task automatic init_outputs;
    begin
      rst_n    = 1'b1;
      raddr1_i = 4'd0;
      raddr2_i = 4'd0;
      we_i     = 1'b0;
      waddr_i  = 4'd0;
      wdata_i  = 32'd0;
    end
  endtask

  task automatic init_golden;
    integer idx;
    begin
      for (idx = 0; idx < 16; idx = idx + 1) begin
        golden_regs[idx] = 32'hxxxx_xxxx;
      end
      golden_regs[0] = 32'd0;
    end
  endtask

  task automatic get_expected_read;
    input  logic [3:0] addr;
    output logic [31:0] exp_data;
    begin
      if (addr == 4'd0) begin
        exp_data = 32'd0;
      end else begin
        exp_data = golden_regs[addr];
      end
    end
  endtask

  task automatic update_golden_after_edge;
    begin
      if ((rst_n === 1'b1) && (we_i === 1'b1) && (waddr_i != 4'd0)) begin
        golden_regs[waddr_i] = wdata_i;
      end
      golden_regs[0] = 32'd0;
    end
  endtask

  task automatic check_signal;
    input string tc_name;
    input string signal_name;
    input logic [31:0] got_val;
    input logic [31:0] exp_val;
    inout bit tc_failed;
    begin
      if (got_val !== exp_val) begin
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
        fail_count = fail_count + 1;
        tc_failed = 1'b1;
      end
    end
  endtask

  task automatic finish_testcase;
    input string tc_name;
    input bit tc_failed;
    begin
      if (!tc_failed) begin
        $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
        pass_count = pass_count + 1;
      end
    end
  endtask

  task automatic run_reset_test;
    string tc_name;
    bit tc_failed;
    logic [31:0] exp1;
    logic [31:0] exp2;
    begin
      tc_name = "TC000_RESET";
      tc_failed = 1'b0;

      rst_n    = 1'b0;
      raddr1_i = 4'd0;
      raddr2_i = 4'd0;
      we_i     = 1'b0;
      waddr_i  = 4'd0;
      wdata_i  = ~32'd0;

      #1;
      get_expected_read(raddr1_i, exp1);
      get_expected_read(raddr2_i, exp2);
      check_signal(tc_name, "rdata1_o", rdata1_o, exp1, tc_failed);
      check_signal(tc_name, "rdata2_o", rdata2_o, exp2, tc_failed);

      finish_testcase(tc_name, tc_failed);

      rst_n = 1'b1;
      #1;
    end
  endtask

  task automatic run_comb_read_test;
    input string tc_name;
    input logic [3:0] addr1;
    input logic [3:0] addr2;
    input logic       we_val;
    input logic [3:0] waddr_val;
    input logic [31:0] wdata_val;
    bit tc_failed;
    logic [31:0] exp1;
    logic [31:0] exp2;
    begin
      tc_failed = 1'b0;

      raddr1_i = addr1;
      raddr2_i = addr2;
      we_i     = we_val;
      waddr_i  = waddr_val;
      wdata_i  = wdata_val;

      #1;
      get_expected_read(addr1, exp1);
      get_expected_read(addr2, exp2);
      check_signal(tc_name, "rdata1_o", rdata1_o, exp1, tc_failed);
      check_signal(tc_name, "rdata2_o", rdata2_o, exp2, tc_failed);

      finish_testcase(tc_name, tc_failed);
    end
  endtask

  task automatic run_write_cycle_test;
    input string tc_name;
    input logic [3:0] addr1;
    input logic [3:0] addr2;
    input logic       we_val;
    input logic [3:0] waddr_val;
    input logic [31:0] wdata_val;
    bit tc_failed;
    logic [31:0] exp1;
    logic [31:0] exp2;
    begin
      tc_failed = 1'b0;

      raddr1_i = addr1;
      raddr2_i = addr2;
      we_i     = we_val;
      waddr_i  = waddr_val;
      wdata_i  = wdata_val;

      @(posedge clk);
      update_golden_after_edge();
      #1;

      get_expected_read(addr1, exp1);
      get_expected_read(addr2, exp2);
      check_signal(tc_name, "rdata1_o", rdata1_o, exp1, tc_failed);
      check_signal(tc_name, "rdata2_o", rdata2_o, exp2, tc_failed);

      finish_testcase(tc_name, tc_failed);
    end
  endtask

  initial begin
    init_outputs();
    init_golden();

    run_reset_test();

    run_comb_read_test("TC001_READ_X0_ZERO", 4'd0, 4'd0, 1'b0, 4'd0, ~32'd0);

    run_write_cycle_test("TC002_WRITE_READ_X1", 4'd1, 4'd0, 1'b1, 4'd1, 32'h1234_5678);

    run_write_cycle_test("TC003_WRITE_READ_X15", 4'd15, 4'd1, 1'b1, 4'd15, 32'hA5A5_A5A5);

    run_write_cycle_test("TC004_WRITE_X0_IGNORED", 4'd0, 4'd1, 1'b1, 4'd0, 32'hDEAD_BEEF);

    run_write_cycle_test("TC005_WRITE_DISABLE_NO_CHANGE", 4'd1, 4'd15, 1'b0, 4'd2, 32'hCAFE_BABE);

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
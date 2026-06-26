`timescale 1ns/1ps

module tb_rv32ec_zmmul_cpu_top (
  output logic        clk,
  output logic        rst_n,
  output logic        boot_mode_spi,
  output logic        ext_irq,
  output logic        instr_ready,
  output logic [31:0] instr_rdata,
  output logic        data_ready,
  output logic [31:0] data_rdata,
  output logic        spi_ready,
  output logic [31:0] spi_rdata,
  input  logic        instr_req,
  input  logic [31:0] instr_addr,
  input  logic        data_req,
  input  logic        data_we,
  input  logic [3:0]  data_be,
  input  logic [31:0] data_addr,
  input  logic [31:0] data_wdata,
  input  logic        spi_req,
  input  logic [31:0] spi_addr,
  input  logic        fail_stop
);

  localparam logic [31:0] RESET_PC = 32'd0;
  localparam logic [31:0] NOP_INSTR = 32'h00000013;

  integer cycle_count = 0;
  integer pass_count  = 0;
  integer fail_count  = 0;
  integer case_fail_base;

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

  function automatic logic [31:0] next_seq_pc(
    input logic [31:0] pc_i,
    input logic        is_compressed_i
  );
    next_seq_pc = pc_i + (is_compressed_i ? 32'd2 : 32'd4);
  endfunction

  function automatic logic [31:0] expected_boot_pc(
    input logic [31:0] spi_word_i
  );
    expected_boot_pc = spi_word_i;
  endfunction

  function automatic logic [31:0] invalid_boot_word();
    invalid_boot_word = ~32'd0;
  endfunction

  task automatic tick();
    @(posedge clk);
    #1;
  endtask

  task automatic drive_defaults();
    rst_n         = 1'b1;
    boot_mode_spi = 1'b0;
    ext_irq       = 1'b0;
    instr_ready   = 1'b0;
    instr_rdata   = 32'd0;
    data_ready    = 1'b0;
    data_rdata    = 32'd0;
    spi_ready     = 1'b0;
    spi_rdata     = 32'd0;
  endtask

  task automatic start_case(input string tc_name);
    case_fail_base = fail_count;
    $display("Running %0s", tc_name);
  endtask

  task automatic finish_case(input string tc_name);
    if (fail_count == case_fail_base) begin
      pass_count = pass_count + 1;
      $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
    end
  endtask

  task automatic check_eq32(
    input string       tc_name,
    input string       signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val
  );
    if (got_val !== exp_val) begin
      fail_count = fail_count + 1;
      $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
               tc_name, signal_name, got_val, exp_val, cycle_count, $time);
    end
  endtask

  task automatic check_eq1(
    input string tc_name,
    input string signal_name,
    input logic  got_val,
    input logic  exp_val
  );
    check_eq32(tc_name, signal_name, {31'd0, got_val}, {31'd0, exp_val});
  endtask

  task automatic check_ne32(
    input string       tc_name,
    input string       signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val
  );
    if (got_val === exp_val) begin
      fail_count = fail_count + 1;
      $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
               tc_name, signal_name, got_val, exp_val, cycle_count, $time);
    end
  endtask

  task automatic reset_core(input logic spi_mode_i);
    drive_defaults();
    boot_mode_spi = spi_mode_i;
    rst_n = 1'b0;
    #1;
    tick();
    tick();
    rst_n = 1'b1;
    tick();
  endtask

  task automatic wait_for_instr_req_within(
    input  integer      max_cycles,
    output bit          seen,
    output logic [31:0] seen_addr
  );
    integer i;
    seen = 1'b0;
    seen_addr = 32'd0;
    for (i = 0; i < max_cycles; i = i + 1) begin
      if (instr_req) begin
        seen = 1'b1;
        seen_addr = instr_addr;
        break;
      end
      tick();
    end
  endtask

  task automatic wait_for_data_req_within(
    input  integer      max_cycles,
    output bit          seen,
    output logic [31:0] seen_addr
  );
    integer i;
    seen = 1'b0;
    seen_addr = 32'd0;
    for (i = 0; i < max_cycles; i = i + 1) begin
      if (data_req) begin
        seen = 1'b1;
        seen_addr = data_addr;
        break;
      end
      tick();
    end
  endtask

  task automatic wait_for_spi_req_within(
    input integer max_cycles,
    output bit    seen
  );
    integer i;
    seen = 1'b0;
    for (i = 0; i < max_cycles; i = i + 1) begin
      if (spi_req) begin
        seen = 1'b1;
        break;
      end
      tick();
    end
  endtask

  task automatic issue_instruction(
    input  logic [31:0] instr_word_i,
    output logic [31:0] issue_pc_o
  );
    bit seen;
    logic [31:0] seen_addr;

    wait_for_instr_req_within(8, seen, seen_addr);
    issue_pc_o = seen_addr;
    if (!seen) begin
      issue_pc_o = 32'd0;
      return;
    end

    instr_ready = 1'b1;
    instr_rdata = instr_word_i;
    tick();
    instr_ready = 1'b0;
    instr_rdata = 32'd0;
  endtask

  task automatic pulse_spi_word(input logic [31:0] spi_word_i);
    spi_ready = 1'b1;
    spi_rdata = spi_word_i;
    tick();
    spi_ready = 1'b0;
    spi_rdata = 32'd0;
  endtask

  task automatic pulse_data_ready(input logic [31:0] data_word_i);
    data_ready = 1'b1;
    data_rdata = data_word_i;
    tick();
    data_ready = 1'b0;
    data_rdata = 32'd0;
  endtask

  initial begin : run_all_tests
    string tc;
    bit seen;
    logic [31:0] addr0;
    logic [31:0] addr1;
    logic [31:0] addr2;
    logic [31:0] seq_pc;
    logic [31:0] boot_word;
    logic [31:0] saved_mepc;
    integer i;

    drive_defaults();
    tick();

    tc = "TC001_RESET_FETCH";
    start_case(tc);
    reset_core(1'b0);
    wait_for_instr_req_within(4, seen, addr0);
    check_eq1(tc, "instr_req", seen, 1'b1);
    if (seen) begin
      check_eq32(tc, "instr_addr", addr0, RESET_PC);
    end
    check_eq1(tc, "data_req", data_req, 1'b0);
    check_eq1(tc, "spi_req", spi_req, 1'b0);
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    tc = "TC002_SPI_BOOT_START";
    start_case(tc);
    reset_core(1'b1);
    wait_for_spi_req_within(4, seen);
    check_eq1(tc, "spi_req", seen, 1'b1);
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    tc = "TC003_SPI_BOOT_SUCCESS";
    start_case(tc);
    reset_core(1'b1);
    wait_for_spi_req_within(4, seen);
    check_eq1(tc, "spi_req", seen, 1'b1);
    boot_word = 32'd32;
    pulse_spi_word(boot_word);
    wait_for_instr_req_within(6, seen, addr0);
    check_eq1(tc, "instr_req", seen, 1'b1);
    if (seen) begin
      check_eq32(tc, "instr_addr", addr0, expected_boot_pc(boot_word));
    end
    check_eq1(tc, "spi_req", spi_req, 1'b0);
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    tc = "TC004_SPI_BOOT_FAILSTOP";
    start_case(tc);
    reset_core(1'b1);
    wait_for_spi_req_within(4, seen);
    check_eq1(tc, "spi_req", seen, 1'b1);
    pulse_spi_word(invalid_boot_word());
    tick();
    check_eq1(tc, "fail_stop", fail_stop, 1'b1);
    check_eq1(tc, "instr_req", instr_req, 1'b0);
    check_eq1(tc, "data_req", data_req, 1'b0);
    finish_case(tc);

    tc = "TC005_LOAD_HANDSHAKE";
    start_case(tc);
    reset_core(1'b0);
    issue_instruction(32'h00002283, addr0);
    wait_for_data_req_within(8, seen, addr1);
    check_eq1(tc, "data_req", seen, 1'b1);
    if (seen) begin
      check_eq1(tc, "data_we", data_we, 1'b0);
      check_eq32(tc, "data_addr", addr1, RESET_PC);
    end
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    tc = "TC006_STORE_HANDSHAKE";
    start_case(tc);
    reset_core(1'b0);
    issue_instruction(32'h00102023, addr0);
    wait_for_data_req_within(8, seen, addr1);
    check_eq1(tc, "data_req", seen, 1'b1);
    if (seen) begin
      check_eq1(tc, "data_we", data_we, 1'b1);
      check_eq32(tc, "data_addr", addr1, RESET_PC);
      check_eq32(tc, "data_wdata", data_wdata, 32'd0);
    end
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    tc = "TC007_BRANCH_REDIRECT";
    start_case(tc);
    reset_core(1'b0);
    issue_instruction(32'h0000006F, addr0);
    wait_for_instr_req_within(6, seen, addr1);
    check_eq1(tc, "instr_req", seen, 1'b1);
    if (seen) begin
      check_eq32(tc, "instr_addr", addr1, addr0);
    end
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    tc = "TC008_ILLEGAL_DIV_TRAP";
    start_case(tc);
    reset_core(1'b0);
    issue_instruction(32'h02004033, addr0);
    seq_pc = next_seq_pc(addr0, 1'b0);
    wait_for_instr_req_within(8, seen, addr1);
    check_eq1(tc, "instr_req", seen, 1'b1);
    if (seen) begin
      check_ne32(tc, "instr_addr", addr1, seq_pc);
    end
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    tc = "TC009_INTERRUPT_ENTRY";
    start_case(tc);
    reset_core(1'b0);
    ext_irq = 1'b1;
    issue_instruction(NOP_INSTR, addr0);
    seq_pc = next_seq_pc(addr0, 1'b0);
    wait_for_instr_req_within(8, seen, addr1);
    check_eq1(tc, "instr_req", seen, 1'b1);
    if (seen) begin
      check_ne32(tc, "instr_addr", addr1, seq_pc);
    end
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    ext_irq = 1'b0;
    finish_case(tc);

    tc = "TC010_MEMORY_WAIT_STALL";
    start_case(tc);
    reset_core(1'b0);
    issue_instruction(32'h00002283, addr0);
    wait_for_data_req_within(8, seen, addr1);
    check_eq1(tc, "data_req", seen, 1'b1);
    addr2 = instr_addr;
    for (i = 0; i < 3; i = i + 1) begin
      tick();
      check_eq1(tc, "data_req", data_req, 1'b1);
      check_eq32(tc, "instr_addr", instr_addr, addr2);
    end
    pulse_data_ready(32'hA5A5A5A5);
    finish_case(tc);

    tc = "TC011_MUL_NO_TRAP";
    start_case(tc);
    reset_core(1'b0);
    issue_instruction(32'h022081B3, addr0);
    addr1 = instr_addr;
    for (i = 0; i < 2; i = i + 1) begin
      tick();
      check_eq1(tc, "fail_stop", fail_stop, 1'b0);
      check_eq1(tc, "data_req", data_req, 1'b0);
      check_eq32(tc, "instr_addr", instr_addr, addr1);
    end
    finish_case(tc);

    tc = "TC012_MRET_RETURN";
    start_case(tc);
    reset_core(1'b0);
    issue_instruction(32'h02004033, addr0);
    saved_mepc = addr0;
    wait_for_instr_req_within(8, seen, addr1);
    check_eq1(tc, "instr_req", seen, 1'b1);
    issue_instruction(32'h30200073, addr2);
    wait_for_instr_req_within(8, seen, addr1);
    check_eq1(tc, "instr_req", seen, 1'b1);
    if (seen) begin
      check_eq32(tc, "instr_addr", addr1, saved_mepc);
    end
    check_eq1(tc, "fail_stop", fail_stop, 1'b0);
    finish_case(tc);

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
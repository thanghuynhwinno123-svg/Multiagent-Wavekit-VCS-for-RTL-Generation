`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module tb_boot_rom_loader (
  output logic        clk,
  output logic        rst_n,
  output logic        start_i,
  output logic        spi_ready_i,
  output logic [31:0] spi_rdata_i,
  output logic        iram_ready_i,
  output logic        validation_enable_i,
  input  logic        spi_req_o,
  input  logic [31:0] spi_addr_o,
  input  logic        iram_we_o,
  input  logic [31:0] iram_addr_o,
  input  logic [31:0] iram_wdata_o,
  input  logic        done_o,
  input  logic [31:0] boot_pc_o,
  input  logic        fail_stop_o
);

  typedef enum logic [2:0] {
    ST_IDLE_G         = 3'd0,
    ST_FETCH_MAGIC_G  = 3'd1,
    ST_FETCH_SIZE_G   = 3'd2,
    ST_FETCH_BOOTPC_G = 3'd3,
    ST_FETCH_DATA_G   = 3'd4,
    ST_WRITE_DATA_G   = 3'd5,
    ST_DONE_G         = 3'd6,
    ST_FAIL_G         = 3'd7
  } boot_state_g_t;

  localparam logic [31:0] SPI_BASE_ADDR = RV32EC_ZMMUL_SPI_BOOT_BASE_ADDR;
  localparam logic [31:0] IRAM_BASE_ADDR = RV32EC_ZMMUL_IRAM_BASE_ADDR;
  localparam logic [31:0] IRAM_LAST_VALID_PC = RV32EC_ZMMUL_IRAM_BASE_ADDR + 32'd32;
  localparam logic [31:0] BAD_PROGRAM_SIZE =
      ((RV32EC_ZMMUL_BOOT_ROM_BYTES_MAX > RV32EC_ZMMUL_IRAM_BYTES) ?
       RV32EC_ZMMUL_BOOT_ROM_BYTES_MAX : RV32EC_ZMMUL_IRAM_BYTES) + 32'd4;
  localparam integer BOOT_TIMEOUT_WAIT_CYCLES = 520;

  integer cycle_count = 0;
  integer pass_count = 0;
  integer fail_count = 0;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish;
  end

  initial begin
    forever begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
    end
  end

  function automatic logic is_valid_boot_pc_golden(input logic [31:0] pc);
    logic [31:0] iram_limit;
    begin
      iram_limit = RV32EC_ZMMUL_IRAM_BASE_ADDR + RV32EC_ZMMUL_IRAM_BYTES;
      is_valid_boot_pc_golden = (pc[1:0] == 2'b00) &&
                                (pc >= RV32EC_ZMMUL_IRAM_BASE_ADDR) &&
                                (pc < iram_limit);
    end
  endfunction

  task automatic drive_defaults;
    begin
      rst_n                = 1'b1;
      start_i              = 1'b0;
      spi_ready_i          = 1'b0;
      spi_rdata_i          = 32'h0000_0000;
      iram_ready_i         = 1'b0;
      validation_enable_i  = 1'b0;
    end
  endtask

  task automatic golden_outputs_from_state(
    input  boot_state_g_t  exp_state,
    input  logic [31:0]    exp_spi_addr,
    input  logic [31:0]    exp_iram_addr,
    input  logic [31:0]    exp_data,
    input  logic [31:0]    exp_boot_pc,
    output logic           exp_spi_req,
    output logic [31:0]    exp_spi_addr_o,
    output logic           exp_iram_we,
    output logic [31:0]    exp_iram_addr_o,
    output logic [31:0]    exp_iram_wdata,
    output logic           exp_done,
    output logic [31:0]    exp_boot_pc_o,
    output logic           exp_fail_stop
  );
    begin
      exp_spi_req     = 1'b0;
      exp_spi_addr_o  = exp_spi_addr;
      exp_iram_we     = 1'b0;
      exp_iram_addr_o = exp_iram_addr;
      exp_iram_wdata  = exp_data;
      exp_done        = 1'b0;
      exp_boot_pc_o   = exp_boot_pc;
      exp_fail_stop   = 1'b0;

      case (exp_state)
        ST_FETCH_MAGIC_G,
        ST_FETCH_SIZE_G,
        ST_FETCH_BOOTPC_G,
        ST_FETCH_DATA_G: begin
          exp_spi_req    = 1'b1;
          exp_spi_addr_o = exp_spi_addr;
        end

        ST_WRITE_DATA_G: begin
          exp_iram_we     = 1'b1;
          exp_iram_addr_o = exp_iram_addr;
          exp_iram_wdata  = exp_data;
        end

        ST_DONE_G: begin
          exp_done      = 1'b1;
          exp_boot_pc_o = exp_boot_pc;
        end

        ST_FAIL_G: begin
          exp_fail_stop = 1'b1;
        end

        default: begin
        end
      endcase
    end
  endtask

  task automatic check_signal(
    input string tc_name,
    input string signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val,
    inout integer tc_failures
  );
    begin
      if (got_val !== exp_val) begin
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
        fail_count = fail_count + 1;
        tc_failures = tc_failures + 1;
      end
    end
  endtask

  task automatic finish_testcase(
    input string tc_name,
    input integer tc_failures
  );
    begin
      if (tc_failures == 0) begin
        $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
        pass_count = pass_count + 1;
      end
    end
  endtask

  task automatic reset_only;
    begin
      drive_defaults();
      rst_n = 1'b0;
      #2;
      @(posedge clk);
      #1;
      rst_n = 1'b1;
      @(posedge clk);
      #1;
    end
  endtask

  task automatic tc001_reset_idle;
    string tc_name;
    integer tc_failures;
    logic exp_spi_req;
    logic [31:0] exp_spi_addr;
    logic exp_iram_we;
    logic [31:0] exp_iram_addr;
    logic [31:0] exp_iram_wdata;
    logic exp_done;
    logic [31:0] exp_boot_pc;
    logic exp_fail_stop;
    begin
      tc_name = "TC001_RESET_IDLE";
      tc_failures = 0;

      drive_defaults();
      rst_n = 1'b0;
      #1;

      golden_outputs_from_state(
        ST_IDLE_G, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000, 32'h0000_0000,
        exp_spi_req, exp_spi_addr, exp_iram_we, exp_iram_addr,
        exp_iram_wdata, exp_done, exp_boot_pc, exp_fail_stop
      );

      check_signal(tc_name, "spi_req_o",   {31'd0, spi_req_o},   {31'd0, exp_spi_req},   tc_failures);
      check_signal(tc_name, "iram_we_o",   {31'd0, iram_we_o},   {31'd0, exp_iram_we},   tc_failures);
      check_signal(tc_name, "done_o",      {31'd0, done_o},      {31'd0, exp_done},      tc_failures);
      check_signal(tc_name, "fail_stop_o", {31'd0, fail_stop_o}, {31'd0, exp_fail_stop}, tc_failures);

      rst_n = 1'b1;
      @(posedge clk);
      #1;

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  task automatic tc002_start_header_fetch;
    string tc_name;
    integer tc_failures;
    logic exp_spi_req;
    logic [31:0] exp_spi_addr;
    logic exp_iram_we;
    logic [31:0] exp_iram_addr;
    logic [31:0] exp_iram_wdata;
    logic exp_done;
    logic [31:0] exp_boot_pc;
    logic exp_fail_stop;
    begin
      tc_name = "TC002_START_HEADER_FETCH";
      tc_failures = 0;

      reset_only();
      validation_enable_i = 1'b1;
      start_i = 1'b1;
      @(posedge clk);
      #1;
      start_i = 1'b0;

      golden_outputs_from_state(
        ST_FETCH_MAGIC_G, SPI_BASE_ADDR, IRAM_BASE_ADDR, 32'h0000_0000, 32'h0000_0000,
        exp_spi_req, exp_spi_addr, exp_iram_we, exp_iram_addr,
        exp_iram_wdata, exp_done, exp_boot_pc, exp_fail_stop
      );

      check_signal(tc_name, "spi_req_o",   {31'd0, spi_req_o},   {31'd0, exp_spi_req},   tc_failures);
      check_signal(tc_name, "spi_addr_o",  spi_addr_o,           exp_spi_addr,           tc_failures);
      check_signal(tc_name, "done_o",      {31'd0, done_o},      {31'd0, exp_done},      tc_failures);
      check_signal(tc_name, "fail_stop_o", {31'd0, fail_stop_o}, {31'd0, exp_fail_stop}, tc_failures);

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  task automatic tc003_valid_header_accept;
    string tc_name;
    integer tc_failures;
    logic exp_spi_req;
    logic [31:0] exp_spi_addr;
    logic exp_iram_we;
    logic [31:0] exp_iram_addr;
    logic [31:0] exp_iram_wdata;
    logic exp_done;
    logic [31:0] exp_boot_pc;
    logic exp_fail_stop;
    begin
      tc_name = "TC003_VALID_HEADER_ACCEPT";
      tc_failures = 0;

      reset_only();
      validation_enable_i = 1'b1;
      start_i = 1'b1;
      @(posedge clk);
      #1;
      start_i = 1'b0;

      spi_ready_i = 1'b1;
      spi_rdata_i = RV32EC_ZMMUL_BOOT_MAGIC;
      @(posedge clk);
      #1;
      spi_ready_i = 1'b0;

      golden_outputs_from_state(
        ST_FETCH_SIZE_G, SPI_BASE_ADDR + 32'd4, IRAM_BASE_ADDR, 32'h0000_0000, 32'h0000_0000,
        exp_spi_req, exp_spi_addr, exp_iram_we, exp_iram_addr,
        exp_iram_wdata, exp_done, exp_boot_pc, exp_fail_stop
      );

      check_signal(tc_name, "spi_req_o",   {31'd0, spi_req_o},   {31'd0, exp_spi_req},   tc_failures);
      check_signal(tc_name, "fail_stop_o", {31'd0, fail_stop_o}, {31'd0, exp_fail_stop}, tc_failures);

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  task automatic tc004_program_word_copy;
    string tc_name;
    integer tc_failures;
    logic exp_spi_req;
    logic [31:0] exp_spi_addr;
    logic exp_iram_we;
    logic [31:0] exp_iram_addr;
    logic [31:0] exp_iram_wdata;
    logic exp_done;
    logic [31:0] exp_boot_pc;
    logic exp_fail_stop;
    logic [31:0] copy_word;
    begin
      tc_name = "TC004_PROGRAM_WORD_COPY";
      tc_failures = 0;
      copy_word = 32'h1122_3344;

      reset_only();
      validation_enable_i = 1'b0;
      start_i = 1'b1;
      @(posedge clk);
      #1;
      start_i = 1'b0;

      spi_ready_i = 1'b1;
      spi_rdata_i = copy_word;
      iram_ready_i = 1'b0;
      @(posedge clk);
      #1;
      spi_ready_i = 1'b0;

      golden_outputs_from_state(
        ST_WRITE_DATA_G, SPI_BASE_ADDR, IRAM_BASE_ADDR, copy_word, 32'h0000_0000,
        exp_spi_req, exp_spi_addr, exp_iram_we, exp_iram_addr,
        exp_iram_wdata, exp_done, exp_boot_pc, exp_fail_stop
      );

      check_signal(tc_name, "iram_we_o",   {31'd0, iram_we_o},   {31'd0, exp_iram_we},   tc_failures);
      if (exp_iram_we) begin
        check_signal(tc_name, "iram_wdata_o", iram_wdata_o, exp_iram_wdata, tc_failures);
      end
      check_signal(tc_name, "fail_stop_o", {31'd0, fail_stop_o}, {31'd0, exp_fail_stop}, tc_failures);

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  task automatic tc005_boot_success;
    string tc_name;
    integer tc_failures;
    logic exp_spi_req;
    logic [31:0] exp_spi_addr;
    logic exp_iram_we;
    logic [31:0] exp_iram_addr;
    logic [31:0] exp_iram_wdata;
    logic exp_done;
    logic [31:0] exp_boot_pc;
    logic exp_fail_stop;
    logic [31:0] boot_pc_word;
    begin
      tc_name = "TC005_BOOT_SUCCESS";
      tc_failures = 0;
      boot_pc_word = IRAM_LAST_VALID_PC;

      reset_only();
      validation_enable_i = 1'b0;
      start_i = 1'b1;
      @(posedge clk);
      #1;
      start_i = 1'b0;

      spi_ready_i = 1'b1;
      spi_rdata_i = boot_pc_word;
      @(posedge clk);
      #1;
      spi_ready_i = 1'b0;

      golden_outputs_from_state(
        ST_DONE_G, SPI_BASE_ADDR, IRAM_BASE_ADDR, 32'h0000_0000, boot_pc_word,
        exp_spi_req, exp_spi_addr, exp_iram_we, exp_iram_addr,
        exp_iram_wdata, exp_done, exp_boot_pc, exp_fail_stop
      );

      check_signal(tc_name, "done_o",      {31'd0, done_o},      {31'd0, exp_done},      tc_failures);
      if (exp_done) begin
        check_signal(tc_name, "boot_pc_o", boot_pc_o, exp_boot_pc, tc_failures);
      end
      check_signal(tc_name, "fail_stop_o", {31'd0, fail_stop_o}, {31'd0, exp_fail_stop}, tc_failures);

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  task automatic tc006_header_malformed_fail;
    string tc_name;
    integer tc_failures;
    logic exp_spi_req;
    logic [31:0] exp_spi_addr;
    logic exp_iram_we;
    logic [31:0] exp_iram_addr;
    logic [31:0] exp_iram_wdata;
    logic exp_done;
    logic [31:0] exp_boot_pc;
    logic exp_fail_stop;
    begin
      tc_name = "TC006_HEADER_MALFORMED_FAIL";
      tc_failures = 0;

      reset_only();
      validation_enable_i = 1'b1;
      start_i = 1'b1;
      @(posedge clk);
      #1;
      start_i = 1'b0;

      spi_ready_i = 1'b1;
      spi_rdata_i = ~RV32EC_ZMMUL_BOOT_MAGIC;
      @(posedge clk);
      #1;
      spi_ready_i = 1'b0;

      golden_outputs_from_state(
        ST_FAIL_G, SPI_BASE_ADDR, IRAM_BASE_ADDR, 32'h0000_0000, 32'h0000_0000,
        exp_spi_req, exp_spi_addr, exp_iram_we, exp_iram_addr,
        exp_iram_wdata, exp_done, exp_boot_pc, exp_fail_stop
      );

      check_signal(tc_name, "fail_stop_o", {31'd0, fail_stop_o}, {31'd0, exp_fail_stop}, tc_failures);
      check_signal(tc_name, "done_o",      {31'd0, done_o},      {31'd0, exp_done},      tc_failures);
      check_signal(tc_name, "spi_req_o",   {31'd0, spi_req_o},   {31'd0, exp_spi_req},   tc_failures);

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  task automatic tc007_size_range_violation_fail;
    string tc_name;
    integer tc_failures;
    logic exp_spi_req;
    logic [31:0] exp_spi_addr;
    logic exp_iram_we;
    logic [31:0] exp_iram_addr;
    logic [31:0] exp_iram_wdata;
    logic exp_done;
    logic [31:0] exp_boot_pc;
    logic exp_fail_stop;
    begin
      tc_name = "TC007_SIZE_RANGE_VIOLATION_FAIL";
      tc_failures = 0;

      reset_only();
      validation_enable_i = 1'b1;
      start_i = 1'b1;
      @(posedge clk);
      #1;
      start_i = 1'b0;

      spi_ready_i = 1'b1;
      spi_rdata_i = RV32EC_ZMMUL_BOOT_MAGIC;
      @(posedge clk);
      #1;

      spi_rdata_i = BAD_PROGRAM_SIZE;
      @(posedge clk);
      #1;
      spi_ready_i = 1'b0;

      golden_outputs_from_state(
        ST_FAIL_G, SPI_BASE_ADDR + 32'd4, IRAM_BASE_ADDR, 32'h0000_0000, 32'h0000_0000,
        exp_spi_req, exp_spi_addr, exp_iram_we, exp_iram_addr,
        exp_iram_wdata, exp_done, exp_boot_pc, exp_fail_stop
      );

      check_signal(tc_name, "fail_stop_o", {31'd0, fail_stop_o}, {31'd0, exp_fail_stop}, tc_failures);
      check_signal(tc_name, "done_o",      {31'd0, done_o},      {31'd0, exp_done},      tc_failures);

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  task automatic wait_for_fail_stop_within(
    input  string tc_name,
    input  integer max_cycles,
    output logic seen_fail
  );
    integer wait_idx;
    begin
      seen_fail = 1'b0;
      for (wait_idx = 0; wait_idx < max_cycles; wait_idx = wait_idx + 1) begin
        @(posedge clk);
        #1;
        if (fail_stop_o === 1'b1) begin
          seen_fail = 1'b1;
          wait_idx = max_cycles;
        end
      end

      if (!seen_fail) begin
        $display("[TESTCASE_RESULT] FAIL: %0s.fail_stop_o | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, fail_stop_o, 1'b1, cycle_count, $time);
        fail_count = fail_count + 1;
      end
    end
  endtask

  task automatic tc008_spi_timeout_or_error_fail;
    string tc_name;
    integer tc_failures;
    logic seen_fail;
    begin
      tc_name = "TC008_SPI_TIMEOUT_OR_ERROR_FAIL";
      tc_failures = 0;

      reset_only();
      validation_enable_i = 1'b1;
      start_i = 1'b1;
      @(posedge clk);
      #1;
      start_i = 1'b0;
      spi_ready_i = 1'b0;

      wait_for_fail_stop_within(tc_name, BOOT_TIMEOUT_WAIT_CYCLES, seen_fail);
      if (!seen_fail) begin
        tc_failures = tc_failures + 1;
      end
      else begin
        check_signal(tc_name, "done_o", {31'd0, done_o}, 32'h0000_0000, tc_failures);
      end

      finish_testcase(tc_name, tc_failures);
    end
  endtask

  initial begin
    drive_defaults();

    tc001_reset_idle();
    tc002_start_header_fetch();
    tc003_valid_header_accept();
    tc004_program_word_copy();
    tc005_boot_success();
    tc006_header_malformed_fail();
    tc007_size_range_violation_fail();
    tc008_spi_timeout_or_error_fail();

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
`timescale 1ns/1ps

module tb_fetch_unit (
  output logic        clk,
  output logic        rst_n,
  output logic        stall_i,
  output logic        flush_i,
  output logic        trap_redirect_valid_i,
  output logic [31:0] trap_redirect_pc_i,
  output logic        mret_redirect_valid_i,
  output logic [31:0] mret_redirect_pc_i,
  output logic        branch_redirect_valid_i,
  output logic [31:0] branch_redirect_pc_i,
  output logic        instr_ready_i,
  output logic [31:0] instr_rdata_i,
  output logic        is_compressed_i,
  output logic [31:0] reset_vector_i,
  input  logic        instr_req_o,
  input  logic [31:0] instr_addr_o,
  input  logic [31:0] pc_o,
  input  logic        instr_valid_o,
  input  logic [31:0] instr_o
);

  integer cycle_count = 0;
  integer pass_count = 0;
  integer fail_count = 0;

  logic [31:0] exp_pc;
  logic [31:0] exp_instr;
  logic        exp_valid;

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
  end

  initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish;
  end

  task automatic drive_defaults;
    begin
      rst_n                    = 1'b1;
      stall_i                  = 1'b0;
      flush_i                  = 1'b0;
      trap_redirect_valid_i    = 1'b0;
      trap_redirect_pc_i       = 32'h0000_0000;
      mret_redirect_valid_i    = 1'b0;
      mret_redirect_pc_i       = 32'h0000_0000;
      branch_redirect_valid_i  = 1'b0;
      branch_redirect_pc_i     = 32'h0000_0000;
      instr_ready_i            = 1'b0;
      instr_rdata_i            = 32'h0000_0000;
      is_compressed_i          = 1'b0;
      reset_vector_i           = 32'h0000_0000;
    end
  endtask

  task automatic model_reset(input logic [31:0] rv);
    begin
      exp_pc    = rv;
      exp_instr = 32'h0000_0000;
      exp_valid = 1'b0;
    end
  endtask

  task automatic model_step;
    logic [31:0] next_pc;
    begin
      if (!rst_n) begin
        exp_pc    = reset_vector_i;
        exp_instr = 32'h0000_0000;
        exp_valid = 1'b0;
      end else if (stall_i) begin
        exp_pc    = exp_pc;
        exp_instr = exp_instr;
        exp_valid = exp_valid;
      end else begin
        next_pc = exp_pc;

        if (flush_i || trap_redirect_valid_i || mret_redirect_valid_i || branch_redirect_valid_i) begin
          exp_valid = 1'b0;
        end

        if (trap_redirect_valid_i) begin
          next_pc = trap_redirect_pc_i;
        end else if (mret_redirect_valid_i) begin
          next_pc = mret_redirect_pc_i;
        end else if (branch_redirect_valid_i) begin
          next_pc = branch_redirect_pc_i;
        end else if (instr_ready_i) begin
          exp_instr = instr_rdata_i;
          exp_valid = 1'b1;
          next_pc   = exp_pc + (is_compressed_i ? 32'd2 : 32'd4);
        end

        exp_pc = next_pc;
      end
    end
  endtask

  task automatic wait_posedge_settle;
    begin
      @(posedge clk);
      #1;
    end
  endtask

  task automatic check_bit(
    input string tc_name,
    input string signal_name,
    input logic  got_val,
    input logic  exp_val,
    inout integer case_fail
  );
    begin
      if (got_val !== exp_val) begin
        fail_count = fail_count + 1;
        case_fail  = case_fail + 1;
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
      end
    end
  endtask

  task automatic check_word(
    input string tc_name,
    input string signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val,
    inout integer case_fail
  );
    begin
      if (got_val !== exp_val) begin
        fail_count = fail_count + 1;
        case_fail  = case_fail + 1;
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
      end
    end
  endtask

  task automatic finish_case(
    input string tc_name,
    input integer case_fail
  );
    begin
      if (case_fail == 0) begin
        pass_count = pass_count + 1;
        $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
      end
    end
  endtask

  task automatic do_reset(input logic [31:0] rv);
    begin
      drive_defaults();
      reset_vector_i = rv;
      rst_n = 1'b0;
      model_reset(rv);
      #1;
      rst_n = 1'b1;
      wait_posedge_settle();
      model_step();
    end
  endtask

  task automatic preload_buffer(
    input logic [31:0] rv,
    input logic [31:0] data_word,
    input logic        compressed
  );
    begin
      do_reset(rv);
      instr_ready_i   = 1'b1;
      instr_rdata_i   = data_word;
      is_compressed_i = compressed;
      wait_posedge_settle();
      model_step();
      instr_ready_i   = 1'b0;
      instr_rdata_i   = 32'h0000_0000;
      is_compressed_i = 1'b0;
    end
  endtask

  task automatic run_tc001_reset_vector_load;
    integer case_fail;
    logic [31:0] exp_req;
    begin
      case_fail = 0;
      drive_defaults();
      reset_vector_i        = 32'h0000_0080;
      trap_redirect_pc_i    = 32'h0000_0100;
      mret_redirect_pc_i    = 32'h0000_0200;
      branch_redirect_pc_i  = 32'h0000_0300;
      rst_n                 = 1'b0;
      model_reset(reset_vector_i);
      #1;
      rst_n = 1'b1;
      wait_posedge_settle();
      model_step();

      exp_req = 32'd1;
      check_bit ("TC001_RESET_VECTOR_LOAD", "instr_req_o",  instr_req_o,  exp_req[0], case_fail);
      check_word("TC001_RESET_VECTOR_LOAD", "instr_addr_o", instr_addr_o, exp_pc,      case_fail);
      check_word("TC001_RESET_VECTOR_LOAD", "pc_o",         pc_o,         exp_pc,      case_fail);
      check_bit ("TC001_RESET_VECTOR_LOAD", "instr_valid_o", instr_valid_o, exp_valid,  case_fail);
      finish_case("TC001_RESET_VECTOR_LOAD", case_fail);
    end
  endtask

  task automatic run_tc002_sequential_pc_plus4;
    integer case_fail;
    begin
      case_fail = 0;
      do_reset(32'h0000_0000);
      instr_ready_i   = 1'b1;
      instr_rdata_i   = 32'h0000_0013;
      is_compressed_i = 1'b0;
      wait_posedge_settle();
      model_step();

      check_bit ("TC002_SEQUENTIAL_PC_PLUS4", "instr_valid_o", instr_valid_o, exp_valid, case_fail);
      check_word("TC002_SEQUENTIAL_PC_PLUS4", "instr_o",       instr_o,       exp_instr, case_fail);
      check_word("TC002_SEQUENTIAL_PC_PLUS4", "instr_addr_o",  instr_addr_o,  exp_pc,    case_fail);
      finish_case("TC002_SEQUENTIAL_PC_PLUS4", case_fail);
    end
  endtask

  task automatic run_tc003_sequential_pc_plus2;
    integer case_fail;
    begin
      case_fail = 0;
      do_reset(32'h0000_0000);
      instr_ready_i   = 1'b1;
      instr_rdata_i   = 32'h0000_0001;
      is_compressed_i = 1'b1;
      wait_posedge_settle();
      model_step();

      check_bit ("TC003_SEQUENTIAL_PC_PLUS2", "instr_valid_o", instr_valid_o, exp_valid, case_fail);
      check_word("TC003_SEQUENTIAL_PC_PLUS2", "instr_o",       instr_o,       exp_instr, case_fail);
      check_word("TC003_SEQUENTIAL_PC_PLUS2", "instr_addr_o",  instr_addr_o,  exp_pc,    case_fail);
      finish_case("TC003_SEQUENTIAL_PC_PLUS2", case_fail);
    end
  endtask

  task automatic run_tc004_branch_redirect_priority_over_sequential;
    integer case_fail;
    begin
      case_fail = 0;
      preload_buffer(32'h0000_0000, 32'h1111_1111, 1'b0);
      flush_i                 = 1'b1;
      branch_redirect_valid_i = 1'b1;
      branch_redirect_pc_i    = 32'h0000_0120;
      wait_posedge_settle();
      model_step();

      check_word("TC004_BRANCH_REDIRECT_PRIORITY", "instr_addr_o",  instr_addr_o, exp_pc,    case_fail);
      check_bit ("TC004_BRANCH_REDIRECT_PRIORITY", "instr_valid_o", instr_valid_o, exp_valid, case_fail);
      finish_case("TC004_BRANCH_REDIRECT_PRIORITY", case_fail);
    end
  endtask

  task automatic run_tc005_mret_redirect_priority_over_branch;
    integer case_fail;
    begin
      case_fail = 0;
      preload_buffer(32'h0000_0000, 32'h2222_2222, 1'b0);
      flush_i                 = 1'b1;
      mret_redirect_valid_i   = 1'b1;
      mret_redirect_pc_i      = 32'h0000_0220;
      branch_redirect_valid_i = 1'b1;
      branch_redirect_pc_i    = 32'h0000_0120;
      wait_posedge_settle();
      model_step();

      check_word("TC005_MRET_REDIRECT_PRIORITY", "instr_addr_o",  instr_addr_o, exp_pc,    case_fail);
      check_bit ("TC005_MRET_REDIRECT_PRIORITY", "instr_valid_o", instr_valid_o, exp_valid, case_fail);
      finish_case("TC005_MRET_REDIRECT_PRIORITY", case_fail);
    end
  endtask

  task automatic run_tc006_trap_redirect_highest_priority;
    integer case_fail;
    begin
      case_fail = 0;
      preload_buffer(32'h0000_0000, 32'h3333_3333, 1'b0);
      flush_i                 = 1'b1;
      trap_redirect_valid_i   = 1'b1;
      trap_redirect_pc_i      = 32'h0000_0300;
      mret_redirect_valid_i   = 1'b1;
      mret_redirect_pc_i      = 32'h0000_0220;
      branch_redirect_valid_i = 1'b1;
      branch_redirect_pc_i    = 32'h0000_0120;
      wait_posedge_settle();
      model_step();

      check_word("TC006_TRAP_REDIRECT_PRIORITY", "instr_addr_o",  instr_addr_o, exp_pc,    case_fail);
      check_bit ("TC006_TRAP_REDIRECT_PRIORITY", "instr_valid_o", instr_valid_o, exp_valid, case_fail);
      finish_case("TC006_TRAP_REDIRECT_PRIORITY", case_fail);
    end
  endtask

  task automatic run_tc007_stall_holds_fetch_address;
    integer case_fail;
    logic [31:0] held_addr;
    logic [31:0] held_pc;
    begin
      case_fail = 0;
      preload_buffer(32'h0000_0000, 32'h0000_0013, 1'b0);
      held_addr = instr_addr_o;
      held_pc   = pc_o;

      stall_i = 1'b1;
      wait_posedge_settle();
      model_step();
      check_bit ("TC007_STALL_HOLDS_FETCH_ADDRESS", "instr_req_o",  instr_req_o, 1'b1,    case_fail);
      check_word("TC007_STALL_HOLDS_FETCH_ADDRESS", "instr_addr_o", instr_addr_o, held_addr, case_fail);
      check_word("TC007_STALL_HOLDS_FETCH_ADDRESS", "pc_o",         pc_o,         held_pc,   case_fail);

      wait_posedge_settle();
      model_step();
      check_word("TC007_STALL_HOLDS_FETCH_ADDRESS", "instr_addr_o", instr_addr_o, held_addr, case_fail);
      finish_case("TC007_STALL_HOLDS_FETCH_ADDRESS", case_fail);
    end
  endtask

  task automatic run_tc008_buffer_capture_on_ready;
    integer case_fail;
    begin
      case_fail = 0;
      do_reset(32'h0000_0000);
      instr_ready_i   = 1'b1;
      instr_rdata_i   = 32'hDEAD_BEEF;
      is_compressed_i = 1'b0;
      wait_posedge_settle();
      model_step();

      check_bit ("TC008_BUFFER_CAPTURE_ON_READY", "instr_valid_o", instr_valid_o, exp_valid, case_fail);
      check_word("TC008_BUFFER_CAPTURE_ON_READY", "instr_o",       instr_o,       exp_instr, case_fail);
      finish_case("TC008_BUFFER_CAPTURE_ON_READY", case_fail);
    end
  endtask

  initial begin
    drive_defaults();
    model_reset(32'h0000_0000);

    run_tc001_reset_vector_load();
    run_tc002_sequential_pc_plus4();
    run_tc003_sequential_pc_plus2();
    run_tc004_branch_redirect_priority_over_sequential();
    run_tc005_mret_redirect_priority_over_branch();
    run_tc006_trap_redirect_highest_priority();
    run_tc007_stall_holds_fetch_address();
    run_tc008_buffer_capture_on_ready();

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
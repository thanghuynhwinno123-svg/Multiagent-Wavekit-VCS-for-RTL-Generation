`timescale 1ns/1ps

module tb_load_store_unit (
  output logic        clk,
  output logic        rst_n,
  output logic        req_i,
  output logic        we_i,
  output logic [1:0]  size_i,
  output logic        unsigned_i,
  output logic [31:0] base_addr_i,
  output logic [31:0] offset_i,
  output logic [31:0] store_data_i,
  output logic        mem_ready_i,
  output logic [31:0] mem_rdata_i,
  output logic        trap_on_misaligned_i,

  input  logic        mem_req_o,
  input  logic        mem_we_o,
  input  logic [3:0]  mem_be_o,
  input  logic [31:0] mem_addr_o,
  input  logic [31:0] mem_wdata_o,
  input  logic [31:0] load_data_o,
  input  logic        done_o,
  input  logic        stall_o,
  input  logic        misaligned_o
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

  task automatic report_pass(input string tc_name);
    begin
      pass_count = pass_count + 1;
      $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
    end
  endtask

  task automatic report_fail_1b(
    input string tc_name,
    input string signal_name,
    input logic got_val,
    input logic exp_val
  );
    begin
      fail_count = fail_count + 1;
      $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
               tc_name, signal_name, got_val, exp_val, cycle_count, $time);
    end
  endtask

  task automatic report_fail_4b(
    input string tc_name,
    input string signal_name,
    input logic [3:0] got_val,
    input logic [3:0] exp_val
  );
    begin
      fail_count = fail_count + 1;
      $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
               tc_name, signal_name, got_val, exp_val, cycle_count, $time);
    end
  endtask

  task automatic report_fail_32b(
    input string tc_name,
    input string signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val
  );
    begin
      fail_count = fail_count + 1;
      $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
               tc_name, signal_name, got_val, exp_val, cycle_count, $time);
    end
  endtask

  task automatic check_1b(
    input string tc_name,
    input string signal_name,
    input logic got_val,
    input logic exp_val,
    inout integer local_fail
  );
    begin
      if (got_val !== exp_val) begin
        local_fail = local_fail + 1;
        report_fail_1b(tc_name, signal_name, got_val, exp_val);
      end
    end
  endtask

  task automatic check_4b(
    input string tc_name,
    input string signal_name,
    input logic [3:0] got_val,
    input logic [3:0] exp_val,
    inout integer local_fail
  );
    begin
      if (got_val !== exp_val) begin
        local_fail = local_fail + 1;
        report_fail_4b(tc_name, signal_name, got_val, exp_val);
      end
    end
  endtask

  task automatic check_32b(
    input string tc_name,
    input string signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val,
    inout integer local_fail
  );
    begin
      if (got_val !== exp_val) begin
        local_fail = local_fail + 1;
        report_fail_32b(tc_name, signal_name, got_val, exp_val);
      end
    end
  endtask

  task automatic golden_effective_addr(
    input  logic [31:0] base_addr,
    input  logic [31:0] offset,
    output logic [31:0] eff_addr
  );
    begin
      eff_addr = base_addr + offset;
    end
  endtask

  task automatic golden_misaligned(
    input  logic [1:0]  size_sel,
    input  logic [31:0] eff_addr,
    output logic        misaligned
  );
    begin
      case (size_sel)
        2'd0: misaligned = 1'b0;
        2'd1: misaligned = eff_addr[0];
        2'd2: misaligned = |eff_addr[1:0];
        default: misaligned = 1'b0;
      endcase
    end
  endtask

  task automatic golden_mem_be(
    input  logic [1:0] size_sel,
    input  logic [1:0] addr_lsb,
    output logic [3:0] be
  );
    begin
      case (size_sel)
        2'd0: be = (4'b0001 << addr_lsb);
        2'd1: be = addr_lsb[1] ? 4'b1100 : 4'b0011;
        2'd2: be = 4'b1111;
        default: be = 4'b0000;
      endcase
    end
  endtask

  task automatic golden_store_data(
    input  logic [1:0]  size_sel,
    input  logic [1:0]  addr_lsb,
    input  logic [31:0] store_data,
    output logic [31:0] exp_wdata
  );
    begin
      case (size_sel)
        2'd0: exp_wdata = {4{store_data[7:0]}} << (addr_lsb * 8);
        2'd1: exp_wdata = {2{store_data[15:0]}} << (addr_lsb[1] * 16);
        2'd2: exp_wdata = store_data;
        default: exp_wdata = 32'h00000000;
      endcase
    end
  endtask

  task automatic golden_load_data(
    input  logic [1:0]  size_sel,
    input  logic        unsigned_sel,
    input  logic [1:0]  addr_lsb,
    input  logic [31:0] mem_rdata,
    output logic [31:0] exp_load
  );
    logic [7:0]  byte_val;
    logic [15:0] half_val;
    begin
      byte_val = (mem_rdata >> (addr_lsb * 8)) & 32'h000000FF;
      half_val = (mem_rdata >> (addr_lsb[1] * 16)) & 32'h0000FFFF;

      case (size_sel)
        2'd0: exp_load = unsigned_sel ? {24'h000000, byte_val} : {{24{byte_val[7]}}, byte_val};
        2'd1: exp_load = unsigned_sel ? {16'h0000, half_val} : {{16{half_val[15]}}, half_val};
        2'd2: exp_load = mem_rdata;
        default: exp_load = 32'h00000000;
      endcase
    end
  endtask

  task automatic drive_idle;
    begin
      req_i                 = 1'b0;
      we_i                  = 1'b0;
      size_i                = 2'd0;
      unsigned_i            = 1'b0;
      base_addr_i           = 32'h00000000;
      offset_i              = 32'h00000000;
      store_data_i          = 32'h00000000;
      mem_ready_i           = 1'b0;
      mem_rdata_i           = 32'h00000000;
      trap_on_misaligned_i  = 1'b1;
    end
  endtask

  task automatic apply_reset;
    integer local_fail;
    begin
      local_fail = 0;
      drive_idle();
      rst_n = 1'b0;
      #1;
      check_1b ("TC000_RESET", "done_o",       done_o,       1'b0,         local_fail);
      check_1b ("TC000_RESET", "stall_o",      stall_o,      1'b0,         local_fail);
      check_32b("TC000_RESET", "load_data_o",  load_data_o,  32'h00000000, local_fail);
      check_1b ("TC000_RESET", "misaligned_o", misaligned_o, 1'b0,         local_fail);

      @(posedge clk);
      #1;
      check_1b ("TC000_RESET", "done_o",       done_o,       1'b0,         local_fail);
      check_1b ("TC000_RESET", "stall_o",      stall_o,      1'b0,         local_fail);
      check_32b("TC000_RESET", "load_data_o",  load_data_o,  32'h00000000, local_fail);
      check_1b ("TC000_RESET", "misaligned_o", misaligned_o, 1'b0,         local_fail);

      rst_n = 1'b1;
      @(posedge clk);
      #1;

      if (local_fail == 0) begin
        report_pass("TC000_RESET");
      end
    end
  endtask

  task automatic run_tc001_lw_address_calc;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic        exp_misaligned;
    logic [3:0]  exp_be;
    begin
      tc_name = "TC001_LW_ADDRESS_CALC";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd2;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00001000;
      offset_i     = 32'h00000004;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b0;
      mem_rdata_i  = 32'h00000000;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_misaligned(size_i, exp_addr, exp_misaligned);
      golden_mem_be(size_i, exp_addr[1:0], exp_be);

      @(posedge clk);
      #1;
      check_1b (tc_name, "mem_req_o",    mem_req_o,    1'b1,     local_fail);
      check_1b (tc_name, "mem_we_o",     mem_we_o,     1'b0,     local_fail);
      check_32b(tc_name, "mem_addr_o",   mem_addr_o,   exp_addr, local_fail);
      check_4b (tc_name, "mem_be_o",     mem_be_o,     exp_be,   local_fail);
      check_1b (tc_name, "stall_o",      stall_o,      1'b1,     local_fail);
      check_1b (tc_name, "misaligned_o", misaligned_o, exp_misaligned, local_fail);

      req_i = 1'b0;
      @(posedge clk);
      #1;
      check_1b (tc_name, "mem_req_o",  mem_req_o, 1'b1, local_fail);
      check_32b(tc_name, "mem_addr_o", mem_addr_o, exp_addr, local_fail);
      check_4b (tc_name, "mem_be_o",   mem_be_o, exp_be, local_fail);
      check_1b (tc_name, "stall_o",    stall_o, 1'b1, local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc002_sw_address_and_data;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic        exp_misaligned;
    logic [3:0]  exp_be;
    logic [31:0] exp_wdata;
    begin
      tc_name = "TC002_SW_ADDRESS_AND_DATA";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b1;
      size_i       = 2'd2;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00002000;
      offset_i     = 32'h00000008;
      store_data_i = 32'h12345678;
      mem_ready_i  = 1'b0;
      mem_rdata_i  = 32'h00000000;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_misaligned(size_i, exp_addr, exp_misaligned);
      golden_mem_be(size_i, exp_addr[1:0], exp_be);
      golden_store_data(size_i, exp_addr[1:0], store_data_i, exp_wdata);

      @(posedge clk);
      #1;
      check_1b (tc_name, "mem_req_o",    mem_req_o,    1'b1,      local_fail);
      check_1b (tc_name, "mem_we_o",     mem_we_o,     1'b1,      local_fail);
      check_32b(tc_name, "mem_addr_o",   mem_addr_o,   exp_addr,  local_fail);
      check_4b (tc_name, "mem_be_o",     mem_be_o,     exp_be,    local_fail);
      check_32b(tc_name, "mem_wdata_o",  mem_wdata_o,  exp_wdata, local_fail);
      check_1b (tc_name, "stall_o",      stall_o,      1'b1,      local_fail);
      check_1b (tc_name, "misaligned_o", misaligned_o, exp_misaligned, local_fail);

      req_i = 1'b0;
      @(posedge clk);
      #1;
      check_1b (tc_name, "mem_req_o",   mem_req_o,   1'b1,      local_fail);
      check_32b(tc_name, "mem_addr_o",  mem_addr_o,  exp_addr,  local_fail);
      check_32b(tc_name, "mem_wdata_o", mem_wdata_o, exp_wdata, local_fail);
      check_1b (tc_name, "stall_o",     stall_o,     1'b1,      local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc003_lb_sign_extend;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic [31:0] exp_load;
    logic        exp_misaligned;
    begin
      tc_name = "TC003_LB_SIGN_EXTEND";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd0;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00003000;
      offset_i     = 32'h00000001;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b1;
      mem_rdata_i  = 32'h0000AA00;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_load_data(size_i, unsigned_i, exp_addr[1:0], mem_rdata_i, exp_load);
      golden_misaligned(size_i, exp_addr, exp_misaligned);

      @(posedge clk);
      #1;
      check_32b(tc_name, "load_data_o",  load_data_o,  exp_load,       local_fail);
      check_1b (tc_name, "done_o",       done_o,       1'b1,           local_fail);
      check_1b (tc_name, "misaligned_o", misaligned_o, exp_misaligned, local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc004_lbu_zero_extend;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic [31:0] exp_load;
    logic        exp_misaligned;
    begin
      tc_name = "TC004_LBU_ZERO_EXTEND";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd0;
      unsigned_i   = 1'b1;
      base_addr_i  = 32'h00003000;
      offset_i     = 32'h00000001;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b1;
      mem_rdata_i  = 32'h0000AA00;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_load_data(size_i, unsigned_i, exp_addr[1:0], mem_rdata_i, exp_load);
      golden_misaligned(size_i, exp_addr, exp_misaligned);

      @(posedge clk);
      #1;
      check_32b(tc_name, "load_data_o",  load_data_o,  exp_load,       local_fail);
      check_1b (tc_name, "done_o",       done_o,       1'b1,           local_fail);
      check_1b (tc_name, "misaligned_o", misaligned_o, exp_misaligned, local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc005_lh_sign_extend;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic [31:0] exp_load;
    logic        exp_misaligned;
    begin
      tc_name = "TC005_LH_SIGN_EXTEND";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd1;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00004000;
      offset_i     = 32'h00000002;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b1;
      mem_rdata_i  = 32'h80010000;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_load_data(size_i, unsigned_i, exp_addr[1:0], mem_rdata_i, exp_load);
      golden_misaligned(size_i, exp_addr, exp_misaligned);

      @(posedge clk);
      #1;
      check_32b(tc_name, "load_data_o",  load_data_o,  exp_load,       local_fail);
      check_1b (tc_name, "done_o",       done_o,       1'b1,           local_fail);
      check_1b (tc_name, "misaligned_o", misaligned_o, exp_misaligned, local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc006_lhu_zero_extend;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic [31:0] exp_load;
    logic        exp_misaligned;
    begin
      tc_name = "TC006_LHU_ZERO_EXTEND";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd1;
      unsigned_i   = 1'b1;
      base_addr_i  = 32'h00004000;
      offset_i     = 32'h00000002;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b1;
      mem_rdata_i  = 32'h80010000;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_load_data(size_i, unsigned_i, exp_addr[1:0], mem_rdata_i, exp_load);
      golden_misaligned(size_i, exp_addr, exp_misaligned);

      @(posedge clk);
      #1;
      check_32b(tc_name, "load_data_o",  load_data_o,  exp_load,       local_fail);
      check_1b (tc_name, "done_o",       done_o,       1'b1,           local_fail);
      check_1b (tc_name, "misaligned_o", misaligned_o, exp_misaligned, local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc007_load_wait_state;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    begin
      tc_name = "TC007_LOAD_WAIT_STATE";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd2;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00005000;
      offset_i     = 32'h00000000;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b0;
      mem_rdata_i  = 32'h00000000;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);

      @(posedge clk);
      #1;
      check_1b (tc_name, "mem_req_o",  mem_req_o, 1'b1,     local_fail);
      check_1b (tc_name, "stall_o",    stall_o,   1'b1,     local_fail);
      check_1b (tc_name, "done_o",     done_o,    1'b0,     local_fail);

      req_i = 1'b0;
      @(posedge clk);
      #1;
      check_1b (tc_name, "mem_req_o",  mem_req_o, 1'b1,     local_fail);
      check_1b (tc_name, "stall_o",    stall_o,   1'b1,     local_fail);
      check_1b (tc_name, "done_o",     done_o,    1'b0,     local_fail);
      check_32b(tc_name, "mem_addr_o", mem_addr_o, exp_addr, local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc008_load_complete;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic [31:0] exp_load;
    begin
      tc_name = "TC008_LOAD_COMPLETE";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd2;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00005000;
      offset_i     = 32'h00000000;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b1;
      mem_rdata_i  = 32'hDEADBEEF;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_load_data(size_i, unsigned_i, exp_addr[1:0], mem_rdata_i, exp_load);

      @(posedge clk);
      #1;
      check_32b(tc_name, "load_data_o", load_data_o, exp_load, local_fail);
      check_1b (tc_name, "done_o",      done_o,      1'b1,     local_fail);
      check_1b (tc_name, "stall_o",     stall_o,     1'b0,     local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc009_misaligned_word_trap_enabled;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    logic        exp_misaligned;
    begin
      tc_name = "TC009_MISALIGNED_WORD_TRAP_ENABLED";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd2;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00006000;
      offset_i     = 32'h00000002;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b0;
      mem_rdata_i  = 32'h00000000;
      trap_on_misaligned_i = 1'b1;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);
      golden_misaligned(size_i, exp_addr, exp_misaligned);

      @(posedge clk);
      #1;
      check_1b (tc_name, "misaligned_o", misaligned_o, exp_misaligned, local_fail);
      check_1b (tc_name, "mem_req_o",    mem_req_o,    1'b0,           local_fail);
      check_1b (tc_name, "done_o",       done_o,       1'b1,           local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  task automatic run_tc010_misaligned_word_no_trap_policy;
    string tc_name;
    integer local_fail;
    logic [31:0] exp_addr;
    begin
      tc_name = "TC010_MISALIGNED_WORD_NO_TRAP_POLICY";
      local_fail = 0;
      apply_reset();

      req_i        = 1'b1;
      we_i         = 1'b0;
      size_i       = 2'd2;
      unsigned_i   = 1'b0;
      base_addr_i  = 32'h00006000;
      offset_i     = 32'h00000002;
      store_data_i = 32'h00000000;
      mem_ready_i  = 1'b0;
      mem_rdata_i  = 32'h00000000;
      trap_on_misaligned_i = 1'b0;

      golden_effective_addr(base_addr_i, offset_i, exp_addr);

      @(posedge clk);
      #1;
      check_1b (tc_name, "misaligned_o", misaligned_o, 1'b0,     local_fail);
      check_1b (tc_name, "mem_req_o",    mem_req_o,    1'b1,     local_fail);
      check_32b(tc_name, "mem_addr_o",   mem_addr_o,   exp_addr, local_fail);

      if (local_fail == 0) begin
        report_pass(tc_name);
      end
    end
  endtask

  initial begin
    drive_idle();
    rst_n = 1'b1;

    run_tc001_lw_address_calc();
    run_tc002_sw_address_and_data();
    run_tc003_lb_sign_extend();
    run_tc004_lbu_zero_extend();
    run_tc005_lh_sign_extend();
    run_tc006_lhu_zero_extend();
    run_tc007_load_wait_state();
    run_tc008_load_complete();
    run_tc009_misaligned_word_trap_enabled();
    run_tc010_misaligned_word_no_trap_policy();

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
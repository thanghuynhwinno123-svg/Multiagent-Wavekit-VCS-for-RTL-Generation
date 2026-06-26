`timescale 1ns/1ps

module tb_execute_writeback_unit (
  output logic        clk,
  output logic        rst_n,
  output logic [31:0] pc_i,
  output logic [31:0] rs1_data_i,
  output logic [31:0] rs2_data_i,
  output logic [31:0] imm_i,
  output logic [4:0]  rd_idx_i,
  output logic [3:0]  alu_op_i,
  output logic [2:0]  branch_op_i,
  output logic        mul_en_i,
  output logic        mem_req_i,
  output logic        mem_we_i,
  output logic        csr_en_i,
  output logic        mret_i,
  output logic        illegal_i,
  output logic [31:0] load_data_i,
  output logic        load_ready_i,
  output logic [31:0] mul_result_i,
  output logic        mul_done_i,
  output logic [31:0] csr_rdata_i,

  input  logic        branch_taken_o,
  input  logic [31:0] branch_target_o,
  input  logic        wb_en_o,
  input  logic [4:0]  wb_rd_idx_o,
  input  logic [31:0] wb_data_o,
  input  logic [31:0] mem_addr_o,
  input  logic [31:0] mem_wdata_o,
  input  logic        mem_req_o,
  input  logic        mem_we_o,
  input  logic        trap_req_o,
  input  logic [3:0]  trap_cause_o,
  input  logic        mret_req_o,
  input  logic        stall_o
);

  integer cycle_count = 0;
  integer pass_count = 0;
  integer fail_count = 0;

  initial clk = 1'b0;
  initial forever #5 clk = ~clk;

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
  end

  initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish;
  end

  task automatic drive_idle();
    begin
      pc_i         = 32'h0000_0000;
      rs1_data_i   = 32'h0000_0000;
      rs2_data_i   = 32'h0000_0000;
      imm_i        = 32'h0000_0000;
      rd_idx_i     = 5'd0;
      alu_op_i     = 4'd0;
      branch_op_i  = 3'd0;
      mul_en_i     = 1'b0;
      mem_req_i    = 1'b0;
      mem_we_i     = 1'b0;
      csr_en_i     = 1'b0;
      mret_i       = 1'b0;
      illegal_i    = 1'b0;
      load_data_i  = 32'h0000_0000;
      load_ready_i = 1'b0;
      mul_result_i = 32'h0000_0000;
      mul_done_i   = 1'b0;
      csr_rdata_i  = 32'h0000_0000;
    end
  endtask

  task automatic check_equal32(
    input string tc_name,
    input string signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val,
    inout bit tc_failed
  );
    begin
      if (got_val !== exp_val) begin
        tc_failed = 1'b1;
        fail_count = fail_count + 1;
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
      end
    end
  endtask

  task automatic finish_case(
    input string tc_name,
    input bit tc_failed
  );
    begin
      if (!tc_failed) begin
        pass_count = pass_count + 1;
        $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
      end
    end
  endtask

  task automatic golden_model(
    output logic        exp_branch_taken,
    output logic [31:0] exp_branch_target,
    output logic        exp_wb_en,
    output logic [4:0]  exp_wb_rd_idx,
    output logic [31:0] exp_wb_data,
    output logic [31:0] exp_mem_addr,
    output logic [31:0] exp_mem_wdata,
    output logic        exp_mem_req,
    output logic        exp_mem_we,
    output logic        exp_trap_req,
    output logic [3:0]  exp_trap_cause,
    output logic        exp_mret_req,
    output logic        exp_stall
  );
    logic [31:0] alu_result;
    logic        beq_taken;
    logic [31:0] pc_plus_4;
    begin
      alu_result        = 32'h0000_0000;
      beq_taken         = 1'b0;
      pc_plus_4         = pc_i + 32'd4;

      exp_branch_taken  = 1'b0;
      exp_branch_target = 32'h0000_0000;
      exp_wb_en         = 1'b0;
      exp_wb_rd_idx     = 5'd0;
      exp_wb_data       = 32'h0000_0000;
      exp_mem_addr      = rs1_data_i + imm_i;
      exp_mem_wdata     = rs2_data_i;
      exp_mem_req       = 1'b0;
      exp_mem_we        = 1'b0;
      exp_trap_req      = 1'b0;
      exp_trap_cause    = 4'h0;
      exp_mret_req      = 1'b0;
      exp_stall         = 1'b0;

      case (alu_op_i)
        4'd0: alu_result = rs1_data_i + rs2_data_i;
        4'd1: alu_result = rs1_data_i - rs2_data_i;
        4'd2: alu_result = rs1_data_i & rs2_data_i;
        4'd3: alu_result = rs1_data_i | rs2_data_i;
        4'd4: alu_result = rs1_data_i ^ rs2_data_i;
        4'd5: alu_result = rs1_data_i << rs2_data_i[4:0];
        4'd6: alu_result = rs1_data_i >> rs2_data_i[4:0];
        4'd7: alu_result = $signed(rs1_data_i) >>> rs2_data_i[4:0];
        4'd8: alu_result = ($signed(rs1_data_i) < $signed(rs2_data_i)) ? 32'd1 : 32'd0;
        4'd9: alu_result = (rs1_data_i < rs2_data_i) ? 32'd1 : 32'd0;
        default: alu_result = rs1_data_i + rs2_data_i;
      endcase

      if (branch_op_i == 3'd1) begin
        beq_taken = (rs1_data_i == rs2_data_i);
        exp_branch_taken  = beq_taken;
        exp_branch_target = pc_i + imm_i;
      end else if (branch_op_i == 3'd6) begin
        exp_branch_taken  = 1'b1;
        exp_branch_target = pc_i + imm_i;
      end else if (branch_op_i == 3'd7) begin
        exp_branch_taken  = 1'b1;
        exp_branch_target = (rs1_data_i + imm_i) & 32'hFFFF_FFFE;
      end

      if (illegal_i) begin
        exp_branch_taken  = 1'b0;
        exp_branch_target = 32'h0000_0000;
        exp_wb_en         = 1'b0;
        exp_wb_rd_idx     = 5'd0;
        exp_wb_data       = 32'h0000_0000;
        exp_mem_req       = 1'b0;
        exp_mem_we        = 1'b0;
        exp_trap_req      = 1'b1;
        exp_trap_cause    = 4'd2;
        exp_mret_req      = 1'b0;
        exp_stall         = 1'b0;
      end else if (mret_i) begin
        exp_branch_taken  = 1'b0;
        exp_branch_target = 32'h0000_0000;
        exp_wb_en         = 1'b0;
        exp_wb_rd_idx     = 5'd0;
        exp_wb_data       = 32'h0000_0000;
        exp_mem_req       = 1'b0;
        exp_mem_we        = 1'b0;
        exp_trap_req      = 1'b0;
        exp_trap_cause    = 4'h0;
        exp_mret_req      = 1'b1;
        exp_stall         = 1'b0;
      end else if (mem_req_i) begin
        exp_mem_req = 1'b1;
        exp_mem_we  = mem_we_i;
        exp_stall   = !load_ready_i;

        if (load_ready_i && !mem_we_i) begin
          exp_wb_en     = 1'b1;
          exp_wb_rd_idx = rd_idx_i;
          exp_wb_data   = load_data_i;
        end
      end else if (mul_en_i) begin
        exp_stall = !mul_done_i;

        if (mul_done_i) begin
          exp_wb_en     = 1'b1;
          exp_wb_rd_idx = rd_idx_i;
          exp_wb_data   = mul_result_i;
        end
      end else if (csr_en_i) begin
        exp_wb_en     = 1'b1;
        exp_wb_rd_idx = rd_idx_i;
        exp_wb_data   = csr_rdata_i;
      end else if (branch_op_i == 3'd6 || branch_op_i == 3'd7) begin
        exp_wb_en     = 1'b1;
        exp_wb_rd_idx = rd_idx_i;
        exp_wb_data   = pc_plus_4;
      end else if (branch_op_i != 3'd0) begin
        exp_wb_en = 1'b0;
      end else begin
        exp_wb_en     = 1'b1;
        exp_wb_rd_idx = rd_idx_i;
        exp_wb_data   = alu_result;
      end
    end
  endtask

  task automatic run_case(
    input string tc_name,
    input bit check_branch_taken,
    input bit check_branch_target,
    input bit check_wb_en,
    input bit check_wb_rd_idx,
    input bit check_wb_data,
    input bit check_mem_addr,
    input bit check_mem_wdata,
    input bit check_mem_req,
    input bit check_mem_we,
    input bit check_trap_req,
    input bit check_trap_cause,
    input bit check_mret_req,
    input bit check_stall
  );
    logic        exp_branch_taken;
    logic [31:0] exp_branch_target;
    logic        exp_wb_en;
    logic [4:0]  exp_wb_rd_idx;
    logic [31:0] exp_wb_data;
    logic [31:0] exp_mem_addr;
    logic [31:0] exp_mem_wdata;
    logic        exp_mem_req;
    logic        exp_mem_we;
    logic        exp_trap_req;
    logic [3:0]  exp_trap_cause;
    logic        exp_mret_req;
    logic        exp_stall;
    bit          tc_failed;
    begin
      tc_failed = 1'b0;
      golden_model(
        exp_branch_taken,
        exp_branch_target,
        exp_wb_en,
        exp_wb_rd_idx,
        exp_wb_data,
        exp_mem_addr,
        exp_mem_wdata,
        exp_mem_req,
        exp_mem_we,
        exp_trap_req,
        exp_trap_cause,
        exp_mret_req,
        exp_stall
      );

      @(posedge clk);
      #1;

      if (check_branch_taken) begin
        check_equal32(tc_name, "branch_taken_o", {31'd0, branch_taken_o}, {31'd0, exp_branch_taken}, tc_failed);
      end
      if (check_branch_target) begin
        check_equal32(tc_name, "branch_target_o", branch_target_o, exp_branch_target, tc_failed);
      end
      if (check_wb_en) begin
        check_equal32(tc_name, "wb_en_o", {31'd0, wb_en_o}, {31'd0, exp_wb_en}, tc_failed);
      end
      if (check_wb_rd_idx) begin
        check_equal32(tc_name, "wb_rd_idx_o", {27'd0, wb_rd_idx_o}, {27'd0, exp_wb_rd_idx}, tc_failed);
      end
      if (check_wb_data) begin
        check_equal32(tc_name, "wb_data_o", wb_data_o, exp_wb_data, tc_failed);
      end
      if (check_mem_addr) begin
        check_equal32(tc_name, "mem_addr_o", mem_addr_o, exp_mem_addr, tc_failed);
      end
      if (check_mem_wdata) begin
        check_equal32(tc_name, "mem_wdata_o", mem_wdata_o, exp_mem_wdata, tc_failed);
      end
      if (check_mem_req) begin
        check_equal32(tc_name, "mem_req_o", {31'd0, mem_req_o}, {31'd0, exp_mem_req}, tc_failed);
      end
      if (check_mem_we) begin
        check_equal32(tc_name, "mem_we_o", {31'd0, mem_we_o}, {31'd0, exp_mem_we}, tc_failed);
      end
      if (check_trap_req) begin
        check_equal32(tc_name, "trap_req_o", {31'd0, trap_req_o}, {31'd0, exp_trap_req}, tc_failed);
      end
      if (check_trap_cause) begin
        check_equal32(tc_name, "trap_cause_o", {28'd0, trap_cause_o}, {28'd0, exp_trap_cause}, tc_failed);
      end
      if (check_mret_req) begin
        check_equal32(tc_name, "mret_req_o", {31'd0, mret_req_o}, {31'd0, exp_mret_req}, tc_failed);
      end
      if (check_stall) begin
        check_equal32(tc_name, "stall_o", {31'd0, stall_o}, {31'd0, exp_stall}, tc_failed);
      end

      finish_case(tc_name, tc_failed);
    end
  endtask

  task automatic run_reset_case();
    bit tc_failed;
    begin
      tc_failed = 1'b0;

      drive_idle();
      rst_n       = 1'b1;
      mem_req_i   = 1'b1;
      mem_we_i    = 1'b0;
      rd_idx_i    = 5'd5;
      rs1_data_i  = 32'h0000_1000;
      imm_i       = 32'h0000_0004;
      load_ready_i = 1'b0;

      @(posedge clk);
      #1;
      check_equal32("TC000_RESET", "stall_o", {31'd0, stall_o}, 32'd1, tc_failed);

      rst_n = 1'b0;
      #1;
      check_equal32("TC000_RESET", "stall_o", {31'd0, stall_o}, 32'd0, tc_failed);
      check_equal32("TC000_RESET", "branch_taken_o", {31'd0, branch_taken_o}, 32'd0, tc_failed);
      check_equal32("TC000_RESET", "wb_en_o", {31'd0, wb_en_o}, 32'd0, tc_failed);
      check_equal32("TC000_RESET", "trap_req_o", {31'd0, trap_req_o}, 32'd0, tc_failed);
      check_equal32("TC000_RESET", "mret_req_o", {31'd0, mret_req_o}, 32'd0, tc_failed);

      rst_n = 1'b1;
      drive_idle();
      @(posedge clk);
      #1;

      finish_case("TC000_RESET", tc_failed);
    end
  endtask

  initial begin
    rst_n = 1'b0;
    drive_idle();

    repeat (2) @(posedge clk);
    #1;
    rst_n = 1'b1;
    drive_idle();
    @(posedge clk);
    #1;

    run_reset_case();

    drive_idle();
    pc_i        = 32'h0000_0000;
    rs1_data_i  = 32'h0000_0005;
    rs2_data_i  = 32'h0000_0003;
    rd_idx_i    = 5'd3;
    alu_op_i    = 4'd0;
    run_case("TC001_ALU_WRITEBACK", 1, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1);

    drive_idle();
    pc_i        = 32'h0000_0100;
    rs1_data_i  = 32'h0000_0009;
    rs2_data_i  = 32'h0000_0009;
    imm_i       = 32'h0000_0010;
    branch_op_i = 3'd1;
    run_case("TC002_BRANCH_TAKEN", 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0);

    drive_idle();
    pc_i        = 32'h0000_0100;
    rs1_data_i  = 32'h0000_0009;
    rs2_data_i  = 32'h0000_0008;
    imm_i       = 32'h0000_0010;
    branch_op_i = 3'd1;
    run_case("TC003_BRANCH_NOTTAKEN", 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0);

    drive_idle();
    pc_i        = 32'h0000_0100;
    imm_i       = 32'h0000_0020;
    rd_idx_i    = 5'd1;
    branch_op_i = 3'd6;
    run_case("TC004_JAL_LINK", 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0);

    drive_idle();
    rs1_data_i   = 32'h0000_1000;
    imm_i        = 32'h0000_0004;
    rd_idx_i     = 5'd5;
    mem_req_i    = 1'b1;
    mem_we_i     = 1'b0;
    load_ready_i = 1'b0;
    run_case("TC005_LOAD_WAIT", 0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1);

    drive_idle();
    rs1_data_i   = 32'h0000_1000;
    imm_i        = 32'h0000_0004;
    rd_idx_i     = 5'd5;
    mem_req_i    = 1'b1;
    mem_we_i     = 1'b0;
    load_data_i  = 32'hA5A5_A5A5;
    load_ready_i = 1'b1;
    run_case("TC006_LOAD_COMPLETE", 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1);

    drive_idle();
    rs1_data_i  = 32'h0000_2000;
    rs2_data_i  = 32'h1234_5678;
    imm_i       = 32'h0000_0008;
    mem_req_i   = 1'b1;
    mem_we_i    = 1'b1;
    run_case("TC007_STORE_ISSUE", 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0);

    drive_idle();
    rs1_data_i  = 32'h0000_0006;
    rs2_data_i  = 32'h0000_0007;
    rd_idx_i    = 5'd4;
    mul_en_i    = 1'b1;
    mul_done_i  = 1'b0;
    run_case("TC008_MUL_WAIT", 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1);

    drive_idle();
    rs1_data_i  = 32'h0000_0006;
    rs2_data_i  = 32'h0000_0007;
    rd_idx_i    = 5'd4;
    mul_en_i    = 1'b1;
    mul_result_i = 32'h0000_002A;
    mul_done_i  = 1'b1;
    run_case("TC009_MUL_COMPLETE", 0, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1);

    drive_idle();
    rs1_data_i  = 32'h0000_0001;
    rd_idx_i    = 5'd1;
    csr_en_i    = 1'b1;
    csr_rdata_i = 32'h0000_1800;
    run_case("TC010_CSR_READ", 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0);

    drive_idle();
    pc_i       = 32'h0000_0040;
    illegal_i  = 1'b1;
    run_case("TC011_ILLEGAL_TRAP", 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0);

    drive_idle();
    pc_i      = 32'h0000_0080;
    mret_i    = 1'b1;
    run_case("TC012_MRET", 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0);

    drive_idle();
    rs1_data_i  = 32'hFFFF_FFFF;
    rs2_data_i  = 32'h0000_0001;
    rd_idx_i    = 5'd15;
    alu_op_i    = 4'd0;
    run_case("TC013_ALU_BOUNDARY", 0, 0, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1);

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

endmodule
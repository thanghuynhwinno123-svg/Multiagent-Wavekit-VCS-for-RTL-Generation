`timescale 1ns/1ps

module tb_decode_control_unit (
  output logic [31:0] instr_i,
  output logic [31:0] pc_i,
  input  logic [4:0]  rs1_idx_o,
  input  logic [4:0]  rs2_idx_o,
  input  logic [4:0]  rd_idx_o,
  input  logic [31:0] imm_o,
  input  logic [3:0]  alu_op_o,
  input  logic [2:0]  branch_op_o,
  input  logic        mul_en_o,
  input  logic        mem_req_o,
  input  logic        mem_we_o,
  input  logic        csr_en_o,
  input  logic        mret_o,
  input  logic        ebreak_o,
  input  logic        illegal_o,
  input  logic        is_compressed_o,
  input  logic        wb_en_o
);

  integer cycle_count = 0;
  integer pass_count = 0;
  integer fail_count = 0;

  function automatic logic [31:0] sext12(input logic [11:0] val);
    sext12 = {{20{val[11]}}, val};
  endfunction

  function automatic logic [31:0] sext13(input logic [12:0] val);
    sext13 = {{19{val[12]}}, val};
  endfunction

  function automatic logic [31:0] sext21(input logic [20:0] val);
    sext21 = {{11{val[20]}}, val};
  endfunction

  function automatic logic [31:0] sext6(input logic [5:0] val);
    sext6 = {{26{val[5]}}, val};
  endfunction

  task automatic apply_stimulus(
    input logic [31:0] instr,
    input logic [31:0] pc
  );
    begin
      instr_i = instr;
      pc_i    = pc;
      #1;
    end
  endtask

  task automatic check_signal(
    input string tc_name,
    input string signal_name,
    input logic [31:0] got_val,
    input logic [31:0] exp_val,
    inout bit case_failed
  );
    begin
      if (got_val !== exp_val) begin
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
        case_failed = 1'b1;
      end
    end
  endtask

  task automatic finish_case(
    input string tc_name,
    input bit case_failed
  );
    begin
      if (case_failed) begin
        fail_count = fail_count + 1;
      end else begin
        pass_count = pass_count + 1;
        $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
      end
    end
  endtask

  task automatic golden_decode(
    input  logic [31:0] instr,
    input  logic [31:0] pc,
    output logic [4:0]  exp_rs1,
    output logic [4:0]  exp_rs2,
    output logic [4:0]  exp_rd,
    output logic [31:0] exp_imm,
    output logic [3:0]  exp_alu_op,
    output logic [2:0]  exp_branch_op,
    output logic        exp_mul_en,
    output logic        exp_mem_req,
    output logic        exp_mem_we,
    output logic        exp_csr_en,
    output logic        exp_mret,
    output logic        exp_ebreak,
    output logic        exp_illegal,
    output logic        exp_is_compressed,
    output logic        exp_wb_en
  );
    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;
    logic [15:0] cinstr;
    logic uses_rs1;
    logic uses_rs2;
    logic uses_rd;

    begin
      exp_rs1           = 5'd0;
      exp_rs2           = 5'd0;
      exp_rd            = 5'd0;
      exp_imm           = 32'd0;
      exp_alu_op        = 4'd0;
      exp_branch_op     = 3'd0;
      exp_mul_en        = 1'b0;
      exp_mem_req       = 1'b0;
      exp_mem_we        = 1'b0;
      exp_csr_en        = 1'b0;
      exp_mret          = 1'b0;
      exp_ebreak        = 1'b0;
      exp_illegal       = 1'b0;
      exp_is_compressed = (instr[1:0] != 2'b11);
      exp_wb_en         = 1'b0;

      opcode  = instr[6:0];
      funct3  = instr[14:12];
      funct7  = instr[31:25];
      cinstr  = instr[15:0];
      uses_rs1 = 1'b0;
      uses_rs2 = 1'b0;
      uses_rd  = 1'b0;

      if (exp_is_compressed) begin
        unique casez (cinstr)
          16'b1001_00000_00000_10: begin
            exp_ebreak = 1'b1;
            exp_wb_en  = 1'b0;
          end

          16'b1001_?????_?????_10: begin
            exp_rs1   = cinstr[11:7];
            exp_rs2   = cinstr[6:2];
            exp_rd    = cinstr[11:7];
            uses_rs1  = 1'b1;
            uses_rs2  = 1'b1;
            uses_rd   = 1'b1;
            exp_wb_en = 1'b1;

            if ((cinstr[11:7] == 5'd0) || (cinstr[6:2] == 5'd0)) begin
              exp_illegal = 1'b1;
            end
          end

          default: begin
            if ((cinstr[15:13] == 3'b100) && (cinstr[1:0] == 2'b01) &&
                (cinstr[11:10] == 2'b10)) begin
              exp_rs1   = 5'd8 + cinstr[9:7];
              exp_rd    = 5'd8 + cinstr[9:7];
              uses_rs1  = 1'b1;
              uses_rd   = 1'b1;
              exp_imm   = sext6({cinstr[12], cinstr[6:2]});
              exp_wb_en = 1'b1;
            end else begin
              exp_illegal = 1'b1;
            end
          end
        endcase
      end else begin
        unique case (opcode)
          7'b0110011: begin
            exp_rs1  = instr[19:15];
            exp_rs2  = instr[24:20];
            exp_rd   = instr[11:7];
            uses_rs1 = 1'b1;
            uses_rs2 = 1'b1;
            uses_rd  = 1'b1;

            if ((funct7 == 7'b0000000) && (funct3 == 3'b000)) begin
              exp_alu_op = 4'd0;
              exp_wb_en  = 1'b1;
            end else if ((funct7 == 7'b0100000) && (funct3 == 3'b000)) begin
              exp_alu_op = 4'd1;
              exp_wb_en  = 1'b1;
            end else if (funct7 == 7'b0000001) begin
              if (funct3 == 3'b000) begin
                exp_mul_en = 1'b1;
                exp_wb_en  = 1'b1;
              end else begin
                exp_illegal = 1'b1;
              end
            end else begin
              exp_illegal = 1'b1;
            end
          end

          7'b0010011: begin
            exp_rs1  = instr[19:15];
            exp_rd   = instr[11:7];
            exp_imm  = sext12(instr[31:20]);
            uses_rs1 = 1'b1;
            uses_rd  = 1'b1;

            if (funct3 == 3'b111) begin
              exp_alu_op = 4'd4;
              exp_wb_en  = 1'b1;
            end else begin
              exp_illegal = 1'b1;
            end
          end

          7'b0000011: begin
            exp_rs1     = instr[19:15];
            exp_rd      = instr[11:7];
            exp_imm     = sext12(instr[31:20]);
            uses_rs1    = 1'b1;
            uses_rd     = 1'b1;
            exp_mem_req = 1'b1;
            exp_mem_we  = 1'b0;
            exp_wb_en   = 1'b1;
          end

          7'b0100011: begin
            exp_rs1     = instr[19:15];
            exp_rs2     = instr[24:20];
            exp_imm     = sext12({instr[31:25], instr[11:7]});
            uses_rs1    = 1'b1;
            uses_rs2    = 1'b1;
            exp_mem_req = 1'b1;
            exp_mem_we  = 1'b1;
            exp_wb_en   = 1'b0;
          end

          7'b1100011: begin
            exp_rs1       = instr[19:15];
            exp_rs2       = instr[24:20];
            exp_imm       = sext13({instr[31], instr[7], instr[30:25], instr[11:8], 1'b0});
            uses_rs1      = 1'b1;
            uses_rs2      = 1'b1;
            exp_branch_op = 3'd1;
            exp_wb_en     = 1'b0;
          end

          7'b1101111: begin
            exp_rd        = instr[11:7];
            exp_imm       = sext21({instr[31], instr[19:12], instr[20], instr[30:21], 1'b0});
            uses_rd       = 1'b1;
            exp_branch_op = 3'd6;
            exp_wb_en     = 1'b1;
          end

          7'b1110011: begin
            exp_rs1  = instr[19:15];
            exp_rd   = instr[11:7];
            uses_rs1 = 1'b1;
            uses_rd  = 1'b1;

            if (instr == 32'h3020_0073) begin
              exp_mret  = 1'b1;
              exp_wb_en = 1'b0;
            end else if (funct3 != 3'b000) begin
              exp_csr_en = 1'b1;
              exp_wb_en  = (instr[11:7] != 5'd0);
            end else begin
              exp_illegal = 1'b1;
            end
          end

          default: begin
            exp_illegal = 1'b1;
          end
        endcase
      end

      if (uses_rs1 && (exp_rs1 > 5'd15)) exp_illegal = 1'b1;
      if (uses_rs2 && (exp_rs2 > 5'd15)) exp_illegal = 1'b1;
      if (uses_rd  && (exp_rd  > 5'd15)) exp_illegal = 1'b1;

      if (exp_illegal) begin
        exp_alu_op    = 4'd0;
        exp_branch_op = 3'd0;
        exp_mul_en    = 1'b0;
        exp_mem_req   = 1'b0;
        exp_mem_we    = 1'b0;
        exp_csr_en    = 1'b0;
        exp_mret      = 1'b0;
        exp_ebreak    = 1'b0;
        exp_wb_en     = 1'b0;
      end

      pc = pc;
    end
  endtask

  task automatic run_tc001_add;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC001_ADD";
      case_failed = 1'b0;
      apply_stimulus(32'h0020_81B3, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rs2_idx_o",         {27'd0, rs2_idx_o},         {27'd0, exp_rs2}, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "imm_o",             imm_o,                      exp_imm, case_failed);
      check_signal(tc_name, "alu_op_o",          {28'd0, alu_op_o},          {28'd0, exp_alu_op}, case_failed);
      check_signal(tc_name, "mul_en_o",          {31'd0, mul_en_o},          {31'd0, exp_mul_en}, case_failed);
      check_signal(tc_name, "mem_req_o",         {31'd0, mem_req_o},         {31'd0, exp_mem_req}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc002_sub;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC002_SUB";
      case_failed = 1'b0;
      apply_stimulus(32'h4020_81B3, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rs2_idx_o",         {27'd0, rs2_idx_o},         {27'd0, exp_rs2}, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "alu_op_o",          {28'd0, alu_op_o},          {28'd0, exp_alu_op}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc003_andi;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC003_ANDI";
      case_failed = 1'b0;
      apply_stimulus(32'hFFF0_F113, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rs2_idx_o",         {27'd0, rs2_idx_o},         32'd0, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "imm_o",             imm_o,                      exp_imm, case_failed);
      check_signal(tc_name, "alu_op_o",          {28'd0, alu_op_o},          {28'd0, exp_alu_op}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc004_load;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC004_LOAD";
      case_failed = 1'b0;
      apply_stimulus(32'h0041_2283, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "imm_o",             imm_o,                      exp_imm, case_failed);
      check_signal(tc_name, "mem_req_o",         {31'd0, mem_req_o},         {31'd0, exp_mem_req}, case_failed);
      check_signal(tc_name, "mem_we_o",          {31'd0, mem_we_o},          {31'd0, exp_mem_we}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc005_store;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC005_STORE";
      case_failed = 1'b0;
      apply_stimulus(32'h0051_2423, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rs2_idx_o",         {27'd0, rs2_idx_o},         {27'd0, exp_rs2}, case_failed);
      check_signal(tc_name, "imm_o",             imm_o,                      exp_imm, case_failed);
      check_signal(tc_name, "mem_req_o",         {31'd0, mem_req_o},         {31'd0, exp_mem_req}, case_failed);
      check_signal(tc_name, "mem_we_o",          {31'd0, mem_we_o},          {31'd0, exp_mem_we}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc006_branch;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC006_BRANCH";
      case_failed = 1'b0;
      apply_stimulus(32'h0020_8463, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rs2_idx_o",         {27'd0, rs2_idx_o},         {27'd0, exp_rs2}, case_failed);
      check_signal(tc_name, "imm_o",             imm_o,                      exp_imm, case_failed);
      check_signal(tc_name, "branch_op_o",       {29'd0, branch_op_o},       {29'd0, exp_branch_op}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc007_jal;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC007_JAL";
      case_failed = 1'b0;
      apply_stimulus(32'h0100_00EF, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "imm_o",             imm_o,                      exp_imm, case_failed);
      check_signal(tc_name, "branch_op_o",       {29'd0, branch_op_o},       {29'd0, exp_branch_op}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc008_mul;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC008_MUL";
      case_failed = 1'b0;
      apply_stimulus(32'h0220_81B3, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rs2_idx_o",         {27'd0, rs2_idx_o},         {27'd0, exp_rs2}, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "mul_en_o",          {31'd0, mul_en_o},          {31'd0, exp_mul_en}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc009_div_illegal;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC009_DIV_ILLEGAL";
      case_failed = 1'b0;
      apply_stimulus(32'h0220_C1B3, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "mul_en_o",          {31'd0, mul_en_o},          {31'd0, exp_mul_en}, case_failed);
      check_signal(tc_name, "mem_req_o",         {31'd0, mem_req_o},         {31'd0, exp_mem_req}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc010_x16_illegal;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC010_X16_ILLEGAL";
      case_failed = 1'b0;
      apply_stimulus(32'h0028_0833, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc011_csrrs;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC011_CSRRS";
      case_failed = 1'b0;
      apply_stimulus(32'h3001_20F3, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "csr_en_o",          {31'd0, csr_en_o},          {31'd0, exp_csr_en}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc012_mret;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC012_MRET";
      case_failed = 1'b0;
      apply_stimulus(32'h3020_0073, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "mret_o",            {31'd0, mret_o},            {31'd0, exp_mret}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc013_c_add;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC013_C_ADD";
      case_failed = 1'b0;
      apply_stimulus(32'h0000_908A, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rs2_idx_o",         {27'd0, rs2_idx_o},         {27'd0, exp_rs2}, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "is_compressed_o",   {31'd0, is_compressed_o},   {31'd0, exp_is_compressed}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc014_c_andi;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC014_C_ANDI";
      case_failed = 1'b0;
      apply_stimulus(32'h0000_8865, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "rs1_idx_o",         {27'd0, rs1_idx_o},         {27'd0, exp_rs1}, case_failed);
      check_signal(tc_name, "rd_idx_o",          {27'd0, rd_idx_o},          {27'd0, exp_rd}, case_failed);
      check_signal(tc_name, "imm_o",             imm_o,                      exp_imm, case_failed);
      check_signal(tc_name, "is_compressed_o",   {31'd0, is_compressed_o},   {31'd0, exp_is_compressed}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  task automatic run_tc015_c_ebreak;
    string tc_name;
    bit case_failed;
    logic [4:0] exp_rs1, exp_rs2, exp_rd;
    logic [31:0] exp_imm;
    logic [3:0] exp_alu_op;
    logic [2:0] exp_branch_op;
    logic exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak, exp_illegal, exp_is_compressed, exp_wb_en;
    begin
      tc_name = "TC015_C_EBREAK";
      case_failed = 1'b0;
      apply_stimulus(32'h0000_9002, 32'h0000_0000);
      golden_decode(instr_i, pc_i, exp_rs1, exp_rs2, exp_rd, exp_imm, exp_alu_op, exp_branch_op,
                    exp_mul_en, exp_mem_req, exp_mem_we, exp_csr_en, exp_mret, exp_ebreak,
                    exp_illegal, exp_is_compressed, exp_wb_en);
      check_signal(tc_name, "ebreak_o",          {31'd0, ebreak_o},          {31'd0, exp_ebreak}, case_failed);
      check_signal(tc_name, "is_compressed_o",   {31'd0, is_compressed_o},   {31'd0, exp_is_compressed}, case_failed);
      check_signal(tc_name, "illegal_o",         {31'd0, illegal_o},         {31'd0, exp_illegal}, case_failed);
      check_signal(tc_name, "wb_en_o",           {31'd0, wb_en_o},           {31'd0, exp_wb_en}, case_failed);
      finish_case(tc_name, case_failed);
    end
  endtask

  initial begin
    instr_i = 32'd0;
    pc_i    = 32'd0;

    run_tc001_add();
    run_tc002_sub();
    run_tc003_andi();
    run_tc004_load();
    run_tc005_store();
    run_tc006_branch();
    run_tc007_jal();
    run_tc008_mul();
    run_tc009_div_illegal();
    run_tc010_x16_illegal();
    run_tc011_csrrs();
    run_tc012_mret();
    run_tc013_c_add();
    run_tc014_c_andi();
    run_tc015_c_ebreak();

    $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
    $finish;
  end

  initial begin
    #1_000_000;
    $display("TIMEOUT");
    $finish;
  end

endmodule
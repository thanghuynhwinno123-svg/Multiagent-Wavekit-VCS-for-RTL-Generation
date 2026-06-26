`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module decode_control_unit (
  input  logic [31:0] instr_i,
  input  logic [31:0] pc_i,
  output logic [4:0]  rs1_idx_o,
  output logic [4:0]  rs2_idx_o,
  output logic [4:0]  rd_idx_o,
  output logic [31:0] imm_o,
  output logic [3:0]  alu_op_o,
  output logic [2:0]  branch_op_o,
  output logic        mul_en_o,
  output logic        mem_req_o,
  output logic        mem_we_o,
  output logic        csr_en_o,
  output logic        mret_o,
  output logic        ebreak_o,
  output logic        illegal_o,
  output logic        is_compressed_o,
  output logic        wb_en_o
);

  logic [15:0] c_instr;

  logic [4:0]  rs1_idx_d;
  logic [4:0]  rs2_idx_d;
  logic [4:0]  rd_idx_d;
  logic [31:0] imm_d;
  logic [3:0]  alu_op_d;
  logic [2:0]  branch_op_d;
  logic        mul_en_d;
  logic        mem_req_d;
  logic        mem_we_d;
  logic        csr_en_d;
  logic        mret_d;
  logic        ebreak_d;
  logic        wb_en_d;
  logic        illegal_d;

  logic        use_rs1_d;
  logic        use_rs2_d;
  logic        use_rd_d;
  logic        regs_illegal;

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  logic [4:0] c_rd_rs1;
  logic [4:0] c_rs2;
  logic [4:0] c_rdp;
  logic [4:0] c_rs1p;
  logic [4:0] c_rs2p;

  function automatic logic [31:0] sext12(input logic [11:0] value);
    sext12 = {{20{value[11]}}, value};
  endfunction

  function automatic logic [31:0] sext6(input logic [5:0] value);
    sext6 = {{26{value[5]}}, value};
  endfunction

  always_comb begin
    c_instr   = instr_i[15:0];
    opcode    = instr_i[6:0];
    funct3    = instr_i[14:12];
    funct7    = instr_i[31:25];

    c_rd_rs1  = c_instr[11:7];
    c_rs2     = c_instr[6:2];
    c_rdp     = {2'b01, c_instr[4:2]};
    c_rs1p    = {2'b01, c_instr[9:7]};
    c_rs2p    = {2'b01, c_instr[4:2]};

    rs1_idx_d       = 5'd0;
    rs2_idx_d       = 5'd0;
    rd_idx_d        = 5'd0;
    imm_d           = 32'd0;
    alu_op_d        = 4'd0;
    branch_op_d     = 3'd0;
    mul_en_d        = 1'b0;
    mem_req_d       = 1'b0;
    mem_we_d        = 1'b0;
    csr_en_d        = 1'b0;
    mret_d          = 1'b0;
    ebreak_d        = 1'b0;
    wb_en_d         = 1'b0;
    illegal_d       = 1'b0;
    use_rs1_d       = 1'b0;
    use_rs2_d       = 1'b0;
    use_rd_d        = 1'b0;
    is_compressed_o = (instr_i[1:0] != 2'b11);

    if (instr_i[1:0] == 2'b11) begin
      unique case (opcode)
        7'b0110011: begin
          rs1_idx_d = instr_i[19:15];
          rs2_idx_d = instr_i[24:20];
          rd_idx_d  = instr_i[11:7];
          use_rs1_d = 1'b1;
          use_rs2_d = 1'b1;
          use_rd_d  = 1'b1;
          wb_en_d   = 1'b1;

          if (funct7 == 7'b0000000) begin
            unique case (funct3)
              3'b000: alu_op_d = 4'd0;
              3'b111: alu_op_d = 4'd2;
              3'b110: alu_op_d = 4'd3;
              3'b100: alu_op_d = 4'd4;
              3'b001: alu_op_d = 4'd5;
              3'b101: alu_op_d = 4'd6;
              3'b010: alu_op_d = 4'd8;
              3'b011: alu_op_d = 4'd9;
              default: illegal_d = 1'b1;
            endcase
          end else if (funct7 == 7'b0100000) begin
            unique case (funct3)
              3'b000: alu_op_d = 4'd1;
              3'b101: alu_op_d = 4'd7;
              default: illegal_d = 1'b1;
            endcase
          end else if (funct7 == 7'b0000001) begin
            unique case (funct3)
              3'b000,
              3'b001,
              3'b010,
              3'b011: mul_en_d = 1'b1;
              3'b100,
              3'b101,
              3'b110,
              3'b111: illegal_d = 1'b1;
              default: illegal_d = 1'b1;
            endcase
          end else begin
            illegal_d = 1'b1;
          end
        end

        7'b0010011: begin
          rs1_idx_d = instr_i[19:15];
          rd_idx_d  = instr_i[11:7];
          imm_d     = sext12(instr_i[31:20]);
          use_rs1_d = 1'b1;
          use_rd_d  = 1'b1;
          wb_en_d   = 1'b1;

          unique case (funct3)
            3'b000: alu_op_d = 4'd0;
            3'b010: alu_op_d = 4'd8;
            3'b011: alu_op_d = 4'd9;
            3'b100: alu_op_d = 4'd4;
            3'b110: alu_op_d = 4'd3;
            3'b111: alu_op_d = 4'd4;
            3'b001: begin
              if (instr_i[31:25] == 7'b0000000) begin
                alu_op_d = 4'd5;
                imm_d    = {27'd0, instr_i[24:20]};
              end else begin
                illegal_d = 1'b1;
              end
            end
            3'b101: begin
              if (instr_i[31:25] == 7'b0000000) begin
                alu_op_d = 4'd6;
                imm_d    = {27'd0, instr_i[24:20]};
              end else if (instr_i[31:25] == 7'b0100000) begin
                alu_op_d = 4'd7;
                imm_d    = {27'd0, instr_i[24:20]};
              end else begin
                illegal_d = 1'b1;
              end
            end
            default: illegal_d = 1'b1;
          endcase
        end

        7'b0000011: begin
          rs1_idx_d = instr_i[19:15];
          rd_idx_d  = instr_i[11:7];
          imm_d     = sext12(instr_i[31:20]);
          use_rs1_d = 1'b1;
          use_rd_d  = 1'b1;
          mem_req_d = 1'b1;
          wb_en_d   = 1'b1;

          unique case (funct3)
            3'b000,
            3'b001,
            3'b010,
            3'b100,
            3'b101: begin
            end
            default: illegal_d = 1'b1;
          endcase
        end

        7'b0100011: begin
          rs1_idx_d = instr_i[19:15];
          rs2_idx_d = instr_i[24:20];
          imm_d     = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
          use_rs1_d = 1'b1;
          use_rs2_d = 1'b1;
          mem_req_d = 1'b1;
          mem_we_d  = 1'b1;

          unique case (funct3)
            3'b000,
            3'b001,
            3'b010: begin
            end
            default: illegal_d = 1'b1;
          endcase
        end

        7'b1100011: begin
          rs1_idx_d   = instr_i[19:15];
          rs2_idx_d   = instr_i[24:20];
          imm_d       = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
          use_rs1_d   = 1'b1;
          use_rs2_d   = 1'b1;

          unique case (funct3)
            3'b000: branch_op_d = 3'd1;
            3'b001: branch_op_d = 3'd2;
            3'b100,
            3'b110: branch_op_d = 3'd3;
            3'b101,
            3'b111: branch_op_d = 3'd4;
            default: illegal_d = 1'b1;
          endcase
        end

        7'b1101111: begin
          rd_idx_d    = instr_i[11:7];
          imm_d       = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
          branch_op_d = 3'd6;
          use_rd_d    = 1'b1;
          wb_en_d     = 1'b1;
        end

        7'b1100111: begin
          rs1_idx_d   = instr_i[19:15];
          rd_idx_d    = instr_i[11:7];
          imm_d       = sext12(instr_i[31:20]);
          use_rs1_d   = 1'b1;
          use_rd_d    = 1'b1;
          wb_en_d     = 1'b1;

          if (funct3 == 3'b000) begin
            branch_op_d = 3'd7;
          end else begin
            illegal_d = 1'b1;
          end
        end

        7'b0110111: begin
          rd_idx_d  = instr_i[11:7];
          imm_d     = {instr_i[31:12], 12'd0};
          use_rd_d  = 1'b1;
          wb_en_d   = 1'b1;
          alu_op_d  = 4'd0;
        end

        7'b0010111: begin
          rd_idx_d  = instr_i[11:7];
          imm_d     = {instr_i[31:12], 12'd0};
          use_rd_d  = 1'b1;
          wb_en_d   = 1'b1;
          alu_op_d  = 4'd0;
        end

        7'b1110011: begin
          if (funct3 == 3'b000) begin
            unique case (instr_i[31:20])
              12'h001: begin
                ebreak_d = 1'b1;
              end
              12'h302: begin
                mret_d = 1'b1;
              end
              default: begin
                illegal_d = 1'b1;
              end
            endcase
          end else begin
            rd_idx_d  = instr_i[11:7];
            use_rd_d  = 1'b1;
            csr_en_d  = 1'b1;
            wb_en_d   = (instr_i[11:7] != 5'd0);

            unique case (funct3)
              3'b001,
              3'b010,
              3'b011: begin
                rs1_idx_d = instr_i[19:15];
                use_rs1_d = 1'b1;
              end
              3'b101,
              3'b110,
              3'b111: begin
                imm_d = {27'd0, instr_i[19:15]};
              end
              default: illegal_d = 1'b1;
            endcase
          end
        end

        default: begin
          illegal_d = 1'b1;
        end
      endcase
    end else begin
      unique case (c_instr[1:0])
        2'b01: begin
          unique case (c_instr[15:13])
            3'b100: begin
              if (c_instr[11:10] == 2'b10) begin
                rs1_idx_d = c_rs1p;
                rd_idx_d  = c_rs1p;
                imm_d     = sext6({c_instr[12], c_instr[6:2]});
                alu_op_d  = 4'd4;
                use_rs1_d = 1'b1;
                use_rd_d  = 1'b1;
                wb_en_d   = 1'b1;
              end else if ((c_instr[11:10] == 2'b00) && (c_instr[12] == 1'b0)) begin
                rs1_idx_d = c_rs1p;
                rd_idx_d  = c_rs1p;
                imm_d     = {27'd0, c_instr[6:2]};
                alu_op_d  = 4'd6;
                use_rs1_d = 1'b1;
                use_rd_d  = 1'b1;
                wb_en_d   = 1'b1;
              end else if ((c_instr[11:10] == 2'b01) && (c_instr[12] == 1'b0)) begin
                rs1_idx_d = c_rs1p;
                rd_idx_d  = c_rs1p;
                imm_d     = {27'd0, c_instr[6:2]};
                alu_op_d  = 4'd7;
                use_rs1_d = 1'b1;
                use_rd_d  = 1'b1;
                wb_en_d   = 1'b1;
              end else if ({c_instr[15:10], c_instr[6:5]} == 8'b10001100) begin
                rs1_idx_d = c_rs1p;
                rs2_idx_d = c_rs2p;
                rd_idx_d  = c_rs1p;
                alu_op_d  = 4'd1;
                use_rs1_d = 1'b1;
                use_rs2_d = 1'b1;
                use_rd_d  = 1'b1;
                wb_en_d   = 1'b1;
              end else if ({c_instr[15:10], c_instr[6:5]} == 8'b10001101) begin
                rs1_idx_d = c_rs1p;
                rs2_idx_d = c_rs2p;
                rd_idx_d  = c_rs1p;
                alu_op_d  = 4'd4;
                use_rs1_d = 1'b1;
                use_rs2_d = 1'b1;
                use_rd_d  = 1'b1;
                wb_en_d   = 1'b1;
              end else if ({c_instr[15:10], c_instr[6:5]} == 8'b10001110) begin
                rs1_idx_d = c_rs1p;
                rs2_idx_d = c_rs2p;
                rd_idx_d  = c_rs1p;
                alu_op_d  = 4'd3;
                use_rs1_d = 1'b1;
                use_rs2_d = 1'b1;
                use_rd_d  = 1'b1;
                wb_en_d   = 1'b1;
              end else if ({c_instr[15:10], c_instr[6:5]} == 8'b10001111) begin
                rs1_idx_d = c_rs1p;
                rs2_idx_d = c_rs2p;
                rd_idx_d  = c_rs1p;
                alu_op_d  = 4'd2;
                use_rs1_d = 1'b1;
                use_rs2_d = 1'b1;
                use_rd_d  = 1'b1;
                wb_en_d   = 1'b1;
              end else begin
                illegal_d = 1'b1;
              end
            end
            default: begin
              illegal_d = 1'b1;
            end
          endcase
        end

        2'b10: begin
          if (c_instr[15:12] == 4'b1000) begin
            if ((c_rd_rs1 != 5'd0) && (c_rs2 != 5'd0)) begin
              rs1_idx_d = 5'd0;
              rs2_idx_d = c_rs2;
              rd_idx_d  = c_rd_rs1;
              use_rs2_d = 1'b1;
              use_rd_d  = 1'b1;
              wb_en_d   = 1'b1;
              alu_op_d  = 4'd0;
            end else begin
              illegal_d = 1'b1;
            end
          end else if (c_instr[15:12] == 4'b1001) begin
            if ((c_rd_rs1 == 5'd0) && (c_rs2 == 5'd0)) begin
              ebreak_d = 1'b1;
            end else if ((c_rd_rs1 != 5'd0) && (c_rs2 != 5'd0)) begin
              rs1_idx_d = c_rd_rs1;
              rs2_idx_d = c_rs2;
              rd_idx_d  = c_rd_rs1;
              use_rs1_d = 1'b1;
              use_rs2_d = 1'b1;
              use_rd_d  = 1'b1;
              wb_en_d   = 1'b1;
              alu_op_d  = 4'd0;
            end else begin
              illegal_d = 1'b1;
            end
          end else begin
            illegal_d = 1'b1;
          end
        end

        default: begin
          illegal_d = 1'b1;
        end
      endcase
    end

    regs_illegal = 1'b0;
    if (use_rs1_d && (rs1_idx_d > RV32EC_ZMMUL_X15)) begin
      regs_illegal = 1'b1;
    end
    if (use_rs2_d && (rs2_idx_d > RV32EC_ZMMUL_X15)) begin
      regs_illegal = 1'b1;
    end
    if (use_rd_d && (rd_idx_d > RV32EC_ZMMUL_X15)) begin
      regs_illegal = 1'b1;
    end

    illegal_o = illegal_d | regs_illegal;

    if (illegal_o) begin
      rs1_idx_o   = 5'd0;
      rs2_idx_o   = 5'd0;
      rd_idx_o    = 5'd0;
      imm_o       = 32'd0;
      alu_op_o    = 4'd0;
      branch_op_o = 3'd0;
      mul_en_o    = 1'b0;
      mem_req_o   = 1'b0;
      mem_we_o    = 1'b0;
      csr_en_o    = 1'b0;
      mret_o      = 1'b0;
      ebreak_o    = 1'b0;
      wb_en_o     = 1'b0;
    end else begin
      rs1_idx_o   = rs1_idx_d;
      rs2_idx_o   = rs2_idx_d;
      rd_idx_o    = rd_idx_d;
      imm_o       = imm_d;
      alu_op_o    = alu_op_d;
      branch_op_o = branch_op_d;
      mul_en_o    = mul_en_d;
      mem_req_o   = mem_req_d;
      mem_we_o    = mem_we_d;
      csr_en_o    = csr_en_d;
      mret_o      = mret_d;
      ebreak_o    = ebreak_d;
      wb_en_o     = wb_en_d;
    end
  end

  logic unused_pc;
  assign unused_pc = ^pc_i;

endmodule
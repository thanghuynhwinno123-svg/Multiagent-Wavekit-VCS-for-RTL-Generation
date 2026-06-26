`timescale 1ns/1ps

package rv32ec_zmmul_core_pkg;

  localparam int unsigned RV32EC_ZMMUL_XLEN               = 32;
  localparam int unsigned RV32EC_ZMMUL_ILEN               = 32;
  localparam int unsigned RV32EC_ZMMUL_CLEN               = 16;
  localparam int unsigned RV32EC_ZMMUL_PC_W               = 32;
  localparam int unsigned RV32EC_ZMMUL_INSTR_W            = 32;
  localparam int unsigned RV32EC_ZMMUL_REG_COUNT          = 16;
  localparam int unsigned RV32EC_ZMMUL_REG_ADDR_W         = 4;
  localparam int unsigned RV32EC_ZMMUL_ARCH_REG_ENC_W     = 5;
  localparam int unsigned RV32EC_ZMMUL_CSR_ADDR_W         = 12;
  localparam int unsigned RV32EC_ZMMUL_ALU_OP_W           = 4;
  localparam int unsigned RV32EC_ZMMUL_BRANCH_OP_W        = 3;
  localparam int unsigned RV32EC_ZMMUL_MEM_SIZE_W         = 2;
  localparam int unsigned RV32EC_ZMMUL_TRAP_CAUSE_W       = 4;
  localparam int unsigned RV32EC_ZMMUL_BYTE_W             = 8;
  localparam int unsigned RV32EC_ZMMUL_HALF_W             = 16;
  localparam int unsigned RV32EC_ZMMUL_WORD_W             = 32;
  localparam int unsigned RV32EC_ZMMUL_SHAMT_W            = 5;
  localparam int unsigned RV32EC_ZMMUL_BOOT_TIMEOUT_W     = 16;

  localparam logic [31:0] RV32EC_ZMMUL_RESET_VECTOR       = 32'h0000_0000;
  localparam logic [31:0] RV32EC_ZMMUL_MTVEC_RESET        = 32'h0000_0100;
  localparam logic [31:0] RV32EC_ZMMUL_SPI_BOOT_BASE_ADDR = 32'h0000_0000;
  localparam logic [31:0] RV32EC_ZMMUL_IRAM_BASE_ADDR     = 32'h0000_0000;
  localparam int unsigned RV32EC_ZMMUL_IRAM_BYTES         = 16384;
  localparam int unsigned RV32EC_ZMMUL_DRAM_BYTES         = 8192;
  localparam int unsigned RV32EC_ZMMUL_BOOT_ROM_BYTES_MAX = 16384;

  localparam logic [31:0] RV32EC_ZMMUL_BOOT_MAGIC         = 32'hB007_CAFE;

  localparam logic [4:0] RV32EC_ZMMUL_X0                  = 5'd0;
  localparam logic [4:0] RV32EC_ZMMUL_X1                  = 5'd1;
  localparam logic [4:0] RV32EC_ZMMUL_X2                  = 5'd2;
  localparam logic [4:0] RV32EC_ZMMUL_X15                 = 5'd15;
  localparam logic [4:0] RV32EC_ZMMUL_X16                = 5'd16;
  localparam logic [4:0] RV32EC_ZMMUL_X31                = 5'd31;

  typedef logic [RV32EC_ZMMUL_XLEN-1:0]      rv32_word_t;
  typedef logic [RV32EC_ZMMUL_ILEN-1:0]      rv32_instr_t;
  typedef logic [RV32EC_ZMMUL_CLEN-1:0]      rv32_cinstr_t;
  typedef logic [RV32EC_ZMMUL_PC_W-1:0]      rv32_pc_t;
  typedef logic [RV32EC_ZMMUL_CSR_ADDR_W-1:0] csr_addr_t;
  typedef logic [RV32EC_ZMMUL_ARCH_REG_ENC_W-1:0] reg_idx_t;
  typedef logic [RV32EC_ZMMUL_REG_ADDR_W-1:0] regfile_idx_t;

  typedef enum logic [RV32EC_ZMMUL_ALU_OP_W-1:0] {
    ALU_OP_ADD    = 4'd0,
    ALU_OP_SUB    = 4'd1,
    ALU_OP_AND    = 4'd2,
    ALU_OP_OR     = 4'd3,
    ALU_OP_XOR    = 4'd4,
    ALU_OP_SLL    = 4'd5,
    ALU_OP_SRL    = 4'd6,
    ALU_OP_SRA    = 4'd7,
    ALU_OP_SLT    = 4'd8,
    ALU_OP_SLTU   = 4'd9,
    ALU_OP_PASS_A = 4'd10,
    ALU_OP_PASS_B = 4'd11,
    ALU_OP_ZERO   = 4'd15
  } alu_op_t;

  typedef enum logic [RV32EC_ZMMUL_BRANCH_OP_W-1:0] {
    BR_OP_NONE = 3'd0,
    BR_OP_BEQ  = 3'd1,
    BR_OP_BNE  = 3'd2,
    BR_OP_BLT  = 3'd3,
    BR_OP_BGEU = 3'd4,
    BR_OP_BGE  = 3'd5,
    BR_OP_JAL  = 3'd6,
    BR_OP_JALR = 3'd7
  } branch_op_t;

  typedef enum logic [RV32EC_ZMMUL_MEM_SIZE_W-1:0] {
    MEM_SIZE_B = 2'd0,
    MEM_SIZE_H = 2'd1,
    MEM_SIZE_W = 2'd2
  } mem_size_t;

  typedef enum logic [RV32EC_ZMMUL_TRAP_CAUSE_W-1:0] {
    TRAP_CAUSE_INSTR_ADDR_MISALIGNED = 4'd0,
    TRAP_CAUSE_ILLEGAL_INSTR         = 4'd2,
    TRAP_CAUSE_BREAKPOINT            = 4'd3,
    TRAP_CAUSE_LOAD_ADDR_MISALIGNED  = 4'd4,
    TRAP_CAUSE_STORE_ADDR_MISALIGNED = 4'd6,
    TRAP_CAUSE_M_EXT_IRQ             = 4'd11
  } trap_cause_t;

  typedef enum logic [1:0] {
    MUL_STATE_IDLE = 2'd0,
    MUL_STATE_BUSY = 2'd1,
    MUL_STATE_DONE = 2'd2
  } mul_state_t;

  typedef enum logic [1:0] {
    LSU_STATE_IDLE       = 2'd0,
    LSU_STATE_WAIT_RESP  = 2'd1,
    LSU_STATE_DONE_PULSE = 2'd2
  } lsu_state_t;

  typedef enum logic [3:0] {
    BOOT_STATE_IDLE          = 4'd0,
    BOOT_STATE_FETCH_HEADER  = 4'd1,
    BOOT_STATE_CHECK_HEADER  = 4'd2,
    BOOT_STATE_FETCH_SIZE    = 4'd3,
    BOOT_STATE_FETCH_ENTRY   = 4'd4,
    BOOT_STATE_FETCH_DATA    = 4'd5,
    BOOT_STATE_WRITE_DATA    = 4'd6,
    BOOT_STATE_DONE          = 4'd7,
    BOOT_STATE_FAIL_STOP     = 4'd8
  } boot_state_t;

  typedef enum logic [1:0] {
    CORE_STATE_RESET = 2'd0,
    CORE_STATE_BOOT  = 2'd1,
    CORE_STATE_RUN   = 2'd2,
    CORE_STATE_FAIL  = 2'd3
  } core_state_t;

  localparam logic [6:0] OPCODE_LOAD      = 7'b0000011;
  localparam logic [6:0] OPCODE_LOAD_FP   = 7'b0000111;
  localparam logic [6:0] OPCODE_MISC_MEM  = 7'b0001111;
  localparam logic [6:0] OPCODE_OP_IMM    = 7'b0010011;
  localparam logic [6:0] OPCODE_AUIPC     = 7'b0010111;
  localparam logic [6:0] OPCODE_OP_IMM_32 = 7'b0011011;
  localparam logic [6:0] OPCODE_STORE     = 7'b0100011;
  localparam logic [6:0] OPCODE_STORE_FP  = 7'b0100111;
  localparam logic [6:0] OPCODE_AMO       = 7'b0101111;
  localparam logic [6:0] OPCODE_OP        = 7'b0110011;
  localparam logic [6:0] OPCODE_LUI       = 7'b0110111;
  localparam logic [6:0] OPCODE_OP_32     = 7'b0111011;
  localparam logic [6:0] OPCODE_BRANCH    = 7'b1100011;
  localparam logic [6:0] OPCODE_JALR      = 7'b1100111;
  localparam logic [6:0] OPCODE_JAL       = 7'b1101111;
  localparam logic [6:0] OPCODE_SYSTEM    = 7'b1110011;

  localparam logic [2:0] F3_ADD_SUB  = 3'b000;
  localparam logic [2:0] F3_SLL      = 3'b001;
  localparam logic [2:0] F3_SLT      = 3'b010;
  localparam logic [2:0] F3_SLTU     = 3'b011;
  localparam logic [2:0] F3_XOR      = 3'b100;
  localparam logic [2:0] F3_SRL_SRA  = 3'b101;
  localparam logic [2:0] F3_OR       = 3'b110;
  localparam logic [2:0] F3_AND      = 3'b111;

  localparam logic [2:0] F3_BEQ      = 3'b000;
  localparam logic [2:0] F3_BNE      = 3'b001;
  localparam logic [2:0] F3_BLT      = 3'b100;
  localparam logic [2:0] F3_BGE      = 3'b101;
  localparam logic [2:0] F3_BLTU     = 3'b110;
  localparam logic [2:0] F3_BGEU     = 3'b111;

  localparam logic [2:0] F3_LB       = 3'b000;
  localparam logic [2:0] F3_LH       = 3'b001;
  localparam logic [2:0] F3_LW       = 3'b010;
  localparam logic [2:0] F3_LBU      = 3'b100;
  localparam logic [2:0] F3_LHU      = 3'b101;

  localparam logic [2:0] F3_SB       = 3'b000;
  localparam logic [2:0] F3_SH       = 3'b001;
  localparam logic [2:0] F3_SW       = 3'b010;

  localparam logic [2:0] F3_CSRRW    = 3'b001;
  localparam logic [2:0] F3_CSRRS    = 3'b010;
  localparam logic [2:0] F3_CSRRC    = 3'b011;
  localparam logic [2:0] F3_CSRRWI   = 3'b101;
  localparam logic [2:0] F3_CSRRSI   = 3'b110;
  localparam logic [2:0] F3_CSRRCI   = 3'b111;

  localparam logic [6:0] F7_BASE     = 7'b0000000;
  localparam logic [6:0] F7_SUB_SRA  = 7'b0100000;
  localparam logic [6:0] F7_MULDIV   = 7'b0000001;

  localparam logic [2:0] F3_MUL      = 3'b000;
  localparam logic [2:0] F3_MULH     = 3'b001;
  localparam logic [2:0] F3_MULHSU   = 3'b010;
  localparam logic [2:0] F3_MULHU    = 3'b011;
  localparam logic [2:0] F3_DIV      = 3'b100;
  localparam logic [2:0] F3_DIVU     = 3'b101;
  localparam logic [2:0] F3_REM      = 3'b110;
  localparam logic [2:0] F3_REMU     = 3'b111;

  localparam logic [11:0] SYS_ECALL  = 12'h000;
  localparam logic [11:0] SYS_EBREAK = 12'h001;
  localparam logic [11:0] SYS_MRET   = 12'h302;

  localparam logic [1:0] C_QUADRANT_0 = 2'b00;
  localparam logic [1:0] C_QUADRANT_1 = 2'b01;
  localparam logic [1:0] C_QUADRANT_2 = 2'b10;

  localparam logic [2:0] C_F3_ADDI4SPN = 3'b000;
  localparam logic [2:0] C_F3_LW       = 3'b010;
  localparam logic [2:0] C_F3_SW       = 3'b110;
  localparam logic [2:0] C_F3_ADDI     = 3'b000;
  localparam logic [2:0] C_F3_JAL      = 3'b001;
  localparam logic [2:0] C_F3_LI       = 3'b010;
  localparam logic [2:0] C_F3_LUI_ADDI16SP = 3'b011;
  localparam logic [2:0] C_F3_MISC_ALU = 3'b100;
  localparam logic [2:0] C_F3_J        = 3'b101;
  localparam logic [2:0] C_F3_BEQZ     = 3'b110;
  localparam logic [2:0] C_F3_BNEZ     = 3'b111;

  localparam logic [3:0] C_F4_MV       = 4'b1000;
  localparam logic [3:0] C_F4_ADD_EBREAK_JALR = 4'b1001;

  localparam logic [5:0] C_F6_ALU_SUBXORORAND = 6'b100011;

  localparam logic [11:0] CSR_MSTATUS  = 12'h300;
  localparam logic [11:0] CSR_MISA     = 12'h301;
  localparam logic [11:0] CSR_MIE      = 12'h304;
  localparam logic [11:0] CSR_MTVEC    = 12'h305;
  localparam logic [11:0] CSR_MSCRATCH = 12'h340;
  localparam logic [11:0] CSR_MEPC     = 12'h341;
  localparam logic [11:0] CSR_MCAUSE   = 12'h342;
  localparam logic [11:0] CSR_MIP      = 12'h344;

  localparam logic [31:0] MSTATUS_MIE_MASK  = 32'h0000_0008;
  localparam logic [31:0] MSTATUS_MPIE_MASK = 32'h0000_0080;
  localparam logic [31:0] MIP_MEIP_MASK     = 32'h0000_0800;
  localparam logic [31:0] MIE_MEIE_MASK     = 32'h0000_0800;

  localparam logic [31:0] MISA_RV32E_C_ZMMUL = 32'h4000_1100;

  localparam logic [31:0] INSTR_NOP = 32'h0000_0013;

  function automatic logic rv32ec_is_legal_reg(input reg_idx_t reg_idx);
    return (reg_idx < 5'd16);
  endfunction

  function automatic regfile_idx_t rv32ec_regfile_idx(input reg_idx_t reg_idx);
    return reg_idx[RV32EC_ZMMUL_REG_ADDR_W-1:0];
  endfunction

endpackage
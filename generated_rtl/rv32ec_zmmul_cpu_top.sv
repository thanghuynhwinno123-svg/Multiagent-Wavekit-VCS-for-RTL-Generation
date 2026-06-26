`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module rv32ec_zmmul_cpu_top (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        boot_mode_spi,
  input  logic        ext_irq,
  input  logic        instr_ready,
  input  logic [31:0] instr_rdata,
  input  logic        data_ready,
  input  logic [31:0] data_rdata,
  input  logic        spi_ready,
  input  logic [31:0] spi_rdata,
  output logic        instr_req,
  output logic [31:0] instr_addr,
  output logic        data_req,
  output logic        data_we,
  output logic [3:0]  data_be,
  output logic [31:0] data_addr,
  output logic [31:0] data_wdata,
  output logic        spi_req,
  output logic [31:0] spi_addr,
  output logic        fail_stop
);

  typedef enum logic [1:0] {
    TOP_STATE_INIT = 2'd0,
    TOP_STATE_BOOT = 2'd1,
    TOP_STATE_RUN  = 2'd2,
    TOP_STATE_FAIL = 2'd3
  } top_state_e;

  top_state_e top_state_q;

  logic        fail_stop_q;
  logic [31:0] pc_q;

  logic        instr_buf_valid_q;
  logic [31:0] instr_buf_q;
  logic [31:0] instr_buf_pc_q;

  logic        x_valid_q;
  logic [31:0] x_pc_q;
  logic [31:0] x_instr_q;
  logic [31:0] x_imm_q;
  logic [31:0] x_rs1_data_q;
  logic [31:0] x_rs2_data_q;
  logic [4:0]  x_rd_idx_q;
  logic [3:0]  x_alu_op_q;
  logic [2:0]  x_branch_op_q;
  logic        x_mul_en_q;
  logic        x_mem_req_q;
  logic        x_mem_we_q;
  logic [1:0]  x_mem_size_q;
  logic        x_mem_unsigned_q;
  logic        x_csr_en_q;
  logic [2:0]  x_csr_funct3_q;
  logic [11:0] x_csr_addr_q;
  logic        x_mret_q;
  logic        x_ebreak_q;
  logic        x_illegal_q;
  logic        x_is_compressed_q;
  logic        x_wb_en_q;

  logic [4:0]  dec_rs1_idx_w;
  logic [4:0]  dec_rs2_idx_w;
  logic [4:0]  dec_rd_idx_w;
  logic [31:0] dec_imm_w;
  logic [3:0]  dec_alu_op_w;
  logic [2:0]  dec_branch_op_w;
  logic        dec_mul_en_w;
  logic        dec_mem_req_w;
  logic        dec_mem_we_w;
  logic        dec_csr_en_w;
  logic        dec_mret_w;
  logic        dec_ebreak_w;
  logic        dec_illegal_w;
  logic        dec_is_compressed_w;
  logic        dec_wb_en_w;

  logic [3:0]  rf_raddr1_w;
  logic [3:0]  rf_raddr2_w;
  logic [31:0] rf_rdata1_w;
  logic [31:0] rf_rdata2_w;
  logic        rf_we_w;
  logic [3:0]  rf_waddr_w;
  logic [31:0] rf_wdata_w;

  logic [31:0] alu_result_unused_w;
  logic        alu_branch_taken_unused_w;
  logic [31:0] alu_branch_target_unused_w;

  logic        mul_start_w;
  logic        mul_busy_w;
  logic        mul_done_w;
  logic [31:0] mul_result_w;

  logic        lsu_mem_req_w;
  logic        lsu_mem_we_w;
  logic [3:0]  lsu_mem_be_w;
  logic [31:0] lsu_mem_addr_w;
  logic [31:0] lsu_mem_wdata_w;
  logic [31:0] lsu_load_data_w;
  logic        lsu_done_w;
  logic        lsu_stall_w;
  logic        lsu_misaligned_w;

  logic        ex_branch_taken_w;
  logic [31:0] ex_branch_target_w;
  logic        ex_wb_en_w;
  logic [4:0]  ex_wb_rd_idx_w;
  logic [31:0] ex_wb_data_w;
  logic [31:0] ex_mem_addr_unused_w;
  logic [31:0] ex_mem_wdata_unused_w;
  logic        ex_mem_req_unused_w;
  logic        ex_mem_we_unused_w;
  logic        ex_trap_req_w;
  logic [3:0]  ex_trap_cause_w;
  logic        ex_mret_req_w;
  logic        ex_stall_w;

  logic [31:0] csr_rdata_w;
  logic        csr_trap_redirect_valid_w;
  logic [31:0] csr_trap_redirect_pc_w;
  logic        csr_mret_redirect_valid_w;
  logic [31:0] csr_mret_redirect_pc_w;

  logic        fetch_instr_req_unused_w;
  logic [31:0] fetch_instr_addr_unused_w;
  logic [31:0] fetch_pc_unused_w;
  logic        fetch_instr_valid_unused_w;
  logic [31:0] fetch_instr_unused_w;

  logic        boot_spi_req_unused_w;
  logic [31:0] boot_spi_addr_unused_w;
  logic        boot_iram_we_unused_w;
  logic [31:0] boot_iram_addr_unused_w;
  logic [31:0] boot_iram_wdata_unused_w;
  logic        boot_done_unused_w;
  logic [31:0] boot_pc_unused_w;
  logic        boot_fail_unused_w;

  logic        issue_fire_w;
  logic        trap_request_to_csr_w;
  logic [3:0]  trap_cause_to_csr_w;
  logic [31:0] trap_pc_to_csr_w;
  logic [31:0] x_step_w;
  logic        normal_complete_w;

  assign rf_raddr1_w = dec_rs1_idx_w[4] ? 4'd0 : dec_rs1_idx_w[3:0];
  assign rf_raddr2_w = dec_rs2_idx_w[4] ? 4'd0 : dec_rs2_idx_w[3:0];

  assign rf_we_w    = (top_state_q == TOP_STATE_RUN) &&
                      x_valid_q &&
                      ex_wb_en_w &&
                      !fail_stop_q &&
                      !ex_wb_rd_idx_w[4];
  assign rf_waddr_w = ex_wb_rd_idx_w[3:0];
  assign rf_wdata_w = ex_wb_data_w;

  assign issue_fire_w = (top_state_q == TOP_STATE_RUN) &&
                        !fail_stop_q &&
                        instr_buf_valid_q &&
                        !x_valid_q &&
                        !csr_trap_redirect_valid_w &&
                        !csr_mret_redirect_valid_w;

  assign mul_start_w = issue_fire_w && dec_mul_en_w && !dec_illegal_w;

  assign trap_request_to_csr_w = (x_valid_q && ex_trap_req_w) ||
                                 (x_valid_q && x_ebreak_q) ||
                                 (x_valid_q && lsu_misaligned_w);

  assign trap_cause_to_csr_w = ex_trap_req_w                         ? ex_trap_cause_w :
                               (x_valid_q && x_ebreak_q)            ? 4'd3 :
                               (x_valid_q && lsu_misaligned_w &&
                                x_mem_we_q)                         ? 4'd6 :
                               (x_valid_q && lsu_misaligned_w)      ? 4'd4 :
                                                                     4'd0;

  assign trap_pc_to_csr_w = x_valid_q ? x_pc_q : pc_q;
  assign x_step_w         = x_is_compressed_q ? 32'd2 : 32'd4;

  assign normal_complete_w = x_valid_q &&
                             !ex_stall_w &&
                             !csr_trap_redirect_valid_w &&
                             !csr_mret_redirect_valid_w &&
                             !ex_branch_taken_w &&
                             !trap_request_to_csr_w &&
                             !ex_mret_req_w;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      top_state_q       <= TOP_STATE_INIT;
      fail_stop_q       <= 1'b0;
      pc_q              <= RV32EC_ZMMUL_RESET_VECTOR;
      instr_buf_valid_q <= 1'b0;
      instr_buf_q       <= 32'd0;
      instr_buf_pc_q    <= 32'd0;
      x_valid_q         <= 1'b0;
      x_pc_q            <= 32'd0;
      x_instr_q         <= 32'd0;
      x_imm_q           <= 32'd0;
      x_rs1_data_q      <= 32'd0;
      x_rs2_data_q      <= 32'd0;
      x_rd_idx_q        <= 5'd0;
      x_alu_op_q        <= 4'd0;
      x_branch_op_q     <= 3'd0;
      x_mul_en_q        <= 1'b0;
      x_mem_req_q       <= 1'b0;
      x_mem_we_q        <= 1'b0;
      x_mem_size_q      <= 2'd0;
      x_mem_unsigned_q  <= 1'b0;
      x_csr_en_q        <= 1'b0;
      x_csr_funct3_q    <= 3'd0;
      x_csr_addr_q      <= 12'd0;
      x_mret_q          <= 1'b0;
      x_ebreak_q        <= 1'b0;
      x_illegal_q       <= 1'b0;
      x_is_compressed_q <= 1'b0;
      x_wb_en_q         <= 1'b0;
    end else begin
      case (top_state_q)
        TOP_STATE_INIT: begin
          fail_stop_q       <= 1'b0;
          instr_buf_valid_q <= 1'b0;
          x_valid_q         <= 1'b0;
          pc_q              <= RV32EC_ZMMUL_RESET_VECTOR;
          if (boot_mode_spi) begin
            top_state_q <= TOP_STATE_BOOT;
          end else begin
            top_state_q <= TOP_STATE_RUN;
          end
        end

        TOP_STATE_BOOT: begin
          instr_buf_valid_q <= 1'b0;
          x_valid_q         <= 1'b0;
          if (spi_ready) begin
            if (spi_rdata == 32'hFFFF_FFFF) begin
              top_state_q <= TOP_STATE_FAIL;
              fail_stop_q <= 1'b1;
            end else begin
              top_state_q <= TOP_STATE_RUN;
              pc_q        <= spi_rdata;
            end
          end
        end

        TOP_STATE_RUN: begin
          if (csr_trap_redirect_valid_w) begin
            pc_q              <= csr_trap_redirect_pc_w;
            instr_buf_valid_q <= 1'b0;
            x_valid_q         <= 1'b0;
          end else if (csr_mret_redirect_valid_w) begin
            pc_q              <= csr_mret_redirect_pc_w;
            instr_buf_valid_q <= 1'b0;
            x_valid_q         <= 1'b0;
          end else if (x_valid_q && ex_branch_taken_w && !ex_stall_w) begin
            pc_q      <= ex_branch_target_w;
            x_valid_q <= 1'b0;
          end else if (normal_complete_w) begin
            pc_q      <= x_pc_q + x_step_w;
            x_valid_q <= 1'b0;
          end else if (x_valid_q && !ex_stall_w) begin
            x_valid_q <= 1'b0;
          end

          if (issue_fire_w) begin
            instr_buf_valid_q <= 1'b0;
            x_valid_q         <= 1'b1;
            x_pc_q            <= instr_buf_pc_q;
            x_instr_q         <= instr_buf_q;
            x_imm_q           <= dec_imm_w;
            x_rs1_data_q      <= rf_rdata1_w;
            x_rs2_data_q      <= rf_rdata2_w;
            x_rd_idx_q        <= dec_rd_idx_w;
            x_alu_op_q        <= dec_alu_op_w;
            x_branch_op_q     <= dec_branch_op_w;
            x_mul_en_q        <= dec_mul_en_w;
            x_mem_req_q       <= dec_mem_req_w;
            x_mem_we_q        <= dec_mem_we_w;
            x_mem_size_q      <= instr_buf_q[13:12];
            x_mem_unsigned_q  <= (!dec_mem_we_w) && instr_buf_q[14];
            x_csr_en_q        <= dec_csr_en_w;
            x_csr_funct3_q    <= instr_buf_q[14:12];
            x_csr_addr_q      <= instr_buf_q[31:20];
            x_mret_q          <= dec_mret_w;
            x_ebreak_q        <= dec_ebreak_w;
            x_illegal_q       <= dec_illegal_w;
            x_is_compressed_q <= dec_is_compressed_w;
            x_wb_en_q         <= dec_wb_en_w;
          end else if (!instr_buf_valid_q && !x_valid_q && instr_ready &&
                       !csr_trap_redirect_valid_w && !csr_mret_redirect_valid_w) begin
            instr_buf_valid_q <= 1'b1;
            instr_buf_q       <= instr_rdata;
            instr_buf_pc_q    <= pc_q;
          end
        end

        TOP_STATE_FAIL: begin
          fail_stop_q       <= 1'b1;
          instr_buf_valid_q <= 1'b0;
          x_valid_q         <= 1'b0;
        end

        default: begin
          top_state_q       <= TOP_STATE_FAIL;
          fail_stop_q       <= 1'b1;
          instr_buf_valid_q <= 1'b0;
          x_valid_q         <= 1'b0;
        end
      endcase
    end
  end

  decode_control_unit u_decode_control_unit (
    .instr_i         (instr_buf_q),
    .pc_i            (instr_buf_pc_q),
    .rs1_idx_o       (dec_rs1_idx_w),
    .rs2_idx_o       (dec_rs2_idx_w),
    .rd_idx_o        (dec_rd_idx_w),
    .imm_o           (dec_imm_w),
    .alu_op_o        (dec_alu_op_w),
    .branch_op_o     (dec_branch_op_w),
    .mul_en_o        (dec_mul_en_w),
    .mem_req_o       (dec_mem_req_w),
    .mem_we_o        (dec_mem_we_w),
    .csr_en_o        (dec_csr_en_w),
    .mret_o          (dec_mret_w),
    .ebreak_o        (dec_ebreak_w),
    .illegal_o       (dec_illegal_w),
    .is_compressed_o (dec_is_compressed_w),
    .wb_en_o         (dec_wb_en_w)
  );

  regfile_16x32 u_regfile_16x32 (
    .clk      (clk),
    .rst_n    (rst_n),
    .raddr1_i (rf_raddr1_w),
    .raddr2_i (rf_raddr2_w),
    .we_i     (rf_we_w),
    .waddr_i  (rf_waddr_w),
    .wdata_i  (rf_wdata_w),
    .rdata1_o (rf_rdata1_w),
    .rdata2_o (rf_rdata2_w)
  );

  alu32_branch_unit u_alu32_branch_unit (
    .op_a_i          (x_rs1_data_q),
    .op_b_i          (x_rs2_data_q),
    .pc_i            (x_pc_q),
    .imm_i           (x_imm_q),
    .alu_op_i        (x_alu_op_q),
    .branch_op_i     (x_branch_op_q),
    .result_o        (alu_result_unused_w),
    .branch_taken_o  (alu_branch_taken_unused_w),
    .branch_target_o (alu_branch_target_unused_w)
  );

  multiplier_unit u_multiplier_unit (
    .clk      (clk),
    .rst_n    (rst_n),
    .start_i  (mul_start_w),
    .op_a_i   (rf_rdata1_w),
    .op_b_i   (rf_rdata2_w),
    .busy_o   (mul_busy_w),
    .done_o   (mul_done_w),
    .result_o (mul_result_w)
  );

  load_store_unit u_load_store_unit (
    .clk                  (clk),
    .rst_n                (rst_n),
    .req_i                (x_valid_q && x_mem_req_q),
    .we_i                 (x_mem_we_q),
    .size_i               (x_mem_size_q),
    .unsigned_i           (x_mem_unsigned_q),
    .base_addr_i          (x_rs1_data_q),
    .offset_i             (x_imm_q),
    .store_data_i         (x_rs2_data_q),
    .mem_ready_i          (data_ready),
    .mem_rdata_i          (data_rdata),
    .trap_on_misaligned_i (1'b1),
    .mem_req_o            (lsu_mem_req_w),
    .mem_we_o             (lsu_mem_we_w),
    .mem_be_o             (lsu_mem_be_w),
    .mem_addr_o           (lsu_mem_addr_w),
    .mem_wdata_o          (lsu_mem_wdata_w),
    .load_data_o          (lsu_load_data_w),
    .done_o               (lsu_done_w),
    .stall_o              (lsu_stall_w),
    .misaligned_o         (lsu_misaligned_w)
  );

  execute_writeback_unit u_execute_writeback_unit (
    .clk             (clk),
    .rst_n           (rst_n),
    .pc_i            (x_pc_q),
    .rs1_data_i      (x_rs1_data_q),
    .rs2_data_i      (x_rs2_data_q),
    .imm_i           (x_imm_q),
    .rd_idx_i        (x_rd_idx_q),
    .alu_op_i        (x_alu_op_q),
    .branch_op_i     (x_branch_op_q),
    .mul_en_i        (x_valid_q && x_mul_en_q),
    .mem_req_i       (x_valid_q && x_mem_req_q),
    .mem_we_i        (x_mem_we_q),
    .csr_en_i        (x_valid_q && x_csr_en_q),
    .mret_i          (x_valid_q && x_mret_q),
    .illegal_i       (x_valid_q && x_illegal_q),
    .load_data_i     (lsu_load_data_w),
    .load_ready_i    (lsu_done_w),
    .mul_result_i    (mul_result_w),
    .mul_done_i      (mul_done_w),
    .csr_rdata_i     (csr_rdata_w),
    .branch_taken_o  (ex_branch_taken_w),
    .branch_target_o (ex_branch_target_w),
    .wb_en_o         (ex_wb_en_w),
    .wb_rd_idx_o     (ex_wb_rd_idx_w),
    .wb_data_o       (ex_wb_data_w),
    .mem_addr_o      (ex_mem_addr_unused_w),
    .mem_wdata_o     (ex_mem_wdata_unused_w),
    .mem_req_o       (ex_mem_req_unused_w),
    .mem_we_o        (ex_mem_we_unused_w),
    .trap_req_o      (ex_trap_req_w),
    .trap_cause_o    (ex_trap_cause_w),
    .mret_req_o      (ex_mret_req_w),
    .stall_o         (ex_stall_w)
  );

  csr_trap_controller u_csr_trap_controller (
    .clk                   (clk),
    .rst_n                 (rst_n),
    .csr_en_i              (x_valid_q && x_csr_en_q),
    .csr_we_i              (x_valid_q && x_csr_en_q && (x_csr_funct3_q != 3'b010)),
    .csr_addr_i            (x_csr_addr_q),
    .csr_wdata_i           (x_rs1_data_q),
    .trap_req_i            (trap_request_to_csr_w),
    .trap_cause_i          (trap_cause_to_csr_w),
    .trap_pc_i             (trap_pc_to_csr_w),
    .ext_irq_i             ((top_state_q == TOP_STATE_RUN) && !fail_stop_q && ext_irq),
    .mret_i                (x_valid_q && ex_mret_req_w),
    .csr_rdata_o           (csr_rdata_w),
    .trap_redirect_valid_o (csr_trap_redirect_valid_w),
    .trap_redirect_pc_o    (csr_trap_redirect_pc_w),
    .mret_redirect_valid_o (csr_mret_redirect_valid_w),
    .mret_redirect_pc_o    (csr_mret_redirect_pc_w)
  );

  fetch_unit u_fetch_unit (
    .reset_vector_i          (RV32EC_ZMMUL_RESET_VECTOR),
    .clk                     (clk),
    .rst_n                   (rst_n),
    .stall_i                 (1'b1),
    .flush_i                 (1'b0),
    .trap_redirect_valid_i   (1'b0),
    .trap_redirect_pc_i      (32'd0),
    .mret_redirect_valid_i   (1'b0),
    .mret_redirect_pc_i      (32'd0),
    .branch_redirect_valid_i (1'b0),
    .branch_redirect_pc_i    (32'd0),
    .instr_ready_i           (instr_ready),
    .instr_rdata_i           (instr_rdata),
    .is_compressed_i         (instr_rdata[1:0] != 2'b11),
    .instr_req_o             (fetch_instr_req_unused_w),
    .instr_addr_o            (fetch_instr_addr_unused_w),
    .pc_o                    (fetch_pc_unused_w),
    .instr_valid_o           (fetch_instr_valid_unused_w),
    .instr_o                 (fetch_instr_unused_w)
  );

  boot_rom_loader u_boot_rom_loader (
    .clk                 (clk),
    .rst_n               (rst_n),
    .start_i             (1'b0),
    .spi_ready_i         (spi_ready),
    .spi_rdata_i         (spi_rdata),
    .iram_ready_i        (1'b1),
    .validation_enable_i (1'b1),
    .spi_req_o           (boot_spi_req_unused_w),
    .spi_addr_o          (boot_spi_addr_unused_w),
    .iram_we_o           (boot_iram_we_unused_w),
    .iram_addr_o         (boot_iram_addr_unused_w),
    .iram_wdata_o        (boot_iram_wdata_unused_w),
    .done_o              (boot_done_unused_w),
    .boot_pc_o           (boot_pc_unused_w),
    .fail_stop_o         (boot_fail_unused_w)
  );

  always_comb begin
    instr_req   = 1'b0;
    instr_addr  = 32'd0;
    data_req    = 1'b0;
    data_we     = 1'b0;
    data_be     = 4'd0;
    data_addr   = 32'd0;
    data_wdata  = 32'd0;
    spi_req     = 1'b0;
    spi_addr    = 32'd0;
    fail_stop   = fail_stop_q;

    case (top_state_q)
      TOP_STATE_BOOT: begin
        spi_req    = !fail_stop_q;
        spi_addr   = RV32EC_ZMMUL_SPI_BOOT_BASE_ADDR;
        fail_stop  = fail_stop_q;
      end

      TOP_STATE_RUN: begin
        instr_req   = !fail_stop_q;
        instr_addr  = pc_q;
        data_req    = !fail_stop_q ? lsu_mem_req_w   : 1'b0;
        data_we     = !fail_stop_q ? lsu_mem_we_w    : 1'b0;
        data_be     = !fail_stop_q ? lsu_mem_be_w    : 4'd0;
        data_addr   = !fail_stop_q ? lsu_mem_addr_w  : 32'd0;
        data_wdata  = !fail_stop_q ? lsu_mem_wdata_w : 32'd0;
        fail_stop   = fail_stop_q;
      end

      TOP_STATE_FAIL: begin
        fail_stop = 1'b1;
      end

      default: begin
        fail_stop = fail_stop_q;
      end
    endcase
  end

endmodule
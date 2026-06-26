`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module boot_rom_loader (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start_i,
  input  logic        spi_ready_i,
  input  logic [31:0] spi_rdata_i,
  input  logic        iram_ready_i,
  input  logic        validation_enable_i,
  output logic        spi_req_o,
  output logic [31:0] spi_addr_o,
  output logic        iram_we_o,
  output logic [31:0] iram_addr_o,
  output logic [31:0] iram_wdata_o,
  output logic        done_o,
  output logic [31:0] boot_pc_o,
  output logic        fail_stop_o
);

  typedef enum logic [2:0] {
    ST_IDLE         = 3'd0,
    ST_FETCH_MAGIC  = 3'd1,
    ST_FETCH_SIZE   = 3'd2,
    ST_FETCH_BOOTPC = 3'd3,
    ST_FETCH_DATA   = 3'd4,
    ST_WRITE_DATA   = 3'd5,
    ST_DONE         = 3'd6,
    ST_FAIL         = 3'd7
  } boot_state_t;

  localparam logic [RV32EC_ZMMUL_BOOT_TIMEOUT_W-1:0] BOOT_TIMEOUT_LIMIT = 16'd511;

  boot_state_t state_q, state_d;

  logic [31:0] spi_addr_q, spi_addr_d;
  logic [31:0] iram_addr_q, iram_addr_d;
  logic [31:0] boot_pc_q, boot_pc_d;
  logic [31:0] program_size_q, program_size_d;
  logic [31:0] words_remaining_q, words_remaining_d;
  logic [31:0] data_latched_q, data_latched_d;
  logic [31:0] data_words_seen_q, data_words_seen_d;
  logic [RV32EC_ZMMUL_BOOT_TIMEOUT_W-1:0] timeout_cnt_q, timeout_cnt_d;

  logic timeout_expired;

  function automatic logic is_valid_boot_pc(input logic [31:0] pc);
    logic [31:0] iram_limit;
    begin
      iram_limit = RV32EC_ZMMUL_IRAM_BASE_ADDR + RV32EC_ZMMUL_IRAM_BYTES;
      is_valid_boot_pc = (pc[1:0] == 2'b00) &&
                         (pc >= RV32EC_ZMMUL_IRAM_BASE_ADDR) &&
                         (pc < iram_limit);
    end
  endfunction

  assign timeout_expired = (timeout_cnt_q >= BOOT_TIMEOUT_LIMIT);

  always_comb begin
    state_d           = state_q;
    spi_addr_d        = spi_addr_q;
    iram_addr_d       = iram_addr_q;
    boot_pc_d         = boot_pc_q;
    program_size_d    = program_size_q;
    words_remaining_d = words_remaining_q;
    data_latched_d    = data_latched_q;
    data_words_seen_d = data_words_seen_q;
    timeout_cnt_d     = timeout_cnt_q;

    case (state_q)
      ST_IDLE: begin
        timeout_cnt_d = '0;
        if (start_i) begin
          state_d           = ST_FETCH_MAGIC;
          spi_addr_d        = RV32EC_ZMMUL_SPI_BOOT_BASE_ADDR;
          iram_addr_d       = RV32EC_ZMMUL_IRAM_BASE_ADDR;
          boot_pc_d         = 32'h0000_0000;
          program_size_d    = 32'h0000_0000;
          words_remaining_d = 32'h0000_0000;
          data_latched_d    = 32'h0000_0000;
          data_words_seen_d = 32'h0000_0000;
        end
      end

      ST_FETCH_MAGIC: begin
        if (spi_ready_i) begin
          timeout_cnt_d = '0;
          if (validation_enable_i) begin
            if (spi_rdata_i == RV32EC_ZMMUL_BOOT_MAGIC) begin
              state_d    = ST_FETCH_SIZE;
              spi_addr_d = spi_addr_q + 32'd4;
            end
            else begin
              state_d = ST_FAIL;
            end
          end
          else begin
            if (is_valid_boot_pc(spi_rdata_i)) begin
              boot_pc_d = spi_rdata_i;
              state_d   = ST_DONE;
            end
            else begin
              data_latched_d = spi_rdata_i;
              state_d        = ST_WRITE_DATA;
            end
          end
        end
        else begin
          if (timeout_expired) begin
            state_d = ST_FAIL;
          end
          else begin
            timeout_cnt_d = timeout_cnt_q + {{(RV32EC_ZMMUL_BOOT_TIMEOUT_W-1){1'b0}}, 1'b1};
          end
        end
      end

      ST_FETCH_SIZE: begin
        if (spi_ready_i) begin
          timeout_cnt_d  = '0;
          program_size_d = spi_rdata_i;
          if ((spi_rdata_i == 32'h0000_0000) ||
              (spi_rdata_i[1:0] != 2'b00) ||
              (spi_rdata_i > RV32EC_ZMMUL_BOOT_ROM_BYTES_MAX) ||
              (spi_rdata_i > RV32EC_ZMMUL_IRAM_BYTES)) begin
            state_d = ST_FAIL;
          end
          else begin
            words_remaining_d = spi_rdata_i >> 2;
            spi_addr_d        = spi_addr_q + 32'd4;
            state_d           = ST_FETCH_BOOTPC;
          end
        end
        else begin
          if (timeout_expired) begin
            state_d = ST_FAIL;
          end
          else begin
            timeout_cnt_d = timeout_cnt_q + {{(RV32EC_ZMMUL_BOOT_TIMEOUT_W-1){1'b0}}, 1'b1};
          end
        end
      end

      ST_FETCH_BOOTPC: begin
        if (spi_ready_i) begin
          timeout_cnt_d = '0;
          boot_pc_d     = spi_rdata_i;
          if (!is_valid_boot_pc(spi_rdata_i)) begin
            state_d = ST_FAIL;
          end
          else begin
            spi_addr_d = spi_addr_q + 32'd4;
            if (words_remaining_q == 32'h0000_0000) begin
              state_d = ST_DONE;
            end
            else begin
              state_d = ST_FETCH_DATA;
            end
          end
        end
        else begin
          if (timeout_expired) begin
            state_d = ST_FAIL;
          end
          else begin
            timeout_cnt_d = timeout_cnt_q + {{(RV32EC_ZMMUL_BOOT_TIMEOUT_W-1){1'b0}}, 1'b1};
          end
        end
      end

      ST_FETCH_DATA: begin
        if (spi_ready_i) begin
          timeout_cnt_d = '0;
          if (validation_enable_i) begin
            if (words_remaining_q == 32'h0000_0000) begin
              state_d = ST_DONE;
            end
            else begin
              data_latched_d = spi_rdata_i;
              state_d        = ST_WRITE_DATA;
            end
          end
          else begin
            if ((data_words_seen_q != 32'h0000_0000) && is_valid_boot_pc(spi_rdata_i)) begin
              boot_pc_d = spi_rdata_i;
              state_d   = ST_DONE;
            end
            else begin
              data_latched_d = spi_rdata_i;
              state_d        = ST_WRITE_DATA;
            end
          end
        end
        else begin
          if (timeout_expired) begin
            state_d = ST_FAIL;
          end
          else begin
            timeout_cnt_d = timeout_cnt_q + {{(RV32EC_ZMMUL_BOOT_TIMEOUT_W-1){1'b0}}, 1'b1};
          end
        end
      end

      ST_WRITE_DATA: begin
        if (iram_ready_i) begin
          timeout_cnt_d     = '0;
          data_words_seen_d = data_words_seen_q + 32'd1;
          if (validation_enable_i) begin
            if (words_remaining_q == 32'd1) begin
              words_remaining_d = 32'h0000_0000;
              state_d           = ST_DONE;
            end
            else begin
              words_remaining_d = words_remaining_q - 32'd1;
              spi_addr_d        = spi_addr_q + 32'd4;
              iram_addr_d       = iram_addr_q + 32'd4;
              state_d           = ST_FETCH_DATA;
            end
          end
          else begin
            spi_addr_d  = spi_addr_q + 32'd4;
            iram_addr_d = iram_addr_q + 32'd4;
            state_d     = ST_FETCH_DATA;
          end
        end
      end

      ST_DONE: begin
        timeout_cnt_d = '0;
      end

      ST_FAIL: begin
        timeout_cnt_d = '0;
      end

      default: begin
        state_d = ST_IDLE;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q           <= ST_IDLE;
      spi_addr_q        <= 32'h0000_0000;
      iram_addr_q       <= 32'h0000_0000;
      boot_pc_q         <= 32'h0000_0000;
      program_size_q    <= 32'h0000_0000;
      words_remaining_q <= 32'h0000_0000;
      data_latched_q    <= 32'h0000_0000;
      data_words_seen_q <= 32'h0000_0000;
      timeout_cnt_q     <= '0;
    end
    else begin
      state_q           <= state_d;
      spi_addr_q        <= spi_addr_d;
      iram_addr_q       <= iram_addr_d;
      boot_pc_q         <= boot_pc_d;
      program_size_q    <= program_size_d;
      words_remaining_q <= words_remaining_d;
      data_latched_q    <= data_latched_d;
      data_words_seen_q <= data_words_seen_d;
      timeout_cnt_q     <= timeout_cnt_d;
    end
  end

  always_comb begin
    spi_req_o    = 1'b0;
    spi_addr_o   = spi_addr_q;
    iram_we_o    = 1'b0;
    iram_addr_o  = iram_addr_q;
    iram_wdata_o = data_latched_q;
    done_o       = 1'b0;
    boot_pc_o    = boot_pc_q;
    fail_stop_o  = 1'b0;

    case (state_q)
      ST_FETCH_MAGIC,
      ST_FETCH_SIZE,
      ST_FETCH_BOOTPC,
      ST_FETCH_DATA: begin
        spi_req_o  = 1'b1;
        spi_addr_o = spi_addr_q;
      end

      ST_WRITE_DATA: begin
        iram_we_o    = 1'b1;
        iram_addr_o  = iram_addr_q;
        iram_wdata_o = data_latched_q;
      end

      ST_DONE: begin
        done_o    = 1'b1;
        boot_pc_o = boot_pc_q;
      end

      ST_FAIL: begin
        fail_stop_o = 1'b1;
      end

      default: begin
      end
    endcase
  end

endmodule
`timescale 1ns/1ps

import rv32ec_zmmul_core_pkg::*;

module load_store_unit (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [1:0]  size_i,
  input  logic        unsigned_i,
  input  logic [31:0] base_addr_i,
  input  logic [31:0] offset_i,
  input  logic [31:0] store_data_i,
  input  logic        mem_ready_i,
  input  logic [31:0] mem_rdata_i,
  input  logic        trap_on_misaligned_i,
  output logic        mem_req_o,
  output logic        mem_we_o,
  output logic [3:0]  mem_be_o,
  output logic [31:0] mem_addr_o,
  output logic [31:0] mem_wdata_o,
  output logic [31:0] load_data_o,
  output logic        done_o,
  output logic        stall_o,
  output logic        misaligned_o
);

  logic        outstanding_q;
  logic        we_q;
  logic [1:0]  size_q;
  logic        unsigned_q;
  logic [31:0] addr_q;
  logic [31:0] store_data_q;

  logic [31:0] load_data_q;
  logic        done_q;
  logic        misaligned_q;

  logic [31:0] eff_addr;
  logic        misaligned_req;
  logic        trap_misaligned_req;

  function automatic logic [3:0] calc_be (
    input logic [1:0] size,
    input logic [1:0] addr_lsb
  );
    logic [4:0] be_ext;
    begin
      be_ext = 5'b0_0000;
      unique case (size)
        2'b00: be_ext = {1'b0, (4'b0001 << addr_lsb)};
        2'b01: be_ext = {1'b0, (4'b0011 << addr_lsb)};
        default: be_ext = 5'b0_1111;
      endcase
      calc_be = be_ext[3:0];
    end
  endfunction

  function automatic logic [31:0] calc_wdata (
    input logic [1:0] size,
    input logic [1:0] addr_lsb,
    input logic [31:0] store_data
  );
    logic [4:0] shift_amt;
    begin
      shift_amt = {3'b000, addr_lsb} << 3;
      unique case (size)
        2'b00: calc_wdata = ({24'h000000, store_data[7:0]}  << shift_amt);
        2'b01: calc_wdata = ({16'h0000,   store_data[15:0]} << shift_amt);
        default: calc_wdata = store_data;
      endcase
    end
  endfunction

  function automatic logic [31:0] calc_load_data (
    input logic [1:0] size,
    input logic       unsigned_sel,
    input logic [1:0] addr_lsb,
    input logic [31:0] mem_rdata
  );
    logic [4:0]  shift_amt;
    logic [31:0] shifted_data;
    logic [7:0]  byte_data;
    logic [15:0] half_data;
    begin
      shift_amt    = {3'b000, addr_lsb} << 3;
      shifted_data = mem_rdata >> shift_amt;
      byte_data    = shifted_data[7:0];
      half_data    = shifted_data[15:0];

      unique case (size)
        2'b00: begin
          if (unsigned_sel) begin
            calc_load_data = {24'h000000, byte_data};
          end else begin
            calc_load_data = {{24{byte_data[7]}}, byte_data};
          end
        end
        2'b01: begin
          if (unsigned_sel) begin
            calc_load_data = {16'h0000, half_data};
          end else begin
            calc_load_data = {{16{half_data[15]}}, half_data};
          end
        end
        default: calc_load_data = mem_rdata;
      endcase
    end
  endfunction

  always_comb begin
    eff_addr = base_addr_i + offset_i;

    unique case (size_i)
      2'b00: misaligned_req = 1'b0;
      2'b01: misaligned_req = eff_addr[0];
      default: misaligned_req = |eff_addr[1:0];
    endcase

    trap_misaligned_req = req_i && misaligned_req && trap_on_misaligned_i;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      outstanding_q <= 1'b0;
      we_q          <= 1'b0;
      size_q        <= 2'b00;
      unsigned_q    <= 1'b0;
      addr_q        <= 32'h0000_0000;
      store_data_q  <= 32'h0000_0000;
      load_data_q   <= 32'h0000_0000;
      done_q        <= 1'b0;
      misaligned_q  <= 1'b0;
    end else begin
      done_q       <= 1'b0;
      misaligned_q <= 1'b0;

      if (outstanding_q) begin
        if (mem_ready_i) begin
          outstanding_q <= 1'b0;
          done_q        <= 1'b1;

          if (!we_q) begin
            load_data_q <= calc_load_data(size_q, unsigned_q, addr_q[1:0], mem_rdata_i);
          end
        end
      end else if (req_i) begin
        if (trap_misaligned_req) begin
          done_q       <= 1'b1;
          misaligned_q <= 1'b1;
        end else if (mem_ready_i) begin
          done_q <= 1'b1;

          if (!we_i) begin
            load_data_q <= calc_load_data(size_i, unsigned_i, eff_addr[1:0], mem_rdata_i);
          end
        end else begin
          outstanding_q <= 1'b1;
          we_q          <= we_i;
          size_q        <= size_i;
          unsigned_q    <= unsigned_i;
          addr_q        <= eff_addr;
          store_data_q  <= store_data_i;
        end
      end
    end
  end

  always_comb begin
    mem_req_o    = 1'b0;
    mem_we_o     = 1'b0;
    mem_be_o     = 4'b0000;
    mem_addr_o   = 32'h0000_0000;
    mem_wdata_o  = 32'h0000_0000;
    stall_o      = 1'b0;

    if (outstanding_q) begin
      mem_req_o   = 1'b1;
      mem_we_o    = we_q;
      mem_be_o    = calc_be(size_q, addr_q[1:0]);
      mem_addr_o  = addr_q;
      mem_wdata_o = calc_wdata(size_q, addr_q[1:0], store_data_q);
      stall_o     = !mem_ready_i;
    end
  end

  assign load_data_o  = load_data_q;
  assign done_o       = done_q;
  assign misaligned_o = misaligned_q;

endmodule
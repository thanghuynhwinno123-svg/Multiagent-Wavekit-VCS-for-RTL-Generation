`timescale 1ns/1ps

module multiplier_unit (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start_i,
  input  logic [31:0] op_a_i,
  input  logic [31:0] op_b_i,
  output logic        busy_o,
  output logic        done_o,
  output logic [31:0] result_o
);

  import rv32ec_zmmul_core_pkg::*;

  logic [63:0] accum_q;
  logic [63:0] mcand_q;
  logic [31:0] mult_q;
  logic [5:0]  count_q;

  logic [63:0] accum_next;
  logic [63:0] mcand_next;
  logic [31:0] mult_next;

  always_comb begin
    accum_next = accum_q;
    if (mult_q[0]) begin
      accum_next = accum_q + mcand_q;
    end

    mcand_next = mcand_q << 1;
    mult_next  = mult_q >> 1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy_o   <= 1'b0;
      done_o   <= 1'b0;
      result_o <= 32'h0000_0000;
      accum_q  <= 64'h0000_0000_0000_0000;
      mcand_q  <= 64'h0000_0000_0000_0000;
      mult_q   <= 32'h0000_0000;
      count_q  <= 6'd0;
    end else begin
      done_o <= 1'b0;

      if (!busy_o) begin
        if (start_i) begin
          busy_o  <= 1'b1;
          accum_q <= 64'h0000_0000_0000_0000;
          mcand_q <= {32'h0000_0000, op_a_i};
          mult_q  <= op_b_i;
          count_q <= 6'd0;
        end
      end else begin
        if (count_q == 6'd31) begin
          busy_o   <= 1'b0;
          done_o   <= 1'b1;
          result_o <= accum_next[31:0];
          accum_q  <= accum_next;
          mcand_q  <= mcand_next;
          mult_q   <= mult_next;
          count_q  <= 6'd0;
        end else begin
          accum_q <= accum_next;
          mcand_q <= mcand_next;
          mult_q  <= mult_next;
          count_q <= count_q + 6'd1;
        end
      end
    end
  end

endmodule
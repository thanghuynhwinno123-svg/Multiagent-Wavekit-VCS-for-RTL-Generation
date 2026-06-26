`timescale 1ns/1ps

module top_sim_multiplier_unit;

  import rv32ec_zmmul_core_pkg::*;

  logic        clk;
  logic        rst_n;
  logic        start_i;
  logic [31:0] op_a_i;
  logic [31:0] op_b_i;
  logic        busy_o;
  logic        done_o;
  logic [31:0] result_o;

  multiplier_unit u_dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .start_i  (start_i),
    .op_a_i   (op_a_i),
    .op_b_i   (op_b_i),
    .busy_o   (busy_o),
    .done_o   (done_o),
    .result_o (result_o)
  );

  tb_multiplier_unit u_tb (
    .clk      (clk),
    .rst_n    (rst_n),
    .start_i  (start_i),
    .op_a_i   (op_a_i),
    .op_b_i   (op_b_i),
    .busy_o   (busy_o),
    .done_o   (done_o),
    .result_o (result_o)
  );

  initial begin
    $dumpfile("sim.vcd");
    $dumpvars(0, top_sim_multiplier_unit);
  end

endmodule
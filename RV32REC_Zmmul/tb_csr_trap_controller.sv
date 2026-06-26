`timescale 1ns/1ps
module tb_csr_trap_controller (
    output logic        clk,
    output logic        rst_n,
    output logic        csr_en_i,
    output logic        csr_we_i,
    output logic [11:0] csr_addr_i,
    output logic [31:0] csr_wdata_i,
    output logic        trap_req_i,
    output logic [3:0]  trap_cause_i,
    output logic [31:0] trap_pc_i,
    output logic        ext_irq_i,
    output logic        mret_i,
    input  logic [31:0] csr_rdata_o,
    input  logic        trap_redirect_valid_o,
    input  logic [31:0] trap_redirect_pc_o,
    input  logic        mret_redirect_valid_o,
    input  logic [31:0] mret_redirect_pc_o
);

    localparam logic [11:0] CSR_MSTATUS = 12'h300;
    localparam logic [11:0] CSR_MTVEC   = 12'h305;
    localparam logic [11:0] CSR_MEPC    = 12'h341;
    localparam logic [11:0] CSR_MCAUSE  = 12'h342;
    localparam logic [31:0] IRQ_MCAUSE  = 32'h8000_000b;

    integer cycle_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    logic [31:0] golden_mstatus;
    logic [31:0] golden_mtvec;
    logic [31:0] golden_mepc;
    logic [31:0] golden_mcause;

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

    task automatic init_defaults;
    begin
        rst_n        = 1'b1;
        csr_en_i     = 1'b0;
        csr_we_i     = 1'b0;
        csr_addr_i   = 12'h000;
        csr_wdata_i  = 32'h0000_0000;
        trap_req_i   = 1'b0;
        trap_cause_i = 4'h0;
        trap_pc_i    = 32'h0000_0000;
        ext_irq_i    = 1'b0;
        mret_i       = 1'b0;
    end
    endtask

    task automatic golden_reset;
    begin
        golden_mstatus = 32'h0000_0000;
        golden_mtvec   = 32'h0000_0000;
        golden_mepc    = 32'h0000_0000;
        golden_mcause  = 32'h0000_0000;
    end
    endtask

    task automatic golden_read(
        input  logic [11:0] addr,
        output logic [31:0] data
    );
    begin
        case (addr)
            CSR_MSTATUS: data = golden_mstatus;
            CSR_MTVEC:   data = golden_mtvec;
            CSR_MEPC:    data = golden_mepc;
            CSR_MCAUSE:  data = golden_mcause;
            default:     data = 32'h0000_0000;
        endcase
    end
    endtask

    task automatic golden_step(
        input  logic        rst_n_in,
        input  logic        csr_en_in,
        input  logic        csr_we_in,
        input  logic [11:0] csr_addr_in,
        input  logic [31:0] csr_wdata_in,
        input  logic        trap_req_in,
        input  logic [3:0]  trap_cause_in,
        input  logic [31:0] trap_pc_in,
        input  logic        ext_irq_in,
        input  logic        mret_in,
        output logic        exp_trap_valid,
        output logic [31:0] exp_trap_pc,
        output logic        exp_mret_valid,
        output logic [31:0] exp_mret_pc
    );
        logic [31:0] next_mstatus;
        logic [31:0] next_mtvec;
        logic [31:0] next_mepc;
        logic [31:0] next_mcause;
    begin
        if (!rst_n_in) begin
            golden_reset();
            exp_trap_valid = 1'b0;
            exp_trap_pc    = 32'h0000_0000;
            exp_mret_valid = 1'b0;
            exp_mret_pc    = 32'h0000_0000;
        end else begin
            exp_trap_valid = trap_req_in | ext_irq_in;
            exp_trap_pc    = golden_mtvec;
            exp_mret_valid = mret_in;
            exp_mret_pc    = golden_mepc;

            next_mstatus = golden_mstatus;
            next_mtvec   = golden_mtvec;
            next_mepc    = golden_mepc;
            next_mcause  = golden_mcause;

            if (csr_en_in && csr_we_in) begin
                case (csr_addr_in)
                    CSR_MSTATUS: next_mstatus = csr_wdata_in;
                    CSR_MTVEC:   next_mtvec   = {csr_wdata_in[31:2], 2'b00};
                    CSR_MEPC:    next_mepc    = {csr_wdata_in[31:1], 1'b0};
                    CSR_MCAUSE:  next_mcause  = csr_wdata_in;
                    default: begin end
                endcase
            end

            if (trap_req_in) begin
                next_mepc    = trap_pc_in;
                next_mcause  = {28'd0, trap_cause_in};
                next_mstatus = {next_mstatus[31:4], 1'b0, next_mstatus[2:0]};
            end else if (ext_irq_in) begin
                next_mepc    = trap_pc_in;
                next_mcause  = IRQ_MCAUSE;
                next_mstatus = {next_mstatus[31:4], 1'b0, next_mstatus[2:0]};
            end else if (mret_in) begin
                next_mstatus = {next_mstatus[31:4], 1'b1, next_mstatus[2:0]};
            end

            golden_mstatus = next_mstatus;
            golden_mtvec   = next_mtvec;
            golden_mepc    = next_mepc;
            golden_mcause  = next_mcause;
        end
    end
    endtask

    task automatic report_fail(
        input string tc_name,
        input string signal_name,
        input logic [31:0] got_val,
        input logic [31:0] exp_val,
        inout integer case_fail_count
    );
    begin
        fail_count = fail_count + 1;
        case_fail_count = case_fail_count + 1;
        $display("[TESTCASE_RESULT] FAIL: %0s.%0s | got=%h expected=%h | cycle=%0d time=%0t",
                 tc_name, signal_name, got_val, exp_val, cycle_count, $time);
    end
    endtask

    task automatic finish_case(
        input string tc_name,
        input integer case_fail_count
    );
    begin
        if (case_fail_count == 0) begin
            pass_count = pass_count + 1;
            $display("[TESTCASE_RESULT] PASS: %0s", tc_name);
        end
    end
    endtask

    task automatic check_eq32(
        input string tc_name,
        input string signal_name,
        input logic [31:0] got_val,
        input logic [31:0] exp_val,
        inout integer case_fail_count
    );
    begin
        if (got_val !== exp_val) begin
            report_fail(tc_name, signal_name, got_val, exp_val, case_fail_count);
        end
    end
    endtask

    task automatic check_eq1(
        input string tc_name,
        input string signal_name,
        input logic got_val,
        input logic exp_val,
        inout integer case_fail_count
    );
        logic [31:0] got_ext;
        logic [31:0] exp_ext;
    begin
        got_ext = {31'd0, got_val};
        exp_ext = {31'd0, exp_val};
        if (got_val !== exp_val) begin
            report_fail(tc_name, signal_name, got_ext, exp_ext, case_fail_count);
        end
    end
    endtask

    task automatic drive_idle_cycle;
    begin
        csr_en_i     = 1'b0;
        csr_we_i     = 1'b0;
        csr_addr_i   = 12'h000;
        csr_wdata_i  = 32'h0000_0000;
        trap_req_i   = 1'b0;
        trap_cause_i = 4'h0;
        trap_pc_i    = 32'h0000_0000;
        ext_irq_i    = 1'b0;
        mret_i       = 1'b0;
    end
    endtask

    task automatic apply_reset;
        logic exp_trap_valid;
        logic [31:0] exp_trap_pc;
        logic exp_mret_valid;
        logic [31:0] exp_mret_pc;
    begin
        rst_n = 1'b0;
        drive_idle_cycle();
        golden_reset();
        #1;
        @(posedge clk);
        #1;
        golden_step(rst_n, csr_en_i, csr_we_i, csr_addr_i, csr_wdata_i,
                    trap_req_i, trap_cause_i, trap_pc_i, ext_irq_i, mret_i,
                    exp_trap_valid, exp_trap_pc, exp_mret_valid, exp_mret_pc);
        rst_n = 1'b1;
        drive_idle_cycle();
        @(posedge clk);
        #1;
    end
    endtask

    task automatic do_csr_write(
        input logic [11:0] addr,
        input logic [31:0] data
    );
        logic exp_trap_valid;
        logic [31:0] exp_trap_pc;
        logic exp_mret_valid;
        logic [31:0] exp_mret_pc;
    begin
        csr_en_i     = 1'b1;
        csr_we_i     = 1'b1;
        csr_addr_i   = addr;
        csr_wdata_i  = data;
        trap_req_i   = 1'b0;
        ext_irq_i    = 1'b0;
        mret_i       = 1'b0;
        trap_cause_i = 4'h0;
        trap_pc_i    = 32'h0000_0000;
        @(posedge clk);
        #1;
        golden_step(rst_n, csr_en_i, csr_we_i, csr_addr_i, csr_wdata_i,
                    trap_req_i, trap_cause_i, trap_pc_i, ext_irq_i, mret_i,
                    exp_trap_valid, exp_trap_pc, exp_mret_valid, exp_mret_pc);
        drive_idle_cycle();
        #1;
    end
    endtask

    task automatic do_trap_event(
        input logic         trap_req,
        input logic [3:0]   cause,
        input logic [31:0]  pc,
        input logic         irq_req,
        input logic         mret_req,
        output logic        exp_trap_valid,
        output logic [31:0] exp_trap_pc,
        output logic        exp_mret_valid,
        output logic [31:0] exp_mret_pc
    );
    begin
        csr_en_i     = 1'b0;
        csr_we_i     = 1'b0;
        csr_addr_i   = 12'h000;
        csr_wdata_i  = 32'h0000_0000;
        trap_req_i   = trap_req;
        trap_cause_i = cause;
        trap_pc_i    = pc;
        ext_irq_i    = irq_req;
        mret_i       = mret_req;
        @(posedge clk);
        #1;
        golden_step(rst_n, csr_en_i, csr_we_i, csr_addr_i, csr_wdata_i,
                    trap_req_i, trap_cause_i, trap_pc_i, ext_irq_i, mret_i,
                    exp_trap_valid, exp_trap_pc, exp_mret_valid, exp_mret_pc);
        drive_idle_cycle();
        #1;
    end
    endtask

    task automatic tc001_reset_csr_defaults;
        string tc_name;
        integer case_fail_count;
        logic [31:0] exp_rdata;
    begin
        tc_name = "TC001_RESET";
        case_fail_count = 0;

        rst_n        = 1'b0;
        csr_en_i     = 1'b0;
        csr_we_i     = 1'b0;
        csr_addr_i   = CSR_MSTATUS;
        csr_wdata_i  = 32'h0000_0000;
        trap_req_i   = 1'b0;
        trap_cause_i = 4'h0;
        trap_pc_i    = 32'h0000_0000;
        ext_irq_i    = 1'b0;
        mret_i       = 1'b0;
        golden_reset();
        golden_read(csr_addr_i, exp_rdata);
        #1;

        check_eq1(tc_name, "trap_redirect_valid_o", trap_redirect_valid_o, 1'b0, case_fail_count);
        check_eq1(tc_name, "mret_redirect_valid_o", mret_redirect_valid_o, 1'b0, case_fail_count);
        check_eq32(tc_name, "csr_rdata_o", csr_rdata_o, exp_rdata, case_fail_count);

        rst_n = 1'b1;
        @(posedge clk);
        #1;
        finish_case(tc_name, case_fail_count);
    end
    endtask

    task automatic tc002_write_mtvec;
        string tc_name;
        integer case_fail_count;
        logic [31:0] exp_rdata;
    begin
        tc_name = "TC002_WRITE";
        case_fail_count = 0;

        apply_reset();
        do_csr_write(CSR_MTVEC, 32'h0000_0100);

        csr_en_i   = 1'b1;
        csr_we_i   = 1'b0;
        csr_addr_i = CSR_MTVEC;
        golden_read(csr_addr_i, exp_rdata);
        #1;
        check_eq32(tc_name, "csr_rdata_o", csr_rdata_o, exp_rdata, case_fail_count);
        drive_idle_cycle();
        finish_case(tc_name, case_fail_count);
    end
    endtask

    task automatic tc003_read_mtvec;
        string tc_name;
        integer case_fail_count;
        logic [31:0] exp_rdata;
    begin
        tc_name = "TC003_READ";
        case_fail_count = 0;

        csr_en_i   = 1'b1;
        csr_we_i   = 1'b0;
        csr_addr_i = CSR_MTVEC;
        golden_read(csr_addr_i, exp_rdata);
        #1;
        check_eq32(tc_name, "csr_rdata_o", csr_rdata_o, exp_rdata, case_fail_count);
        drive_idle_cycle();
        finish_case(tc_name, case_fail_count);
    end
    endtask

    task automatic tc004_illegal_instr_trap_entry;
        string tc_name;
        integer case_fail_count;
        logic exp_trap_valid;
        logic [31:0] exp_trap_pc;
        logic exp_mret_valid;
        logic [31:0] exp_mret_pc;
    begin
        tc_name = "TC004_TRAP";
        case_fail_count = 0;

        do_trap_event(1'b1, 4'd2, 32'h0000_0040, 1'b0, 1'b0,
                      exp_trap_valid, exp_trap_pc, exp_mret_valid, exp_mret_pc);

        check_eq1(tc_name, "trap_redirect_valid_o", trap_redirect_valid_o, exp_trap_valid, case_fail_count);
        if (exp_trap_valid) begin
            check_eq32(tc_name, "trap_redirect_pc_o", trap_redirect_pc_o, exp_trap_pc, case_fail_count);
        end
        finish_case(tc_name, case_fail_count);
    end
    endtask

    task automatic tc005_external_interrupt_entry;
        string tc_name;
        integer case_fail_count;
        logic exp_trap_valid;
        logic [31:0] exp_trap_pc;
        logic exp_mret_valid;
        logic [31:0] exp_mret_pc;
    begin
        tc_name = "TC005_IRQ";
        case_fail_count = 0;

        do_trap_event(1'b0, 4'd0, 32'h0000_0080, 1'b1, 1'b0,
                      exp_trap_valid, exp_trap_pc, exp_mret_valid, exp_mret_pc);

        check_eq1(tc_name, "trap_redirect_valid_o", trap_redirect_valid_o, exp_trap_valid, case_fail_count);
        if (exp_trap_valid) begin
            check_eq32(tc_name, "trap_redirect_pc_o", trap_redirect_pc_o, exp_trap_pc, case_fail_count);
        end
        finish_case(tc_name, case_fail_count);
    end
    endtask

    task automatic tc006_mret_return;
        string tc_name;
        integer case_fail_count;
        logic exp_trap_valid;
        logic [31:0] exp_trap_pc;
        logic exp_mret_valid;
        logic [31:0] exp_mret_pc;
    begin
        tc_name = "TC006_MRET";
        case_fail_count = 0;

        do_trap_event(1'b1, 4'd2, 32'h0000_0040, 1'b0, 1'b0,
                      exp_trap_valid, exp_trap_pc, exp_mret_valid, exp_mret_pc);
        do_trap_event(1'b0, 4'd0, 32'h0000_0000, 1'b0, 1'b1,
                      exp_trap_valid, exp_trap_pc, exp_mret_valid, exp_mret_pc);

        check_eq1(tc_name, "mret_redirect_valid_o", mret_redirect_valid_o, exp_mret_valid, case_fail_count);
        if (exp_mret_valid) begin
            check_eq32(tc_name, "mret_redirect_pc_o", mret_redirect_pc_o, exp_mret_pc, case_fail_count);
        end
        finish_case(tc_name, case_fail_count);
    end
    endtask

    task automatic tc007_read_mepc_after_trap;
        string tc_name;
        integer case_fail_count;
        logic [31:0] exp_rdata;
    begin
        tc_name = "TC007_MEPC";
        case_fail_count = 0;

        csr_en_i   = 1'b1;
        csr_we_i   = 1'b0;
        csr_addr_i = CSR_MEPC;
        golden_read(csr_addr_i, exp_rdata);
        #1;
        check_eq32(tc_name, "csr_rdata_o", csr_rdata_o, exp_rdata, case_fail_count);
        drive_idle_cycle();
        finish_case(tc_name, case_fail_count);
    end
    endtask

    task automatic tc008_read_mcause_after_trap;
        string tc_name;
        integer case_fail_count;
        logic [31:0] exp_rdata;
    begin
        tc_name = "TC008_MCAUSE";
        case_fail_count = 0;

        csr_en_i   = 1'b1;
        csr_we_i   = 1'b0;
        csr_addr_i = CSR_MCAUSE;
        golden_read(csr_addr_i, exp_rdata);
        #1;
        check_eq32(tc_name, "csr_rdata_o", csr_rdata_o, exp_rdata, case_fail_count);
        drive_idle_cycle();
        finish_case(tc_name, case_fail_count);
    end
    endtask

    initial begin
        init_defaults();
        golden_reset();

        tc001_reset_csr_defaults();
        tc002_write_mtvec();
        tc003_read_mtvec();
        tc004_illegal_instr_trap_entry();
        tc005_external_interrupt_entry();
        tc006_mret_return();
        tc007_read_mepc_after_trap();
        tc008_read_mcause_after_trap();

        $display("[TEST_SUMMARY] PASS=%0d FAIL=%0d", pass_count, fail_count);
        $finish;
    end

endmodule
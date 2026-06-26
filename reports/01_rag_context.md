# RAG Context Report
_Generated: 2026-06-20 16:07:57_

## Summary
RV32EC_Zmmul MCU-class CPU partitioned into fetch, decode/control, execute/writeback, register file, CSR/trap, load/store, multiplier, boot loader, and observable top-level integration logic for RV32E+C+Zmmul with illegal-instruction trapping, variable-latency memory, interrupts, and SPI boot fail-stop handling.

## Detected Modules (10)

- `rv32ec_zmmul_cpu_top`
- `fetch_unit`
- `decode_control_unit`
- `execute_writeback_unit`
- `alu32_branch_unit`
- `multiplier_unit`
- `regfile_16x32`
- `csr_trap_controller`
- `load_store_unit`
- `boot_rom_loader`

## Module Analysis & Inferred Test Cases

### `rv32ec_zmmul_cpu_top`
**Description:** Top-level CPU integration module that sequences reset/boot, instruction fetch, decode, execute, memory access, trap/interrupt routing, multiply stalls, and fail-stop behavior using only architecturally observable external interfaces.

**Inferred Test Cases (12):**
- RESET_FETCH_BOOT_ROM: rst_n=0 then rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=0 instr_rdata=0x00000000 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → instr_req=1 instr_addr=0x00000000 data_req=0 spi_req=0 fail_stop=0
- SPI_BOOT_START: rst_n=1 boot_mode_spi=1 ext_irq=0 instr_ready=0 instr_rdata=0x00000000 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → spi_req=1 fail_stop=0
- SPI_BOOT_SUCCESS_TO_FETCH: rst_n=1 boot_mode_spi=1 ext_irq=0 spi_ready=1 spi_rdata=0x00000020 instr_ready=0 instr_rdata=0x00000000 data_ready=0 data_rdata=0x00000000 → spi_req=0 instr_req=1 instr_addr=0x00000020 fail_stop=0
- SPI_BOOT_FAIL_STOP: rst_n=1 boot_mode_spi=1 ext_irq=0 spi_ready=1 spi_rdata=0xFFFFFFFF instr_ready=0 instr_rdata=0x00000000 data_ready=0 data_rdata=0x00000000 → fail_stop=1 instr_req=0 data_req=0
- LOAD_HANDSHAKE: rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=1 instr_rdata=0x00002283 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → data_req=1 data_we=0 data_addr=0x00000000 fail_stop=0
- STORE_HANDSHAKE: rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=1 instr_rdata=0x00102023 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → data_req=1 data_we=1 data_addr=0x00000000 data_wdata=0x00000000 fail_stop=0
- BRANCH_REDIRECT_OBSERVABLE: rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=1 instr_rdata=0x0000006F data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → instr_req=1 instr_addr=0x00000000 or redirected jump target with no fail_stop=0
- ILLEGAL_DIV_TRAP_FLOW: rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=1 instr_rdata=0x02004033 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → fail_stop=0 instr_req=1 and next observable fetch redirects away from sequential PC to trap vector
- INTERRUPT_ENTRY_FLOW: rst_n=1 boot_mode_spi=0 ext_irq=1 instr_ready=1 instr_rdata=0x00000013 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → fail_stop=0 instr_req=1 and next observable fetch redirects to trap vector
- MEMORY_WAIT_STATE_STALL: rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=1 instr_rdata=0x00002283 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → data_req=1 and instr_addr holds constant until data_ready=1
- MUL_NO_TRAP_FLOW: rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=1 instr_rdata=0x022081B3 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → fail_stop=0 data_req=0 and fetch remains stalled or replayed until multiply completes without trap
- MRET_RETURN_FLOW: rst_n=1 boot_mode_spi=0 ext_irq=0 instr_ready=1 instr_rdata=0x30200073 data_ready=0 data_rdata=0x00000000 spi_ready=0 spi_rdata=0x00000000 → fail_stop=0 instr_req=1 and next observable fetch redirects to saved mepc

### `fetch_unit`
**Description:** Maintains the program counter, selects next PC by trap/MRET/branch/sequential priority, handles 16-bit versus 32-bit instruction stepping, and buffers fetch responses across stalls.

**Inferred Test Cases (8):**
- RESET_VECTOR_LOAD: rst_n=0 then rst_n=1 stall_i=0 flush_i=0 trap_redirect_valid_i=0 trap_redirect_pc_i=0x00000100 mret_redirect_valid_i=0 mret_redirect_pc_i=0x00000200 branch_redirect_valid_i=0 branch_redirect_pc_i=0x00000300 instr_ready_i=0 instr_rdata_i=0x00000000 is_compressed_i=0 reset_vector_i=0x00000080 → instr_req_o=1 instr_addr_o=0x00000080 pc_o=0x00000080 instr_valid_o=0
- SEQUENTIAL_PC_PLUS4: rst_n=1 stall_i=0 flush_i=0 trap_redirect_valid_i=0 trap_redirect_pc_i=0x00000000 mret_redirect_valid_i=0 mret_redirect_pc_i=0x00000000 branch_redirect_valid_i=0 branch_redirect_pc_i=0x00000000 instr_ready_i=1 instr_rdata_i=0x00000013 is_compressed_i=0 reset_vector_i=0x00000000 → instr_valid_o=1 instr_o=0x00000013 and next instr_addr_o=0x00000004
- SEQUENTIAL_PC_PLUS2: rst_n=1 stall_i=0 flush_i=0 trap_redirect_valid_i=0 trap_redirect_pc_i=0x00000000 mret_redirect_valid_i=0 mret_redirect_pc_i=0x00000000 branch_redirect_valid_i=0 branch_redirect_pc_i=0x00000000 instr_ready_i=1 instr_rdata_i=0x00000001 is_compressed_i=1 reset_vector_i=0x00000000 → instr_valid_o=1 instr_o=0x00000001 and next instr_addr_o=0x00000002
- BRANCH_REDIRECT_PRIORITY_OVER_SEQUENTIAL: rst_n=1 stall_i=0 flush_i=1 trap_redirect_valid_i=0 trap_redirect_pc_i=0x00000000 mret_redirect_valid_i=0 mret_redirect_pc_i=0x00000000 branch_redirect_valid_i=1 branch_redirect_pc_i=0x00000120 instr_ready_i=0 instr_rdata_i=0x00000000 is_compressed_i=0 reset_vector_i=0x00000000 → instr_addr_o=0x00000120 instr_valid_o=0
- MRET_REDIRECT_PRIORITY_OVER_BRANCH: rst_n=1 stall_i=0 flush_i=1 trap_redirect_valid_i=0 trap_redirect_pc_i=0x00000000 mret_redirect_valid_i=1 mret_redirect_pc_i=0x00000220 branch_redirect_valid_i=1 branch_redirect_pc_i=0x00000120 instr_ready_i=0 instr_rdata_i=0x00000000 is_compressed_i=0 reset_vector_i=0x00000000 → instr_addr_o=0x00000220 instr_valid_o=0
- TRAP_REDIRECT_HIGHEST_PRIORITY: rst_n=1 stall_i=0 flush_i=1 trap_redirect_valid_i=1 trap_redirect_pc_i=0x00000300 mret_redirect_valid_i=1 mret_redirect_pc_i=0x00000220 branch_redirect_valid_i=1 branch_redirect_pc_i=0x00000120 instr_ready_i=0 instr_rdata_i=0x00000000 is_compressed_i=0 reset_vector_i=0x00000000 → instr_addr_o=0x00000300 instr_valid_o=0
- STALL_HOLDS_FETCH_ADDRESS: rst_n=1 stall_i=1 flush_i=0 trap_redirect_valid_i=0 trap_redirect_pc_i=0x00000000 mret_redirect_valid_i=0 mret_redirect_pc_i=0x00000000 branch_redirect_valid_i=0 branch_redirect_pc_i=0x00000000 instr_ready_i=0 instr_rdata_i=0x00000000 is_compressed_i=0 reset_vector_i=0x00000000 → instr_req_o=1 and instr_addr_o holds previous PC
- BUFFER_CAPTURE_ON_READY: rst_n=1 stall_i=0 flush_i=0 trap_redirect_valid_i=0 trap_redirect_pc_i=0x00000000 mret_redirect_valid_i=0 mret_redirect_pc_i=0x00000000 branch_redirect_valid_i=0 branch_redirect_pc_i=0x00000000 instr_ready_i=1 instr_rdata_i=0xDEADBEEF is_compressed_i=0 reset_vector_i=0x00000000 → instr_valid_o=1 instr_o=0xDEADBEEF

### `decode_control_unit`
**Description:** Decodes RV32E, compressed C, CSR/system, branch/jump, load/store, and Zmmul instructions; generates immediates and control signals; detects illegal encodings including x16-x31 register references and divide/remainder opcodes.

**Inferred Test Cases (15):**
- ADD_DECODE: instr_i=0x002081B3 pc_i=0x00000000 → rs1_idx_o=1 rs2_idx_o=2 rd_idx_o=3 imm_o=0x00000000 alu_op_o=0 mul_en_o=0 mem_req_o=0 illegal_o=0 wb_en_o=1
- SUB_DECODE: instr_i=0x402081B3 pc_i=0x00000000 → rs1_idx_o=1 rs2_idx_o=2 rd_idx_o=3 alu_op_o=1 illegal_o=0 wb_en_o=1
- ANDI_IMM_SIGNEXT_DECODE: instr_i=0xFFF0F113 pc_i=0x00000000 → rs1_idx_o=1 rs2_idx_o=0 rd_idx_o=2 imm_o=0xFFFFFFFF alu_op_o=4 illegal_o=0 wb_en_o=1
- LOAD_DECODE: instr_i=0x00412283 pc_i=0x00000000 → rs1_idx_o=2 rd_idx_o=5 imm_o=0x00000004 mem_req_o=1 mem_we_o=0 illegal_o=0 wb_en_o=1
- STORE_DECODE: instr_i=0x00512423 pc_i=0x00000000 → rs1_idx_o=2 rs2_idx_o=5 imm_o=0x00000008 mem_req_o=1 mem_we_o=1 illegal_o=0 wb_en_o=0
- BRANCH_DECODE: instr_i=0x00208463 pc_i=0x00000000 → rs1_idx_o=1 rs2_idx_o=2 imm_o=0x00000008 branch_op_o=1 illegal_o=0 wb_en_o=0
- JAL_DECODE: instr_i=0x010000EF pc_i=0x00000000 → rd_idx_o=1 imm_o=0x00000010 branch_op_o=6 illegal_o=0 wb_en_o=1
- MUL_DECODE: instr_i=0x022081B3 pc_i=0x00000000 → rs1_idx_o=1 rs2_idx_o=2 rd_idx_o=3 mul_en_o=1 illegal_o=0 wb_en_o=1
- DIV_ILLEGAL_DECODE: instr_i=0x0220C1B3 pc_i=0x00000000 → illegal_o=1 mul_en_o=0 mem_req_o=0 wb_en_o=0
- X16_REFERENCE_ILLEGAL_DECODE: instr_i=0x00280833 pc_i=0x00000000 → illegal_o=1
- CSRRS_DECODE: instr_i=0x300120F3 pc_i=0x00000000 → rs1_idx_o=2 rd_idx_o=1 csr_en_o=1 illegal_o=0 wb_en_o=1
- MRET_DECODE: instr_i=0x30200073 pc_i=0x00000000 → mret_o=1 illegal_o=0 wb_en_o=0
- C_ADD_DECODE: instr_i=0x0000908A pc_i=0x00000000 → rs1_idx_o=1 rs2_idx_o=2 rd_idx_o=1 is_compressed_o=1 illegal_o=0 wb_en_o=1
- C_ANDI_DECODE: instr_i=0x00008865 pc_i=0x00000000 → rs1_idx_o=8 rd_idx_o=8 imm_o=0x00000019 is_compressed_o=1 illegal_o=0 wb_en_o=1
- C_EBREAK_DECODE: instr_i=0x00009002 pc_i=0x00000000 → ebreak_o=1 is_compressed_o=1 illegal_o=0 wb_en_o=0

### `execute_writeback_unit`
**Description:** Consumes decoded control and operands, performs ALU/branch/memory/multiply/CSR execution, generates branch redirects, selects writeback data, and raises exception requests.

**Inferred Test Cases (12):**
- ALU_WRITEBACK: clk=1 rst_n=1 pc_i=0x00000000 rs1_data_i=0x00000005 rs2_data_i=0x00000003 imm_i=0x00000000 rd_idx_i=3 alu_op_i=0 branch_op_i=0 mul_en_i=0 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → wb_en_o=1 wb_rd_idx_o=3 wb_data_o=0x00000008 branch_taken_o=0 trap_req_o=0 stall_o=0
- BRANCH_TAKEN_REDIRECT: clk=1 rst_n=1 pc_i=0x00000100 rs1_data_i=0x00000009 rs2_data_i=0x00000009 imm_i=0x00000010 rd_idx_i=0 alu_op_i=0 branch_op_i=1 mul_en_i=0 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → branch_taken_o=1 branch_target_o=0x00000110 wb_en_o=0 trap_req_o=0
- BRANCH_NOT_TAKEN: clk=1 rst_n=1 pc_i=0x00000100 rs1_data_i=0x00000009 rs2_data_i=0x00000008 imm_i=0x00000010 rd_idx_i=0 alu_op_i=0 branch_op_i=1 mul_en_i=0 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → branch_taken_o=0 wb_en_o=0 trap_req_o=0
- JAL_LINK_WRITEBACK: clk=1 rst_n=1 pc_i=0x00000100 rs1_data_i=0x00000000 rs2_data_i=0x00000000 imm_i=0x00000020 rd_idx_i=1 alu_op_i=0 branch_op_i=6 mul_en_i=0 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → branch_taken_o=1 branch_target_o=0x00000120 wb_en_o=1 wb_rd_idx_o=1 wb_data_o=0x00000104
- LOAD_WAIT_STALL: clk=1 rst_n=1 pc_i=0x00000000 rs1_data_i=0x00001000 rs2_data_i=0x00000000 imm_i=0x00000004 rd_idx_i=5 alu_op_i=0 branch_op_i=0 mul_en_i=0 mem_req_i=1 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → mem_req_o=1 mem_we_o=0 mem_addr_o=0x00001004 stall_o=1 wb_en_o=0
- LOAD_COMPLETE_WRITEBACK: clk=1 rst_n=1 pc_i=0x00000000 rs1_data_i=0x00001000 rs2_data_i=0x00000000 imm_i=0x00000004 rd_idx_i=5 alu_op_i=0 branch_op_i=0 mul_en_i=0 mem_req_i=1 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0xA5A5A5A5 load_ready_i=1 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → mem_addr_o=0x00001004 stall_o=0 wb_en_o=1 wb_rd_idx_o=5 wb_data_o=0xA5A5A5A5
- STORE_ISSUE: clk=1 rst_n=1 pc_i=0x00000000 rs1_data_i=0x00002000 rs2_data_i=0x12345678 imm_i=0x00000008 rd_idx_i=0 alu_op_i=0 branch_op_i=0 mul_en_i=0 mem_req_i=1 mem_we_i=1 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → mem_req_o=1 mem_we_o=1 mem_addr_o=0x00002008 mem_wdata_o=0x12345678 wb_en_o=0
- MUL_WAIT_STALL: clk=1 rst_n=1 pc_i=0x00000000 rs1_data_i=0x00000006 rs2_data_i=0x00000007 imm_i=0x00000000 rd_idx_i=4 alu_op_i=0 branch_op_i=0 mul_en_i=1 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → stall_o=1 wb_en_o=0 trap_req_o=0
- MUL_COMPLETE_WRITEBACK: clk=1 rst_n=1 pc_i=0x00000000 rs1_data_i=0x00000006 rs2_data_i=0x00000007 imm_i=0x00000000 rd_idx_i=4 alu_op_i=0 branch_op_i=0 mul_en_i=1 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x0000002A mul_done_i=1 csr_rdata_i=0x00000000 → stall_o=0 wb_en_o=1 wb_rd_idx_o=4 wb_data_o=0x0000002A
- CSR_READ_WRITEBACK: clk=1 rst_n=1 pc_i=0x00000000 rs1_data_i=0x00000001 rs2_data_i=0x00000000 imm_i=0x00000000 rd_idx_i=1 alu_op_i=0 branch_op_i=0 mul_en_i=0 mem_req_i=0 mem_we_i=0 csr_en_i=1 mret_i=0 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00001800 → wb_en_o=1 wb_rd_idx_o=1 wb_data_o=0x00001800 trap_req_o=0
- ILLEGAL_TRAP_REQUEST: clk=1 rst_n=1 pc_i=0x00000040 rs1_data_i=0x00000000 rs2_data_i=0x00000000 imm_i=0x00000000 rd_idx_i=0 alu_op_i=0 branch_op_i=0 mul_en_i=0 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=0 illegal_i=1 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → trap_req_o=1 trap_cause_o=2 wb_en_o=0
- MRET_REQUEST: clk=1 rst_n=1 pc_i=0x00000080 rs1_data_i=0x00000000 rs2_data_i=0x00000000 imm_i=0x00000000 rd_idx_i=0 alu_op_i=0 branch_op_i=0 mul_en_i=0 mem_req_i=0 mem_we_i=0 csr_en_i=0 mret_i=1 illegal_i=0 load_data_i=0x00000000 load_ready_i=0 mul_result_i=0x00000000 mul_done_i=0 csr_rdata_i=0x00000000 → mret_req_o=1 trap_req_o=0 wb_en_o=0

### `alu32_branch_unit`
**Description:** Combinational arithmetic, logical, shift, compare, branch condition, and target generation block used by the execute stage.

**Inferred Test Cases (16):**
- ADD: op_a_i=0x00000005 op_b_i=0x00000003 pc_i=0x00000000 imm_i=0x00000000 alu_op_i=0 branch_op_i=0 → result_o=0x00000008 branch_taken_o=0 branch_target_o=0x00000000
- SUB: op_a_i=0x00000005 op_b_i=0x00000003 pc_i=0x00000000 imm_i=0x00000000 alu_op_i=1 branch_op_i=0 → result_o=0x00000002 branch_taken_o=0 branch_target_o=0x00000000
- AND: op_a_i=0x000000F0 op_b_i=0x000000CC pc_i=0x00000000 imm_i=0x00000000 alu_op_i=2 branch_op_i=0 → result_o=0x000000C0 branch_taken_o=0 branch_target_o=0x00000000
- OR: op_a_i=0x000000F0 op_b_i=0x0000000C pc_i=0x00000000 imm_i=0x00000000 alu_op_i=3 branch_op_i=0 → result_o=0x000000FC branch_taken_o=0 branch_target_o=0x00000000
- XOR: op_a_i=0x000000F0 op_b_i=0x000000CC pc_i=0x00000000 imm_i=0x00000000 alu_op_i=4 branch_op_i=0 → result_o=0x0000003C branch_taken_o=0 branch_target_o=0x00000000
- SLL: op_a_i=0x00000003 op_b_i=0x00000004 pc_i=0x00000000 imm_i=0x00000000 alu_op_i=5 branch_op_i=0 → result_o=0x00000030 branch_taken_o=0 branch_target_o=0x00000000
- SRL: op_a_i=0x80000000 op_b_i=0x00000004 pc_i=0x00000000 imm_i=0x00000000 alu_op_i=6 branch_op_i=0 → result_o=0x08000000 branch_taken_o=0 branch_target_o=0x00000000
- SRA: op_a_i=0x80000000 op_b_i=0x00000004 pc_i=0x00000000 imm_i=0x00000000 alu_op_i=7 branch_op_i=0 → result_o=0xF8000000 branch_taken_o=0 branch_target_o=0x00000000
- SLT_SIGNED_TRUE: op_a_i=0xFFFFFFFF op_b_i=0x00000001 pc_i=0x00000000 imm_i=0x00000000 alu_op_i=8 branch_op_i=0 → result_o=0x00000001 branch_taken_o=0 branch_target_o=0x00000000
- SLTU_TRUE: op_a_i=0x00000001 op_b_i=0xFFFFFFFF pc_i=0x00000000 imm_i=0x00000000 alu_op_i=9 branch_op_i=0 → result_o=0x00000001 branch_taken_o=0 branch_target_o=0x00000000
- BEQ_TAKEN: op_a_i=0x00000009 op_b_i=0x00000009 pc_i=0x00000100 imm_i=0x00000010 alu_op_i=0 branch_op_i=1 → result_o=0x00000012 branch_taken_o=1 branch_target_o=0x00000110
- BNE_TAKEN: op_a_i=0x00000009 op_b_i=0x00000008 pc_i=0x00000100 imm_i=0x00000010 alu_op_i=0 branch_op_i=2 → branch_taken_o=1 branch_target_o=0x00000110
- BLT_TAKEN: op_a_i=0xFFFFFFFF op_b_i=0x00000001 pc_i=0x00000100 imm_i=0x00000010 alu_op_i=0 branch_op_i=3 → branch_taken_o=1 branch_target_o=0x00000110
- BGEU_TAKEN: op_a_i=0xFFFFFFFF op_b_i=0x00000001 pc_i=0x00000100 imm_i=0x00000010 alu_op_i=0 branch_op_i=4 → branch_taken_o=1 branch_target_o=0x00000110
- JAL_TARGET: op_a_i=0x00000000 op_b_i=0x00000000 pc_i=0x00000200 imm_i=0x00000020 alu_op_i=0 branch_op_i=6 → branch_taken_o=1 branch_target_o=0x00000220
- JALR_TARGET_ALIGN: op_a_i=0x00000301 op_b_i=0x00000000 pc_i=0x00000000 imm_i=0x00000008 alu_op_i=0 branch_op_i=7 → branch_taken_o=1 branch_target_o=0x00000308

### `multiplier_unit`
**Description:** Implements Zmmul multiply operations with start/busy/done handshake and low-32-bit product result used by the pipeline.

**Inferred Test Cases (6):**
- RESET_IDLE: clk=1 rst_n=0 start_i=0 op_a_i=0x00000000 op_b_i=0x00000000 → busy_o=0 done_o=0 result_o=0x00000000
- MUL_POSITIVE: clk=1 rst_n=1 start_i=1 op_a_i=0x00000006 op_b_i=0x00000007 → busy_o=1 then done_o=1 result_o=0x0000002A
- MUL_BY_ZERO: clk=1 rst_n=1 start_i=1 op_a_i=0x12345678 op_b_i=0x00000000 → busy_o=1 then done_o=1 result_o=0x00000000
- MUL_NEGATIVE_OPERAND_LOW32: clk=1 rst_n=1 start_i=1 op_a_i=0xFFFFFFFF op_b_i=0x00000002 → busy_o=1 then done_o=1 result_o=0xFFFFFFFE
- MUL_OVERFLOW_LOW32: clk=1 rst_n=1 start_i=1 op_a_i=0x80000000 op_b_i=0x00000002 → busy_o=1 then done_o=1 result_o=0x00000000
- BUSY_HOLDS_UNTIL_DONE: clk=1 rst_n=1 start_i=1 op_a_i=0x00000003 op_b_i=0x00000005 → busy_o=1 before done_o=1 and final result_o=0x0000000F

### `regfile_16x32`
**Description:** Sixteen-entry 32-bit integer register file for RV32E with two read ports, one write port, and hardwired x0 equal to zero.

**Inferred Test Cases (5):**
- READ_X0_ZERO: clk=1 rst_n=1 raddr1_i=0 raddr2_i=0 we_i=0 waddr_i=0 wdata_i=0xFFFFFFFF → rdata1_o=0x00000000 rdata2_o=0x00000000
- WRITE_READ_X1: clk=1 rst_n=1 raddr1_i=1 raddr2_i=0 we_i=1 waddr_i=1 wdata_i=0x12345678 → after write rdata1_o=0x12345678 rdata2_o=0x00000000
- WRITE_READ_X15: clk=1 rst_n=1 raddr1_i=15 raddr2_i=1 we_i=1 waddr_i=15 wdata_i=0xA5A5A5A5 → after write rdata1_o=0xA5A5A5A5 rdata2_o=0x12345678
- WRITE_X0_IGNORED: clk=1 rst_n=1 raddr1_i=0 raddr2_i=1 we_i=1 waddr_i=0 wdata_i=0xDEADBEEF → rdata1_o=0x00000000 rdata2_o=0x12345678
- WRITE_DISABLE_NO_CHANGE: clk=1 rst_n=1 raddr1_i=1 raddr2_i=15 we_i=0 waddr_i=2 wdata_i=0xCAFEBABE → rdata1_o=0x12345678 rdata2_o=0xA5A5A5A5

### `csr_trap_controller`
**Description:** Maintains machine-mode CSR state needed for direct traps, interrupt entry, exception cause capture, MRET return address restore, and CSR read/write accesses.

**Inferred Test Cases (8):**
- RESET_CSR_DEFAULTS: clk=1 rst_n=0 csr_en_i=0 csr_we_i=0 csr_addr_i=0x300 csr_wdata_i=0x00000000 trap_req_i=0 trap_cause_i=0 trap_pc_i=0x00000000 ext_irq_i=0 mret_i=0 → trap_redirect_valid_o=0 mret_redirect_valid_o=0 csr_rdata_o=0x00000000 or defined reset value
- WRITE_MTVEC: clk=1 rst_n=1 csr_en_i=1 csr_we_i=1 csr_addr_i=0x305 csr_wdata_i=0x00000100 trap_req_i=0 trap_cause_i=0 trap_pc_i=0x00000000 ext_irq_i=0 mret_i=0 → csr_rdata_o=0x00000100
- READ_MTVEC: clk=1 rst_n=1 csr_en_i=1 csr_we_i=0 csr_addr_i=0x305 csr_wdata_i=0x00000000 trap_req_i=0 trap_cause_i=0 trap_pc_i=0x00000000 ext_irq_i=0 mret_i=0 → csr_rdata_o=0x00000100
- ILLEGAL_INSTR_TRAP_ENTRY: clk=1 rst_n=1 csr_en_i=0 csr_we_i=0 csr_addr_i=0x000 csr_wdata_i=0x00000000 trap_req_i=1 trap_cause_i=2 trap_pc_i=0x00000040 ext_irq_i=0 mret_i=0 → trap_redirect_valid_o=1 trap_redirect_pc_o=0x00000100
- EXTERNAL_INTERRUPT_ENTRY: clk=1 rst_n=1 csr_en_i=0 csr_we_i=0 csr_addr_i=0x000 csr_wdata_i=0x00000000 trap_req_i=0 trap_cause_i=0 trap_pc_i=0x00000080 ext_irq_i=1 mret_i=0 → trap_redirect_valid_o=1 trap_redirect_pc_o=0x00000100
- MRET_RETURN: clk=1 rst_n=1 csr_en_i=0 csr_we_i=0 csr_addr_i=0x000 csr_wdata_i=0x00000000 trap_req_i=0 trap_cause_i=0 trap_pc_i=0x00000000 ext_irq_i=0 mret_i=1 → mret_redirect_valid_o=1 mret_redirect_pc_o=0x00000040
- READ_MEPC_AFTER_TRAP: clk=1 rst_n=1 csr_en_i=1 csr_we_i=0 csr_addr_i=0x341 csr_wdata_i=0x00000000 trap_req_i=0 trap_cause_i=0 trap_pc_i=0x00000000 ext_irq_i=0 mret_i=0 → csr_rdata_o=0x00000040
- READ_MCAUSE_AFTER_TRAP: clk=1 rst_n=1 csr_en_i=1 csr_we_i=0 csr_addr_i=0x342 csr_wdata_i=0x00000000 trap_req_i=0 trap_cause_i=0 trap_pc_i=0x00000000 ext_irq_i=0 mret_i=0 → csr_rdata_o=0x00000002

### `load_store_unit`
**Description:** Calculates effective addresses, generates byte enables and store data, handles variable-latency memory handshakes, returns aligned load data, and optionally traps on misaligned access.

**Inferred Test Cases (10):**
- LW_ADDRESS_CALC: clk=1 rst_n=1 req_i=1 we_i=0 size_i=2 unsigned_i=0 base_addr_i=0x00001000 offset_i=0x00000004 store_data_i=0x00000000 mem_ready_i=0 mem_rdata_i=0x00000000 trap_on_misaligned_i=1 → mem_req_o=1 mem_we_o=0 mem_addr_o=0x00001004 mem_be_o=0xF stall_o=1 misaligned_o=0
- SW_ADDRESS_AND_DATA: clk=1 rst_n=1 req_i=1 we_i=1 size_i=2 unsigned_i=0 base_addr_i=0x00002000 offset_i=0x00000008 store_data_i=0x12345678 mem_ready_i=0 mem_rdata_i=0x00000000 trap_on_misaligned_i=1 → mem_req_o=1 mem_we_o=1 mem_addr_o=0x00002008 mem_be_o=0xF mem_wdata_o=0x12345678 stall_o=1 misaligned_o=0
- LB_SIGN_EXTEND: clk=1 rst_n=1 req_i=1 we_i=0 size_i=0 unsigned_i=0 base_addr_i=0x00003000 offset_i=0x00000001 store_data_i=0x00000000 mem_ready_i=1 mem_rdata_i=0x0000AA00 trap_on_misaligned_i=1 → load_data_o=0xFFFFFFAA done_o=1 misaligned_o=0
- LBU_ZERO_EXTEND: clk=1 rst_n=1 req_i=1 we_i=0 size_i=0 unsigned_i=1 base_addr_i=0x00003000 offset_i=0x00000001 store_data_i=0x00000000 mem_ready_i=1 mem_rdata_i=0x0000AA00 trap_on_misaligned_i=1 → load_data_o=0x000000AA done_o=1 misaligned_o=0
- LH_SIGN_EXTEND: clk=1 rst_n=1 req_i=1 we_i=0 size_i=1 unsigned_i=0 base_addr_i=0x00004000 offset_i=0x00000002 store_data_i=0x00000000 mem_ready_i=1 mem_rdata_i=0x80010000 trap_on_misaligned_i=1 → load_data_o=0xFFFF8001 done_o=1 misaligned_o=0
- LHU_ZERO_EXTEND: clk=1 rst_n=1 req_i=1 we_i=0 size_i=1 unsigned_i=1 base_addr_i=0x00004000 offset_i=0x00000002 store_data_i=0x00000000 mem_ready_i=1 mem_rdata_i=0x80010000 trap_on_misaligned_i=1 → load_data_o=0x00008001 done_o=1 misaligned_o=0
- LOAD_WAIT_STATE: clk=1 rst_n=1 req_i=1 we_i=0 size_i=2 unsigned_i=0 base_addr_i=0x00005000 offset_i=0x00000000 store_data_i=0x00000000 mem_ready_i=0 mem_rdata_i=0x00000000 trap_on_misaligned_i=1 → mem_req_o=1 stall_o=1 done_o=0
- LOAD_COMPLETE: clk=1 rst_n=1 req_i=1 we_i=0 size_i=2 unsigned_i=0 base_addr_i=0x00005000 offset_i=0x00000000 store_data_i=0x00000000 mem_ready_i=1 mem_rdata_i=0xDEADBEEF trap_on_misaligned_i=1 → load_data_o=0xDEADBEEF done_o=1 stall_o=0
- MISALIGNED_WORD_TRAP_ENABLED: clk=1 rst_n=1 req_i=1 we_i=0 size_i=2 unsigned_i=0 base_addr_i=0x00006000 offset_i=0x00000002 store_data_i=0x00000000 mem_ready_i=0 mem_rdata_i=0x00000000 trap_on_misaligned_i=1 → misaligned_o=1 mem_req_o=0 done_o=1
- MISALIGNED_WORD_NO_TRAP_POLICY: clk=1 rst_n=1 req_i=1 we_i=0 size_i=2 unsigned_i=0 base_addr_i=0x00006000 offset_i=0x00000002 store_data_i=0x00000000 mem_ready_i=0 mem_rdata_i=0x00000000 trap_on_misaligned_i=0 → misaligned_o=0 mem_req_o=1 mem_addr_o=0x00006002

### `boot_rom_loader`
**Description:** SPI-to-IRAM boot assist engine that reads boot image metadata, validates header constraints, copies image data, signals boot entry on success, and asserts fail-stop on malformed or failed boot conditions.

**Inferred Test Cases (8):**
- RESET_IDLE: clk=1 rst_n=0 start_i=0 spi_ready_i=0 spi_rdata_i=0x00000000 iram_ready_i=0 validation_enable_i=0 → spi_req_o=0 iram_we_o=0 done_o=0 fail_stop_o=0
- START_HEADER_FETCH: clk=1 rst_n=1 start_i=1 spi_ready_i=0 spi_rdata_i=0x00000000 iram_ready_i=0 validation_enable_i=1 → spi_req_o=1 spi_addr_o=0x00000000 done_o=0 fail_stop_o=0
- VALID_HEADER_ACCEPT: clk=1 rst_n=1 start_i=1 spi_ready_i=1 spi_rdata_i=0xB007CAFE iram_ready_i=0 validation_enable_i=1 → spi_req_o=1 fail_stop_o=0
- PROGRAM_WORD_COPY: clk=1 rst_n=1 start_i=1 spi_ready_i=1 spi_rdata_i=0x11223344 iram_ready_i=1 validation_enable_i=0 → iram_we_o=1 iram_wdata_o=0x11223344 fail_stop_o=0
- BOOT_SUCCESS: clk=1 rst_n=1 start_i=1 spi_ready_i=1 spi_rdata_i=0x00000020 iram_ready_i=1 validation_enable_i=0 → done_o=1 boot_pc_o=0x00000020 fail_stop_o=0
- HEADER_MALFORMED_FAIL: clk=1 rst_n=1 start_i=1 spi_ready_i=1 spi_rdata_i=0xFFFFFFFF iram_ready_i=0 validation_enable_i=1 → fail_stop_o=1 done_o=0 spi_req_o=0
- SIZE_RANGE_VIOLATION_FAIL: clk=1 rst_n=1 start_i=1 spi_ready_i=1 spi_rdata_i=0x00010000 iram_ready_i=0 validation_enable_i=1 → fail_stop_o=1 done_o=0
- SPI_TIMEOUT_OR_ERROR_FAIL: clk=1 rst_n=1 start_i=1 spi_ready_i=0 spi_rdata_i=0x00000000 iram_ready_i=0 validation_enable_i=1 → if timeout expires fail_stop_o=1 done_o=0


## Raw Context
```
RV32EC_Zmmul Microarchitecture (Detailed)

1. Overview

This document defines a concrete microarchitectural blueprint for implementing the RV32EC_Zmmul core.

Target characteristics:

3-stage single-issue in-order pipeline

Small control logic footprint

Deterministic trap/interrupt handling

Configurable multiply unit implementation

Top-level blocks:

Fetch Unit (FU)

Decode/Control Unit (DU)

Execute/Writeback Unit (EX/WB)

Integer Register File (16 x 32)

CSR/Trap Controller

Load/Store Interface

Boot ROM Loader Assist Logic (for SPI-to-IRAM mode)

2. Pipeline Structure

Stages:

F (Fetch)

D (Decode)

X (Execute + memory access + writeback)

Pipeline goals:

One instruction issued per cycle in no-stall path

Global stall and flush controls for hazards and traps

3. Fetch Unit

3.1 Responsibilities

Maintain PC and next-PC generation

Fetch 16/32-bit instruction stream

Handle compressed instruction boundaries

Redirect fetch on branch/jump/trap

3.2 PC Selection Priority (highest first)

Trap/interrupt redirect (mtvec)

Exception return (mepc via MRET)

Taken branch/jump target from X

Sequential next PC (PC + 2 or PC + 4)

3.3 Instruction Buffering

RV32EC_Zmmul Tiny MCU Core Specification (v0.2-draft)

1. Scope

Defines a Cortex-M0-class microcontroller CPU core based on RISC-V for low-cost, low-power embedded systems.

2. Architecture Overview

Core type: 32-bit in-order MCU CPU

Core ISA: RV32EC_Zmmul

Privilege levels: M-mode only

Pipeline: 3-stage (Fetch, Decode, Execute)

Issue: Single-issue

Branch prediction: Not implemented

MMU/FPU: Not implemented

3. ISA Support

Mandatory:

RV32E

C (compressed instructions)

Zmmul (multiply-only signed integer multiply subset)

Multiply/Divide behavior:

Multiply instructions supported

Divide/remainder instructions not supported

Unsupported opcode policy:

Unsupported/illegal opcodes shall raise an illegal-instruction trap

4. Interrupt and Exception Model

RISC-V machine-level trap handling

Direct trap mode only: mtvec.MODE=0

Vectored mode: Not supported

Single external interrupt input (no priority/preemption model)

Interrupt entry latency target: 12-20 cycles (implementation dependent)

5. Bus and Memory Interface

Instruction fetch path:

Primary execution memory is internal IRAM/SRAM

External SPI ROM is used as boot image source in SPI boot mode

RV32EC_Zmmul ISA Definition

1. Profile

Supported ISA profile:

RV32E

C

Zmmul

Execution/trap policy:

Machine mode only (M-mode)

Unsupported/illegal opcode -> illegal-instruction trap

Divide/remainder instructions are not supported

Register model:

Architectural integer registers: x0..x15

Any encoding that names x16..x31 is illegal for this core profile

2. Instruction Encoding Fields

2.1 32-bit Base Formats

R-type: funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]

I-type: imm[31:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]

S-type: imm[11:5][31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[4:0][11:7] | opcode[6:0]

B-type: imm[12|10:5][31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[4:1|11][11:7] | opcode[6:0]

U-type: imm[31:12] | rd[11:7] | opcode[6:0]

J-type: imm[20|10:1|11|19:12] | rd[11:7] | opcode[6:0]

2.2 16-bit Compressed Formats

CR: funct4[15:12] | rd/rs1[11:7] | rs2[6:2] | op[1:0]

CI: funct3[15:13] | imm[12] | rd/rs1[11:7] | imm[6:2] | op[1:0]

CSS: funct3[15:13] | imm[12:7] | rs2[6:2] | op[1:0]

CIW: funct3[15:13] | imm[12:5] | rd'[4:2] | op[1:0]

Trap/interrupt redirect (mtvec)

Exception return (mepc via MRET)

Taken branch/jump target from X

Sequential next PC (PC + 2 or PC + 4)

3.3 Instruction Buffering

Recommended minimal prefetch structure:

32-bit fetch register + halfword align control

Valid bit and replay support on stalls

4. Decode and Control Unit

4.1 Responsibilities

Decode RV32E, C, Zmmul opcodes

Generate control signals for EX datapath and writeback

Classify instruction type: ALU, branch/jump, load/store, CSR, multiply, trap-return

Detect illegal instruction patterns

4.2 Immediate Generation

Support all required immediate forms for RV32E/C instructions in scope

Sign-extension performed in decode path

4.3 Register Read

Two read ports from register file (or equivalent time-multiplexed implementation)

Read in D, consume in X

5. Execute/Writeback Unit

5.1 ALU Subsystem

Required operations:

Add/subtract

Logical ops (and/or/xor)

Shifts

Compare/set operations

Branch target calculation and condition evaluation

5.2 Branch and Jump Handling

Branch resolution in X

On taken control transfer, flush younger instructions (F/D) and redirect PC

No branch prediction

5.3 Multiply Unit (Zmmul)

5.2 Branch and Jump Handling

Branch resolution in X

On taken control transfer, flush younger instructions (F/D) and redirect PC

No branch prediction

5.3 Multiply Unit (Zmmul)

Configurable implementation options:

Iterative multiplier (small area, higher latency)

Multi-cycle optimized multiplier (moderate area/performance tradeoff)

Control requirements:

mul_busy handshake to pipeline control

Stall front-end while multiply result is pending

Commit writeback when multiply completes

5.4 Divide/Remainder Handling

No divide/remainder datapath

Decode of unsupported divide/remainder opcodes triggers illegal-instruction exception path

5.5 Writeback

Single architectural writeback point at end of X

Writeback sources:

ALU result

Multiply result

Load data

CSR read result (if applicable)

6. Load/Store Path

6.1 Responsibilities

Effective address calculation in X

Issue memory transaction for load/store

Return load data for register writeback

6.2 Memory Wait-State Behavior

Variable-latency memory supported via stall/ready handshake

During pending memory response:

X stage holds instruction context

F and D are stalled

6.3 Alignment and Fault Policy

Valid magic/version

program_size < 16 KB

Start address in allowed execution region

Failure conditions (any -> fail-stop):

SPI transaction timeout/error

Header malformed

Size/range violation

Validation failure (if enabled)

11. Reset and Initialization Behavior

On reset deassertion:

PC <- reset vector (Boot ROM)

Integer registers unspecified unless explicitly zeroed by ROM/startup

CSRs initialized to defined reset values

Pipeline valid bits cleared

Outstanding memory operations cancelled/invalidated

12. Clocking and Power Intent (Microarchitectural)

Clock-gating points may include:

Multiplier when idle

Fetch pipeline when globally stalled

Optional CSR/counter blocks when disabled

WFI behavior should quiesce front-end until wake condition

13. Configurable Parameters

Recommended synthesis-time parameters:

MUL_IMPL (ITERATIVE, MCYCLE_OPT)

IRAM_BYTES (default 16384)

DRAM_BYTES (default 8192)

BOOT_ROM_BYTES_MAX (16384)

ENABLE_IMAGE_VALIDATION (0/1)

TRAP_ON_MISALIGNED (0/1)

14. Verification Guidance

Minimum verification matrix:

ISA compliance subset (RV32E, C, Zmmul)

Illegal instruction trapping (including divide/rem opcodes)

TRAP_ON_MISALIGNED (0/1)

14. Verification Guidance

Minimum verification matrix:

ISA compliance subset (RV32E, C, Zmmul)

Illegal instruction trapping (including divide/rem opcodes)

Branch flush correctness under back-to-back control transfers

Interrupt entry/exit correctness (mepc/mcause/mstatus effects)

SPI-to-IRAM boot success/failure paths

Fail-stop terminal behavior

Memory wait-state robustness (load/store stalls)

Recommended methods:

Directed tests for boot/trap edge cases

Constrained-random instruction streams with reference model comparison

Assertions for stall/flush mutual exclusion and single-commit invariants

4.4 Register-register ALU (compressed)

Instruction Format Quadrant ( op[1:0] ) Key fields C.MV CR 10 funct4=1000, rd!=x0, rs2!=x0 C.ADD CR 10 funct4=1001, rd/rs1!=x0, rs2!=x0 C.ANDI CB 01 funct3=100, funct2=10, rs1', imm C.SRLI CB 01 funct3=100, funct2=00, rs1', shamt C.SRAI CB 01 funct3=100, funct2=01, rs1', shamt C.SUB CA 01 funct6=100011, funct2=00, rd'/rs1', rs2' C.XOR CA 01 funct6=100011, funct2=01, rd'/rs1', rs2' C.OR CA 01 funct6=100011, funct2=10, rd'/rs1', rs2' C.AND CA 01 funct6=100011, funct2=11, rd'/rs1', rs2'

4.5 Breakpoint

Instruction Format Quadrant ( op[1:0] ) Key fields C.EBREAK CR 10 funct4=1001, rd/rs1=x0, rs2=x0

5. Explicitly Unsupported Instructions

All divide/remainder instructions: DIV, DIVU, REM, REMU

Any RV32I/RV32E encoding that references x16..x31

Any extension opcode not listed in this file (F/D/A/V/B/...) unless added in a future revision

6. Quick Field Reference

rd: destination register (5-bit encoding; legal values map to x0..x15)

rs1, rs2: source registers

rd', rs1', rs2': compressed compact regs (x8..x15)

imm: sign-extended immediate

uimm: zero-extended immediate

shamt: shift amount

csr: CSR address field

Optional image validation (policy is SoC/product-defined)

On boot failure (e.g., SPI read/validation failure), system enters fail-stop state

7. Toolchain

GCC RISC-V support (bare-metal)

8. Design Targets (Non-Normative)

Performance/area class: Cortex-M0-class

Priorities: low gate count, deterministic behavior, low power

9. Configurability

Multiply microarchitecture choice (e.g., iterative vs optimized multi-cycle)

SoC-defined APB map and memory sizing

10. Open Items

Final APB memory map and peripheral slot allocation

Reset/application vector addresses

Boot mode select mechanism (e.g., strap pin or configuration fuse)

Instruction/data interface timing and handshake details

Instruction-class cycle timing table

Sleep/deep-sleep behavior and WFI policy

Boot image validation policy details (if enabled)
```
Name: Joshua Vigel
EID: jpv865

Multi-cycle Tinker CPU implementation in SystemVerilog.

## How to run

From the 9prog directory:

```
iverilog -g2012 -o vvp/tb_tinker.vvp test/tb_tinker.sv tinker.sv
vvp vvp/tb_tinker.vvp
```

Optional waveform:
```
gtkwave sim/tb_tinker.vcd
```

## Design

5-stage FSM: IF → ID → EX → (MEM) → (WB)

- IF: fetch instruction
- ID: decode, read registers
- EX: ALU/FPU, branch resolution, address calc for memory ops
- MEM: load/store/call/return memory access (skipped for non-memory instructions)
- WB: write result back to register file (skipped for branches/stores)

Cycle counts:
- ALU/FPU ops: 4 cycles (no MEM stage)
- Branches: 3 cycles (no MEM or WB)
- Load: 5 cycles
- Store, CALL, RETURN: 4 cycles (no WB)
- HALT: detected in EX, hlt output goes high the same cycle

Memory is 512KB, byte-addressed, little-endian. PC starts at 0x2000. r31 initialized to MEM_SIZE and used as the stack pointer for CALL/RETURN.

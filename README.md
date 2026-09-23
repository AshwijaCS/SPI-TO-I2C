SPI to I²C Protocol Converter (FPGA Implementation)
A robust, fully verifiable hardware bridge implemented in Verilog that converts incoming SPI packets into I²C register transactions. This project features robust clock-domain crossing (CDC), asynchronous FIFO buffering, and a custom finite state machine (FSM) for packet parsing.

System Architecture
The design relies on a unidirectional data pipeline crossing two distinct clock domains (e.g., 5 MHz SPI clock to 50 MHz System clock):

SPI Master (spi_master.v): Interfaces with an external SPI device. Captures raw serial bitstreams via the MISO pin and deserializes them into 8-bit parallel bytes.

Async FIFO (async_fifo.v): Safely buffers the incoming bytes across the clock boundary using 2-stage flip-flop synchronizers and Gray-coded pointers.

Packet Parser (packet_parser.v): An FSM-based decoder that pulls bytes from the FIFO, extracts the protocol headers, and dynamically calculates target memory addresses.

I²C Slave (i2c_slave.v): Contains the memory register map. It receives parallel data from the parser and serializes it out to the physical open-drain SDA and SCL pins for external I²C controllers to read.

Reset & Clock Sync (rst_sync.v, clock_gen.v): Ensures stable, glitch-free asynchronous resets across all clock domains.

Custom Packet Protocol
The converter expects a specific contiguous byte sequence over SPI to initiate an I²C write sequence.

Standard Packet Structure:
[CMD] [I2C_ADDR] [REG_ADDR] [LENGTH] [DATA_0] ... [DATA_N]

Example Test Vector (01 50 20 03 A5 B6 C7):

01 - Command (Write)

50 - Target I²C Slave Address (Hex)

20 - Starting Register Address (Hex)

03 - Payload Length (3 bytes)

A5 B6 C7 - Payload Data (Written sequentially to registers 0x20, 0x21, and 0x22)

Simulation & Verification
This repository includes a unified, self-checking testbench (tb_spi_to_i2c_top.v) compatible with both RTL Simulation and Gate-Level Simulation (GLS). It utilizes Verilog conditional compilation to monitor internal FSM states during RTL checks while remaining perfectly compatible with flattened post-synthesis gate-level netlists.

Prerequisites
Quartus Prime (Synthesis and Netlist Generation)

Questa / ModelSim (Simulation)

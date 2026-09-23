SPI to I²C Protocol Converter
Overview

An FPGA-based SPI-to-I²C protocol converter implemented using Verilog/SystemVerilog. The design receives SPI data, transfers it across clock domains using an asynchronous FIFO, parses the command packet, and performs the corresponding I²C transaction.

Architecture
SPI Slave
    │
    │ MISO
    ▼
SPI Master
    │
    ▼
Async FIFO
    │
    ▼
Packet Parser
    │
    ▼
I²C Slave
    │
    ▼
I²C Master / Controller
Main Modules
clock_gen.sv – Generates required clock signals.
rst_sync.sv – Provides synchronized reset for clock domains.
spi_master.sv – Receives serial data through SPI.
async_fifo.sv – Provides buffering and clock-domain crossing.
packet_parser.sv – Decodes commands, address, register, length, and data.
i2c_slave.sv – Handles I²C transactions and register access.
spi_to_i2c_top.sv – Top-level integration module.
Packet Format
CMD | I2C ADDR | REG ADDR | LENGTH | DATA

Example:

01 50 20 03 A5 B6 C7
Features
SPI Master interface
I²C Slave interface
Asynchronous FIFO for CDC
Packet-based data transfer
ACK/NACK handling
I²C clock stretching
Register-based data storage
RTL and gate-level verification
Tools
Intel Quartus
Questa / ModelSim
Verilog/SystemVerilog
Verification

The design is verified through RTL simulation and gate-level simulation, including SPI reception, FIFO transfer, packet parsing, I²C transactions, and end-to-end data transfer.

#!/bin/sh

~/bin/ghdl synth --std=08 --out=verilog vhd/top.vhd vhd/clocks.vhd ../vhd/uart_tx.vhd ../vhd/hyperram_ctl.vhd ../vhd/reset.vhd ../vhd/simple_memory_check.vhd -e top > top.v
apio build
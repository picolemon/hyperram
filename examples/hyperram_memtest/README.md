# HyperRam_memTest :lemon: # 


### Description :books:
A Very simple HyperRam memory tester to verify the device is functional. Once the device has reset and setup the state machine writes a single value into memory and reads back then to confirm the bus is functional.

### Features :rocket:
- [x] Very basic controller, doesnt use any ODDR instances for portability at the expense of speed.
- [x] Wishbone memory controller initializes the device and allow read/write of 32bit wide bus.
- [x] Full test-bench available ( separate model downloadable separately for licensing ).
- [x] Vivado & Lattice project templates.
- [x] Test state via led & UART.
	

### Getting started :car:
- Open examples/hyperram_memtest test project in Vivado or Diamond.
- Setup board constraints to match pins in the [datasheet](../../docs/datasheet.pdf).
- Add status led & UART to constraints to get test output.
- Optionally run Vivado simulation.
- Run memory tester and wait for led to light solid, it will either not respond or flash for an error detected.

### Project overview :mag:

* **vhd/**
  * Main project RTL source which contains the main memory tester and stubs for platform specifics such as clock/pll generators.
* **vivado/**
	* Xilinx project files 
* **vivado/vhd**
	* Xilinx specific implementation for example clock PLLs are instanced in clocks.impl.vhd.
* **vivado/test**
	* Vivado simulation of ram tester. Note the simulation will fail until the [Infineon model](https://www.infineon.com/dgdl/Infineon-S27KL0641_S27KS0641_VERILOG-SimulationModels-v05_00-EN.zip?fileId=8ac78c8c7d0d8da4017d0f6349a14f68) as been downloaded and added to the project,
	this is not included and must be downloaded separately. To setup, download the model then extract the S27kl0641.exe using 7zip ( or optionally run the exe if using Windows/wine ), then copy "S27kl0641\model\s27kl0641.v" to "vivado/test/s27kl0641.v".

* **diamond/**
	* Lattice diamond project file.

* **apio/**
	* [apio](https://github.com/FPGAwars/apio) project.
* **apio/build.sh**
	* Translates vhd to verilog ( required for apio ).
* **apio/vhd**
	* Apio specific top level and Lattice specific clocks.

### Software dependencies :loop:
- HyperRAM Simulation model:	https://www.infineon.com/dgdl/Infineon-S27KL0641_S27KS0641_VERILOG-SimulationModels-v05_00-EN.zip?fileId=8ac78c8c7d0d8da4017d0f6349a14f68
- Vivado Vivado 2019.2 or greater.
- Diamond 3.12 or greater.

### Tested devices
- [Arty-S7-50](https://projects.digilentinc.com/products/arty-s7-50)

-- ###############################################################################
-- # [ hyperram_tester_tb - Memory checker test bench
-- # =============================================================================
-- # Runs the memory checker and sets the led state. Observe the led signal for 
-- # test results.
-- # 
-- # Dependencies:
-- # The HyperRam simulation model file "vivado/test/s27kl0641.v" is required to 
-- # be downloaded from:
-- # https://www.infineon.com/dgdl/Infineon-S27KL0641_S27KS0641_VERILOG-Simulation
-- # Models-v05_00-EN.zip?fileId=8ac78c8c7d0d8da4017d0f6349a14f68
-- ###############################################################################
-- # Copyright (c) 2023 picoLemon
-- # 
-- # Permission is hereby granted, free of charge, to any person obtaining a copy
-- # of this software and associated documentation files (the "Software"), to deal
-- # in the Software without restriction, including without limitation the rights
-- # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- # copies of the Software, and to permit persons to whom the Software is
-- # furnished to do so, subject to the following conditions:
-- # 
-- # The above copyright notice and this permission notice shall be included in all
-- # copies or substantial portions of the Software.
-- # 
-- # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- # LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- # OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- # SOFTWARE.
-- ###############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity hyperram_tester_tb is
end hyperram_tester_tb;

architecture hyperram_tester_tb_rtl of hyperram_tester_tb is

    constant f_clock_c               : natural := 100000000; -- main clock in Hz
    constant t_clock_c        : time := (1 sec) / f_clock_c;
    constant baud0_rate_c            : natural := 921600; -- simulation UART0 (primary UART) baud rate
    constant uart0_baud_val_c : real := real(f_clock_c) / real(baud0_rate_c);
    
    -- external board clock
    signal clk_i : std_logic := '0';    
    
    -- reset logic	
	signal resetn : std_logic;  

    -- clocks
    signal clk_sys : std_ulogic;    
    
    -- HyperRAM device
    signal hrd_resetn   : std_ulogic;
    signal hrd_csn      : std_ulogic;
    signal hrd_ck       : std_ulogic;
    signal hrd_rwds     : std_ulogic;
    signal hrd_dq       : std_ulogic_vector(7 downto 0);
    
    -- UART0
    signal uart0_txd : std_ulogic; -- UART0 send data

    -- Debug
    signal led           : std_ulogic;

begin

    -- Simulated ram device
    -- NOTE: Download dependency model (see top) and place inside vivado/test
    hyperram_i : entity s27kl0641		
        port map (
         DQ7      => hrd_dq(7),
         DQ6      => hrd_dq(6),
         DQ5      => hrd_dq(5),
         DQ4      => hrd_dq(4),
         DQ3      => hrd_dq(3),
         DQ2      => hrd_dq(2),
         DQ1      => hrd_dq(1),
         DQ0      => hrd_dq(0),
         RWDS     => hrd_rwds,
         CSNeg    => hrd_csn,
         CK       => hrd_ck,         
         RESETNeg => hrd_resetn
      ); 
      
      
    -- onboard sys clock generator
    clk_i <= not clk_i after (t_clock_c/2);

    -- design clock generators
    clock_i: entity work.clocks 
    port map(     
        clk_i => clk_i,    
        clk_sys_o => clk_sys
     );
     
    -- reset device
    reset_i: entity work.reset 
    port map(     
        clk_i => clk_sys,    
        resetn_o => resetn
     );
    
    -- mem checker main instance
    hyerram_test_top_i: entity work.simple_memory_check
      port map (    
        clk_sys_i       => clk_sys,       
        resetn_i        => resetn,       
        hrd_resetn_o    => hrd_resetn,
        hrd_csn_o       => hrd_csn,
        hrd_ck_o        => hrd_ck,
        hrd_rwds_io     => hrd_rwds,
        hrd_dq_io       => hrd_dq,
        led_o           => led,        
        uart0_txd_o     => uart0_txd
      );

    -- test main
    test_runner : process		
		variable DEBUG_ID : natural := 0;
	begin
		report "[BEGIN]Test";
		
		-- wait for led change to signal completion.
		wait until led = '1';

		report "[END]Test";
	end process;
	
end hyperram_tester_tb_rtl;
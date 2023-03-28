-- ###############################################################################
-- # [ top - memory checker top ]
-- # =============================================================================
-- # Runs the memory checker and sets the led state. Observe the led signal for 
-- # test results.
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

entity top is
  port (
    -- Global control
    clk_i       : in  std_ulogic; -- global fabric clock

    -- HyperRAM device interface
    hr_resetn   : out   std_ulogic;
	hr_ck       : out   std_ulogic;	
    hr_csn      : out   std_ulogic;    
    hr_rwds     : inout std_ulogic;
    hr_dq       : inout std_ulogic_vector(7 downto 0);

    -- Uart debug output
    uart0_txd_o : out std_ulogic; -- UART0 send data    

    -- Output leds to board
    led : out std_ulogic
  );
end entity;

architecture top_rtl of top is

    -- reset logic
	signal resetn : std_logic;    -- init reset for root devices

    -- clocks
    signal clk_sys : std_ulogic;    
    
begin    

    -- Memory checker, runs memory check and sets feedback on led
    memory_check_inst : entity work.simple_memory_check 
	generic map(
		CLOCKFREQ => 48000000
	)
    port map(     
        clk_sys_i => clk_sys,    
        resetn_i => resetn,           
        hrd_resetn_o => hrctl_resetn,        
        hrd_ck_o => hrctl_ck,
        hrd_ckn_o => hrctl_ckn,
		hrd_csn_o => hr1_csn,
        hrd_rwds_io => hr1_rwds,
        hrd_dq_io => hr1_dq,    
        uart0_txd_o => uart0_txd_o, 
        led_o => led
     );


    -- reset device on startup
    reset_inst : entity work.reset 
    port map(     
        clk_i => clk_i,    
        resetn_o => resetn
     );
     
     
    -- clock generation, provides clock from external clock input 
    clock_inst : entity work.clocks 
    port map(     
        clk_i => clk_i,    
        clk_sys_o => clk_sys
     );
     
     
end architecture;

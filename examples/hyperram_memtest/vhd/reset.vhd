-- ###############################################################################
-- # [ reset - Reset generator ]
-- # =============================================================================
-- # Creates reset signals from the initial system state.
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
 
entity reset is
port(
	-- Inputs
	clk_i              : in std_ulogic;     -- sytem clock
	resetn_o :          out std_ulogic        -- reset active-low
);	
	
end entity;
 
architecture a of reset is
	signal rst : std_logic := '0';    -- init reset for root devices
	signal init_rst : std_logic := '1';  -- main reset
begin   
  
	-- main reset process
    process(clk_i) is	
    begin
        if rising_edge(clk_i) then
        
            -- set reset hi on first clock, initialized value set to 1
            if init_rst = '1' then
                init_rst <= '0';                
                rst <= '1'; 	            
            end if;		

        end if;
        
        resetn_o <= rst; 
        
    end process;
    
end architecture;
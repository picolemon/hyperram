-- ###############################################################################
-- # [ uart_tx - UART transmitter
-- # =========================================================================== #
-- # Sends a single byte over UART wire to serial port for debug purposes.
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
 
entity uart_tx is
  generic (
    BAUD : natural;  		-- Baud rate eg. 19200
    FREQ: natural			-- Frequency of clk_i to calculate correct timings.
);
port(
	-- Inputs
	clk_i                      : in std_ulogic; -- sytem clock
	resetn_i                   : in std_ulogic; -- device reset, active low
    tx_data_i                    : in std_ulogic_vector(7 downto 0);  -- byte to send
    tx_en_i                   : in std_ulogic; -- strobe to send data   
	
	-- Outputs
	tx_busy_o                    : out std_ulogic; -- busy sending indicator	
	tx_o                         : out std_ulogic; -- UART tx signal
	tx_sent_o                    : out std_ulogic := '0' -- send complete strobe	
);	
	
end entity;
 
architecture a of uart_tx is
    constant cycles_per_bit : natural :=  FREQ / BAUD;  
begin     
    main : process(clk_i) is        
		type TxState_t is (Idle, SendingData);
		variable tx_state : TxState_t := Idle;
		variable latch_tx_data : std_ulogic_vector(9 downto 0);  -- serial data [start][data 0-7][stop]
		variable tx_index : natural range 0 to latch_tx_data'length-1 := 0;
		variable tx_bit_counter : natural range 0 to cycles_per_bit-1 := 0;
    begin
		
		if rising_edge(clk_i) then
			if resetn_i = '0' then
				-- setup tx to high ( non xmit )
				tx_o <= '1';
				tx_busy_o <= '0';

			else
				tx_o <= '0';
				
				-- tx state machine
				case tx_state is
					when Idle =>
						-- reset tx to non-sending
						tx_o <= '1';			
						tx_busy_o <= '0';						
				
						-- wait for tx ready
						if tx_en_i = '1' then
						
							tx_busy_o <= '1';			
							
							-- reset bit index
							tx_index := 0;
							
							-- assign data with stopbit ( msb ) data and start bit ( lsb )
							latch_tx_data := '1' & tx_data_i & '0';

							-- reset bit counter
							tx_bit_counter := 0;
							
							-- clear state
							tx_sent_o <= '0';
							
							-- set state
							tx_state := SendingData;
							
						end if;
				
					when SendingData =>
					
						-- set current bit
						tx_o <= latch_tx_data(0);
						tx_busy_o <= '1';
						
						-- wait for next bit
						if tx_bit_counter = cycles_per_bit - 1 then
						
							-- check end of data
							if tx_index = latch_tx_data'length-1 then
								tx_state := Idle;
								
								-- notify sender
								tx_sent_o <= '1';
							else
								tx_index := tx_index + 1;
							end if;
						
							-- load next bit
							latch_tx_data := '0' & latch_tx_data( latch_tx_data'left downto 1 );

							-- reset bit counter
							tx_bit_counter := 0;						
						
						else
							tx_bit_counter := tx_bit_counter + 1;
						end if;
				end case;				
				  
			end if;
		end if;
    end process;
end architecture;
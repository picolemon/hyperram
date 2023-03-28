-- ###############################################################################
-- # [ simple_memory_check - Memory checker
-- # =========================================================================== #
-- # Very simple memory checker, writes a pattern into memory and reads back.
-- # The results are presented via an a solid led for success and flashing for fail.
-- # The UART output will generate 1 for success and 0 for failure if attached.
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
		
entity simple_memory_check is
  generic(
    CLOCKFREQ : natural := 100000000  -- default 100 Mhz clock
  );
  port (
    -- Global control --            
    clk_sys_i : in std_ulogic;    
    resetn_i : in std_ulogic;
    
    -- HyperRAM device interface
    hrd_resetn_o   : out   std_ulogic;
    hrd_csn_o      : out   std_ulogic;
    hrd_ck_o       : out   std_ulogic;
    hrd_ckn_o       : out   std_ulogic;
    hrd_rwds_io     : inout std_ulogic;
    hrd_dq_io       : inout std_ulogic_vector(7 downto 0);

    -- UART0
    uart0_txd_o : out std_ulogic; -- UART0 send data
    
    -- Debug led
    led_o : out std_ulogic	
  );
end entity;

architecture a of simple_memory_check is
    signal hr_addr : std_ulogic_vector(31 downto 0); -- address
	signal hr_wdata : std_ulogic_vector(31 downto 0); -- write data
	signal hr_rdata : std_ulogic_vector(31 downto 0); -- read data	
	signal hr_we : std_ulogic; -- write enable
	signal hr_sel : std_ulogic_vector(03 downto 0); -- byte enable
	signal hr_stb : std_ulogic; -- strobe
	signal hr_cyc : std_ulogic; -- valid cycle
	signal hr_ack : std_ulogic; -- transfer acknowledge
	signal hr_err : std_ulogic; -- transfer error
	signal hr_busy : std_ulogic; -- transfer error
	signal hr_tag : std_ulogic_vector(02 downto 0); -- request tag

    -- uart state
    signal tx_data : std_ulogic_vector(7 downto 0) := "00000000";
    signal tx_en : std_ulogic := '0';
    signal tx_busy : std_ulogic := '0';
    
    -- test state
	type TestState_t is (Init, WriteOne, WaitWrite, Readback, WaitRead, TestSuccess, TestFail, Idle );
    signal testState : TestState_t;		        
    signal counter : unsigned(24 downto 0) := (others=>'0');
    signal test_success : std_ulogic := '0';     
    signal led_flash : std_ulogic := '0';     
begin
	
    -- Main test state machine
    testmain_inst : process(clk_sys_i)            
    begin
        if rising_edge(clk_sys_i) then		
        
          if resetn_i = '0' then -- reset
            testState <= Init;
            
            hr_addr <= (others=>'0');
            hr_rdata <= (others=>'0');            
			hr_we <= '0';
			hr_sel <= (others=>'0');
			hr_stb <= '0';
			hr_cyc <= '0';
			hr_tag <= (others=>'0');	
			tx_data <= (others=>'0');	
            tx_en <= '0';    	
            counter <= (others=>'0');

            led_flash <= '0';
            
          else
          
            -- defaults
            hr_cyc <= '0';
            hr_stb <= '0';
            hr_we <= '0';
            hr_rdata <= (others=>'0');
            tx_en <= '0';    
            
            -- led counter
            counter <= counter + 1;	
            
            -- test state machine
            case testState is
                when Init =>
                    -- wait for ram ready
                    if hr_err = '1' then
                         testState <= TestFail;
                                             
                    elsif hr_busy = '0' then
                        testState <= WriteOne;                                                
                   end if;
				   
				   if counter > 240000 then
						testState <= TestFail;
				   end if;
				   
                when WriteOne =>
                
                    -- start write transaction
                    hr_cyc <= '1';
                    hr_stb <= '1';
                    hr_we <= '1';
                    hr_addr <= x"00000000";
                    hr_rdata <= x"deadb00f"; -- pattern to write
                    hr_sel <= (others=>'1');
                    
                    testState <= WaitWrite;
                    
                when WaitWrite =>
                    
                    -- wait for write ack
                    if hr_ack = '1' then
                        testState <= ReadBack;                    
                    end if;                  
                    
                when ReadBack =>
                
                    -- start read transaction
                    hr_cyc <= '1';
                    hr_stb <= '1';
                    hr_we <= '0';
                    hr_addr <= x"00000000";
                    hr_sel <= (others=>'1');
                    
                    testState <= WaitRead;
                
                when WaitRead =>
                    
                    -- check for read errors eg. timeout
                    if hr_err = '1' then

                         testState <= TestFail;
                         
                    elsif hr_ack = '1' then
                        
                        report "Got result ";
                        
                        -- compare result
                        if hr_wdata = x"deadb00f" then -- hardcoded pattern to compare
                        
                            testState <= TestSuccess;
                            
                        else
                        
                            testState <= TestFail;
                                                        
                        end if;
                        
                    end if;
                
                when TestSuccess =>
                 
                    test_success <= '1';
                    led_flash <= '1';
                    
                    -- uart debug write
                    tx_data <= x"31"; -- Write 1[success] to uart
                    tx_en <= '1';        
                
                    report "[SUCESS] Memory test pass";                              
                    testState <= Idle;
                             
                when TestFail =>
                  
                    test_success <= '0';
                    led_flash <= '1';
                    
                    -- uart debug write    
                    tx_data <= x"30"; -- Write 0[fail] to uart
                    tx_en <= '1';
                    
                    report "[SUCESS] Memory test fail";
                
                    testState <= Idle;
                    
                when Idle =>                    
                    if test_success = '1' then                    
                         led_flash <= '1';                         
                    else
                       
                       -- flash led
                       if counter( counter'length-1 ) = '1' then
                            led_flash <= not led_flash;
                       end if;               
                                   
                    end if;                 
            end case;          
          end if;
        end if; 
    end process;    


    -- wire led
    led_o <= led_flash;


	-- Debug UART output
	uart_tx_inst : entity work.uart_tx(a)	 
		generic map (
			BAUD => 921600,		-- Baud
			FREQ => CLOCKFREQ -- Configure clk_sys_i freq 
		)	
	port map(
		clk_i => clk_sys_i,
		resetn_i => resetn_i,
		tx_o => uart0_txd_o,		
		tx_data_i => tx_data,		
		tx_busy_o => tx_busy,
		tx_en_i => tx_en
	);


    -- Ram ctrl instance
    ram_ctrl_inst : entity work.hyperram_ctl(a) 
		port map(
			clk_i => clk_sys_i,
			rstn_i => resetn_i,
			busy_o => hr_busy,
			addr_i => hr_addr,
			wdata_o => hr_wdata,
			rdata_i => hr_rdata,	
			we_i => hr_we,
			sel_i => hr_sel,
			stb_i => hr_stb,
			cyc_i => hr_cyc,
			ack_o => hr_ack,
			err_o => hr_err,
			tag_i => hr_tag,
			hrd_resetn_o => hrd_resetn_o,
			hrd_csn_o => hrd_csn_o,
			hrd_ck_o => hrd_ck_o,
			hrd_ckn_o => hrd_ckn_o,
			hrd_rwds_io => hrd_rwds_io,
			hrd_dq_io => hrd_dq_io
		);
		
		
end architecture;

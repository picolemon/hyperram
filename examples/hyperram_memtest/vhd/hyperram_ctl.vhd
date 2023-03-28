-- ###############################################################################
-- # [ hyperram_ctl - HyperRAM controller ]
-- # =========================================================================== #
-- # Read/write HyperRAM memory using a Wishbone interface.
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

entity hyperram_ctl is
port(
	clk_i : in std_logic; 
	rstn_i : in std_logic; 	
	-- Wishbone bus
	addr_i             : in std_ulogic_vector(31 downto 0); -- address
	wdata_o            : out std_ulogic_vector(31 downto 0); -- write data
	rdata_i            : in std_ulogic_vector(31 downto 0); -- read data	
	we_i               : in std_ulogic; -- write enable
	sel_i              : in std_ulogic_vector(03 downto 0); -- byte enable
	stb_i              : in std_ulogic; -- strobe
	cyc_i              : in std_ulogic; -- valid cycle
	ack_o              : out std_ulogic; -- transfer acknowledge
	err_o              : out std_ulogic; -- transfer error
	tag_i              : in std_ulogic_vector(02 downto 0); -- request tag	
	busy_o             : out std_logic;    -- busy signal during init & operations	
	-- HyperRAM interface
    hrd_resetn_o            : out   std_ulogic;   -- HyperRam reset
    hrd_csn_o               : out   std_ulogic;  -- HyperRam chip select ( active low )
    hrd_ck_o                : out   std_ulogic;  -- HyperRam clock 
    hrd_ckn_o               : out   std_ulogic;  -- HyperRam diff clock 
    hrd_rwds_io             : inout std_ulogic;   -- HyperRam  rwds
    hrd_dq_io               : inout std_ulogic_vector(7 downto 0)   -- HyperRam data bus
    
);	
end entity;
 
architecture a of hyperram_ctl is  
    
    -- main states
    type ReadyState_t is ( Init,
        WaitCtlReset, 
        ReadMfrData0, WaitReadMfrData0, WaitReadMfrData0Delay,        
        InitWriteCSR0, WaitWriteCSR0,        
        Ready,
        WaitRead, WaitWrite);	
    signal readyState : ReadyState_t := Init;	
    
    signal command_delay : natural := 0;
    signal timeout_counter : natural := 1024;

    -- registers
    constant Reg_Configuration0         : std_ulogic_vector(15 downto 0) :=  x"0100"; -- creg 0  CA[31~24]=1, CA[7~0]=0)
    constant Reg_Mfr0                   : std_ulogic_vector(15 downto 0) :=  x"0000"; -- mfr reg 0 
          
    -- config
    constant Config_Reg0             	: std_ulogic_vector(31 downto 0) := x"8f1f0000"; -- safe settings see spec for faster timings
    constant Config_Delay1x         	: std_ulogic_vector(7 downto 0) := x"00"; -- zero as rwds can float during read.
    constant Config_Delay2x         	: std_ulogic_vector(7 downto 0) := x"16"; -- fixed 2x latency
	
	-- wishbone bus access to ctl registers
	constant Wbone_CtlStatus0             	: std_ulogic_vector(31 downto 0) := x"CFFF0000";   -- ctl status reg0 ([wr]reset=31, ctl_was_reset=1) [rw]
	constant Wbone_HrConfiguration0         : std_ulogic_vector(31 downto 0) := x"CFFF0004";   -- Ram Configuration0 [rw]
	constant Wbone_HrDelay0                : std_ulogic_vector(31 downto 0) := x"CFFF0008";   -- Ram Delay0 ( packed delay1x(0-7) delay2x(8-15) [rw]
	constant Wbone_HrMfr0             	    : std_ulogic_vector(31 downto 0) := x"CFFF000C";    -- Ram Mfr0 id [rw]
	constant Wbone_StatReadCnt           	: std_ulogic_vector(31 downto 0) := x"CFFF0010";    -- Read counter stat [rw]
	constant Wbone_StatWriteCnt           	: std_ulogic_vector(31 downto 0) := x"CFFF0014";    -- Write counter stat [rw]
	
	signal ctl_cfg0  : std_ulogic_vector(31 downto 0) := Config_Reg0;	-- cfg0 state		
	signal ctl_mfr0  : std_ulogic_vector(31 downto 0);	-- mfr0 state			
    signal ctl_hr_delay1x : std_ulogic_vector(7 downto 0) := Config_Delay1x;    	
    signal ctl_hr_delay2x : std_ulogic_vector(7 downto 0) := Config_Delay2x;    	
	signal stat_write_cnt : unsigned(31 downto 0) := (others=>'0');
	signal stat_read_cnt : unsigned(31 downto 0) := (others=>'0');
	signal ctl_was_reset : std_ulogic := '0';  -- status notify flag
	
    -- hr main
    signal hr_resetn_i : std_ulogic;    
    signal hr_mem_addr_i : std_ulogic_vector(31 downto 0);	-- memory space address
    signal hr_reg_addr_i : std_ulogic_vector(15 downto 0);	-- register space address
    signal hr_read_req_i : std_ulogic;	-- read request strobe
    signal hr_write_req_i : std_ulogic; -- write request strobe
    signal hr_write_mask_i : std_ulogic_vector(3 downto 0);    -- write mask
    signal hr_data_i : std_ulogic_vector(31 downto 0); -- writing data    
    signal hr_read_dwords_i : unsigned(7 downto 0); -- read dword count          
    signal hr_is_mem_i : std_ulogic; -- memory space flag
    signal hr_is_mem_buff : std_ulogic; -- memory space buff
    signal hr_internal_busy_o : std_ulogic;    -- ram state machine busy                
    signal hr_delay1 : std_ulogic_vector(7 downto 0); -- delay buff
    signal hr_delay2 : std_ulogic_vector(7 downto 0); 
    signal hr_exec : std_ulogic;
    signal hr_en_ddr_clk_phase : unsigned(1 downto 0);      
    signal hr_en_ddrclk : std_ulogic;
    signal hr_en_ddrclk_buff : std_ulogic;
    signal hr_en_addr_shifter : std_ulogic;  
    signal hr_addr_shifter : std_ulogic_vector(47 downto 0);
    signal hr_en_data_shifter : std_ulogic;
    signal hr_data_shifter : std_ulogic_vector(31 downto 0);     
    signal hr_write_en_shifter : std_ulogic_vector(3 downto 0);
    signal hr_rwds_out_buff : std_ulogic;
    type TransactionPhase_t is ( PhaseIdle, PhaseAddr, PhaseDelay, PhaseData );
    signal hr_txnPhase : TransactionPhase_t;
    signal hr_txnPhase_cnt : unsigned(7 downto 0); -- counter for each phase    	  
    signal hr_byte_write_enable : std_ulogic;  
    signal hr_read_complete : std_ulogic;
    signal hr_do_read : std_ulogic;
    signal hr_exec_reader : std_ulogic; 
    signal hr_read_cnt : unsigned(7 downto 0); -- dword read counter
    signal hr_read_data_shifter : std_ulogic_vector(31 downto 0) := (others=>'0');  -- data shifted 1 word each clock                      
    type DDRReadOp_t is ( RDOP_WaitRisingEdge, RDOP_Next1, RDOP_Next2 );      	               
    signal hr_reader_ddr_op : DDRReadOp_t;
    signal hr_read_ready_buff : std_ulogic;
    signal hr_read_data_o : std_ulogic_vector(31 downto 0);    
    signal hr_read_dwords_counter : unsigned(7 downto 0);  
    signal hr_is_write_buff : std_ulogic;  
    
	-- hr buffers
	signal hr_rwds_in_buff : std_ulogic; 
	signal hr_rwds_in_buff2 : std_ulogic; 
	signal hr_ck_buff1 : std_ulogic;
	signal hr_ck_buff2 : std_ulogic;
	signal hr_dq_in_buff : std_ulogic_vector(7 downto 0);  
	signal hr_write_data : std_ulogic_vector(7 downto 0);  
	signal hr_dq_out_buff : std_ulogic_vector(7 downto 0);
    signal hr_csn_o_buff : std_ulogic;
    signal hr_dq_oe_buff : std_ulogic;  
    signal hr_rwds_oe_buff : std_ulogic;       
    signal hr_csn_o_buff2 : std_ulogic;
    
    -- tri state buffers     
    signal hrt_rwds_in           : std_ulogic;
    signal hrt_dq_in             : std_ulogic_vector(7 downto 0);            
    signal hrt_dq_oe             : std_ulogic;    
begin  

    -- wishbone memory transaction process
    mem_access_i: process(clk_i)
    begin
    if rising_edge(clk_i) then	
    	
      if rstn_i = '0' then
      
        wdata_o <= (others=>'0');        
        ack_o <= '0';
        err_o <= '0';
        hr_resetn_i <= '1'; -- reset ctl ( active hi )
        timeout_counter <= 1024; -- init timeout
        busy_o <= '1';

      else -- rst

        hr_read_req_i <= '0';
        hr_write_req_i <= '0';
        hr_is_mem_i <= '1';        

        wdata_o <= (others=>'0');        
        ack_o <= '0';
        err_o <= '0';

        if timeout_counter > 0 then
            timeout_counter <= timeout_counter - 1;
        else
            -- strobe error
            err_o <= '1';

            -- reset device
            readyState <= Init; -- reset ctl + ram
        end if;

        
        -- register access 
        if cyc_i = '1' and stb_i = '1' and we_i = '1' and unsigned(addr_i) >= unsigned(Wbone_CtlStatus0) then -- [REG WRITE], CtlStatus0==Base, end of mem rage

            -- register access
            if addr_i = Wbone_CtlStatus0 then
 
                -- reset trigger
                if rdata_i(31) = '1' then
                    readyState <= Init;
                    ctl_was_reset <= '1';
                end if;
                
                ack_o <= '1';
            elsif addr_i = Wbone_HrConfiguration0 then
                ctl_cfg0 <= rdata_i;
                ack_o <= '1';
            elsif addr_i = Wbone_HrMfr0 then
                ctl_mfr0 <= rdata_i;
                ack_o <= '1';
            elsif addr_i = Wbone_HrDelay0 then
                ctl_hr_delay1x <= rdata_i(7 downto 0);
                ctl_hr_delay2x <= rdata_i(15 downto 8);
                ack_o <= '1';
            elsif addr_i = Wbone_StatReadCnt then
                stat_read_cnt <= unsigned(rdata_i);
                ack_o <= '1';
            elsif addr_i = Wbone_StatWriteCnt then
                stat_write_cnt <= unsigned(rdata_i);
                ack_o <= '1';                
            end if;                

        elsif cyc_i = '1' and stb_i = '1' and  we_i = '0' and unsigned(addr_i) >= unsigned(Wbone_CtlStatus0) then -- [REG READ]
                        
            -- register access
            if addr_i = Wbone_CtlStatus0 then
                
                wdata_o <= (others=>'0');
                if readyState = Ready then
                    wdata_o(0) <= '1'; -- ready bit                    
                end if;
                wdata_o(1) <= ctl_was_reset; -- was reset
                ctl_was_reset <= '0';
                
                ack_o <= '1';
                
            elsif addr_i = Wbone_HrConfiguration0 then
                wdata_o <= ctl_cfg0;
                ack_o <= '1';
            elsif addr_i = Wbone_HrMfr0 then
                wdata_o <= ctl_mfr0; -- Mfr0 data
                ack_o <= '1';    
            elsif addr_i = Wbone_HrDelay0 then
                wdata_o <= x"0000" & ctl_hr_delay2x & ctl_hr_delay1x;
                ack_o <= '1'; 
            elsif addr_i = Wbone_StatReadCnt then
                wdata_o <= std_ulogic_vector(stat_read_cnt);
                ack_o <= '1';              
            elsif addr_i = Wbone_StatWriteCnt then
                wdata_o <= std_ulogic_vector(stat_write_cnt);
                ack_o <= '1';                                            
            end if;
        
        elsif command_delay > 0 then  -- delay
        
             command_delay <= command_delay - 1;
             timeout_counter <= 1024; -- prevent timeout during delays
             
        else
            case readyState is
            when Init =>
                -- put ctl(and ram) into reset
                readyState <= WaitCtlReset;

                hr_resetn_i <= '1'; -- reset ctl ( active hi )        
                command_delay <= (15000*4); -- TODO: add register to configure this
                timeout_counter <= 1024; -- prevent timeout

                -- reset stats
	            stat_write_cnt <= (others=>'0');
	            stat_read_cnt <= (others=>'0');
	
            when WaitCtlReset =>
                
                -- wait for command_delay               
                hr_resetn_i <= '0'; -- reset ctl ( active hi )
                command_delay <= (10000*4);  -- TODO: add register to configure this
                readyState <= InitWriteCSR0;               
                  
                timeout_counter <= 1024; -- prevent timeout                          

            when InitWriteCSR0 =>

                -- write config        
                hr_write_req_i <= '1';
                hr_is_mem_i <= '0'; -- reg                
                hr_reg_addr_i <= Reg_Configuration0;
                hr_write_mask_i <= "0001";
                hr_read_dwords_i <= to_unsigned(1, hr_read_dwords_i'length);                                    
                
                -- setup cf0 reg state
                hr_data_i <= ctl_cfg0;
                
                -- ram timings
                hr_delay1 <= ctl_hr_delay1x;
                hr_delay2 <= ctl_hr_delay2x;           

                readyState <= WaitWriteCSR0;
                command_delay <= 1;                                         
                timeout_counter <= 1024; -- cmd timeout
                
            when WaitWriteCSR0 =>

                -- wait write
                if hr_internal_busy_o = '0' then
                    readyState <= ReadMfrData0;                    
                    command_delay <= 4;
                end if;    
        
            when ReadMfrData0 =>
            
                -- read mfr data
                hr_read_req_i <= '1';
                hr_is_mem_i <= '0'; -- reg                
                hr_reg_addr_i <= Reg_Mfr0;
                hr_write_mask_i <= "0000";
                hr_read_dwords_i <= to_unsigned(2, hr_read_dwords_i'length);                        
                      
                -- wait for read
                readyState <= WaitReadMfrData0;                        
                command_delay <= 1;
    
            when WaitReadMfrData0 =>
            
                if hr_read_ready_buff = '1' then
                    readyState <= WaitReadMfrData0Delay;  
                    command_delay <= 64;
                    
                    ctl_mfr0 <= hr_read_data_o;
                end if;    
                    
            when WaitReadMfrData0Delay =>            
                readyState <= Ready;  
                
            when Ready =>                
                timeout_counter <= 1024; -- no timeout ( default request timeout )
                
                -- clear busy
                busy_o <= '0';
                
                -- check bus request        
                if cyc_i = '1' and stb_i = '1' then
                    
                    if we_i = '1' then -- [WRITE]

                        hr_write_req_i <= '1';                                                                                                                  
                        hr_is_mem_i <= '1'; -- mem                                                                                                      
                        hr_write_mask_i <= sel_i;                                                                                                        
                        hr_read_dwords_i <= to_unsigned(2, hr_read_dwords_i'length);                  
                        hr_mem_addr_i <= x"00" & "00" & addr_i(23 downto 2);  -- addr packed, dword aligned          
                        hr_data_i <= rdata_i; -- data
                        
                        -- control      
                        command_delay <= 1;                    
                        readyState <= WaitWrite;  
                        
                        busy_o <= '1';
                        
                        command_delay <= 1; 
                                               
                    else -- [READ]
                          
                        hr_read_req_i <= '1';
                        hr_is_mem_i <= '1'; -- mem
                        hr_write_mask_i <= "0000";
                        hr_read_dwords_i <= to_unsigned(2, hr_read_dwords_i'length);              
                        hr_mem_addr_i <= x"00" & "00" & addr_i(23 downto 2); -- addr packed, dword aligned
                        
                        -- control      
                        command_delay <= 1;                    
                        readyState <= WaitRead;  

                        busy_o <= '1';
                        
                        command_delay <= 1;
                                                          
                    end if;
                    
                end if;                

            when WaitWrite  =>
            
                if hr_internal_busy_o = '0' then
                    -- control      
                    command_delay <= 1;                    
                    readyState <= Ready;                          
                    ack_o <= '1';
                    
                    stat_write_cnt <= stat_write_cnt + 1;
                    
                end if;       
                            
            when WaitRead =>

                if hr_read_ready_buff = '1' then

                    -- output data to bus                
                    wdata_o <= hr_read_data_o;
     
                    -- control      
                    command_delay <= 1;                    
                    readyState <= Ready;                          
                    ack_o <= '1';                
                    
                    stat_read_cnt <= stat_read_cnt + 1;      
                end if;

            end case;                      
        end if; -- command_delay
      end if; -- rst
    end if; -- rising edge
    end process;
    
    
    -- main ram process
    process (clk_i) is
    begin
    if rising_edge(clk_i) then
    
        -- defaults
        hr_read_ready_buff <= '0';
        hr_read_data_o <= x"00000000";
        hr_exec <= '0';      
        hr_internal_busy_o <= hr_en_ddrclk or hr_exec;
        hr_en_addr_shifter <= '0';
        hr_en_data_shifter <= '0';
      
        -- reset
        if hr_resetn_i = '1' then
            hr_csn_o_buff <= '1'; -- de-select ram
            hr_exec <= '0';
            hr_en_ddrclk <= '0';
            hr_exec_reader <= '0';
            hr_byte_write_enable <= '0';
            hr_csn_o_buff2 <= '0';      
        end if;
        
        -- drive ddr clock
        if hr_en_ddrclk = '1' then
            hr_en_ddr_clk_phase <= hr_en_ddr_clk_phase + "01";
        else
            hr_en_ddr_clk_phase <= "00";
        end if;

        -- buffer output
        hr_ck_buff1 <= hr_en_ddr_clk_phase(1);
        hr_ck_buff2 <= hr_ck_buff1;
        hr_rwds_in_buff <= hrt_rwds_in;
        hr_dq_in_buff <= hrt_dq_in;
        hr_dq_out_buff <= hr_write_data;
        hr_rwds_out_buff <= not hr_byte_write_enable;
        hr_csn_o_buff <= not hr_csn_o_buff2;
        
        -- ddr edge detect
        hr_rwds_in_buff2 <= hr_rwds_in_buff;
        hr_read_complete <= '0';
        hr_do_read <= '0';
        if hr_exec_reader = '1' then
        
            -- detect rising edge of rwds
            if hr_reader_ddr_op = RDOP_WaitRisingEdge then                              
                if  hr_rwds_in_buff2 = '0' and hr_rwds_in_buff = '1' then
                    hr_reader_ddr_op <= RDOP_Next1;
                    hr_do_read <= '1';
                end if;
            
            else            
                -- wait + 2 cycles & sample on rwds low ( idealy should sample this )
                if hr_reader_ddr_op = RDOP_Next2 then
                    hr_reader_ddr_op <= RDOP_WaitRisingEdge;
                    hr_do_read <= '1';
                else
                    hr_reader_ddr_op <= RDOP_Next2;
                end if;                                            
            end if;

        else -- reset state when not reading
            hr_read_cnt <= X"00";            
            hr_reader_ddr_op <= RDOP_WaitRisingEdge;
        end if;
        
        -- sample on both edges
        if hr_do_read = '1' then
            
            -- handle completion, max 32 bit wide wishbone bus
            hr_read_cnt <= hr_read_cnt + X"01";
            if hr_read_cnt = X"03" then
                
                hr_read_cnt <= X"00";
                
                -- flag complete next clk
                hr_read_complete <= '1';
            end if;
            
            -- sample into shifter
            hr_read_data_shifter <= hr_read_data_shifter(23 downto 0) & hr_dq_in_buff;
        end if;
        
        -- handle read completion
        if hr_read_complete = '1' then
            hr_read_data_o <= hr_read_data_shifter;
            hr_read_ready_buff <= '1';
            
            if hr_read_dwords_counter = 1 then
                hr_en_ddrclk <= '0';
                hr_exec_reader <= '0';
            else            
                hr_read_dwords_counter <= hr_read_dwords_counter - 1;
            end if;
                    
        end if;         
           
        -- address shifter
        if hr_en_addr_shifter = '1' then
            hr_addr_shifter <= hr_addr_shifter(39 downto 0) & X"00";
        end if;
    
        -- data shifter
        if hr_en_data_shifter = '1' then
            -- shift write enable
            hr_write_en_shifter <= hr_write_en_shifter(2 downto 0) & '0';
            -- shift data
            hr_data_shifter <= hr_data_shifter(23 downto 0) & X"00";
        end if;
   
        -- bus exec control
        if ((hr_read_req_i = '1' or hr_write_req_i = '1') and hr_exec = '0') then
        
            -- begin transaction
            hr_exec <= '1';
            hr_internal_busy_o <= '1';        
    
             -- capture address        
            hr_addr_shifter <= (others=>'0');
            hr_addr_shifter(45) <= '1';
            hr_addr_shifter(46) <= '0';  -- AS=0 memory space
            if hr_is_mem_i = '0' then  -- AS=1 reg space
                hr_addr_shifter(46) <= '1';
            end if;
            
            hr_addr_shifter(47) <= hr_read_req_i;    -- rw transaction, 1 = read transaction, 0 for write. etc        
                         
            -- map address space from wishbone 32bit 
            if hr_is_mem_i = '0' then                                
                -- Reg access mapped   CA[31~24]=1, CA[7~0]=0)
                hr_addr_shifter(31 downto 24) <= hr_reg_addr_i(15 downto 8);
                hr_addr_shifter(7 downto 0) <= hr_reg_addr_i(7 downto 0);                        
            else
                -- Mem access
                hr_addr_shifter(44 downto 16) <= hr_mem_addr_i(30 downto 2);  -- row & upper col addr
                hr_addr_shifter(2 downto 0) <= hr_mem_addr_i(1 downto 0) & '0';  -- lower Column address, round to 2 bytes.            
            end if;
                           
            -- capture data 
            hr_data_shifter <= hr_data_i;
            -- cature write mask        
            hr_write_en_shifter <= hr_write_mask_i;
            
            -- capture rw bits
            hr_is_write_buff <= hr_write_req_i;
            hr_is_mem_buff <= hr_is_mem_i;              
            
            -- capture read count
            hr_read_dwords_counter <= hr_read_dwords_i;
                       
        end if;             

      -- exec fixup
      if hr_exec = '1' then
      
        -- enable fake ddr clock
        hr_en_ddrclk <= '1';
        hr_dq_oe_buff <= '0';
        hr_rwds_oe_buff <= '0';
              
        hr_txnPhase <= PhaseAddr;
        hr_txnPhase_cnt <= to_unsigned(6, hr_txnPhase_cnt'length); 
        
      end if;
      
      -- ddr low phase ( 1 clk before high )      
      if hr_en_ddr_clk_phase(0) = '1' then
      
        -- transaction phases
        case hr_txnPhase is
        when PhaseAddr =>
            -- enable data output & rwds input
            hr_dq_oe_buff <= '1';
            hr_rwds_oe_buff <= '0';
            hr_byte_write_enable <= '0';
            
            -- sample address & shift next
            hr_write_data <= hr_addr_shifter(47 downto 40);
            hr_en_addr_shifter <= '1';
                      
            hr_txnPhase_cnt <= hr_txnPhase_cnt - "001";
            
            -- wait for end of address ( 3 ddr clk cycles )
            if hr_txnPhase_cnt = 1 then
            
                -- Check for no-delay reg write
                if hr_is_write_buff = '1' and hr_is_mem_buff = '0' then
                    hr_txnPhase <= PhaseData;
                    hr_txnPhase_cnt <= to_unsigned(2, hr_txnPhase_cnt'length); -- max
                else
                                
                    -- check rwds for latency mode, ram can signal to extend transaction during refresh
                    -- NOTE: when using fixed this can line float as is not driven by ram device and can cause bad timings.
                    if hr_rwds_in_buff = '0' then
                        hr_txnPhase_cnt <= unsigned(hr_delay1);
                    else
                        hr_txnPhase_cnt <= unsigned(hr_delay2);
                    end if;
                    
                    hr_txnPhase <= PhaseDelay;
                end if;                
                
                -- check for read and enable reader
                if hr_is_write_buff = '0' then
                    hr_txnPhase <= PhaseDelay;
                    hr_txnPhase_cnt <= to_unsigned(255, hr_txnPhase_cnt'length); -- max
                    hr_exec_reader <= '1';
                end if;                                          
            end if;
                          
        when PhaseDelay =>
        
            -- disable output
            hr_byte_write_enable <= '0';
        
            -- wait for delay cycles
            hr_txnPhase_cnt <= hr_txnPhase_cnt - 1;
            if hr_txnPhase_cnt = 1 then
                hr_txnPhase <= PhaseData;
                hr_txnPhase_cnt <= to_unsigned(4, hr_txnPhase_cnt'length); -- 2x dword
            end if;
            
            -- dq & rwds output
            hr_dq_oe_buff <= hr_is_write_buff;
            hr_rwds_oe_buff <= hr_is_write_buff;
            
        when PhaseData =>
            
            -- enable data output and shift write mask
            hr_en_data_shifter <= '1';
            hr_write_data <= hr_data_shifter(31 downto 24);
            hr_byte_write_enable <= hr_write_en_shifter(3);            
                      
            -- wait data
            hr_txnPhase_cnt <= hr_txnPhase_cnt - 1;
            if hr_txnPhase_cnt = 1 then
                -- disable ddr clk on last dword
                hr_en_ddrclk <= '0';
                hr_txnPhase <= PhaseIdle;
            end if;
                           
            -- dq & rwds output
            hr_dq_oe_buff <= hr_is_write_buff;
            hr_rwds_oe_buff <= hr_is_write_buff;
            
        when PhaseIdle =>            
        end case;

      end if;
	  
	  -- cs buffering
      hr_en_ddrclk_buff <= hr_en_ddrclk;     
      if hr_en_ddrclk = '1' then
        -- enable when ddr clk active
        hr_csn_o_buff2 <= '1';        
      else      
        -- disable cs on no ddr clk
        if hr_en_ddrclk_buff = '0' then
            hr_csn_o_buff2 <= '0';
        end if;              
      end if;
                      
    end if; -- clk
    end process;
  
    -- wirings
    hrd_resetn_o <= not hr_resetn_i;    
    hrd_csn_o <= hr_csn_o_buff;    
    hrd_ck_o <= hr_ck_buff2;            
    hrd_ckn_o <= not hr_ck_buff2;            
    hrt_dq_oe <= hr_dq_oe_buff;    

    -- tristate buffering ram bi-directional hyperbus    
    hrd_rwds_io     <= hr_rwds_out_buff when hr_rwds_oe_buff = '1' else 'Z';
    hrd_dq_io       <= hr_dq_out_buff when hrt_dq_oe = '1' else (others => 'Z'); 
    hrt_rwds_in     <= hrd_rwds_io;
    hrt_dq_in       <= hrd_dq_io;   
  	
end architecture;
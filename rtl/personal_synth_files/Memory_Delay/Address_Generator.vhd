library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity Address_Generator is
  Port ( 
    clk           : in  std_logic;
    go            : in  std_logic;
    rst           : in  std_logic;
    stall         : in  std_logic;
    dram_ready    : in  std_logic;
    size          : in  std_logic_vector(16 downto 0);
    start_address : in  std_logic_vector(14 downto 0);
    wr_rst_busy   : in  std_logic;
    delay_ack     : out  std_logic;
    done_gen          : out std_logic := '0';
    debug_size    : out std_logic_vector(16 downto 0);
    dram_rd_addr  : out std_logic_vector(14 downto 0);
    debug_start   : out std_logic_vector(14 downto 0);
    dram_rd_en    : out std_logic
  );
end Address_Generator;

architecture Behavioral of Address_Generator is

    type state_type is (Initial, Counting, Done);

    -- state reg + next-state
    signal state, next_state : state_type;

    -- burst size after edge-case fix
    signal size_out, next_size_out   : std_logic_vector(16 downto 0);
    signal actual_size               : std_logic_vector(16 downto 0);

    -- start address (latched on go)
    signal start_address_out, next_start_address_out : std_logic_vector(14 downto 0);

    -- current burst address
    signal current_address, next_current_address     : std_logic_vector(14 downto 0);

begin

    -- debug & addr outputs from regs
    debug_size   <= size_out;
    debug_start  <= start_address_out;
    dram_rd_addr <= current_address;

   
    process(clk, rst)
    begin
        if rst = '1' then
            state             <= Initial;
            size_out          <= (others => '0');
            start_address_out <= (others => '0');
            current_address   <= (others => '0');
        elsif rising_edge(clk) then
            state             <= next_state;
            size_out          <= next_size_out;
            start_address_out <= next_start_address_out;
            current_address   <= next_current_address;
        end if;
    end process;

    ------------------------------------------------------------------------
    -- 2) COMBINATIONAL PROCESS: next-state + outputs
    ------------------------------------------------------------------------
    process(state, go, stall, dram_ready,
            size_out, actual_size,
            start_address, start_address_out,
            current_address,wr_rst_busy)
    begin
        -- defaults (hold values)
        next_state             <= state;
        next_size_out          <= size_out;
        next_start_address_out <= start_address_out;
        next_current_address   <= current_address;
        dram_rd_en             <= '0';  -- default: no read

        case state is

            ----------------------------------------------------------------
            -- Initial: wait for 'go' to start a new burst
            ----------------------------------------------------------------
            when Initial =>
                delay_ack <= '0';
                next_current_address <= (others => '0');

                if go = '1' then
                    delay_ack <= '1';
                    next_size_out          <= actual_size;
                    next_start_address_out <= start_address;
                    next_current_address   <= start_address;  -- first addr
                    next_state             <= Counting;
                end if;

            ----------------------------------------------------------------
            -- Counting: generate addresses, obey stall & dram_ready
            ----------------------------------------------------------------
            when Counting =>
                done_gen <= '0';
                delay_ack <= '1';
                if (stall = '0') and (dram_ready = '1')and (wr_rst_busy = '0') then
                    -- active read cycle this clk
                    dram_rd_en <= '1';

                    -- determine if this is the last address
                    if  to_integer(unsigned(current_address)) =
                        to_integer(unsigned(start_address_out)) +
                        to_integer(unsigned(size_out)) - 1 then
                        next_state <= Done;
                    else
                        next_current_address <= std_logic_vector(
                            unsigned(current_address) + 1
                        );
                    end if;
                else
                    -- stall or dram not ready: hold addr, no enable
                    dram_rd_en <= '0';
                end if;

            ----------------------------------------------------------------
            -- Done: burst finished; wait for 'go' to drop before next burst
            ----------------------------------------------------------------
            when Done =>
                done_gen <= '1';
                delay_ack <= '1';
                dram_rd_en <= '0';

                if go = '0' then
                    next_state <= Initial;
                end if;

            when others =>
                next_state <= Initial;

        end case;
    end process;

  
    process(size)
    begin
        actual_size <= size;  -- default
        if to_integer(unsigned(size)) = 1 then
            actual_size <= std_logic_vector(to_unsigned(2, 17));
        elsif to_integer(unsigned(size)) = 0 then
            actual_size <= std_logic_vector(to_unsigned(1, 17));
        end if;
    end process;

end Behavioral;




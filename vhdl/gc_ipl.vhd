-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

library ieee;
use ieee.std_logic_1164.all;

entity gc_ipl is
    port (
        exi_miso : out std_logic_vector(1 downto 0);
        exi_mosi : in std_logic;
        exi_cs : in std_logic;
        exi_clk : in std_logic;

		  led_pth : out std_logic;
		  led_dis : out std_logic;

        f_miso : in std_logic;
        f_mosi : out std_logic;
        f_cs : out std_logic
    );
end gc_ipl;

architecture Behavioral of gc_ipl is
    type state_t is (
        translate,
        passthrough_wait,
        passthrough,
        ignore_wait,
        ignore,
		  qoob_wait,
        disable
    );
    signal state : state_t;
	 signal old_state : state_t;
	 
    signal outbuf : std_logic_vector(5 downto 0);
    signal zero : std_logic;
    signal bits : integer range 0 to 40;
begin
    f_cs <= exi_cs when (state = translate or state = passthrough) else '1';
    f_mosi <= outbuf(5) when state = translate else exi_mosi;
    exi_miso <= (others => f_miso) when (state /= ignore and state /= disable and state /= qoob_wait and exi_cs = '0') else (others => 'Z');

	 led_pth <= '1' when state = passthrough else '0';
	 led_dis <= '1' when state = disable else '0';

    process (exi_cs, exi_clk, state)
    begin
        if exi_cs = '1' then
            if (state /= disable) then
                state <= translate;
            end if;
            outbuf <= (others => '0');
            zero <= '0';
            bits <= 0;
        elsif rising_edge(exi_clk) then
				if bits < 40 then
					bits <= (bits + 1);
				end if;
				zero <= zero or exi_mosi;
            case state is
                when translate | passthrough_wait | ignore_wait =>
                    outbuf <= outbuf(4 downto 0) & exi_mosi;
                    case bits is
                        when 0 =>
                            outbuf(0) <= '1';
                            -- When writing, temporarily deselect flash
                            -- It will be reselected later on, so that raw commands can be issued
                            if exi_mosi = '1' then
                                state <= passthrough_wait;
                            end if;

                        when 1 =>
									-- When getting 0xcXXXXXXX await disable 
									 if exi_mosi = '1' then
										old_state <= ignore;
										state <= qoob_wait;
										zero <= '0';
									 else
										outbuf(0) <= '1';
									 end if;
                        when 2 | 3 =>
                            -- Flash is 2048KB, no point in overriding accesses higher than that
                            if exi_mosi = '1' then
                                state <= ignore_wait;
                            end if;

                        when 15 =>
                            -- Ignore reads below 0x800, we don't provide a BS1
                            if (zero = '0') then
                                state <= ignore;
                            end if;

                        when 26 =>
                            if state = ignore_wait then
                                state <= ignore;
                            end if;
									 
                        when 31 =>
									state <= passthrough;
                        when others =>
									null;
                    end case;
					when qoob_wait =>				
						case bits is 
							when 37 | 38 =>
								if (exi_mosi /= '1') and (old_state = ignore) then
									state <= old_state;
								elsif (exi_mosi /= '0') and (old_state = disable) then
									state <= old_state;
								end if;
							when 39 => 
								if (exi_mosi = '0') and (old_state = ignore) then
									state <= disable;
								elsif (exi_mosi = '1') and (old_state = disable) then
									state <= ignore;
								end if;
							when 40 =>
								state <= old_state;
							when others =>
								if zero /= '0' then
									state <= old_state;
								end if;
						end case;
                when passthrough =>
                    null;
					 when ignore =>
						null;
                when disable =>
						case bits is
							when 0 => 
								if exi_mosi /= '1' then 
									bits <= 2;	-- skip execution of 'when 1'
								end if;
							when 1 =>
								if exi_mosi = '1' then
									zero <= '0';
									old_state <= disable;
									state <= qoob_wait;
								end if;
							when others =>
								null;
						end case;
                    null;
            end case;
        end if;
    end process;
end Behavioral;

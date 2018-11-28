-- Copyright 2018 Delft University of Technology
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.axi_tb_pkg.all;
use work.StreamSim.all;

-- This simulation-only unit represents an AXI-lite master, controllable
-- through the procedures and functions available in axi_tb.

entity axi_tb_lite_master is
  generic (

    -- AXI bus metrics.
    ADDRESS_WIDTH               : natural := 32;
    DATA_WIDTH                  : natural := 32;

    -- Name of this master.
    NAME                        : string

  );
  port (
    clk                         : in  std_logic;
    reset_n                     : in  std_logic;

    m_axil_awvalid              : out std_logic;
    m_axil_awready              : in  std_logic := '0';
    m_axil_awaddr               : out std_logic_vector(ADDRESS_WIDTH-1 downto 0);

    m_axil_wvalid               : out std_logic;
    m_axil_wready               : in  std_logic := '0';
    m_axil_wdata                : out std_logic_vector(DATA_WIDTH-1 downto 0);
    m_axil_wstrb                : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);

    m_axil_bvalid               : in  std_logic := '0';
    m_axil_bready               : out std_logic;
    m_axil_bresp                : in  std_logic_vector(1 downto 0) := (others => '1');

    m_axil_arvalid              : out std_logic;
    m_axil_arready              : in  std_logic;
    m_axil_araddr               : out std_logic_vector(ADDRESS_WIDTH-1 downto 0);

    m_axil_rvalid               : in  std_logic := '0';
    m_axil_rready               : out std_logic;
    m_axil_rdata                : in  std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
    m_axil_rresp                : in  std_logic_vector(1 downto 0) := (others => '1')
  );
end axi_tb_lite_master;

architecture Behavioral of axi_tb_lite_master is
  signal m_axil_awvalid_s       : std_logic;
  signal m_axil_wvalid_s        : std_logic;
  signal m_axil_bready_s        : std_logic;
  signal m_axil_arvalid_s       : std_logic;
  signal m_axil_rready_s        : std_logic;
begin

  write_proc: process (clk) is
    variable m_axil_awvalid_v   : std_logic;
    variable m_axil_wvalid_v    : std_logic;
    variable m_axil_bready_v    : std_logic;
    variable ok                 : boolean;
    variable data               : std_logic_vector(m_axil_awaddr'length + m_axil_wdata'length + m_axil_wstrb'length - 1 downto 0);
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        m_axil_awvalid_s <= '0';
        m_axil_awaddr    <= (others => 'U');
        m_axil_wvalid_s  <= '0';
        m_axil_wdata     <= (others => 'U');
        m_axil_wstrb     <= (others => 'U');
        m_axil_bready_s  <= '0';
      else
        m_axil_awvalid_v := m_axil_awvalid_s;
        m_axil_wvalid_v  := m_axil_wvalid_s;
        m_axil_bready_v  := m_axil_bready_s;

        -- Write address handshake.
        if m_axil_awvalid_v = '1' then
          if is_X(m_axil_awready) then
            stream_tb_fail("awready is X during handshake for " & NAME);
          elsif to_X01(m_axil_awready) = '1' then
            m_axil_awvalid_v := '0';
          end if;
        end if;

        -- Write data handshake.
        if m_axil_wvalid_v = '1' then
          if is_X(m_axil_wready) then
            stream_tb_fail("wready is X during handshake for " & NAME);
          elsif to_X01(m_axil_wready) = '1' then
            m_axil_wvalid_v := '0';
          end if;
        end if;

        -- Write response handshake.
        if m_axil_bready_v = '1' then
          if is_X(m_axil_bvalid) then
            stream_tb_fail("bvalid is X during handshake for " & NAME);
          elsif to_X01(m_axil_bvalid) = '1' then
            stream_tb_push(NAME & "_b", m_axil_bresp);
            m_axil_bready_v := '0';
          end if;
        end if;

        -- Look for new write data.
        if m_axil_awvalid_v = '0' and m_axil_wvalid_v = '0' and m_axil_bready_v = '0' then
          stream_tb_pop(NAME & "_aw", data, ok);
          if ok then
            m_axil_awaddr    <= data(data'length-1 downto data'length-m_axil_awaddr'length);
            m_axil_wdata     <= data(m_axil_wstrb'length+m_axil_wdata'length-1 downto m_axil_wstrb'length);
            m_axil_wstrb     <= data(m_axil_wstrb'length-1 downto 0);
            m_axil_awvalid_v := '1';
            m_axil_wvalid_v  := '1';
            m_axil_bready_v  := '1';
          end if;
        end if;

        m_axil_awvalid_s <= m_axil_awvalid_v;
        m_axil_wvalid_s  <= m_axil_wvalid_v;
        m_axil_bready_s  <= m_axil_bready_v;
      end if;
    end if;
  end process;

  read_proc: process (clk) is
    variable m_axil_arvalid_v   : std_logic;
    variable m_axil_rready_v    : std_logic;
    variable ok                 : boolean;
    variable data               : std_logic_vector(m_axil_araddr'length - 1 downto 0);
  begin
    if rising_edge(clk) then
      if reset_n = '0' then
        m_axil_arvalid_s <= '0';
        m_axil_araddr    <= (others => 'U');
        m_axil_rready_s  <= '0';
      else
        m_axil_arvalid_v := m_axil_arvalid_s;
        m_axil_rready_v  := m_axil_rready_s;

        -- Read address handshake.
        if m_axil_arvalid_v = '1' then
          if is_X(m_axil_arready) then
            stream_tb_fail("arready is X during handshake for " & NAME);
          elsif to_X01(m_axil_arready) = '1' then
            m_axil_arvalid_v := '0';
          end if;
        end if;

        -- Read response handshake.
        if m_axil_rready_v = '1' then
          if is_X(m_axil_rvalid) then
            stream_tb_fail("rvalid is X during handshake for " & NAME);
          elsif to_X01(m_axil_rvalid) = '1' then
            stream_tb_push(NAME & "_r", m_axil_rdata & m_axil_rresp);
            m_axil_rready_v := '0';
          end if;
        end if;

        -- Look for new read commands.
        if m_axil_arvalid_v = '0' and m_axil_rready_v = '0' then
          stream_tb_pop(NAME & "_ar", data, ok);
          if ok then
            m_axil_araddr    <= data;
            m_axil_arvalid_v := '1';
            m_axil_rready_v  := '1';
          end if;
        end if;

        m_axil_arvalid_s <= m_axil_arvalid_v;
        m_axil_rready_s  <= m_axil_rready_v;
      end if;
    end if;
  end process;

  m_axil_awvalid <= m_axil_awvalid_s;
  m_axil_wvalid  <= m_axil_wvalid_s;
  m_axil_bready  <= m_axil_bready_s;
  m_axil_arvalid <= m_axil_arvalid_s;
  m_axil_rready  <= m_axil_rready_s;

end Behavioral;


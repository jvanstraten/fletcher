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
use work.Utils.all;
use work.Streams.all;
use work.Buffers.all;
use work.Columns.all;
use work.ColumnConfig.all;
use work.ColumnConfigParse.all;
use work.Interconnect.all;
use work.Wrapper.all;

--pragma simulation timeout 100 ms

entity ColumnReaderSpeed_tc is
  generic (
    XX_BUS_DATA_WIDTH           : natural := 512;
    XX_BUS_BURST_STEP_LEN       : natural := 4;
    XX_BUS_BURST_MAX_LEN        : natural := 16;
    XX_CFG                      : string := "listprim(8;epc=64)";
    XX_LIST_LEN_MIN             : natural := 10;
    XX_LIST_LEN_MAX             : natural := 200;
    XX_CMD_LEN_MIN              : natural := 50000;
    XX_CMD_LEN_MAX              : natural := 1000000;
    XX_CMD_MAX_OUTSTANDING      : natural := 10;
    XX_CMD_COUNT                : natural := 1;
    XX_BUS_PERIOD               : time := 10 ns;
    XX_ACC_PERIOD               : time := 10 ns
  );
end ColumnReaderSpeed_tc;

architecture TestCase of ColumnReaderSpeed_tc is

  signal bus_clk                : std_logic;
  signal bus_reset              : std_logic;
  signal acc_clk                : std_logic;
  signal acc_reset              : std_logic;

  signal cmd_valid              : std_logic;
  signal cmd_ready              : std_logic;
  signal cmd_firstIdx           : std_logic_vector(31 downto 0);
  signal cmd_lastIdx            : std_logic_vector(31 downto 0);
  constant CMD_CTRL             : std_logic_vector(arcfg_ctrlWidth(XX_CFG, 32)-1 downto 0) := (others => '0');

  signal unlock                 : std_logic;

  signal bus_rreq_valid         : std_logic;
  signal bus_rreq_ready         : std_logic;
  signal bus_rreq_addr          : std_logic_vector(31 downto 0);
  signal bus_rreq_len           : std_logic_vector(7 downto 0);
  signal bus_rdat_valid         : std_logic;
  signal bus_rdat_ready         : std_logic;
  signal bus_rdat_data          : std_logic_vector(XX_BUS_DATA_WIDTH-1 downto 0);
  signal bus_rdat_last          : std_logic;

  signal out_valid              : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0);
  constant OUT_READY            : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0) := (others => '1');
  signal out_last               : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0);
  signal out_dvalid             : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0);
  signal out_data               : std_logic_vector(arcfg_userWidth(XX_CFG, 32)-1 downto 0);

  signal cmd_done               : boolean := false;
  signal sim_done               : boolean := false;

  signal bus_cyc_i              : natural := 0;
  signal bus_cyc                : natural := 0;
  signal bus_util               : natural := 0;
  signal acc_cyc_i              : natural := 0;
  signal acc_cyc                : natural := 0;
  signal acc_util               : nat_array(arcfg_userCount(XX_CFG)-1 downto 0) := (others => 0);

begin

  uut: ColumnReader
    generic map (
      BUS_ADDR_WIDTH            => 32,
      BUS_LEN_WIDTH             => 8,
      BUS_DATA_WIDTH            => XX_BUS_DATA_WIDTH,
      BUS_BURST_STEP_LEN        => XX_BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN         => XX_BUS_BURST_MAX_LEN,
      INDEX_WIDTH               => 32,
      CFG                       => XX_CFG,
      CMD_TAG_ENABLE            => true
    )
    port map (
      bus_clk                   => bus_clk,
      bus_reset                 => bus_reset,
      acc_clk                   => acc_clk,
      acc_reset                 => acc_reset,
      cmd_valid                 => cmd_valid,
      cmd_ready                 => cmd_ready,
      cmd_firstIdx              => cmd_firstIdx,
      cmd_lastIdx               => cmd_lastIdx,
      cmd_ctrl                  => CMD_CTRL,
      unlock_valid              => unlock,
      unlock_ready              => '1',
      bus_rreq_valid            => bus_rreq_valid,
      bus_rreq_ready            => bus_rreq_ready,
      bus_rreq_addr             => bus_rreq_addr,
      bus_rreq_len              => bus_rreq_len,
      bus_rdat_valid            => bus_rdat_valid,
      bus_rdat_ready            => bus_rdat_ready,
      bus_rdat_data             => bus_rdat_data,
      bus_rdat_last             => bus_rdat_last,
      out_valid                 => out_valid,
      out_ready                 => OUT_READY,
      out_last                  => out_last,
      out_dvalid                => out_dvalid,
      out_data                  => out_data
    );

  bus_clk_proc: process is
  begin
    wait for XX_BUS_PERIOD / 2;
    bus_clk <= '0';
    wait for XX_BUS_PERIOD / 2;
    bus_clk <= '1';
    if sim_done then
      wait;
    end if;
  end process;

  acc_clk_proc: process is
  begin
    wait for XX_ACC_PERIOD / 2;
    acc_clk <= '0';
    wait for XX_ACC_PERIOD / 2;
    acc_clk <= '1';
    if sim_done then
      wait;
    end if;
  end process;

  reset_proc: process is
  begin
    acc_reset <= '1';
    bus_reset <= '1';
    wait for 1000 ns;
    wait until rising_edge(acc_clk);
    acc_reset <= '0';
    wait until rising_edge(bus_clk);
    bus_reset <= '0';
    wait;
  end process;

  cmd_proc: process (bus_clk) is
    variable cmd_valid_v  : std_logic;
    variable outstanding  : natural := 0;
    variable command_cnt  : natural := 0;
    variable command_idx  : natural := 0;
    variable command_len  : natural := XX_CMD_LEN_MIN;
  begin
    if rising_edge(bus_clk) then

      if cmd_ready = '1' then
        cmd_valid_v := '0';
      end if;

      if unlock = '1' then
        outstanding := outstanding - 1;
      end if;

      if outstanding < XX_CMD_MAX_OUTSTANDING and cmd_valid_v = '0' and command_cnt < XX_CMD_COUNT then
        cmd_firstIdx <= std_logic_vector(to_unsigned(command_idx, 32));
        command_idx := command_idx + command_len;
        cmd_lastIdx <= std_logic_vector(to_unsigned(command_idx, 32));
        cmd_valid_v := '1';
        command_len := command_len + 1;
        if command_len > XX_CMD_LEN_MAX then
          command_len := XX_CMD_LEN_MIN;
        end if;
        command_cnt := command_cnt + 1;
        outstanding := outstanding + 1;
      end if;

      if outstanding = 0 and command_cnt = XX_CMD_COUNT then
        cmd_done <= true;
      end if;

      if bus_reset = '1' then
        cmd_valid_v := '0';
        outstanding := 0;
        command_cnt := 0;
        command_idx := 0;
        command_len := XX_CMD_LEN_MIN;
        cmd_done    <= false;
      end if;

      cmd_valid <= cmd_valid_v;
    end if;
  end process;

  bus_proc: process (bus_clk) is
    function get_data(address: integer) return std_logic_vector is
      constant PERIOD_LEN   : integer := XX_LIST_LEN_MAX - XX_LIST_LEN_MIN + 1;
      variable words        : integer;
      variable period_idx   : integer;
      variable value        : integer;
    begin
      words := address / 4;
      if words = 0 then
        return std_logic_vector(to_unsigned(0, 32));
      end if;
      words := words - 1;
      period_idx := words /  PERIOD_LEN;
      words := words - period_idx * PERIOD_LEN;
      value := period_idx * (XX_LIST_LEN_MAX + XX_LIST_LEN_MIN) * PERIOD_LEN;
      value := value + (words + 2*XX_LIST_LEN_MIN) * (words + 1);
      value := value /  2;
      return std_logic_vector(to_unsigned(value, 32));
    end function;

    variable req_valid      : std_logic;
    variable req_ready      : std_logic;
    variable dat_valid      : std_logic;
    variable dat_ready      : std_logic;
    variable remain         : integer := 0;
    variable address        : integer := 0;
    constant BUS_DATA_WORDS : natural := XX_BUS_DATA_WIDTH / 32;
  begin
    if rising_edge(bus_clk) then
      req_valid := bus_rreq_valid;
      dat_ready := bus_rdat_ready;

      bus_cyc_i <= bus_cyc_i + 1;

      if dat_ready = '1' then
        dat_valid := '0';
      end if;

      if dat_valid = '0' and remain = 0 and req_valid = '1' then
        address := to_integer(unsigned(bus_rreq_addr));
        remain  := to_integer(unsigned(bus_rreq_len));
        req_ready := '1';
      else
        req_ready := '0';
      end if;

      if dat_valid = '0' and remain > 0 then
        for i in 0 to BUS_DATA_WORDS - 1 loop
          bus_rdat_data(i*32+31 downto i*32) <= get_data(address);
          address := address + 4;
        end loop;
        remain := remain - 1;
        if remain = 0 then
          bus_rdat_last <= '1';
        else
          bus_rdat_last <= '0';
        end if;
        dat_valid := '1';
        bus_util <= bus_util + 1;
        bus_cyc <= bus_cyc_i;
      end if;

      if bus_reset = '1' then
        req_ready := '0';
        dat_valid := '0';
        remain    := 0;
        address   := 0;
        bus_cyc_i <= 0;
        bus_cyc   <= 0;
        bus_util  <= 0;
      end if;

      bus_rreq_ready <= req_ready;
      bus_rdat_valid <= dat_valid;
    end if;
  end process;

  acc_proc: process (acc_clk) is
  begin
    if rising_edge(acc_clk) then
      acc_cyc_i <= acc_cyc_i + 1;
      for i in acc_util'range loop
        if out_valid(i) = '1' then
          acc_util(i) <= acc_util(i) + 1;
          acc_cyc <= acc_cyc_i;
        end if;
      end loop;
      if acc_reset = '1' then
        acc_cyc_i <= 0;
        acc_cyc   <= 0;
        acc_util  <= (others => 0);
      end if;
    end if;
  end process;

  sim_proc: process is
    variable cyc  : natural;
  begin
    wait for 1000 ns;
    report "Minimum command length: " & integer'image(XX_CMD_LEN_MIN) severity note;
    wait until cmd_done;
    loop
      cyc := acc_cyc;
      wait for 100 us;
      exit when acc_cyc = cyc;
    end loop;
    sim_done <= true;
    report "Bus utilization: " & integer'image(bus_util * 10000 / bus_cyc) & " / 10000" severity note;
    for i in acc_util'range loop
      report "Acc stream " & integer'image(i) & " utilization: " & integer'image(acc_util(i) * 10000 / acc_cyc) & " / 10000" severity note;
    end loop;
    wait;
  end process;

end TestCase;

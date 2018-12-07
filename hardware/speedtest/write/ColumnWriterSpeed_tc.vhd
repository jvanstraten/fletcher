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

entity ColumnWriterSpeed_tc is
  generic (
    XX_BUS_DATA_WIDTH           : natural := 512;
    XX_BUS_BURST_STEP_LEN       : natural := 4;
    XX_BUS_BURST_MAX_LEN        : natural := 16;
    XX_ELEMENT_WIDTH            : natural := 8;
    XX_ELEMENT_COUNT            : natural := 64;
    XX_LIST                     : boolean := false;
    XX_LIST_LEN_MIN             : natural := 10;
    XX_LIST_LEN_MAX             : natural := 200;
    XX_CMD_LEN_MIN              : natural := 50000;
    XX_CMD_LEN_MAX              : natural := 1000000;
    XX_CMD_MAX_OUTSTANDING      : natural := 10;
    XX_CMD_COUNT                : natural := 1;
    XX_BUS_PERIOD               : time := 10 ns;
    XX_ACC_PERIOD               : time := 10 ns
  );
end ColumnWriterSpeed_tc;

architecture TestCase of ColumnWriterSpeed_tc is

  function xx_cfg_fn return string is
  begin
    if XX_LIST then
      return "listprim(" & integer'image(XX_ELEMENT_WIDTH) & ";epc=" & integer'image(XX_ELEMENT_COUNT) & ")";
    else
      return "prim(" & integer'image(XX_ELEMENT_WIDTH) & ")";
    end if;
  end function;

  constant XX_CFG               : string := xx_cfg_fn;

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

  signal bus_busy               : std_logic;

  signal bus_wreq_addr          : std_logic_vector(31 downto 0);
  signal bus_wreq_len           : std_logic_vector(7 downto 0);
  signal bus_wdat_data          : std_logic_vector(XX_BUS_DATA_WIDTH-1 downto 0);
  signal bus_wdat_strobe        : std_logic_vector(XX_BUS_DATA_WIDTH/8-1 downto 0);

  signal in_valid               : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0);
  signal in_ready               : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0);
  signal in_last                : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0) := (others => '0');
  signal in_dvalid              : std_logic_vector(arcfg_userCount(XX_CFG)-1 downto 0) := (others => '1');
  signal in_data                : std_logic_vector(arcfg_userWidth(XX_CFG, 32)-1 downto 0) := (others => '0');

  signal cmd_done               : boolean := false;
  signal sim_done               : boolean := false;

  signal bus_cyc_i              : natural := 0;
  signal bus_cyc                : natural := 0;
  signal bus_util               : natural := 0;
  signal acc_cyc_i              : natural := 0;
  signal acc_cyc                : natural := 0;
  signal acc_util               : nat_array(arcfg_userCount(XX_CFG)-1 downto 0) := (others => 0);

begin

  uut: ColumnWriter
    generic map (
      BUS_ADDR_WIDTH            => 32,
      BUS_LEN_WIDTH             => 8,
      BUS_DATA_WIDTH            => XX_BUS_DATA_WIDTH,
      BUS_STROBE_WIDTH          => XX_BUS_DATA_WIDTH / 8,
      BUS_BURST_STEP_LEN        => XX_BUS_BURST_STEP_LEN,
      BUS_BURST_MAX_LEN         => XX_BUS_BURST_MAX_LEN,
      INDEX_WIDTH               => 32,
      CFG                       => XX_CFG,
      CMD_TAG_ENABLE            => true,
      CMD_TAG_WIDTH             => 1
    )
    port map (
      bus_clk                   => bus_clk,
      bus_reset                 => bus_reset,
      acc_clk                   => acc_clk,
      acc_reset                 => acc_reset,
      cmd_valid                 => cmd_valid,
      cmd_ready                 => cmd_ready,
      cmd_firstIdx              => CMD_FIRSTIDX,
      cmd_lastIdx               => CMD_LASTIDX,
      cmd_ctrl                  => CMD_CTRL,
      unlock_valid              => unlock,
      unlock_ready              => '1',
      bus_wreq_valid            => open,
      bus_wreq_ready            => '1',
      bus_wreq_addr             => bus_wreq_addr,
      bus_wreq_len              => bus_wreq_len,
      bus_wdat_valid            => bus_busy,
      bus_wdat_ready            => '1',
      bus_wdat_data             => bus_wdat_data,
      bus_wdat_strobe           => bus_wdat_strobe,
      bus_wdat_last             => open,
      in_valid                  => in_valid,
      in_ready                  => in_ready,
      in_last                   => in_last,
      in_dvalid                 => in_dvalid,
      in_data                   => in_data
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
  begin
    if rising_edge(bus_clk) then
      bus_cyc_i <= bus_cyc_i + 1;

      if bus_busy = '1' then
        bus_util <= bus_util + 1;
        bus_cyc <= bus_cyc_i;
      end if;

      if bus_reset = '1' then
        bus_cyc_i <= 0;
        bus_cyc   <= 0;
        bus_util  <= 0;
      end if;
    end if;
  end process;

  acc_proc: process (acc_clk) is
    variable mst_valid        : std_logic;
    variable mst_command_cnt  : natural := 0;
    variable mst_command_len  : natural := XX_CMD_LEN_MIN;
    variable mst_idx          : natural := 0;
    variable mst_len          : natural := XX_LIST_LEN_MIN;

    variable el_valid         : std_logic;
    variable el_command_cnt   : natural := 0;
    variable el_command_len   : natural := XX_CMD_LEN_MIN;
    variable el_list_idx      : natural := 0;
    variable el_list_len      : natural := XX_LIST_LEN_MIN;
    variable el_idx           : natural := 0;
    variable el_epc           : natural := 0;
  begin
    if rising_edge(acc_clk) then

      if in_ready(0) = '1' then
        mst_valid := '0';
      end if;

      if mst_idx = mst_command_len and mst_command_cnt < XX_CMD_COUNT then
        mst_command_len := mst_command_len + 1;
        if mst_command_len > XX_CMD_LEN_MAX then
          mst_command_len := XX_CMD_LEN_MIN;
        end if;
        mst_command_cnt := mst_command_cnt + 1;
      end if;

      if mst_valid = '0' and mst_idx < mst_command_len then
        mst_valid := '1';
        mst_idx := mst_idx + 1;
        if mst_idx = mst_command_len then
          in_last(0) <= '1';
        else
          in_last(0) <= '0';
        end if;
        if XX_LIST then
          in_data(work.utils.min(32, in_data'length)-1 downto 0) <= std_logic_vector(to_unsigned(mst_len, work.utils.min(32, in_data'length)));
          mst_len := mst_len + 1;
          if mst_len > XX_LIST_LEN_MAX then
            mst_len := XX_LIST_LEN_MIN;
          end if;
        end if;
      end if;

      if acc_reset = '1' then
        mst_command_cnt := 0;
        mst_command_len := XX_CMD_LEN_MIN;
        mst_idx := 0;
        mst_len := XX_LIST_LEN_MIN;
        mst_valid := '0';
      end if;

      in_valid(0) <= mst_valid;

      if XX_LIST then
        if in_ready(in_ready'high) = '1' then
          el_valid := '0';
        end if;

        if el_valid = '0' and el_command_cnt < XX_CMD_COUNT then
          el_valid := '1';
          el_epc := work.utils.min(el_list_len - el_idx, XX_ELEMENT_COUNT);
          el_idx := el_idx + el_epc;
          if el_idx = el_list_len then
            in_last(in_last'high) <= '1';
          else
            in_last(in_last'high) <= '0';
          end if;
          in_data(in_data'high downto in_data'high - log2ceil(XX_ELEMENT_COUNT+1) + 1)
            <= std_logic_vector(to_unsigned(el_epc, log2ceil(XX_ELEMENT_COUNT+1)));
          if el_epc = 0 then
            in_dvalid(in_dvalid'high) <= '0';
          else
            in_dvalid(in_dvalid'high) <= '1';
          end if;

          if el_idx = el_list_len then
            el_idx := 0;
            el_list_len := el_list_len + 1;
            if el_list_len > XX_LIST_LEN_MAX then
              el_list_len := XX_LIST_LEN_MIN;
            end if;
            el_list_idx := el_list_idx + 1;
            if el_list_idx = el_command_len then
              el_list_idx := 0;
              el_command_len := el_command_len + 1;
              if el_command_len > XX_CMD_LEN_MAX then
                el_command_len := XX_CMD_LEN_MIN;
              end if;
              el_command_cnt := el_command_cnt + 1;
            end if;
          end if;
        end if;

        if acc_reset = '1' then
          el_command_cnt := 0;
          el_command_len := XX_CMD_LEN_MIN;
          el_list_idx := 0;
          el_list_len := XX_LIST_LEN_MIN;
          el_valid := '0';
          el_idx := 0;
        end if;

        in_valid(in_valid'high) <= el_valid;

      end if;

    end if;
  end process;

  acc_mon_proc: process (acc_clk) is
  begin
    if rising_edge(acc_clk) then
      acc_cyc_i <= acc_cyc_i + 1;
      for i in acc_util'range loop
        if in_valid(i) = '1' and in_ready(i) = '1' then
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
    cyc := work.utils.max(bus_cyc, acc_cyc);
    sim_done <= true;
    report "Bus utilization: " & integer'image(integer(real(bus_util) * 10000.0 / real(cyc))) & " / 10000" severity note;
    for i in acc_util'range loop
      report "Acc stream " & integer'image(i) & " utilization: " & integer'image(integer(real(acc_util(i)) * 10000.0 / real(cyc))) & " / 10000" severity note;
    end loop;
    wait;
  end process;

end TestCase;

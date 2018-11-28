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
use work.Utils.all;
use work.SimUtils.all;
use work.StreamSim.all;

entity AnalyzeDistribution_tc is
end AnalyzeDistribution_tc;

architecture TestCase of AnalyzeDistribution_tc is

  constant DATA_WIDTH           : natural := 16;
  constant BIN_COUNT_LOG2       : natural := 6;
  constant MMIO_DATA_WIDTH      : natural := 32;

  signal clk                    : std_logic;
  signal reset                  : std_logic;

begin

  clk_proc: process is
  begin
    stream_tb_gen_clock(clk, 10 ns);
    wait;
  end process;

  stimulus: process is

    -- Shorthands for writing and reading MMIO registers.
    type reg_enum is (r_cfg, r_ctl, r_off, r_bin, r_min, r_max, r_acc, r_cnt);
    procedure write(reg: reg_enum; val: std_logic_vector) is
    begin
      AXILiteWrite("mmio", std_logic_vector(to_unsigned(reg_enum'pos(reg)*4, 32)), val, 10 us);
    end procedure;
    function read(reg: reg_enum) return std_logic_vector is
      variable val: std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
    begin
      AXILiteRead("mmio", std_logic_vector(to_unsigned(reg_enum'pos(reg)*4, 32)), val, 10 us);
      return val;
    end function;

    -- Reset procedure, should be done in software in the actual design.
    procedure soft_reset is
    begin
      for i in -2**(BIN_COUNT_LOG2-1) to 2**(BIN_COUNT_LOG2-1)-1 loop
        write(r_ctl, X"0000" & "1" & std_logic_vector(to_signed(i, 15)));
      end loop;
      write(r_off, X"00000000");
      write(r_min, X"7FFFFFFF");
      write(r_max, X"80000000");
      write(r_acc, X"00000000");
      write(r_cnt, X"00000000");
      write(r_ctl, X"00000000");
    end procedure;

    -- Change the acceptance state of the analyzer.
    procedure set_accept(ack: boolean; ena: boolean) is
      variable data : std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
    begin
      data := read(r_ctl);
      data(31) := sel(ack, '1', '0');
      data(30) := sel(ena, '1', '0');
      write(r_ctl, data);
    end procedure;

    -- Change the binning right-shift amount the analyzer.
    procedure set_rshift(rshift: natural) is
      variable data : std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
    begin
      data := read(r_ctl);
      data(29 downto 16) := std_logic_vector(to_unsigned(rshift, 14));
      write(r_ctl, data);
    end procedure;

    -- Register dump to stdout.
    procedure reg_dump is
    begin
      for i in reg_enum'low to reg_enum'high loop
        dumpStdOut(reg_enum'image(i) & ": " & sim_hex(read(i)));
      end loop;
    end procedure;
    procedure bin_dump is
      variable data : std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
    begin
      data := read(r_ctl);
      data(15) := '0';
      for i in -2**(BIN_COUNT_LOG2-1) to 2**(BIN_COUNT_LOG2-1)-1 loop
        data(14 downto 0) := std_logic_vector(to_signed(i, 15));
        write(r_ctl, data);
        dumpStdOut("bin " & integer'image(i) & ": " & sim_uint(read(r_bin)));
      end loop;
    end procedure;

    -- Sends a bunch of garbage to the analyzer. This is non-blocking.
    procedure send_stuff(amount: natural; seed: positive) is
      variable seed1  : positive := seed;
      variable seed2  : positive := seed;
      variable rand   : real;
      variable data   : std_logic_vector(DATA_WIDTH-1 downto 0);
    begin
      for i in 1 to amount loop
        uniform(seed1, seed2, rand);
        data := std_logic_vector(to_signed(integer(tan(rand * 20.0 * 3.14159265) * 1.0), DATA_WIDTH));
        stream_tb_push("src", data);
      end loop;
    end procedure;

    -- Checks the UUT with the given settings.
    procedure check(amount: natural; seed: positive; offs: integer; rshift: natural) is
      variable remain       : natural;
      variable data_slv     : std_logic_vector(DATA_WIDTH-1 downto 0);
      variable data         : integer;
      variable ok           : boolean;
      constant BIN_MIN      : integer := -2**(BIN_COUNT_LOG2-1);
      constant BIN_MAX      : integer := 2**(BIN_COUNT_LOG2-1)-1;
      type bin_data_type is array (BIN_MIN to BIN_MAX) of natural;
      variable bin_data     : bin_data_type;
      variable minimum      : integer;
      variable maximum      : integer;
      variable accumulator  : integer;
      variable counter      : natural;
      variable bin          : integer;
      variable enable       : boolean;
      variable actual       : integer;
      variable ctl          : std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
    begin

      -- Configure the analyzer.
      soft_reset;
      set_rshift(rshift);
      write(r_off, std_logic_vector(to_signed(offs, MMIO_DATA_WIDTH)));

      -- Send random data.
      send_stuff(amount, seed);

      -- Initialize statistics.
      for i in BIN_MIN to BIN_MAX loop
        bin_data(i) := 0;
      end loop;
      minimum     := integer'high;
      maximum     := integer'low;
      accumulator := 0;
      counter     := 0;

      -- Receive and check.
      remain := amount;
      enable := true;
      while remain > 0 loop
        set_accept(true, enable);
        wait for 10 us;
        set_accept(false, false);
        wait for 50 ns;

        -- Update expected state.
        loop
          stream_tb_pop("mon", data_slv, ok);
          exit when not ok;
          remain := remain - 1;
          if enable then
            data        := to_integer(signed(data_slv));
            minimum     := work.utils.min(minimum, data);
            maximum     := work.utils.max(maximum, data);
            accumulator := accumulator + data;
            counter     := counter + 1;

            bin := data - offs;
            -- of course VHDL rounds to zero instead of truncating...
            if bin < 0 then
              bin := (bin - (2**rshift-1)) / 2**rshift;
            else
              bin := bin / 2**rshift;
            end if;
            if bin > BIN_MAX then
              bin := BIN_MAX;
            elsif bin < BIN_MIN then
              bin := BIN_MIN;
            end if;
            bin_data(bin) := bin_data(bin) + 1;
          end if;
        end loop;

        -- Compare state with expected.
        if counter > 0 then
          actual := to_integer(signed(read(r_min)));
          if actual /= minimum then
            stream_tb_fail("Unexpected minimum value: " &
              "expected " & integer'image(minimum) &
              " but was " & integer'image(actual));
          end if;
          actual := to_integer(signed(read(r_max)));
          if actual /= maximum then
            stream_tb_fail("Unexpected maximum value: " &
              "expected " & integer'image(maximum) &
              " but was " & integer'image(actual));
          end if;
        end if;
        actual := to_integer(signed(read(r_acc)));
        if actual /= accumulator then
          stream_tb_fail("Unexpected accumulator value: " &
            "expected " & integer'image(accumulator) &
            " but was " & integer'image(actual));
        end if;
        actual := to_integer(signed(read(r_cnt)));
        if actual /= counter then
          stream_tb_fail("Unexpected counter value: " &
            "expected " & integer'image(counter) &
            " but was " & integer'image(actual));
        end if;
        ctl := read(r_ctl);
        ctl(15) := '0';
        for i in BIN_MIN to BIN_MAX loop
          ctl(14 downto 0) := std_logic_vector(to_signed(i, 15));
          write(r_ctl, ctl);
          actual := to_integer(signed(read(r_bin)));
          if actual /= bin_data(i) then
            stream_tb_fail("Unexpected value for bin " & integer'image(i) &
              ": expected "& integer'image(bin_data(i)) &
              " but was " & integer'image(actual));
          end if;
        end loop;

        enable := not enable;
      end loop;

    end procedure;

  begin
    reset <= '1';
    wait for 50 ns;
    wait until rising_edge(clk);
    reset <= '0';
    wait for 10 us;

    report "Testing bin=data..." severity note;
    check(1000, 1, 0, 0);
    bin_dump;
    reg_dump;

    report "Testing bin=data-20..." severity note;
    check(1000, 2, 20, 0);
    bin_dump;
    reg_dump;

    report "Testing bin=data>>2..." severity note;
    check(1000, 3, 0, 2);
    bin_dump;
    reg_dump;

    report "Testing bin=(data+35)>>3..." severity note;
    check(1000, 4, -35, 3);
    bin_dump;
    reg_dump;

    stream_tb_complete;
    wait;
  end process;

  tb: entity work.AnalyzeDistribution_tb
    generic map (
      DATA_WIDTH                => DATA_WIDTH,
      BIN_COUNT_LOG2            => BIN_COUNT_LOG2,
      MMIO_DATA_WIDTH           => MMIO_DATA_WIDTH
    )
    port map (
      clk                       => clk,
      reset                     => reset
    );

end TestCase;


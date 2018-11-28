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

library work;
use work.Utils.all;

-- This unit analyzes the distribution of numeric data passed to it via a
-- stream. The minimum value, maximum value, average value, and a
-- configurable binning of the distribution can be recorded and subsequently
-- read through a Fletcher MMIO interface.
--
-- The MMIO registers are:
--
--  0 (RO): cfg
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    |                 -                 |       D       |       B       |
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    D: data width.
--    B: 2-log of the bin count.
--
--  1 (RW, rst): ctl
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    | - |A|E|...          S             |R|...          B               |
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    A: 0 to block the input stream, 1 to acknowledge the input stream.
--    E: 0 to ignore input data, 1 to use input data
--    S: amount of bits to right-shift the offset-corrected input data by to
--       get the bin address. i.e. this is the 2-log of the bin size.
--    R: 0 to clear the bin selected by B, 1 to read it using register 2.
--    B: bin index to clear or reset.
--
--  2 (RW, rst): off
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    |                           Signed integer                          |
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    Binning offset = center of the bins.
--
--  3 (RW, rst): bin
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    |                          Unsigned integer                         |
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    Current value of the bin selected by ctl->B.
--
--  4 (RW, rst): min
--  5 (RW, rst): max
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    |                           Signed integer                          |
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    When data is received, these registers are updated with min(data, prev)
--    resp. max(data, prev), where prev is the previous value of the register.
--    These registers must be manually set to INT_MAX resp. INT_MIN before
--    starting the analysis for them to be valid.
--
--  6 (RW, rst): acc
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    |                           Signed integer                          |
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    Received data is accumulated in this register. It must be manually
--    cleared before starting the analysis for it to be valid.
--
--  7 (RW, rst): cnt
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    |                          Unsigned integer                         |
--    |...|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|-.-.-.-.-.-.-.-|
--    The number of data words received is counted in this register. It must be
--    manually cleared before starting the analysis for it to be valid.
--
-- Note: all accumulators are overflow-safe: they clamp when they overflow, and
-- accumulation is disabled when they reach INT_MIN or INT_MAX. Thus, positive
-- overflow is represented with INT_MAX and negative overflow is represented
-- with INT_MIN.

entity AnalyzeDistribution is
  generic (

    -- Width of the to-be-recorded value. Note that the value is interpreted
    -- as a signed number.
    DATA_WIDTH                  : natural := 16;

    -- log2 of the number of bins.
    BIN_COUNT_LOG2              : natural := 6;

    -- Width of the MMIO registers. This is also the width of all the counters.
    -- Must be at least 32 bits.
    MMIO_DATA_WIDTH             : natural := 32

  );
  port (

    -- Rising-edge sensitive clock and active-high synchronous reset.
    clk                         : in  std_logic;
    reset                       : in  std_logic;

    -- Data input port.
    in_valid                    : in  std_logic;
    in_ready                    : out std_logic;
    in_data                     : in  std_logic_vector(DATA_WIDTH-1 downto 0);

    -- MMIO interface.
    regs_out                    : in  std_logic_vector(8*MMIO_DATA_WIDTH-1 downto 0);
    regs_in                     : out std_logic_vector(8*MMIO_DATA_WIDTH-1 downto 0);
    regs_in_en                  : out std_logic_vector(8-1 downto 0)

  );
end AnalyzeDistribution;

architecture Behavioral of AnalyzeDistribution is

  constant SHIFT_WIDTH          : natural := log2ceil(DATA_WIDTH);

  -- Unpacked register vectors.
  signal ri_cfg_dataWidth       : unsigned(7 downto 0);
  signal ri_cfg_binCountLog2    : unsigned(7 downto 0);
  signal re_cfg                 : std_logic;
  signal ro_ctl_acknowledge     : std_logic;
  signal ro_ctl_enable          : std_logic;
  signal ro_ctl_shift           : unsigned(SHIFT_WIDTH-1 downto 0);
  signal ro_ctl_binReset        : std_logic;
  signal ro_ctl_binIndex        : signed(BIN_COUNT_LOG2-1 downto 0);
  signal ro_off_data            : signed(DATA_WIDTH-1 downto 0);
  signal ri_bin_data            : unsigned(MMIO_DATA_WIDTH-1 downto 0);
  signal re_bin                 : std_logic;
  signal ro_min_data            : signed(DATA_WIDTH-1 downto 0);
  signal ri_min_data            : signed(DATA_WIDTH-1 downto 0);
  signal re_min                 : std_logic;
  signal ro_max_data            : signed(DATA_WIDTH-1 downto 0);
  signal ri_max_data            : signed(DATA_WIDTH-1 downto 0);
  signal re_max                 : std_logic;
  signal ro_acc_data            : signed(MMIO_DATA_WIDTH-1 downto 0);
  signal ri_acc_data            : signed(MMIO_DATA_WIDTH-1 downto 0);
  signal re_acc                 : std_logic;
  signal ro_cnt_data            : unsigned(MMIO_DATA_WIDTH-1 downto 0);
  signal ri_cnt_data            : unsigned(MMIO_DATA_WIDTH-1 downto 0);
  signal re_cnt                 : std_logic;

  -- Input data, gated by MMIO registers and reformatted to signed.
  signal data                   : signed(DATA_WIDTH-1 downto 0);
  signal valid                  : std_logic;

  -- Binning pipeline stage 1: offset-correcting adder output.
  signal data_s1                : signed(DATA_WIDTH downto 0);
  signal valid_s1               : std_logic;

  -- Binning pipeline stage 2: right-shifter output.
  signal data_s2                : signed(DATA_WIDTH downto 0);
  signal valid_s2               : std_logic;

  -- Binning pipeline stage 3: clamped bin address output.
  signal data_s3                : signed(BIN_COUNT_LOG2-1 downto 0);
  signal valid_s3               : std_logic;

  -- Binning memory interface.
  signal bin_rw_addr            : unsigned(BIN_COUNT_LOG2-1 downto 0);
  signal bin_rw_rdata           : unsigned(MMIO_DATA_WIDTH-1 downto 0);
  signal bin_rw_wdata           : unsigned(MMIO_DATA_WIDTH-1 downto 0);
  signal bin_rw_wen             : std_logic;
  signal bin_r_addr             : unsigned(BIN_COUNT_LOG2-1 downto 0);
  signal bin_r_rdata            : unsigned(MMIO_DATA_WIDTH-1 downto 0);

  -- Binning memory contents.
  type bin_array is array (natural range <>) of unsigned(MMIO_DATA_WIDTH-1 downto 0);
  signal bin_data               : bin_array(0 to 2**BIN_COUNT_LOG2-1);

begin

  reg_packing_proc: process (
    ri_cfg_dataWidth, ri_cfg_binCountLog2, re_cfg, ri_bin_data, re_bin,
    ri_min_data, re_min, ri_max_data, re_max, ri_acc_data, re_acc, ri_cnt_data,
    re_cnt, regs_out
  ) is
    pure function r(reg: natural; idx: natural) return natural is
    begin
      return reg*MMIO_DATA_WIDTH+idx;
    end function;
  begin
    regs_in <= (others => '0');
    regs_in(r(0,               15) downto r(0, 8)) <= std_logic_vector(ri_cfg_dataWidth);
    regs_in(r(0,                7) downto r(0, 0)) <= std_logic_vector(ri_cfg_binCountLog2);
    regs_in(r(3,MMIO_DATA_WIDTH-1) downto r(3, 0)) <= std_logic_vector(ri_bin_data);
    regs_in(r(4,MMIO_DATA_WIDTH-1) downto r(4, 0)) <= std_logic_vector(resize(ri_min_data, MMIO_DATA_WIDTH));
    regs_in(r(5,MMIO_DATA_WIDTH-1) downto r(5, 0)) <= std_logic_vector(resize(ri_max_data, MMIO_DATA_WIDTH));
    regs_in(r(6,MMIO_DATA_WIDTH-1) downto r(6, 0)) <= std_logic_vector(ri_acc_data);
    regs_in(r(7,MMIO_DATA_WIDTH-1) downto r(7, 0)) <= std_logic_vector(ri_cnt_data);

    regs_in_en(0) <= re_cfg;
    regs_in_en(1) <= '0';
    regs_in_en(2) <= '0';
    regs_in_en(3) <= re_bin;
    regs_in_en(4) <= re_min;
    regs_in_en(5) <= re_max;
    regs_in_en(6) <= re_acc;
    regs_in_en(7) <= re_cnt;

    ro_ctl_acknowledge  <= regs_out(r(1,31));
    ro_ctl_enable       <= regs_out(r(1,30));
    ro_ctl_shift        <= unsigned(regs_out(r(1,16+SHIFT_WIDTH-1) downto r(1,16)));
    ro_ctl_binReset     <= regs_out(r(1,15));
    ro_ctl_binIndex     <= resize(signed(regs_out(r(1,14) downto r(1,0))), BIN_COUNT_LOG2);
    ro_off_data         <= resize(signed(regs_out(r(2,MMIO_DATA_WIDTH-1) downto r(2,0))), DATA_WIDTH);
    ro_min_data         <= resize(signed(regs_out(r(4,MMIO_DATA_WIDTH-1) downto r(4,0))), DATA_WIDTH);
    ro_max_data         <= resize(signed(regs_out(r(5,MMIO_DATA_WIDTH-1) downto r(5,0))), DATA_WIDTH);
    ro_acc_data         <= signed(regs_out(r(6,MMIO_DATA_WIDTH-1) downto r(6,0)));
    ro_cnt_data         <= unsigned(regs_out(r(7,MMIO_DATA_WIDTH-1) downto r(7,0)));
  end process;

  -- Configuration register is fixed; always update it.
  ri_cfg_dataWidth      <= to_unsigned(DATA_WIDTH, 8);
  ri_cfg_binCountLog2   <= to_unsigned(BIN_COUNT_LOG2, 8);
  re_cfg                <= '1';

  -- Connect input stream.
  input_stream_proc: process (clk) is
  begin
    if rising_edge(clk) then
      data  <= signed(in_data);
      valid <= in_valid and ro_ctl_enable and ro_ctl_acknowledge;
      if reset = '1' then
        valid <= '0';
      end if;
    end if;
  end process;

  in_ready <= ro_ctl_acknowledge;

  -- Update statistics data when there is valid data at the input.
  stats_proc: process (
    data, valid, ro_min_data, ro_max_data, ro_acc_data, ro_cnt_data
  ) is
    function int_min_f return signed is
      variable retval : signed(MMIO_DATA_WIDTH-1 downto 0) := (others => '0');
    begin
      retval(MMIO_DATA_WIDTH-1) := '1';
      return retval;
    end function;
    constant INT_MIN  : signed(MMIO_DATA_WIDTH-1 downto 0) := int_min_f;
    constant INT_MAX  : signed(MMIO_DATA_WIDTH-1 downto 0) := not int_min_f;
    constant UNS_MAX  : unsigned(MMIO_DATA_WIDTH-1 downto 0) := (others => '1');
    variable accum_v  : signed(MMIO_DATA_WIDTH downto 0);
  begin

    -- Record minimum.
    ri_min_data <= data;
    if data < ro_min_data then
      re_min <= valid;
    else
      re_min <= '0';
    end if;

    -- Record maximum.
    ri_max_data <= data;
    if data > ro_max_data then
      re_max <= valid;
    else
      re_max <= '0';
    end if;

    -- Accumulate data.
    ri_acc_data <= ro_acc_data;
    if ro_acc_data /= INT_MIN and ri_acc_data /= INT_MAX then
      accum_v := resize(ro_acc_data, MMIO_DATA_WIDTH+1) + resize(data, MMIO_DATA_WIDTH+1);
      if accum_v(MMIO_DATA_WIDTH) = '0' and accum_v(MMIO_DATA_WIDTH-1) = '1' then
        ri_acc_data <= INT_MAX;
      elsif accum_v(MMIO_DATA_WIDTH) = '1' and accum_v(MMIO_DATA_WIDTH-1) = '0' then
        ri_acc_data <= INT_MIN;
      else
        ri_acc_data <= resize(accum_v, MMIO_DATA_WIDTH);
      end if;
    end if;
    re_acc <= valid;

    -- Count transfers.
    ri_cnt_data <= ro_cnt_data + 1;
    if ro_cnt_data /= UNS_MAX then
      re_cnt <= valid;
    end if;

  end process;

  -- Select the right bin for each data value in a simple pipeline.
  bin_pipeline_proc: process (clk) is
  begin
    if rising_edge(clk) then

      -- Subtract zero offset.
      data_s1 <= resize(data, DATA_WIDTH+1) - resize(ro_off_data, DATA_WIDTH+1);
      valid_s1 <= valid;

      -- Shift right to set bin size.
      data_s2 <= shift_right(data_s1, to_integer(unsigned(ro_ctl_shift)));
      valid_s2 <= valid_s1;

      -- Clamp the bin index to the size of the binning memory.
      if data_s2 > 2**(BIN_COUNT_LOG2-1)-1 then
        data_s3 <= to_signed(2**(BIN_COUNT_LOG2-1)-1, BIN_COUNT_LOG2);
      elsif data_s2 < -2**(BIN_COUNT_LOG2-1) then
        data_s3 <= to_signed(-2**(BIN_COUNT_LOG2-1), BIN_COUNT_LOG2);
      else
        data_s3 <= resize(data_s2, BIN_COUNT_LOG2);
      end if;
      valid_s3 <= valid_s2;

    end if;
  end process;

  -- 1 read-write + 1 read port memory with async read. Should correspond to
  -- distributed RAM in most devices.
  bin_ram_proc: process (clk) is
  begin
    if rising_edge(clk) then
      if bin_rw_wen = '1' then
        bin_data(to_integer(bin_rw_addr)) <= bin_rw_wdata;
      end if;
    end if;
  end process;

  bin_rw_rdata <= bin_data(to_integer(bin_rw_addr));
  bin_r_rdata  <= bin_data(to_integer(bin_r_addr));

  -- Connect the bin update logic to the read-write port of the bin memory.
  bin_update_proc: process (
    bin_rw_rdata, ro_ctl_binReset, ro_ctl_binIndex, data_s3, valid_s3
  ) is
    constant UNS_MAX  : unsigned(MMIO_DATA_WIDTH-1 downto 0) := (others => '1');
  begin
    if ro_ctl_binReset = '1' then
      bin_rw_addr   <= unsigned(ro_ctl_binIndex);
      bin_rw_wdata  <= (others => '0');
      bin_rw_wen    <= '1';
    else
      bin_rw_addr   <= unsigned(data_s3);
      bin_rw_wdata  <= bin_rw_rdata + 1;
      if bin_rw_rdata /= UNS_MAX then
        bin_rw_wen <= valid_s3;
      else
        bin_rw_wen <= '0';
      end if;
    end if;
  end process;

  -- Connect the bin readout register to the read-only port of the bin memory.
  bin_r_addr <= unsigned(ro_ctl_binIndex);
  ri_bin_data <= bin_r_rdata;
  re_bin <= '1';

end Behavioral;

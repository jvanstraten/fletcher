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

package Analyze is

  component AnalyzeDistribution is
    generic (
      DATA_WIDTH                : natural := 16;
      BIN_COUNT_LOG2            : natural := 6;
      MMIO_DATA_WIDTH           : natural := 32
    );
    port (
      clk                       : in  std_logic;
      reset                     : in  std_logic;
      in_valid                  : in  std_logic;
      in_ready                  : out std_logic;
      in_data                   : in  std_logic_vector(DATA_WIDTH-1 downto 0);
      regs_out                  : in  std_logic_vector(8*MMIO_DATA_WIDTH-1 downto 0);
      regs_in                   : out std_logic_vector(8*MMIO_DATA_WIDTH-1 downto 0);
      regs_in_en                : out std_logic_vector(8-1 downto 0)
    );
  end component;

end Analyze;

package body Analyze is

end Analyze;

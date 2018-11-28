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
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library work;
use work.axi.all;
use work.axi_tb_pkg.all;
use work.StreamSim.all;

entity AnalyzeDistribution_tb is
  generic (
    DATA_WIDTH                  : natural := 16;
    BIN_COUNT_LOG2              : natural := 6;
    MMIO_DATA_WIDTH             : natural := 32
  );
  port (
    clk                         : in  std_logic;
    reset                       : in  std_logic
  );
end AnalyzeDistribution_tb;

architecture TestBench of AnalyzeDistribution_tb is

  signal reset_n                : std_logic;

  signal awvalid                : std_logic;
  signal awready                : std_logic;
  signal awaddr                 : std_logic_vector(31 downto 0);
  signal wvalid                 : std_logic;
  signal wready                 : std_logic;
  signal wdata                  : std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
  signal wstrb                  : std_logic_vector((MMIO_DATA_WIDTH/8)-1 downto 0);
  signal bvalid                 : std_logic;
  signal bready                 : std_logic;
  signal bresp                  : std_logic_vector(1 downto 0);
  signal arvalid                : std_logic;
  signal arready                : std_logic;
  signal araddr                 : std_logic_vector(31 downto 0);
  signal rvalid                 : std_logic;
  signal rready                 : std_logic;
  signal rdata                  : std_logic_vector(MMIO_DATA_WIDTH-1 downto 0);
  signal rresp                  : std_logic_vector(1 downto 0);

  signal regs_out               : std_logic_vector(MMIO_DATA_WIDTH*8-1 downto 0);
  signal regs_in                : std_logic_vector(MMIO_DATA_WIDTH*8-1 downto 0);
  signal regs_in_en             : std_logic_vector(7 downto 0);

  signal src_valid              : std_logic;
  signal src_ready              : std_logic;
  signal src_data               : std_logic_vector(DATA_WIDTH-1 downto 0);

begin

  reset_n <= not reset;

  data_source: StreamTbProd
    generic map (
      DATA_WIDTH                => DATA_WIDTH,
      SEED                      => 1,
      NAME                      => "src"
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      out_valid                 => src_valid,
      out_ready                 => src_ready,
      out_data                  => src_data
    );

  data_mon: StreamTbMon
    generic map (
      DATA_WIDTH                => DATA_WIDTH,
      NAME                      => "mon"
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      in_valid                  => src_valid,
      in_ready                  => src_ready,
      in_data                   => src_data
    );

  uut: entity work.AnalyzeDistribution
    generic map (
      DATA_WIDTH                => DATA_WIDTH,
      BIN_COUNT_LOG2            => BIN_COUNT_LOG2,
      MMIO_DATA_WIDTH           => MMIO_DATA_WIDTH
    )
    port map (
      clk                       => clk,
      reset                     => reset,
      in_valid                  => src_valid,
      in_ready                  => src_ready,
      in_data                   => src_data,
      regs_out                  => regs_out,
      regs_in                   => regs_in,
      regs_in_en                => regs_in_en
    );

  mmio: axi_mmio
    generic map (
      BUS_ADDR_WIDTH            => 32,
      BUS_DATA_WIDTH            => MMIO_DATA_WIDTH,
      NUM_REGS                  => 8,
      REG_CONFIG                => "RBBRBBBB",
      REG_RESET                 => "NYYYYYYY"
    )
    port map (
      clk                       => clk,
      reset_n                   => reset_n,
      s_axi_awvalid             => awvalid,
      s_axi_awready             => awready,
      s_axi_awaddr              => awaddr,
      s_axi_wvalid              => wvalid,
      s_axi_wready              => wready,
      s_axi_wdata               => wdata,
      s_axi_wstrb               => wstrb,
      s_axi_bvalid              => bvalid,
      s_axi_bready              => bready,
      s_axi_bresp               => bresp,
      s_axi_arvalid             => arvalid,
      s_axi_arready             => arready,
      s_axi_araddr              => araddr,
      s_axi_rvalid              => rvalid,
      s_axi_rready              => rready,
      s_axi_rdata               => rdata,
      s_axi_rresp               => rresp,
      regs_out                  => regs_out,
      regs_in                   => regs_in,
      regs_in_en                => regs_in_en
    );

  axi_lite_mst: axi_tb_lite_master
    generic map (
      ADDRESS_WIDTH             => 32,
      DATA_WIDTH                => MMIO_DATA_WIDTH,
      NAME                      => "mmio"
    )
    port map (
      clk                       => clk,
      reset_n                   => reset_n,
      m_axil_awvalid            => awvalid,
      m_axil_awready            => awready,
      m_axil_awaddr             => awaddr,
      m_axil_wvalid             => wvalid,
      m_axil_wready             => wready,
      m_axil_wdata              => wdata,
      m_axil_wstrb              => wstrb,
      m_axil_bvalid             => bvalid,
      m_axil_bready             => bready,
      m_axil_bresp              => bresp,
      m_axil_arvalid            => arvalid,
      m_axil_arready            => arready,
      m_axil_araddr             => araddr,
      m_axil_rvalid             => rvalid,
      m_axil_rready             => rready,
      m_axil_rdata              => rdata,
      m_axil_rresp              => rresp
    );

end TestBench;

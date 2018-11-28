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
use work.StreamSim.all;

package axi_tb_pkg is

  component axi_tb_lite_master is
    generic (
      ADDRESS_WIDTH             : natural := 32;
      DATA_WIDTH                : natural := 32;
      NAME                      : string
    );
    port (
      clk                       : in  std_logic;
      reset_n                   : in  std_logic;
      m_axil_awvalid            : out std_logic;
      m_axil_awready            : in  std_logic := '0';
      m_axil_awaddr             : out std_logic_vector(ADDRESS_WIDTH-1 downto 0);
      m_axil_wvalid             : out std_logic;
      m_axil_wready             : in  std_logic := '0';
      m_axil_wdata              : out std_logic_vector(DATA_WIDTH-1 downto 0);
      m_axil_wstrb              : out std_logic_vector((DATA_WIDTH/8)-1 downto 0);
      m_axil_bvalid             : in  std_logic := '0';
      m_axil_bready             : out std_logic;
      m_axil_bresp              : in  std_logic_vector(1 downto 0) := (others => '1');
      m_axil_arvalid            : out std_logic;
      m_axil_arready            : in  std_logic;
      m_axil_araddr             : out std_logic_vector(ADDRESS_WIDTH-1 downto 0);
      m_axil_rvalid             : in  std_logic := '0';
      m_axil_rready             : out std_logic;
      m_axil_rdata              : in  std_logic_vector(DATA_WIDTH-1 downto 0) := (others => '0');
      m_axil_rresp              : in  std_logic_vector(1 downto 0) := (others => '1')
    );
  end component;

  procedure AXILiteWriteResp(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    strobe    : in  std_logic_vector;
    resp      : out std_logic_vector;
    timeout   : in  time
  );

  procedure AXILiteWrite(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    strobe    : in  std_logic_vector;
    exp_resp  : in  std_logic_vector;
    timeout   : in  time
  );

  procedure AXILiteWrite(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    strobe    : in  std_logic_vector;
    timeout   : in  time
  );

  procedure AXILiteWrite(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    timeout   : in  time
  );

  procedure AXILiteReadResp(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : out std_logic_vector;
    resp      : out std_logic_vector;
    timeout   : in  time
  );

  procedure AXILiteRead(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : out std_logic_vector;
    exp_resp  : in  std_logic_vector;
    timeout   : in  time
  );

  procedure AXILiteRead(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : out std_logic_vector;
    timeout   : in  time
  );

  impure function AXILiteReadFn(
    name      : string;
    addr      : std_logic_vector;
    width     : natural;
    timeout   : time
  ) return std_logic_vector;

end axi_tb_pkg;

package body axi_tb_pkg is

  procedure AXILiteWriteResp(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    strobe    : in  std_logic_vector;
    resp      : out std_logic_vector;
    timeout   : in  time
  ) is
  begin
    stream_tb_push(name & "_aw", addr & data & strobe);
    stream_tb_pop(name & "_b", resp, timeout);
  end procedure;

  procedure AXILiteWrite(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    strobe    : in  std_logic_vector;
    exp_resp  : in  std_logic_vector;
    timeout   : in  time
  ) is
    variable resp   : std_logic_vector(1 downto 0);
  begin
    AXILiteWriteResp(name, addr, data, strobe, resp, timeout);
    if not std_match(resp, exp_resp) then
      stream_tb_fail("unexpected write response for AXI-lite master " & name);
    end if;
  end procedure;

  procedure AXILiteWrite(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    strobe    : in  std_logic_vector;
    timeout   : in  time
  ) is
  begin
    AXILiteWrite(name, addr, data, strobe, "00", timeout);
  end procedure;

  procedure AXILiteWrite(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : in  std_logic_vector;
    timeout   : in  time
  ) is
    constant strobe : std_logic_vector(data'length/8-1 downto 0) := (others => '1');
  begin
    AXILiteWrite(name, addr, data, strobe, "00", timeout);
  end procedure;

  procedure AXILiteReadResp(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : out std_logic_vector;
    resp      : out std_logic_vector;
    timeout   : in  time
  ) is
    variable concat : std_logic_vector(data'length+1 downto 0);
  begin
    stream_tb_push(name & "_ar", addr);
    stream_tb_pop(name & "_r", concat, timeout);
    data := concat(concat'high downto 2);
    resp := concat(1 downto 0);
  end procedure;

  procedure AXILiteRead(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : out std_logic_vector;
    exp_resp  : in  std_logic_vector;
    timeout   : in  time
  ) is
    variable resp   : std_logic_vector(1 downto 0);
  begin
    AXILiteReadResp(name, addr, data, resp, timeout);
    if not std_match(resp, exp_resp) then
      stream_tb_fail("unexpected read response for AXI-lite master " & name);
    end if;
  end procedure;

  procedure AXILiteRead(
    name      : in  string;
    addr      : in  std_logic_vector;
    data      : out std_logic_vector;
    timeout   : in  time
  ) is
  begin
    AXILiteRead(name, addr, data, "00", timeout);
  end procedure;

  impure function AXILiteReadFn(
    name      : string;
    addr      : std_logic_vector;
    width     : natural;
    timeout   : time
  ) return std_logic_vector is
    variable data : std_logic_vector(width-1 downto 0);
  begin
    AXILiteRead(name, addr, data, "00", timeout);
    return data;
  end function;

end axi_tb_pkg;

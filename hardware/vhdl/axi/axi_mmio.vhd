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
use work.Utils.all;
use work.axi.all;

-- Provides an AXI4-lite slave MMIO to a serialized std_logic_vector compatible
-- for use as Fletcher MMIO.
entity axi_mmio is
  generic (
    ---------------------------------------------------------------------------
    -- Bus metrics and configuration
    ---------------------------------------------------------------------------
    BUS_ADDR_WIDTH              : natural;
    BUS_DATA_WIDTH              : natural;
    
    ---------------------------------------------------------------------------
    -- Register configuration
    ---------------------------------------------------------------------------
    
    -- Number of 32-bit registers.    
    NUM_REGS                    : natural;
    
    -- Register read/write configuration:
    -- Each character in this string will determine whether its corresponding
    -- register is Write-Only (W), Read-Only (R) or Bidirectional (B).
    --
    -- Example : 0..3 write only, 4..5 read only 6..7 bidi
    -- Register: 0 1 2 3 4 5 6 7
    -- String  : W W W W R R B B -> "WWWWRRBB"
    --
    -- Leaving this string empty ("") will cause all registers to be 
    -- bidirectional.
    REG_CONFIG                  : string := "";
    
    -- Register reset configuration:
    -- Each character in this string will determine whether its corresponding
    -- register is reset when reset is asserted. 'Y' is used to reset, 'N' is
    -- used to not reset.
    --
    -- Example : 0..3 should be reset, 4..7 should not be reset
    -- Register: 0 1 2 3 4 5 6 7
    -- String  : Y Y Y Y N N N N -> "YYYYNNNN"
    --
    -- Leave blank to reset no registers.    
    REG_RESET                   : string := ""
    
  );
  port (
    clk                         : in  std_logic;
    reset_n                     : in  std_logic;
    
    -- Write adress channel
    s_axi_awvalid               : in  std_logic;
    s_axi_awready               : out std_logic;
    s_axi_awaddr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

    -- Write data channel
    s_axi_wvalid                : in  std_logic;
    s_axi_wready                : out std_logic;
    s_axi_wdata                 : in  std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    s_axi_wstrb                 : in  std_logic_vector((BUS_DATA_WIDTH/8)-1 downto 0);

    -- Write response channel
    s_axi_bvalid                : out std_logic;
    s_axi_bready                : in  std_logic;
    s_axi_bresp                 : out std_logic_vector(1 downto 0);

    -- Read address channel
    s_axi_arvalid               : in  std_logic;
    s_axi_arready               : out std_logic;
    s_axi_araddr                : in  std_logic_vector(BUS_ADDR_WIDTH-1 downto 0);

    -- Read data channel
    s_axi_rvalid                : out std_logic;
    s_axi_rready                : in  std_logic;
    s_axi_rdata                 : out std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    s_axi_rresp                 : out std_logic_vector(1 downto 0);
    
    -- Register access
    regs_out                    : out std_logic_vector(BUS_DATA_WIDTH*NUM_REGS-1 downto 0);
    regs_in                     : in  std_logic_vector(BUS_DATA_WIDTH*NUM_REGS-1 downto 0);
    regs_in_en                  : in  std_logic_vector(NUM_REGS-1 downto 0)
  );
end axi_mmio;

architecture Behavioral of axi_mmio is
  
  constant RESP_OK : std_logic_vector(1 downto 0) := "00";
  
  -- The LSB index in the slave address
  constant SLV_ADDR_LSB : natural := log2ceil(BUS_DATA_WIDTH/4) - 1;
  
  -- The MSB index in the slave address
  constant SLV_ADDR_MSB : natural := SLV_ADDR_LSB + log2ceil(NUM_REGS) - 1;
  
  type state_type is (IDLE, WR, BR, RD);
  
  type regs_array_type is array (0 to NUM_REGS-1) of std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
  
  type reg_type is record
    state : state_type;
    waddr : std_logic_vector(SLV_ADDR_MSB - SLV_ADDR_LSB downto 0);
    raddr : std_logic_vector(SLV_ADDR_MSB - SLV_ADDR_LSB downto 0);
    regs  : regs_array_type;
  end record;
  
  type comb_type is record
    awready : std_logic;
    wready  : std_logic;
    bvalid  : std_logic;
    bresp   : std_logic_vector(1 downto 0);
    arready : std_logic;
    rvalid  : std_logic;
    rdata   : std_logic_vector(BUS_DATA_WIDTH-1 downto 0);
    rresp   : std_logic_vector(1 downto 0);    
  end record;
  
  constant comb_default : comb_type := (
    awready => '0',
    wready  => '0',
    bvalid  => '0',
    bresp   => (others => 'U'),
    arready => '0',
    rvalid  => '0',
    rdata   => (others => 'U'),
    rresp   => (others => 'U')
  );
  
  signal r : reg_type;
  signal d : reg_type;
    
begin

  -- Sequential part of state machine
  seq: process(clk) is
  begin
    if rising_edge(clk) then
      r <= d;
      
      -- Reset:
      if reset_n = '0' then
        r.state <= IDLE;
        
        -- Check for each register if it needs to be reset
        if (REG_RESET /= "") then
          for I in 0 to NUM_REGS-1 loop
              if (REG_RESET(i) = 'Y') then
                r.regs(i) <= (others => '0');
              end if;
          end loop;
        end if;
      end if;
    end if;
  end process;
  
  -- Combinatorial part of state machine
  comb: process(r,
    s_axi_awvalid, s_axi_awaddr,              -- Write Address Channel
    s_axi_wvalid, s_axi_wdata, s_axi_wstrb,   -- Write Data Channel
    s_axi_bready,                             -- Write Response Channel
    s_axi_arvalid, s_axi_araddr,              -- Read Address Channel
    s_axi_rready,                             -- Read Data Channel
    regs_in, regs_in_en
  ) is
    variable widx : natural := 0;
    variable ridx : natural := 0;
  
    variable v : reg_type;
    variable o : comb_type;
  begin
    v := r;
    
    o := comb_default;
    
    -- Writes from peripheral
    for I in 0 to NUM_REGS-1 loop
      if regs_in_en(I) = '1' then
        v.regs(I) := regs_in((I+1)*BUS_DATA_WIDTH-1 downto I*BUS_DATA_WIDTH);
      end if;
    end loop;

    case (r.state) is
      when IDLE =>
        if s_axi_awvalid = '1' then
          -- Write request
          v.state := WR;
          v.waddr := s_axi_awaddr(SLV_ADDR_MSB downto SLV_ADDR_LSB);
          o.awready := '1';
        elsif s_axi_arvalid = '1' then
          -- Read request
          v.state := RD;
          v.raddr := s_axi_araddr(SLV_ADDR_MSB downto SLV_ADDR_LSB);
          o.arready := '1';
        end if;

      -- Write data
      when WR =>
        widx := to_integer(unsigned(r.waddr));
        
        if s_axi_wvalid = '1' then
          -- Acknowledge write
          o.wready := '1';
          v.state := BR;
            
          -- Fast write response
          o.bvalid := '1'; 
          o.bresp := RESP_OK;
          
          -- Write only if register is writeable
          if (REG_CONFIG = "") or (REG_CONFIG(widx) = 'W') or (REG_CONFIG(widx) = 'B') then
            v.regs(widx) := s_axi_wdata;
          else
            -- If not writable, generate a warning in simulation            
            report "[AXI MMIO] Attempted to write to read-only register " & 
              integer'image(ridx) & "."
              severity warning;
          end if;
          
          -- Go to idle if write response was already ready.
          if s_axi_bready = '1' then 
              v.state := IDLE;
            end if;
                    
        end if;
        
      -- Waiting for write response handshake
      when BR =>        
        o.bvalid := '1'; 
        o.bresp := RESP_OK;
        if s_axi_bready = '1' then
          v.state := IDLE;
        end if;

      -- Read response
      when RD => 
        ridx := to_integer(unsigned(r.raddr));

        -- Accept the read
        o.rvalid := '1';
        o.rresp := RESP_OK;
                
        -- Check if register is readable
        if (REG_CONFIG = "") or (REG_CONFIG(widx) = 'R') or (REG_CONFIG(widx) = 'B') then
          o.rdata := r.regs(ridx);
        else
          -- Respond with DEADBEEF if not readable
          o.rdata := X"DEADBEEF";
          
          -- Generate a warning in simulation.
          report "[AXI MMIO] Attempted to read from write-only register " & 
            integer'image(ridx) & "."
            severity warning;
        end if;
        
        -- Go back to idle if the read data was accepted.
        if s_axi_rready = '1' then
          v.state := IDLE;
        end if;

    end case;
    
    -- Registered outputs
    d <= v;
    
    -- Combinatorial outputs
    s_axi_awready <= o.awready;
    s_axi_wready  <= o.wready;
    s_axi_bvalid  <= o.bvalid;
    s_axi_bresp   <= o.bresp;
    s_axi_arready <= o.arready;
    s_axi_rvalid  <= o.rvalid;
    s_axi_rdata   <= o.rdata;
    s_axi_rresp   <= o.rresp;
    
  end process;
  
  -- Serialize the registers onto a single bus
  ser_regs: for I in 0 to NUM_REGS-1 generate
  begin
    regs_out((I+1) * BUS_DATA_WIDTH-1 downto I*BUS_DATA_WIDTH) <= r.regs(I);
  end generate;
  
end Behavioral;

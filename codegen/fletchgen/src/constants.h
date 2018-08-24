// Copyright 2018 Delft University of Technology
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#pragma once

namespace fletchgen {
/**
 * @brief Constant expressions.
 *
 * This contains all sorts of constant expressions, such as port names which are based on the hardware design.
 */
namespace ce {

// Status, Control, Return(2)
constexpr unsigned int NUM_DEFAULT_REGS = 4;

constexpr char
    COPYRIGHT_NOTICE[] = "-- Copyright 2018 Delft University of Technology\n"
                         "--\n"
                         "-- Licensed under the Apache License, Version 2.0 (the \"License\");\n"
                         "-- you may not use this file except in compliance with the License.\n"
                         "-- You may obtain a copy of the License at\n"
                         "--\n"
                         "--     http://www.apache.org/licenses/LICENSE-2.0\n"
                         "--\n"
                         "-- Unless required by applicable law or agreed to in writing, software\n"
                         "-- distributed under the License is distributed on an \"AS IS\" BASIS,\n"
                         "-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n"
                         "-- See the License for the specific language governing permissions and\n"
                         "-- limitations under the License.\n";

constexpr char
    GENERATED_NOTICE[] = "-- This file was automatically generated by FletchGen. Modify this file\n"
                         "-- at your own risk.\n";

constexpr char
    DEFAULT_LIBS[] = "library ieee;\n"
                     "use ieee.std_logic_1164.all;\n"
                     "use ieee.std_logic_misc.all;\n"
                     "\n"
                     "library work;\n"
                     "use work.Arrow.all;\n"
                     "use work.Columns.all;\n"
                     "use work.Interconnect.all;\n"
                     "use work.Wrapper.all;\n";

// Generic names from hardware
constexpr char REG_WIDTH[] = "REG_WIDTH";
constexpr char BUS_ADDR_WIDTH[] = "BUS_ADDR_WIDTH";
constexpr char BUS_DATA_WIDTH[] = "BUS_DATA_WIDTH";
constexpr char BUS_STROBE_WIDTH[] = "BUS_STROBE_WIDTH";
constexpr char BUS_LEN_WIDTH[] = "BUS_LEN_WIDTH";
constexpr char BUS_BURST_STEP_LEN[] = "BUS_BURST_STEP_LEN";
constexpr char BUS_BURST_MAX_LEN[] = "BUS_BURST_MAX_LEN";
constexpr char INDEX_WIDTH[] = "INDEX_WIDTH";
constexpr char TAG_WIDTH[] = "TAG_WIDTH";
constexpr char CONFIG_STRING[] = "CFG";

// Port names from hardware
constexpr char BUS_CLK[] = "bus_clk";
constexpr char BUS_RST[] = "bus_reset";
constexpr char ACC_CLK[] = "acc_clk";
constexpr char ACC_RST[] = "acc_reset";
constexpr char NUM_USER_REGS[] = "NUM_USER_REGS";

// Default values
constexpr unsigned int MMIO_DATA_WIDTH_DEFAULT = 32;
constexpr unsigned int MMIO_ADDR_WIDTH_DEFAULT = 32;
constexpr unsigned int BUS_ADDR_WIDTH_DEFAULT = 64;
constexpr unsigned int BUS_DATA_WIDTH_DEFAULT = 512;
constexpr unsigned int BUS_STROBE_WIDTH_DEFAULT = BUS_DATA_WIDTH_DEFAULT / 8;
constexpr unsigned int BUS_LEN_WIDTH_DEFAULT = 8;
constexpr unsigned int BUS_BURST_STEP_LEN_DEFAULT = 1;
constexpr unsigned int BUS_BURST_MAX_LEN_DEFAULT = 32;
constexpr unsigned int INDEX_WIDTH_DEFAULT = 32;
constexpr unsigned int TAG_WIDTH_DEFAULT = 1;
constexpr unsigned int REGS_PER_ADDRESS = BUS_ADDR_WIDTH_DEFAULT / MMIO_DATA_WIDTH_DEFAULT;

} //namespace ce
} //namespace fletchgen

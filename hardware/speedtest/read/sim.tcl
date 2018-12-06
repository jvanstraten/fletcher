# Copyright 2018 Delft University of Technology
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

proc timestamp {} {
  return [clock seconds]
}

proc add_source {file_name compile_flags} {
  global compile_list

  if {[file exists $file_name]} {
    # calculate md5 hash
    set file_hash [md5::md5 -hex $file_name]

    # Check if file exists in list
    for {set i 0} {$i < [llength $compile_list]} {incr i} {
      set comp_unit [lindex $compile_list $i]
      if {[lindex $comp_unit 0] == $file_name} {
        # file exists, check if mode changed
        if {[lindex $comp_unit 3] != $compile_flags} {
          # change the mode and reset the timestamp
          lset compile_list $i [list $file_name $file_hash 0 $compile_flags]
        }
        return
      }
    }

    # if the file isn't in the list yet, so we haven't returned, add file to 
    # compile list
    lappend compile_list [list $file_name $file_hash 0 $compile_flags]
  } else {
    error $file_name " does not exist."
  }
  return
}

# compile all sources added to the compilation list
proc compile_sources {{quiet 1}} {
  global compile_list

  for {set i 0} {$i < [llength $compile_list]} {incr i} {
    set comp_unit [lindex $compile_list $i]

    # extract file information
    set file_name [lindex $comp_unit 0] 
    set file_hash [lindex $comp_unit 1]
    set file_last [lindex $comp_unit 2]
    set compile_flags [lindex $comp_unit 3]

    # check if file still exists
    if {[file exists $file_name]} {
      set file_disk_time [file mtime $file_name]
      # check if file needs to be recompiled
      if {($file_disk_time > $file_last)} {
        set file_disk_hash [md5::md5 -hex $file_name]
        if {($file_disk_time > $file_last) || ($file_hash != $file_disk_hash)} {
          echo "Compiling \($compile_flags\):" [file tail $file_name]
          eval vcom "-quiet $compile_flags $file_name"
          # if compilation failed, the script will exit and the file will not be
          # added to the compile list.

          # update the compile list
          lset compile_list $i [list $file_name $file_hash [timestamp] $compile_flags]
        }
      }
    } else {
      echo "File " $file_name " no longer exists. Removing from compile list."
      set compile_list [lreplace $compile_list $i $i]
    }
  }
}

# recompile all sources added to the compilation list
proc recompile_sources {{quiet 1}} {
  global compile_list

  # loop over each compilation unit
  for {set i 0} {$i < [llength $compile_list]} {incr i} {
    set comp_unit [lindex $compile_list $i]

    # extract file information
    set file_name [lindex $comp_unit 0] 
    set file_hash [lindex $comp_unit 1]
    set compile_flags [lindex $comp_unit 3]

    # set timestamp to 0
    lset compile_list $i [list $file_name $file_hash 0 $compile_flags]
  }
  compile_sources $quiet
}

proc suppress_warnings {} {
  global StdArithNoWarnings
  global StdNumNoWarnings
  global NumericStdNoWarnings

  set StdArithNoWarnings 1
  set StdNumNoWarnings 1
  set NumericStdNoWarnings 1
}

proc colorize {l c} {
  foreach obj $l {
    # get leaf name
    set nam [lindex [split $obj /] end]
    # change color
    property wave $nam -color $c
  }
}

proc add_colored_unit_signals_to_group {group unit in_color out_color internal_color} {
  # add wave -noupdate -expand -group $group -divider -height 32 $group
  catch {add wave -noupdate -expand -group $group $unit}

  set input_list    [lsort [find signals -in        $unit]]
  set output_list   [lsort [find signals -out       $unit]]
  set port_list     [lsort [find signals -ports     $unit]]
  set internal_list [lsort [find signals -internal  $unit]]

  # This could be used to work with dividers:
  colorize $input_list     $in_color
  colorize $output_list    $out_color
  colorize $internal_list  $internal_color
}

proc add_waves {groups {in_color #00FFFF} {out_color #FFFF00} {internal_color #FFFFFF}} {
  for {set group_idx 0} {$group_idx < [llength $groups]} {incr group_idx} {
    set group [lindex [lindex $groups $group_idx] 0]
    set unit  [lindex [lindex $groups $group_idx] 1]
    add_colored_unit_signals_to_group $group $unit $in_color $out_color $internal_color
    WaveCollapseAll 0
  }
}

proc close_all_sources {} {
  set windows [view]
  foreach window $windows {
    if {[string first ".source" $window] != -1} {
      noview $window
    }
  }
}

proc simulate {lib top {duration -all} cmd_len} {
  global last_sim
  set last_sim [list $lib $top $duration]

  compile_sources

  set generics [list "-GXX_CMD_LEN_MIN=$cmd_len"]

  eval vsim "-novopt $generics $lib.$top"
  suppress_warnings

  if [batch_mode] {
  } else {
    catch {add log -recursive *}
    set lcname [string tolower $top]
    set tcname sim:/${lcname}/*
    set tbname sim:/${lcname}/tb/*
    set uutname sim:/${lcname}/tb/uut/*
    set tcsig [list "TC" $tcname]
    set tbsig [list "TB" $tbname]
    set uutsig [list "UUT" $uutname]
    configure wave -signalnamewidth 1
    add_waves [list $tcsig $tbsig $uutsig]
    configure wave -namecolwidth    256
    configure wave -valuecolwidth   192
  }

  onbreak resume
  run $duration
  onbreak ""
  close_all_sources

  wave zoom full

  echo "Run 'resim' to run the simulation again."
}

proc resim {} {
  global last_sim
  if {$last_sim == 0} {
    echo "No simulation to rerun."
    return 1
  }
  set lib [lindex $last_sim 0]
  set top [lindex $last_sim 1]
  set duration [lindex $last_sim 2]

  compile_sources
  write format wave wave.cfg
  vsim -novopt -assertdebug $lib.$top
  suppress_warnings
  add log -recursive *
  onbreak resume
  run $duration
  onbreak ""
  close_all_sources
  do wave.cfg
  echo "Run 'resim' to run the simulation again."
}

# initialization
package require md5
set last_sim 0
set last_failure 0
set compile_list [list]

vlib work
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/utils/Utils.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnConfigParse.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/Streams.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/buffers/Buffers.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnConfig.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/interconnect/Interconnect.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamSerializer.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/buffers/BufferReaderCmdGenBusReq.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/buffers/BufferReaderRespCtrl.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderListSyncDecoder.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/Columns.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamGearbox.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamNormalizer.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamParallelizer.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/buffers/BufferReaderCmd.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/buffers/BufferReaderPost.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/buffers/BufferReaderResp.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderListSync.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderUnlockCombine.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/interconnect/BusReadBuffer.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamFIFOCounter.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/utils/Ram1R1W.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/buffers/BufferReader.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderList.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderListPrim.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderNull.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderStruct.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamArb.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamFIFO.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamSlice.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamSync.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderLevel.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/interconnect/BusReadArbiterVec.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/streams/StreamBuffer.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReaderArb.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/columns/ColumnReader.vhd {-quiet -work work -2008}
add_source $::env(FLETCHER_HARDWARE_DIR)/vhdl/wrapper/Wrapper.vhd {-quiet -work work -2008}
add_source ColumnReaderSpeed_tc.vhd {-quiet -work work -2008}
simulate work columnreaderspeed_tc "100 ms" 10
simulate work columnreaderspeed_tc "100 ms" 20
simulate work columnreaderspeed_tc "100 ms" 50
simulate work columnreaderspeed_tc "100 ms" 100
simulate work columnreaderspeed_tc "100 ms" 200
simulate work columnreaderspeed_tc "100 ms" 500
simulate work columnreaderspeed_tc "100 ms" 1000
simulate work columnreaderspeed_tc "100 ms" 2000
simulate work columnreaderspeed_tc "100 ms" 5000
simulate work columnreaderspeed_tc "100 ms" 10000
simulate work columnreaderspeed_tc "100 ms" 20000
simulate work columnreaderspeed_tc "100 ms" 50000
simulate work columnreaderspeed_tc "100 ms" 100000

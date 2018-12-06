
data.csv: parse.py vsim_out
	python3 $^ $@

vsim_out: sim.tcl ColumnReaderSpeed_tc.vhd
	vsim < sim.tcl > $@


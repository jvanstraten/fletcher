
data.csv: parse.py vsim_out
	python3 $^ $@

vsim_out: sim.tcl ColumnWriterSpeed_tc.vhd
	vsim < sim.tcl | tee $@

.PHONY: clean
clean:
	rm -rf work
	rm -f data.csv transcript vsim_out vsim.wlf

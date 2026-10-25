transcript on
if ![file isdirectory verilog_libs] {
	file mkdir verilog_libs
}

vlib verilog_libs/altera_ver
vmap altera_ver ./verilog_libs/altera_ver
vlog -vlog01compat -work altera_ver {c:/altera/11.0/quartus/eda/sim_lib/altera_primitives.v}

vlib verilog_libs/cycloneive_ver
vmap cycloneive_ver ./verilog_libs/cycloneive_ver
vlog -vlog01compat -work cycloneive_ver {c:/altera/11.0/quartus/eda/sim_lib/cycloneive_atoms.v}

if {[file exists gate_work]} {
	vdel -lib gate_work -all
}
vlib gate_work
vmap work gate_work

vlog -vlog01compat -work work +incdir+. {AD9226TEST_8_1200mv_85c_slow.vo}

vlog -vlog01compat -work work +incdir+D:/Ddisk/FPGA/quartus/KV/AD9226/AD9226_FPGA_V1.0/prj/../testbench {D:/Ddisk/FPGA/quartus/KV/AD9226/AD9226_FPGA_V1.0/prj/../testbench/AD9226_TEST_tb.V}

vsim -t 1ps +transport_int_delays +transport_path_delays -L altera_ver -L cycloneive_ver -L gate_work -L work -voptargs="+acc" AD9226_TEST_tb

add wave *
view structure
view signals
run -all

open_project Sim_Spectrum.gprj
set_option -top_module video_top
set_option -verilog_std sysv2017
set_option -include_path {src/gowin_fft}
set_option -place_option 2
set_option -route_option 2
run all

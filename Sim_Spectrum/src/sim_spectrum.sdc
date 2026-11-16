// ============================================================================
// sim_spectrum.sdc  --  时序约束 (Tang Nano 20K / GW2AR-18C)
// ============================================================================

create_clock -name I_clk -period 37.037 -waveform {0 18.518} [get_ports {I_clk}]
create_clock -name tmds_clk -period 13.468 -waveform {0 6.734} [get_pins {u_clkdiv/CLKOUT}]
create_clock -name adc_clk -period 18.518 -waveform {0 9.259} [get_pins {u_adc_pll/rpll_inst/CLKOUT}]

// AD9226 源同步输入延时
set_input_delay -clock adc_clk -max 10.0 [get_ports {I_adc_d[*] I_adc_otr}]
set_input_delay -clock adc_clk -min  2.0 [get_ports {I_adc_d[*] I_adc_otr}]

// 跨时钟域 false path (由 2 级同步器与双时钟乒乓 BSRAM 保证)
set_false_path -from [get_clocks {tmds_clk}] -to [get_clocks {adc_clk}]
set_false_path -from [get_clocks {adc_clk}] -to [get_clocks {tmds_clk}]

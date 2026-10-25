//Copyright (C)2014-2025 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//Device: GW2AR-18 (Tang Nano 20K)  AD9226 采集例程

// 板载晶振 50MHz
create_clock -name clk50m -period 20.000 -waveform {0 10} [get_ports {I_clk}]
// 130MHz / 65MHz 由 PLL 派生, PnR 自动推导

// ============================================================================
// ad9226_spectrum.sdc  --  时序约束 (Tang Nano 20K / GW2AR-18C)
//
//   三个真实时钟:
//     I_clk      27.000 MHz  板载晶振
//     tmds_clk   74.250 MHz  像素时钟 (TMDS_rPLL 371.25MHz 经 CLKDIV/5)
//     adc_clk    54.000 MHz  AD9226 采样时钟 (ad9226_pll CLKOUT)
// ============================================================================

// ---------------- 1. 板载晶振 ----------------
create_clock -name I_clk -period 37.037 -waveform {0 18.518} [get_ports {I_clk}]

// ---------------- 2. 像素时钟 (CLKDIV 输出) ----------------
create_clock -name tmds_clk -period 13.468 -waveform {0 6.734} [get_pins {u_clkdiv/CLKOUT}]

// ---------------- 3. AD9226 采样/FFT 时钟 ----------------
//   由 ad9226_pll 的 CLKOUT 直接输出到 O_clk_adc, 同时驱动采样寄存器和 FFT
create_clock -name adc_clk -period 18.518 -waveform {0 9.259} [get_pins {u_adc_pll/rpll_inst/CLKOUT}]

// ============================================================================
// AD9226 并行接口: 源同步 (source synchronous)
//
//   时钟和数据的发射沿是同一个 adc_clk 上升沿:
//     FPGA 在 T 时刻的上升沿把 CLK 送出 (管脚延时 ~1-3ns)
//     AD9226 在收到 CLK 上升沿后 tPD (数据手册典型 3.8ns, 取 5ns) 更新 D0..D11
//     数据经 PCB/杜邦线 (~1ns) 回到 FPGA
//     FPGA 在 T + 18.518ns 的下一个上升沿采样 -> 拿到的是这一次转换的结果
//
//   所以数据相对发射沿的最大延迟 = 管脚 3 + tPD 5 + 走线 1 ≈ 9ns, 取 10ns 留裕量
//   min 取 2ns (最早到达时间, 用于 hold 检查)
// ============================================================================
set_input_delay -clock adc_clk -max 10.0 [get_ports {I_adc_d[*] I_adc_otr}]
set_input_delay -clock adc_clk -min  2.0 [get_ports {I_adc_d[*] I_adc_otr}]

// O_clk_adc 是时钟输出, 不加输出延时 (内部路径 FF/时钟网络 -> 管脚 由工具按 adc_clk 分析)

// ============================================================================
// 跨时钟域 (全部由设计保证, 不需要时序收敛)
//   1. 像素域 -> adc 域: span[1:0] (2 级同步)、frame_tog (2 级同步 + 边沿检测)
//   2. adc 域 -> 像素域: spec_data_if 的 bank 选择 (2 级同步) + spec_ram 双时钟 BSRAM
// ============================================================================
set_false_path -from [get_clocks {tmds_clk}] -to [get_clocks {adc_clk}]
set_false_path -from [get_clocks {adc_clk}] -to [get_clocks {tmds_clk}]

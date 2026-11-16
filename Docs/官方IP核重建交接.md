# 交接：在「AD9226 + HDMI 例程」原始版上用官方 FFT IP 重建底层

> 本文档面向：拿最早的 AD9226+HDMI 例程工程、准备把频谱分析仪的底层（FFT 及其数据通路）换成 Gowin 官方 FFT IP 核的人。
> 目的：把**现有功能、参数、定标、验收标准、以及已经踩过的坑**一次讲清，避免重做时把已解决的问题再踩一遍。
> 对应基线：本仓库 v1.7.4（`d99ad9a`），时序 tmds 80.546 MHz（8.5% 余量）、adc 65.349 MHz（21% 余量）、TNS 全 0。

---

## 1. 产品是什么

一块 **AD9226（12 bit / 65 MSPS）高速 ADC + Tang Nano 20K（GW2AR-LV18QN88）** 的数字频谱分析仪，
以 54 MSPS 采样、4096 点 FFT 出谱，1280×720@60 HDMI 输出，面板式 UI（按键 + 旋转编码器 + 菜单）。

三个视图（KEY2 循环）：

| 视图 | 内容 |
|---|---|
| 0 | 频谱 + 右侧菜单栏 |
| 1 | 纯净频谱（菜单隐藏） |
| 2 | 时域波形（1024 点 + 1~5 次谐波迹线） |

---

## 2. 硬件与时钟

| 时钟 | 频率 | 来源 | 用途 |
|---|---|---|---|
| `adc_clk` | 54 MHz | 板上 27 MHz 晶振经 `ad9226_pll`（rPLL） | ADC 采样、抽取、加窗、FFT、取模 |
| `pix_clk` | 74.25 MHz | `TMDS_rPLL` 371.25 MHz + `CLKDIV` DIV_MODE=5 | 显示时序、像素绘制 |
| `tmds_clk` | 371.25 MHz | `TMDS_rPLL` 第 2 输出 | DVI_TX 串行化 |
| 输出引脚 `O_clk_adc` | 54 MHz | `assign O_clk_adc = adc_clk` 直出 | 给 AD9226 的采样时钟 |

- ADC 数据在 `adc_clk` 上升沿采样，`adc_d[11:0]`，`adc_otr` 溢出标志（未参与显示逻辑）。
- **`adc_clk` 必须能直出引脚**（Gowin：时钟网络输出到 IO 需要在约束里允许，例程已处理）。
- 跨域只有一条通道：FFT 出完一帧 → 写侧翻 bank（`adc_clk` 域） → 2 级同步 → 读侧（`pix_clk` 域）读另一块 bank（`spec_data_if.v`）。
- **逐脚引脚表、`.cst` / `.sdc` 全文与约束的坑见 §3。**

---

## 3. 引脚与时序约束

- **器件**：GW2AR-LV18QN88C8/I7（Tang Nano 20K / GW2AR-18C，BANK 3.3 V）
- **文件**：`src/ad9226_hdmi_spectrum.cst`（引脚）、`src/ad9226_spectrum.sdc`（时序），都在 `.gprj` 里关联
- 原始例程里 HDMI 与 27 MHz 晶振的约束已经有了，**只需要补 AD9226 的 14 根线和人机界面那 10 根**。

### 3.1 引脚总表

| 信号 | 引脚 | IO 类型 / 属性 | 说明 |
|---|---|---|---|
| `I_clk` | **4** | LVCMOS33, PULL_UP | 板载 27 MHz 晶振 |
| `I_rst` | **88** | LVCMOS33, PULL_DOWN, SINGLE_RESISTOR=ON | 板载 S2 复位键（**按下为高**） |
| `I_key[0]` | 15 | LVCMOS33, PULL_UP | KEY1 Span 循环（低有效） |
| `I_key[1]` | 16 | LVCMOS33, PULL_UP | KEY2 视图切换（频谱+菜单 / 纯净频谱 / 时域） |
| `I_key[2]` | 17 | LVCMOS33, PULL_UP | KEY3 AUTO Span |
| `I_key[3]` | 18 | LVCMOS33, PULL_UP | KEY4 光标四态 |
| `I_key[4]` | 19 | LVCMOS33, PULL_UP | KEY5 窗函数循环 |
| `I_enc_a` | 48 | LVCMOS33, PULL_UP | EC11 A 相 |
| `I_enc_b` | 49 | LVCMOS33, PULL_UP | EC11 B 相 |
| `I_enc_sw` | 72 | LVCMOS33, PULL_UP | EC11 按压（低有效） |
| `O_led[0]` | 20 | LVCMOS33, PULL_UP, DRIVE=8 | LED_STAT 心跳（低电平点亮） |
| `O_led[1]` | 71 | LVCMOS33, PULL_UP, DRIVE=8 | LED_OVR 过载（低电平点亮） |
| `O_tmds_clk_p/n` | 33, 34 | **LVDS25**, PULL_NONE, DRIVE=3.5 | HDMI 时钟对 |
| `O_tmds_data_p[0]/n` | 35, 36 | LVDS25 | HDMI 数据 0（蓝） |
| `O_tmds_data_p[1]/n` | 37, 38 | LVDS25 | HDMI 数据 1（绿） |
| `O_tmds_data_p[2]/n` | 39, 40 | LVDS25 | HDMI 数据 2（红） |
| `O_clk_adc` | **76** | LVCMOS33, PULL_NONE, DRIVE=8 | **54 MHz 采样时钟送出**给 AD9226 CLK |
| `I_adc_d[0..3]` | 73, 74, 75, 77 | LVCMOS33, PULL_NONE | ADC D0..D3 |
| `I_adc_d[4..7]` | 27, 28, 25, 26 | LVCMOS33, PULL_NONE | ADC D4..D7 |
| `I_adc_d[8..11]` | 29, 30, 31, **41** | LVCMOS33, PULL_NONE | ADC D8..D11（**D11 在另一排**） |
| `I_adc_otr` | 42 | LVCMOS33, PULL_NONE | ADC 溢出标志 |

### 3.2 排针接线（AD9226 模块 → 开发板）

```
J6（右侧排针，从 USB/HDMI 一侧往下数）
序号:   1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20
引脚:   5V   GND  76   80   42   41   56   54   51   48   55   49   86   79   GND  3V3  72   71   53   52
ADC:               CLK  ─    OTR  D11

J5（左侧排针）
序号:   1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20
引脚:   73   74   75   85   77   15   16   27   28   25   26   29   30   31   17   20   19   18   3V3  GND
ADC:    D0   D1   D2   ─    D3                            D4   D5   D6   D7   D8   D9   D10
```

- AD9226 模块侧是 **P2（2×10 排针）**：`5V GND CLK OTR D0..D11`（以模块丝印为准）。
- ADC 模块用 **5 V 供电**（板载 AD8138 单端转差分 + AX1117-3.3），信号侧 3.3 V 电平，直连即可。
- 采样时钟走 J6-3（紧挨 GND），回流通路最短；D11 单独在 J6-6。

### 3.3 绝对不要用的引脚

| 引脚 | 原因 |
|---|---|
| **54, 55, 56** | SSPI 专用脚，综合直接报 `cannot be placed` |
| 85, 86 | SPI Flash D1/D0（配置用） |
| 80 | SPI Flash D2 |
| 79 | 板载 WS2812 数据 |
| 51 | PA_EN（功放使能） |
| 52, 53 | HDMI EDID I²C |
| 87 | 板载 S1（人机界面移到底板后不再使用；88 仍是硬件复位） |

### 3.4 `.cst` 全文（可直接用）

```tcl
// ============================================================================
// ad9226_hdmi_spectrum.cst  --  引脚约束 (Tang Nano 20K / GW2AR-LV18QN88C8/I7)
//
//   板载资源 (不可更改):
//     I_clk  = 4    (27MHz 晶振)     I_rst = 88 (S2, 硬件复位)
//     HDMI   = 33..40
//   人机界面已全部移到打板底板 (见下面), 板载 S1 和 6 只 LED 不再由本工程驱动
//     HDMI   = 33..40 (4 对 LVDS)
//
//   AD9226 的 14 根线全部接两侧 2x10 排针 (2.54mm), 并避开了有复用功能的脚:
//     避开 85/86 (SPI Flash D1/D0)  80 (Flash D2)   79 (WS2812_DIN)
//          51 (PA_EN)  52/53 (HDMI EDID I2C)
//     54/55/56 是 SSPI 专用脚, 综合会直接报 "cannot be placed" —— 也不能用
//
//   (J5/J6 是本工程的记法: J6 = 靠 USB/HDMI 一侧的右排, J5 = 左排; 板上丝印以实际为准)
//   ---- 排针 J6 (右侧, 从 USB 口往下数) ----
//     序号:  1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20
//     功能:  5V   GND  76   80   42   41   56   54   51   48   55   49   86   79   GND  3V3  72   71   53   52
//     AD9226:          CLK       OTR  D11
//
//   ---- 排针 J5 (左侧) ----
//     序号:  1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20
//     功能:  73   74   75   85   77   15   16   27   28   25   26   29   30   31   17   20   19   18   3V3  GND
//     AD9226: D0   D1   D2        D3                            D4   D5   D6   D7   D8   D9   D10
//
//   ---- 打板底板新增 (5 键 + EC11 + 2 灯) ----
//     KEY1..KEY5 = 15,16,17,18,19      (J5 原 LED 脚)
//     EC11 A/B/SW = 48,49,72           (J6)
//     LED_STAT/OVR = 20,71
//     板载 S1(87) 不再使用; S2(88) 仍作硬件复位
//
//   ---- AD9226 模块侧 (P2 为 2x10 排针) ----
//     5V  GND  CLK  OTR  D0..D11      (以模块丝印为准)
//
//   完整对照表 / 电平与时序说明见 doc/引脚对照与约束.md
// ============================================================================

// ---------------- 板载: 27MHz 晶振 ----------------
IO_LOC "I_clk" 4;
IO_PORT "I_clk" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;

// ---------------- 板载: 按键 ----------------
IO_LOC "I_rst" 88;
IO_PORT "I_rst" IO_TYPE=LVCMOS33 PULL_MODE=DOWN SINGLE_RESISTOR=ON BANK_VCCIO=3.3;
// 板载 S1 (87) 不再使用: 按键移到打板底板, 见下面的 I_key[0..4]

// ---------------- 打板: 人机界面 (5 键 + EC11 + 2 灯) ----------------
//   按键: 一端接 GND, 另一端接引脚, 板上 10k 上拉到 3.3V —— 按下为低
//   编码器: A/B 各 10k 上拉到 3V3 (必须, 机械触点需要上拉); C(公共端) 接 GND;
//           消抖电容默认不装 (软件已做), 只留 0603 焊盘; 要装也只能 10nF
//   LED: 3V3 -> 1k -> LED -> 引脚 (低电平点亮, 与板载 LED 同极性)

IO_LOC "I_key[0]" 15;      // KEY1  Span 循环
IO_PORT "I_key[0]" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;
IO_LOC "I_key[1]" 16;      // KEY2  预留 (Ref Level)
IO_PORT "I_key[1]" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;
IO_LOC "I_key[2]" 17;      // KEY3  AUTO 自动跨度
IO_PORT "I_key[2]" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;
IO_LOC "I_key[3]" 18;      // KEY4  光标开关 (开: 编码器移光标, 关: 编码器调跨度)
IO_PORT "I_key[3]" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;
IO_LOC "I_key[4]" 19;      // KEY5  Preset
IO_PORT "I_key[4]" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;

IO_LOC "I_enc_a" 48;       // EC11 A
IO_PORT "I_enc_a" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;
IO_LOC "I_enc_b" 49;       // EC11 B
IO_PORT "I_enc_b" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;
IO_LOC "I_enc_sw" 72;      // EC11 按压开关
IO_PORT "I_enc_sw" IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3;

IO_LOC "O_led[0]" 20;      // LED_STAT 心跳
IO_PORT "O_led[0]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;
IO_LOC "O_led[1]" 71;      // LED_OVR  过载
IO_PORT "O_led[1]" IO_TYPE=LVCMOS33 PULL_MODE=UP DRIVE=8 BANK_VCCIO=3.3;

// ---------------- HDMI (4 对 LVDS, 不可改) ----------------
IO_LOC "O_tmds_clk_p" 33,34;
IO_PORT "O_tmds_clk_p" IO_TYPE=LVDS25 PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;
IO_LOC "O_tmds_data_p[0]" 35,36;
IO_PORT "O_tmds_data_p[0]" IO_TYPE=LVDS25 PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;
IO_LOC "O_tmds_data_p[1]" 37,38;
IO_PORT "O_tmds_data_p[1]" IO_TYPE=LVDS25 PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;
IO_LOC "O_tmds_data_p[2]" 39,40;
IO_PORT "O_tmds_data_p[2]" IO_TYPE=LVDS25 PULL_MODE=NONE DRIVE=3.5 BANK_VCCIO=3.3;

// ============================================================================
// AD9226 接口 (14 根: 1 时钟 + 12 数据 + 1 OTR)
// ============================================================================
// ---- 采样时钟 54MHz -> AD9226 CLK (J6 第 3 脚, 紧挨 GND, 回流通路最短) ----
IO_LOC "O_clk_adc" 76;
IO_PORT "O_clk_adc" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;

// ---- 数据 D0..D7 (J6 连续排布) ----
IO_LOC "I_adc_d[0]" 73;
IO_PORT "I_adc_d[0]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[1]" 74;
IO_PORT "I_adc_d[1]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[2]" 75;
IO_PORT "I_adc_d[2]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[3]" 77;
IO_PORT "I_adc_d[3]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[4]" 27;
IO_PORT "I_adc_d[4]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[5]" 28;
IO_PORT "I_adc_d[5]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[6]" 25;
IO_PORT "I_adc_d[6]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[7]" 26;
IO_PORT "I_adc_d[7]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;

// ---- 数据 D8..D11 (J5 连续排布) ----
IO_LOC "I_adc_d[8]" 29;
IO_PORT "I_adc_d[8]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[9]" 30;
IO_PORT "I_adc_d[9]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[10]" 31;
IO_PORT "I_adc_d[10]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
IO_LOC "I_adc_d[11]" 41;
IO_PORT "I_adc_d[11]" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;

// ---- OTR 过压标志 (J6) ----
IO_LOC "I_adc_otr" 42;
IO_PORT "I_adc_otr" IO_TYPE=LVCMOS33 PULL_MODE=NONE BANK_VCCIO=3.3;
```

要点：
- `I_key[*]` / `I_enc_*` 一律 `PULL_MODE=UP`（按键一端接 GND；EC11 机械触点也**必须**上拉，板上再并 10 kΩ）。
- `I_rst` 是 `PULL_MODE=DOWN`：不按时为低，按下为高 —— 与顶层 `input I_rst`（按下为高）一致。
- HDMI 四对用 `IO_TYPE=LVDS25` + `BANK_VCCIO=3.3`（Tang Nano 20K 的 HDMI BANK 就是 3.3 V，别改成 2.5 V）。
- `O_clk_adc` 用 `DRIVE=8` 直驱 ADC 时钟；它是**真时钟输出**（由 `ad9226_pll` 的 CLKOUT 直接到管脚），不要经过普通逻辑。
- **注释里的按键功能是旧版**（写成 "KEY2 预留 Ref Level / KEY5 Preset"）——以 `key_enc_ctrl.v` 为准：
  KEY1 Span、KEY2 视图、KEY3 AUTO、KEY4 光标、KEY5 窗；**Preset 是编码器长按**。

### 3.5 `.sdc` 全文（可直接用）

```tcl
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
```

要点：

1. **三个真实时钟**：`I_clk` 27.000 MHz（周期 37.037 ns）、`tmds_clk` 74.250 MHz（13.468 ns，定义在 `u_clkdiv/CLKOUT` 上）、`adc_clk` 54.000 MHz（18.518 ns，定义在 `u_adc_pll/rpll_inst/CLKOUT`）。
   PLL 输出必须用 `get_pins` 指到具体 CLKOUT 引脚上，不能用 `get_ports`。
2. **AD9226 是源同步接口**：时钟与数据同一个发射沿。`set_input_delay -max 10.0 / -min 2.0`
   的由来是"管脚 3 ns + tPD 5 ns + 走线 1 ns ≈ 9 ns，取 10 ns 留裕量；最早到达取 2 ns 供 hold 检查"。
   Swap 成别的接法/更长的杜邦线要重新给这两个数。
3. **跨域全部 false path**：像素域 → adc 域（span 2 级同步、frame_tog 2 级同步 + 边沿检测）、
   adc 域 → 像素域（`spec_data_if` 的 bank 2 级同步 + 双时钟 BSRAM），靠设计保证，不做时序收敛。
4. `O_clk_adc` 不加输出延时（内部 FF/时钟网络到管脚由工具按 `adc_clk` 分析）。

### 3.6 约束相关的坑

1. **改 `.cst` 后必须重跑 PnR**（只综合不检查引脚）；引脚冲突/不可放置的错误只在 place 阶段报。
2. **未被例化的模块会被综合器当"顶层候选"**：Verilog 里没例化的模块可能被当成第二顶层，
   导致 `.cst` 全部报错 —— 所以三个数据源模块（ADC / 单音 / 扫频）必须全部例化（哪怕用 `localparam USE_ADC` 关掉）。
3. **`I_adc_d[*]` 用通配**写 input delay；如果改成单独命名端口，这条约束要跟着改。
4. 引脚图与逐脚对照见仓库里已有的 `ad9226_hdmi_spectrum/doc/引脚对照与约束.md`、
   `引脚约束汇总.md` / `.csv`、`TangNano20K_引脚图.jpg`。

---

## 4. 功能需求（逐条，可当验收单）

### 4.1 七个频率跨度（Span）

`dec_sel` 0..6，依次（KEY1 循环切换）：

| 档 | Span | ADC 抽取比 | 有效采样率 fs | RBW（Hann, 1.5/T） | 一帧采集时长 T=4096/fs | 刷新率 |
|---|---|---|---|---|---|---|
| 0 | 1.000 MHz | /27 | 2 MSPS | 732 Hz | 2.048 ms | ~150 fps |
| 1 | 250.000 kHz | /108 | 500 kSPS | 183 Hz | 8.192 ms | ~79 fps |
| 2 | 50.000 kHz | /540 | 100 kSPS | 36.6 Hz | 40.96 ms | ~22 fps |
| 3 | 10.000 kHz | /2700 | 20 kSPS | 7.3 Hz | 204.8 ms | ~4.8 fps |
| 4 | 1.000 kHz | /27000 | 2 kSPS | 0.73 Hz | 2.048 s | ~0.49 fps |
| 5 | 250.00 Hz | /108000 | 500 SPS | 0.18 Hz | 8.192 s | ~0.12 fps |
| 6 | 27.000 MHz | /1（宽频，不抽取） | 54 MSPS | 19.78 kHz | 75.85 µs | 受 60 Hz 显示帧限制 |

（刷新率 = 1/(一帧采集 + 4.1 ms FFT + 0.42 ms 取模)，再叠加视频平均的帧数：快档 16 帧、慢档 4 帧。）

- **抽取器**：`ad9226_capture.v`，boxcar（移动平均）抽取 + Q16 倒数（27→2427、54→1214、108→607），
  带边 −3.9 dB；输出 `(adc − 2048) << 4`（Q4，即 12 bit → 16 bit 有符号，零均值）。
- 频点换算：显示列 `col`（0..1023）→ 频率 `col × span/1024`；
  27 MHz 档特殊：`col × 27000`（kHz）而不是 `× span`，所以有三处乘 27000 的读数逻辑。
- 纵轴：0 dBFS 在 `PY0=104`，−80 dBFS 在 `PY1=615`，**6.4 像素/dB**。

### 4.2 窗函数（KEY5 循环 Hann / Rect / Black / FlatTop）

- 4096 点窗表 `hann_rom`（4096×12，镜像寻址：`win_mirror = addr[11] ? ~addr : addr`）。
  Hann 取 ROM 第 0 扇区；Rect 直接给 `12'd4095`；Black / FlatTop 是同一张 ROM 的另一段
  （地址 `{win_lat[0], win_mirror[10:0]}`，`win_lat[0]` 选 Black 还是 Flat），即 `hann_w` 三路 mux：
  `(win_lat==0) ? hann_rom_w : (win_lat==1) ? 12'd4095 : win_hw`。
  窗形只在 `O_cap_start` 那一拍锁存（`win_lat`），帧内不变。
- 相干增益补偿（Q7）：Hann 128（1.0）、Rect 64（0.5）、Black 152（1.19）、Flat 296（2.31），
  使**满量程单音在任何窗下都读到同一高度**（实测 65480 / 65535 ≈ −0.007 dBFS）。
- RBW 表索引 = `{I_win, I_span}` = **win×8 + span**（Hann 0..6、Rect 8..14、Black 16..22、Flat 24..30，每个窗留 8 个槽），
  RBW = fs/4096 × ENBW，ENBW：Hann 1.5、Rect 1.0、Black 1.73、FlatTop 3.77。
  实测值：Hann 732 / 183 / 36.6 / 7.3 / 0.73 / 0.18 / 19.78 kHz（27M），
  Rect 488 / 122 / 24.4 / 4.9 / 0.49 / 0.12 / 13.18 kHz，
  Black 843 / 211 / 42.2 / 8.4 / 0.84 / 0.21 / 22.77 kHz，
  Flat 1.84 k / 460 / 92.0 / 18.4 / 1.84 / 0.46 / 49.70 kHz。
  （**坑**：这张表曾误写成"每窗 5 个连续槽"，Rect@1M 会显示成 Hann@10k 的 "7.3 Hz"，上板抓到过。）
- 四窗都有校准门限（`tools/run_regression.sh` 第 3 步）：满量程单音峰值必须落在 64830..65600。

### 4.3 检波（菜单 Detector：Pos Peak / Sample / Average / Neg Peak）

4096 个 bin 压成 1024 列，每列 2 个 bin（`m0 = bin 2k`，`m1 = bin 2k+1`）：

```
det=0 Pos Peak : max(m0, m1)
det=1 Average  : (m0 + m1) >> 1
det=2 Neg Peak : min(m0, m1)
det=3 Sample   : m0
```

### 4.4 迹线（菜单 Trace：Clear Write / Max Hold / Min Hold / View）

- **Clear Write**：直接显示当前帧。
- **Max Hold / Min Hold**：对 1024 列逐列取历史最大 / 最小（存在 `trc_max_mem` / `trc_min_mem`，各 1024×16）。
  换模式时先"预装"一帧（`trc_rdy`），预装完成前用当前帧填充，避免出现 0 或全满。
- **View**：冻结当前保持内容（不再更新，但仍显示）。

### 4.5 视频平均（菜单 Avg：Auto / 1 / 4 / 16 / 64）

逐列一阶 IIR：`avg_new = avg_dat + ((mag − avg_dat) >> k)`，k = 2/4/6 对应 ≈4/16/64 帧时间常数，
输出 `(avg_new + 8) >> 4`（因为内部 `mag_ext = mag_sat << 4` 保留 4 位小数）。
- `Avg=1`（不平均）走直通：`mag_avg = mag_sat`。
- **Auto**：快档（span 0/1/2）用 ÷16，慢档（span 3/4/5）用 ÷4。
- 换 span / 窗 / 检波（cfg 指纹 `I_cfg_id = {span, win, det}`）时自动重新预装（第一帧直通）。

### 4.6 光标（KEY4：关 → 光标 → 增量 Δ → 菜单）

- 单光标：竖线 + 读数（频率 + dBFS），读数在**第 4 行右侧**（cell_col 57..78）。
- 增量模式：两条竖线 + Δf / ΔdB 读数。
- 读数精度：频率用 `col × span`（27M 档 `col × 27000` kHz），dB 用 128 步/倍频程的对数表 → `(L − 512) × 1927 >> 10` 得 dB×10。
- **FINE**：编码器短按翻转，光标步进 4 列 → 1 列（时域视图下禁用短按）。

### 4.7 谐波检测与标记

- 在 1024 列幅度流上找**全带最大列** = 基波列 `O_hrm_col`（幅度必须 ≥ **512**（−42 dBFS）才算有效，否则 `hrm_valid=0`）。
- 同帧在 `2×`、`3×`、`4×`、`5×` 基波列的 **±2 列窗口**内取最大，得 `h2..h5`（`h1` = 基波峰值）。
- 门限：`pk_max >= 512` → `O_hrm_valid = 1`；同时翻转 `O_hrm_tog`（跨域握手）。
- 显示：
  - 顶栏 / 右侧谐波表显示 `H1..H5` 的 dBFS；
  - 频谱图上在每个谐波列画**三角标记**（每一行宽度递增，共 6 行）+ 向下**虚线**（每 2 行一个点）；
  - 五个标记颜色：H1 绿、H2 青、H3 品红、H4 橙、H5 紫；
  - `hrm_valid=0` 时显示 `no f0`（无基波）。
- 实现建议：现版用 1024×16 的"距离表"（每列存 5 个谐波到本列的距离，3 bit 一个，上限截 7）在后台刷新，
  像素域只做一次查表 + 比较 —— 这也是 v1.7.4 把像素域余量从 0.48% 提到 8.5% 的关键改动。

### 4.8 THD / SNR（第 5 行读数）

- `THD = 10·log10((h2² + h3² + h4² + h5²) / h1²)`，用对数域相减实现：
  `thd_db10 = (963 × (lg_h1 − lg_s)) >> 12`，其中 `lg` 是 128 步/倍频程的对数（0.2351 dB/步 ≈ 963/4096）。
- `SNR = 10·log10(1 − Pfund/Ptotal)`：`n = I_pwr − (h1² << 2)`（全带功率减基波功率），
  `snr_db10 = (963 × (lg_total − lg_noise)) >> 12`。
- `I_pwr` 是全带功率（36 bit 累加，末列出）。
- 数字用 `/100`、`/10` 组合除法拆成 3 位显示；实测样例：THD −11.4 dB、SNR 6.0 dB（tb_top 的测试信号）。

### 4.9 低频档"中间帧"（v1.7.0 新增，换 IP 后大概率可以简化）

慢档一帧要 0.2 s ~ 8.2 s，等整帧太难受。做法：**用已采样的前 K 点 + 补零跑一次短 FFT**，每帧出 5 张中间谱：

| 阶梯 rung | K（点数） | 覆盖记录比例 | 幅度补偿左移 | 首次出谱（10k/1k/250Hz） |
|---|---|---|---|---|
| 0 | 128 | 3.1% | << 5 | 6.4 ms / 64 ms / 256 ms |
| 1 | 256 | 6.25% | << 4 | |
| 2 | 512 | 12.5% | << 3 | |
| 3 | 1024 | 25% | << 2 | |
| 4 | 2048 | 50% | << 1 | |

- 只在 span 3/4/5（20 k/2 k/500 Hz）启用；27 MHz 档绝不开（一帧才 76 µs，会与帧尾竞争）。
- **必须用 K 点相对窗**（`hann[i × 4096/K]` = 地址左移），不能直接截断 4096 点 Hann 的前 K 点：
  前 K 点落在 Hann 上升沿 0→0.5 上，K=128 时 sum(w) ≈ 0.41（亏 74 dB），K=1024 亏 20.8 dB。
- 中间帧要**冻结**峰值保持 / Max-Min 保持 / 光标读数 / 谐波表 / THD·SNR（只更新频谱与平均直通），
  顶栏显示 `MID` 标记（与 FINE 共用同一位置 `put(76,0,4,...)`）。
- 完整帧到达后覆盖中间帧并清标记；**完整帧的频谱必须与不开中间帧时逐位一致**（`sim/tb_mid.v` 校验 1024 列 bit-exact）。

### 4.10 AUTO Span（KEY3）

按当前基波频率选最窄的档，使 `5 × f0 ≤ 0.92 × Span`（阈值用整数比较 `col × span_hz` 与
`1_884_160 / 9_420_800 / 47_104_000 / 512_000_000`），超出则给 27 MHz 档；无有效峰时回落 1 MHz。
4 拍流水实现，避免 16.9 ns 的组合链。

### 4.11 时域视图（KEY2 → 视图 2）

- `wave_cap.v`：1024 点、电平穿越触发（Rise/Fall/0V 电平），触发点固定为第 0 点，`NPTS 1024`。
- 显示：网格 + 波形 + 右侧参数栏（WAVE / Span / Trig / NPTS / V/Div / Zoom / Orig / H1..H5）。
- **五次谐波时域迹线**（毕设硬性要求，不能砍）：`harm_est.v` 用 512 点相关算出 1~5 次谐波的复数幅度，
  重建 256 点 × 5 路，打包 50 bit 写 `harm_ram`，每帧 0.43 ms。
- 波形数据在 `pix_clk` 域按列插值（`v_interp` / `v_row`）连成线。

### 4.12 菜单与按键

| 按键 | 功能 |
|---|---|
| KEY1 | Span 循环（7 档，到头回 0） |
| KEY2 | 视图切换（频谱+菜单 / 纯净频谱 / 时域） |
| KEY3 | AUTO Span |
| KEY4 | 光标四态循环（关 → 光标 → 增量 → 菜单） |
| KEY5 | 窗函数循环 |
| 编码器旋转 | 改当前项的值（或移动光标） |
| 编码器短按 | 翻 FINE（光标步进 4→1）；光标档下跳峰；菜单档下切换菜单项 |
| 编码器长按（≥ `SW_LONG_MS`） | Preset：回 Span 1 MHz |

菜单项顺序：Window / Detector / Trace / Avg / Span（KEY4 进菜单后旋转选中、按下确认）。

---

## 5. 只换 FFT 时的接口契约（推荐路径）

**最省事的做法：保留 `video_top` 以外的全部显示/交互代码，只把 `fft4096.v` 换成 IP 包装器。**
那么包装器必须提供下列端口与时序（这些就是现版 `fft4096.v` 的对外行为）：

```
input             I_clk;          // 54 MHz
input             I_rst_n;
input             I_frame_req;    // pix_clk 域同步过来的单拍请求（每显示帧一次）
output reg        O_cap_start;    // 开始采集的单拍（同时锁存 win/avg/det 配置）
input  [15:0]     I_smp;          // 有符号样点（Q4）
input             I_smp_en;       // 样点有效（抽取后）
output reg        O_frame_start;  // 一帧幅度流开始的单拍（写侧翻 bank）
output reg [9:0]  O_mag_addr;     // 0..1023 列地址
output reg [15:0] O_mag;          // 该列幅度（0..65535 = 0 dBFS）
output reg        O_mag_en;       // O_mag 有效
output reg [9:0]  O_hrm_col;      // 基波列
output reg        O_hrm_valid;    // 本帧基波有效（pk_max >= 512）
output reg        O_hrm_tog;      // 每帧翻转一次（跨域握手）
output reg [15:0] O_h2..O_h5, O_h1;
output reg [35:0] O_pwr;          // 全带功率
input  [1:0]      I_win;          // 0 Hann 1 Rect 2 Black 3 Flat
input  [1:0]      I_det_sel;      // 检波
input  [1:0]      I_avg_sel;      // 平均深度选择（0=直通 1=÷4 2=÷16 3=÷64）
input             I_mag_flat;     // 1 = 27 MHz 宽频档（关掉抽取逆 sinc 补偿）
input  [6:0]      I_cfg_id;       // {span,win,det}，变化时重新预装平均
input             I_mid_en;       // 允许中间帧（只在慢档为 1）
output reg        O_mid;          // 本帧是中间帧
output reg [2:0]  O_mid_sh;       // 中间帧幅度补偿左移位数
```

时序要求：

1. `O_frame_start` 必须在 `O_mag_addr=0` 那一列**之前**一拍给出；`O_mag_addr` 单调 0→1023，每列一次 `O_mag_en`。
2. 一帧的列必须**连续**（中间不能断），因为写侧 `spec_ram` 用 `O_mag_addr` 直接当地址。
3. `O_mag` 是"该列最终显示幅度"（已含检波、平均、饱和），0 dBFS = 65535。
4. `O_hrm_*` / `O_h1..h5` / `O_pwr` 在**同一帧的最后一列**更新，`O_hrm_tog` 翻转一次（跨域用边沿锁存）。
5. `O_cap_start` 时锁存 `I_win/I_det_sel/I_avg_sel/I_cfg_id/I_mid_en`（配置只在帧边界生效）。

---

## 6. 必须复现的定标与常数

| 项 | 值 | 出处 |
|---|---|---|
| ADC 中心 | 2048，输出 `(adc−2048) << 4` | `ad9226_capture.v` |
| 抽取比 | 27 / 108 / 540 / 2700 / 27000 / 108000 / 1 | 同上 |
| Q16 倒数 | 2427（/27）、1214（/54）、607（/108） | 同上 |
| Hann 表 | 4096×12，镜像寻址 | `fft_tables.v`（由 `tools/model_fft.py` 生成） |
| 旋转因子 | 2048×16，cos Q15，占 2 块 BSRAM | 同上 |
| 抽取补偿 | `magcomp_rom` 1024×11（Q7，数值 1024..1608，逆 sinc） | 同上 |
| 窗相干增益 | Hann 128 / Rect 64 / Black 152 / Flat 296（Q7） | `fft4096.v` |
| 满量程标定 | 单音满量程 → 65480/65535 = 0 dBFS | 实测 |
| 谐波门限 | 512（−42 dBFS） | `fft4096.v` |
| THD/SNR 系数 | `(963 × Δlg) >> 12`，lg = 128 步/倍频程 | `spec_display.v` |
| 光标 dB | `(lg − 512) × 1927 >> 10` → dB×10 | 同上 |
| 平均移位 | ÷4 (k=2) / ÷16 (k=4) / ÷64 (k=6)，输出 `(x+8)>>4` | `fft4096.v` |
| 中间帧 K 阶梯 | 128/256/512/1024/2048，左移 5/4/3/2/1 | `fft4096.v` |
| 显示几何 | 1280×720@60；图区 x 64..1087、y 104..615；6.4 像素/dB | `spec_display.v` |
| 颜色 | 迹线 (255,216,0)；文字 白 C8D8E8 / 绿 00E050 / 青 66E8FF / 蓝 8CB8E8；H1..H5 绿/青/品红/橙/紫 | 同上 |

---

## 7. 验证与验收（照抄就能复现）

1. **数值等价**：`sim/tb_fft.v` 用定点模型 `tools/model_fft.py` 逐列比对，**必须 0 LSB**（`tools/cmp_fft.py`）。
   换了 IP 之后这一条**没法再对**（IP 内部缩放/截断方式不同）——要么自己写行为级 IP 替身当参考，要么改判据为"峰值列正确 + 幅度误差 < 0.5 dB"。
2. **四窗校准**：满量程单音峰值 64830..65600。
3. **基波列**：`tb_fft +F0=100e3 +DEC=2` → `hrm_col = 102`。
4. **渲染回归**：`sim/tb_top.v` 出 PPM，检查 f0 读数、谐波表、迹线列数、5 个谐波标记列（166/268/370/472/574）。
5. **中间帧**：`sim/tb_mid.v` 要求完整帧 1024 列 bit-exact + 阶梯 5,4,3,2,1 + 中间帧期间 `hrm_tog` 不翻转。
6. **时域**：`sim/tb_wave_frame.v` 检查迹线列数 ≥250。
7. **一键全跑**：`bash tools/run_regression.sh`（11 步 10 项，约 6 分钟，任何 `FAIL` 即失败）。
8. **时序**：三时钟 TNS 必须全 0；本基线 tmds 80.546 MHz（要求 ≥74.25）、adc 65.349（≥54.002）。
9. **文字层**：`tools/put_len_check.py`（字符串长度与 `put()` 的 len 参数必须一致）。

---

## 8. 已经踩过的坑（按重要性）

1. **`cap_done` / `mag_done` 是"陈旧标志"**：原版只在 `frame_kick`/`mag_kick` 清，导致**两个显示帧才出一张新鲜谱**（中间的帧 `ST_CAP` 1 拍就退出、`ST_MAG` 1 拍就退出，什么都不输出）。
   改采集/状态机时如果"顺手修好"它，FFT 刷新率翻倍 → 平均效果减半 → 噪底明显变毛，**渲染会与旧版不一致**。
   现版的取舍是：只有中间帧那帧才提前清 `mag_done`（`mid_seen` 门控），其余帧保持原节拍，保证逐像素兼容。
2. **Hann 上升沿截断**：前 K 点 weight 之和远小于 0.5K（K=128 时 0.41，亏 74 dB）。中间帧必须用 K 点相对窗，不能用 N/K 补偿。
3. **`O_mag` 是全设计最敏感的路径**：v1.6.0 时最差 setup 只有 +0.168 ns（19 级：`root×gain_r` → `>>7` → 饱和 → 平均 mux）。任何往这条路上加逻辑的改动都会直接把时序打穿。
4. **改动放错位置会白改**：幅度补偿必须放在**写侧**（`video_top` 里对 `spec_wr_mag` 左移），不能放在 `u_fft` 输出上。
5. **Gowin PnR 同一网表逐字节可复现**：重跑不会换运气；想换布局必须改网表（哪怕净减少逻辑）。历史结果在 64.7 ~ 80.5 MHz 之间跳，纯抽签。
6. **`gw_sh` 成功也返回 exit 1**，判成败要看日志/buildlog 与 `timing_paths`，不能看 exit code。
7. **时序结论只看 `.timing_paths`**（逐路径 slack，已入库）；`timing_report.py` 顺手抓的 `tr_content.html` 里的 Fmax/TNS 表可能自相矛盾。
8. **文字层是像素域的老瓶颈**：几十个 `put()` 平铺在同一个 always 块里会串成 13~15 级优先链。
   解法：按 `cell_row` 分组（`case` 并行使每行 ≤5 个 put），再把定长字符串改成 `case (cell_col)` 逐列字符表。spec_display 已全部改完，wave_display 也改了分组版。
9. **同名寄存器不要撞车**：`m0/m1` 在幅度通路里已被占用（`reg [32:0] ... m0, m1`），流水标记必须换个名字（现用 `inj0/1/2`）。
10. **补丁脚本必须落盘再跑**（写 `.py` 文件）；用 PowerShell here-string 写含引号/中文的代码会被吃字符，报 `SyntaxError`。
11. **`git show > file` 在 PowerShell 会写成 UTF-16**，要用 `cmd /c "git show ... > file"`。
12. **`git add -A` 会把临时 `_msg.txt` 提交进去**，提交前先 `git reset _msg.txt`。

---

## 9. 27 MHz 宽频档到底占多少资源（实测，不是估算）

做法：同一工程拷两份，`_probe27/a` 原样、`_probe27/b` 删掉全部 27 MHz 支持（97 个 span-6 显示分支、3 个 `×27000` 读数乘法器、`dec_raw`/`dec_wide` 直通、`auto_span` 的 27M 目标、`span_hz20` 的 27e6 默认），两边都只跑综合，读 `impl/gwsynthesis/*_syn_rsc.xml`：

| 资源 | A（含 27 MHz） | B（删掉） | 差值 |
|---|---|---|---|
| LUT | 7263 | 7191 | **−72（0.35%）** |
| Register | 3687 | 3672 | **−15** |
| ALU | 1561 | 1562 | +1（噪声） |
| MULT18X18 | 25 | 22 | **−3（DSP 的 12.5%）** |
| BSRAM | 39 | 39 | **0** |

**结论：27 MHz 档的"显示"几乎不占空间**（72 个 LUT 就是那 97 个标签分支 + 几处直通 mux），
真正贵的是 3 个 kHz 读数的 18×18 乘法器（f0 / 光标 / Δ，各一个）。
如果重建后 DSP 紧张，可以把 `col × 27000 >> 10` 精确改写成 `col × 26 + ((col × 47) >> 7)`
（因为 27000/1024 = 26 + 47/128），用 ALU/LUT 换掉这 3 个 DSP。

各模块实测占用（综合阶段，可直接对照）：

| 模块 | Reg | ALU | LUT | DSP | BSRAM |
|---|---|---|---|---|---|
| `u_display`（频谱绘制） | 908 | 567 | 2986 | 11×M18 + 3×MALU36 | 4 |
| `u_wdisp`（时域绘制） | 386 | 155 | 1540 | 5×MADD18 | 3 |
| `u_fft` | 1138 | 518 | 1122 | 10 | 14 |
| `u_harm`（谐波估计 + sincos ROM） | 590 | 192 | 606 | 4+1 | 2 |
| `video_top` 自身 | 239 | 10 | 218 | – | – |
| `u_key`（按键/编码器） | 93 | – | 134 | – | – |
| `u_cap`（ADC 采集抽取） | 118 | 30 | 122 | 1×MALU36 | – |
| `u_timing`（HDMI 时序） | 48 | 20 | 54 | – | – |
| `u_auto`（AUTO Span） | 30 | – | 61 | 1×MALU36 | – |
| `u_wcap`（时域采集） | 39 | – | 39 | – | – |
| `DVI_TX_Top` | 73 | 69 | 229 | – | – |

---

## 10. 换 IP 之后会失去什么（务必提前确认可以接受）

1. **0 LSB 数值基准失效**：手写版是"每级 ÷2、定点截断"的确定行为，模型可逐位复现；IP 的缩放/舍入/位宽不同，`cmp_fft` 判据作废。
2. **满量程定标要重标**：65480/65535 = 0 dBFS 这个关系要按 IP 的输出位宽与 scaling 重新推导，
   连带 `512` 谐波门限、`963` 的 THD/SNR 系数、`1927` 的 dB 换算都要重算。
3. **IP 是加密 RTL**（`pragma protect`），ModelSim 10.1a 编不了 → 仿真必须自己写行为级替身，
   否则整条回归只剩综合/上板能验。
4. **BSRAM 反而更紧**：Gowin BSRAM 1024×18/块。手写版 4096 点用 8 块（32 bit）+ Hann 4 + twiddle 2 = 14 块；
   IP 需要 8（数据）+ 1~2（twiddle）+ 4（输入缓冲）+ 4（Hann 还得留）= 17~18 块，**净增 3~4 块**（现 39/46）。
   原因：IP 是按块握手吃数的，慢档 27 拍/样点也必须先缓冲；手写版是"边采边就地写工作 RAM"，不需要输入 FIFO。
5. **唯一真实收益是吞吐**：4.1 ms → 约 0.1 ms（≈40×）。好处是中间帧可以更密、27 MHz 档也能开中间帧；
   坏处是（如果沿用原节拍）FFT 会空转更多，需要重新设计帧调度。

---

## 11. 建议的重建顺序（按里程碑，每步都能独立验收）

1. **M1 打通链路**：原始例程 + ADC 采集 + 固定 1 MHz 档 + Hann + IP FFT 4096 + 1024 列输出 → HDMI 出谱线。
   验收：单音谱线位置正确（`col = f0/span × 1024`），噪底可见。
2. **M2 定标**：满量程单音读数、dB 轴（6.4 像素/dB）、RBW 显示、SWT 显示。验收：与本文 §6 的定标表一致（±0.5 dB）。
3. **M3 交互**：7 档 span 与抽取器、4 窗、4 检波、4 迹线、平均、光标、菜单、Preset。验收：`tb_key_enc`、`tb_top` 的 DUMP 检查。
4. **M4 测量**：谐波检测（±2 列窗）、谐波表与标记、THD/SNR、AUTO Span。验收：`tb_harm`、`tb_top +JUMP/+MENU`。
5. **M5 时域视图**：wave_cap + 触发 + 插值绘制 + `harm_est` 五条谐波迹线。验收：`tb_wave_frame`。
6. **M6 中间帧**（可选）：慢档 K 点相对窗 + 冻结 + MID 标记。验收：`tb_mid`。
7. **M7 时序收尾**：三时钟 TNS=0；像素域优先压"文字层 mux 深度"，其次"每帧预算 + 查表"。

---

## 12. 附：现版关键文件（保留/替换建议）

| 文件 | 作用 | 换 IP 时的建议 |
|---|---|---|
| `src/ad9226_capture.v` | 抽取 + 补零 + 定标 | **保留** |
| `src/fft4096.v` | 采集 FSM + 加窗 + 就地 FFT + 取模 + 平均 + 谐波/功率 | **整体替换**（IP 包装器） |
| `src/fft_tables.v` | Hann / twiddle / magcomp | twiddle 交给 IP；Hann 与 magcomp 保留 |
| `src/spec_data_if.v`、`src/spec_ram.v` | 乒乓跨域 | **保留** |
| `src/spec_display.v` | 频谱绘制 + 文字 + 菜单 + 光标 + 谐波表 + THD/SNR | **保留**（只换数据来源） |
| `src/wave_cap.v`、`src/harm_est.v`、`src/wave_display.v` | 时域视图 | **保留** |
| `src/video_timing.v`、`src/dvi_tx/`、`src/gowin_rpll/` | HDMI | **保留** |
| `src/key_enc_ctrl.v`、`src/auto_span.v` | 交互 | **保留** |
| `sim/tb_fft.v`、`sim/tb_mid.v`、`sim/tb_top.v`、`sim/tb_harm.v`、`sim/tb_wave_frame.v` | 验证 | tb_fft 需改写（IP 加密） |

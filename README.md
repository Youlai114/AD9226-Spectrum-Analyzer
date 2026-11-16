# AD9226 + HDMI 数字频谱分析仪 v2.0.1（Tang Nano 20K / GW2AR-18）

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v2.0.1-blue.svg)](https://github.com/Youlai114/AD9226-Spectrum-Analyzer/releases)
[![Language](https://img.shields.io/badge/HDL-Verilog-orange.svg)](#)

基于 **高云 Tang Nano 20K（GW2AR-18C）** + **AD9226（12bit / 54 MSPS）** 实现的片上数字频谱分析仪与时域示波系统，直接输出 1280×720 HDMI 画面，无需 MCU 或上位机，上电即用。

- 操作手册：[doc/操作手册.md](doc/操作手册.md)
- 代码导读：[doc/代码导读.md](doc/代码导读.md)

---

## v2.0.1 更新说明
- **16 档商用 1-2-5 全范围 Span**：由 7 档扩展为 `200 Hz / 500 Hz / 1.00 kHz / 2.00 kHz / 5.00 kHz / 10.0 kHz / 20.0 kHz / 50.0 kHz / 100 kHz / 200 kHz / 500 kHz / 1.00 MHz / 2.70 MHz / 5.40 MHz / 13.5 MHz / 27.0 MHz`，全面覆盖低频音频、`20 kHz`、中高频方波/脉冲/微分尖峰与 27 MHz 全带宽观察。
- **低频滑窗提速 & 浅抽取增益修正**：`200 Hz ~ 2 kHz` 档支持 `256~2048` 滑窗重叠刷新（`0.5~0.6s` 刷新）；修正 `2.7M / 5.4M`（`dec_lo`）与 `13.5M`（`dec_div2`）定标移位，并共用 `f_scale_k` 乘法器使 DSP 降至 `61%`。
- **时序优化**：将 `ui_text_rom` 横坐标刻度字符串预寄存，`74.25 MHz` 像素域 Setup/Hold 违例均为 `0`。

---

## 一、v2.0.0 与上一版（v1.x）的核心区别

相比上一版（`AD9226_Nano20K_Slink` v1.x），**v2.0.0** 对 FFT 内核链路、显示测量引擎和时域/频域分析功能进行了全面重写与升级：

### 1. 重写的部分
- **FFT 计算引擎重写（[src/fft_ip_wrap.v](src/fft_ip_wrap.v)）**：
  - 将 v1.x 的手写基-2 DIF FFT 重写为基于**高云官方可变点数 FFT IP 核（`Gowin_FFT_Top`）**的流水线封装。
  - 在同一封装内集成 4096 点环形采样缓冲、**4096 点一阶 IIR 去直流偏置**（消除 0 Hz 直流尖峰）、4 窗加窗、4 种检波、4 种迹线保持，以及基波/谐波/最大杂散实时扫描。
- **显示与测量状态机重写（[src/spec_display.v](src/spec_display.v)、[src/ui_text_rom.v](src/ui_text_rom.v)）**：
  - 统一重构为 6 级像素流水线，支持 `SPEC` / `SPLIT` / `TIME` 三视图同屏切换。
  - 采用分拍复用的顺序计算状态机（0 额外 BSRAM / 0 新增组合乘法器）完成所有频率、dBc、THD%、SFDR 与时域光标读数的格式化。
- **工程结构精简**：
  - 清理了 v1.x 遗留的旧版工程与冗余中间产物，统一为 `Sim_Spectrum.gprj` + `build.tcl` 一键综合布局布线脚本。

### 2. 新增与升级的功能
| 类别 | v1.x | v2.0.0 |
| :--- | :--- | :--- |
| **扫宽（Span）** | 5 档（1M / 250k / 50k / 10k / 27M） | **16 档商用 1-2-5 序列**（`200 Hz ~ 27.0 MHz`）+ `KEY3` **AUTO Span** 自动缩进 |
| **直流抑制** | 无（0 Hz 存在偏置峰） | **4096 点 IIR 去直流偏置**，自动消除 0 Hz 直流尖峰 |
| **峰值频率精度** | 整数 bin | **1/8-bin 抛物线亚 bin 内插** |
| **频标（MARKER）** | 单标 / 差值标 | 新增 **Peak Track（峰值自动追踪）** 与一键吸峰 |
| **参考迹线（REF）** | 无 | **REF 捕获与浅蓝叠加对比**（`OFF / ON / CAP`） |
| **频域指标** | H1~H5 标记 | 新增 **H2..H5 dBc**、**H1..H5 频率**、**THD%**、**SFDR（无杂散动态范围）** |
| **门限告警（LIMIT）** | 无 | **红色水平门限虚线**（`-10..-80 dB`）+ **LIM:PASS / LIM:FAIL** 自动告警 |
| **时域触发（TRIG）** | 自由运行 | **AUTO / RISE / FALL / SNGL（单次） / HOLD** + 可调橙色 **TLVL** 电平线 |
| **时域缩放与坐标** | 固定点数与倍率 | **V-SCL**（`AUTO` + `x0.25..x64`）与 **T-ZM**（`x0.25..x64`），坐标轴随倍率动态更新 `V/mV` 与 `us/ms/s` |
| **时域测量与光标** | Vpp | 新增 **WF（过零频率）**、**DT%（占空比）** 及 **T1 / dT / 1/dT** 双光标 |
| **时域谐波合成** | 固定叠加 | `HARM WV`（`OFF / H1..H5 / H1-5 / ALL5`）且与时域缩放/抽取时基严格对齐 |

---

## 二、功能说明

1. **三视图切换（`KEY2`）**：
   - `SPEC`：全屏频谱分析视图。
   - `SPLIT`：上半屏频谱 + 下半屏时域波形同步对比。
   - `TIME`：全屏时域示波视图，左侧纵坐标随 `V-SCL` 动态切换 `V/mV` 量程（`AUTO` 显示 `±FS / ±50% / 0V`），底部横坐标随 `T-ZM` 与 `Span` 实时更新 4 等分时间刻度。
2. **频域分析**：
   - 7 档扫宽 + `AUTO Span`（`KEY3`）。
   - 4 种窗函数（`Hann / Rect / Black / FlatTop`）、4 种检波（`PosPeak / Avg / NegPeak / Sample`）、4 种迹线（`CLR / MAXH / MINH / VIEW`）及 `REF` 参考迹线。
   - 垂直刻度 `5 / 2 / 1 dB/div`、顶部参考电平 `0..-40 dB`、门限线 `LIMIT`（`OFF / -10..-80 dB`）。
   - 自动读数：`PEAK`（含 1/8-bin 内插）、`H2..H5 dBc`、`H1..H5` 频率、`THD%`、`SFDR`、`LIM:PASS/FAIL`。
3. **时域示波与谐波对比**：
   - 5 种触发模式（`AUTO / RISE / FALL / SNGL / HOLD`）+ 可调 `TLVL` 触发电平线。
   - `V-SCL`（`AUTO`, `x0.25..x64`）与 `T-ZM`（`x0.25..x64`）。
   - 自动测量 `Vpp`、`WF`、`DT%`，以及 `TIME` 视图独立光标 `T1 / dT / 1/dT`。
   - `HARM WV` 利用基波与 2~5 次谐波复数谱重构时域波形（`H1..H5` 单次、`H1-5` 合成、`ALL5` 分量展开）。

---

## 三、硬件指标与综合结果（GW2AR-18C）

- **采样与时钟**：`54 MHz` ADC 时钟（27 MHz 晶振倍频），`74.25 MHz` HDMI 像素时钟。
- **资源占用**（[impl/pnr/Sim_Spectrum.rpt.txt](impl/pnr/Sim_Spectrum.rpt.txt)）：
  - `Logic`：`14220 / 20736 (69%)`
  - `Register`：`5470 / 15750 (35%)`
  - `BSRAM`：`43 / 46 (94%)`
  - `DSP`：`14.5 / 24 (61%)`
- **时序收敛**（[impl/pnr/Sim_Spectrum_tr_content.html](impl/pnr/Sim_Spectrum_tr_content.html)）：Setup 违例端点 `0`，Hold 违例端点 `0`。
- **即用比特流**：[impl/pnr/Sim_Spectrum.fs](impl/pnr/Sim_Spectrum.fs)。

---

## 四、目录结构

```text
Sim_Spectrum/
├── build.tcl                  # Gowin 一键综合与布局布线脚本
├── Sim_Spectrum.gprj          # Gowin IDE 工程文件
├── doc/
│   └── 操作手册.md            # 按键、编码器、10 项菜单及读数详细说明
├── impl/pnr/
│   ├── Sim_Spectrum.fs        # 编译好的 FPGA 比特流文件
│   ├── Sim_Spectrum.rpt.txt   # 资源占用报告
│   └── Sim_Spectrum_tr_content.html # 时序分析报告
└── src/                       # 全部 Verilog RTL 与约束文件
```

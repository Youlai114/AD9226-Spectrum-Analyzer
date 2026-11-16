# AD9226 + HDMI 数字频谱分析仪

AD9226（12 bit / 65 MSPS）高速 ADC + 高云 Tang Nano 20K（GW2AR-18C）的片内数字频谱分析仪，
直出 1280×720@60 HDMI，无需 MCU 或上位机，上电即用。

本仓库收录从原型到成品的完整演进材料，当前版本为 **v2.0.2**。

## 目录结构

| 目录 | 内容 |
|---|---|
| `Sim_Spectrum/` | **当前版本（v2.0.2）** 完整工程：`src/` 源码、`impl/` 综合布线、`doc/` 文档、`build.tcl` |
| `Docs/` | 跨版本技术交接文档（官方 FFT IP 重建交接等） |
| `Example/` | 四个历史原型工程，用于对照演进过程（仅保留源码与文档，构建产物不入库） |
| `PCB/` | EasyEDA Pro 工程（连接板、SMA + RC 抗混叠小板） |

## 快速开始

```bash
cd Sim_Spectrum
gw_sh build.tcl          # 综合 + 布线 + 生成比特流
# 产物：impl/pnr/Sim_Spectrum.fs
```

操作手册与代码导读见 [`Sim_Spectrum/doc/`](Sim_Spectrum/doc/)。

## 版本

| 版本 | 要点 |
|---|---|
| v2.0.2 | 仓库重组为 `Docs/ Example/ PCB/ Sim_Spectrum/`，构建产物不再入库 |
| v2.0.1 | 16 档商用 1-2-5 全覆盖 Span（200 Hz ~ 27 MHz）、低频滑窗刷新、时序优化 |
| v2.0.0 | 改用高云官方 FFT IP 核，重写频域/时域分析链路（Harmonic / SFDR / Limit / PeakTrack） |
| v1.x | 手写基 2 DIF FFT 版本，见 `Example/ad9226_hdmi_spectrum` |

## 许可证

MIT，见 [LICENSE](LICENSE)。

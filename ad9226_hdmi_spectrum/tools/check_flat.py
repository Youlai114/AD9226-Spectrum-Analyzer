# -*- coding: utf-8 -*-
"""
check_flat.py -- 端到端通带平坦度检查

  AD9226 54MHz 采样 -> 27 点滑动平均抽取 -> 2MHz 样点 -> 4096 点 FFT -> 幅度(带补偿)

  对每个"正好落在 bin 中心"的频率, 满量程输入应该读到 65535 (0 dBFS)。
  用 bin 中心是为了排除窗函数的栅栏损失 (scalloping), 那部分是任何加窗 FFT 都有的。

用法: python check_flat.py
"""
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from model_fft import spectrum, N, window_samples, fft_dif, mag_cols

import argparse

FS_ADC = 54e6
DEC    = 27
FS     = FS_ADC / DEC
BIN    = FS / N


def fmt_hz(v):
    return ("%.2f MHz" % (v / 1e6)) if v >= 1e6 else \
           (("%.3f kHz" % (v / 1e3)) if v >= 1e3 else ("%.2f Hz" % v))


def chain(f0, amp=1.0, phase=0.0):
    """完整链路: 54MHz 采样 (N*DEC 点) -> DEC 点平均 -> 4096 点样点"""
    n = np.arange(N * DEC)
    v = amp * 2047.0 * np.sin(2 * np.pi * f0 / FS_ADC * n + phase)
    adc = np.clip(np.round(v + 2048.0), 0, 4095).astype(np.int64)
    x = adc - 2048
    return x.reshape(N, DEC).sum(axis=1) // DEC      # 与 RTL 的定点平均等价 (向下取整)


def main():
    global DEC, FS, BIN
    ap = argparse.ArgumentParser()
    ap.add_argument("-d", "--dec", type=int, default=27, help="抽取比: 27/108/540/2700")
    args = ap.parse_args()
    DEC = args.dec
    FS  = FS_ADC / DEC
    BIN = FS / N
    print("抽取 %d, fs = %.4f MHz, bin = %.3f Hz, 满量程 = 65535 (0 dBFS)\n"
          % (DEC, FS / 1e6, BIN))
    print("%-12s %-8s %-8s %s" % ("频率", "列", "读数", "误差 dB"))
    worst = 0.0
    for frac in [0.001, 0.05, 0.2, 0.35, 0.5, 0.7, 0.85, 0.95, 0.999]:
        m = max(1, int(round(frac * N / 2)))
        f0 = m * BIN
        x = chain(f0)
        cols = mag_cols(*fft_dif(window_samples(x << 4)))
        k = int(np.argmax(cols))
        db = 20 * np.log10(max(cols.max(), 1) / 65535.0)
        if m not in (1,):
            worst = max(worst, abs(db))
        print("%-12s %-8d %-8d %+.2f" % (fmt_hz(f0), k, cols.max(), db))
    print("\n除 DC 附近外, 最大误差 %.2f dB" % worst)
    print("(bin 中心处应该接近 0 dB; 落在两个 bin 之间时另有 -1.4 dB 的栅栏损失, 属正常)")


if __name__ == "__main__":
    main()

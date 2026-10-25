# -*- coding: utf-8 -*-
"""
cmp_fft.py -- 把 RTL 仿真结果和比特精确模型对齐

  sim/out/smp.txt  : 采集模块实际吐出的 4096 个样点
  sim/out/mag.txt  : RTL 算出的 1024 列幅度 ("addr mag")

用法:  python cmp_fft.py
"""
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from model_fft import window_samples, fft_dif, mag_cols, N

SIM = os.path.join(HERE, "..", "sim", "out")


def load_smp():
    v = []
    with open(os.path.join(SIM, "smp.txt")) as f:
        for line in f:
            line = line.strip()
            if line:
                v.append(int(line))
    return np.array(v, dtype=np.int64)


def load_mag():
    m = np.zeros(1024, dtype=np.int64)
    cnt = 0
    with open(os.path.join(SIM, "mag.txt")) as f:
        for line in f:
            p = line.split()
            if len(p) == 2:
                m[int(p[0])] = int(p[1])
                cnt += 1
    return m, cnt


def main():
    smp = load_smp()
    rtl, cnt = load_mag()
    print("样点 %d 个, 频点列 %d 个" % (len(smp), cnt))
    if len(smp) < N:
        print("!! 样点不足, 检查采集")
        return 1

    x16 = smp[:N]
    xw = window_samples(x16)
    re, im = fft_dif(xw)
    ref = mag_cols(re, im)

    d = np.abs(rtl.astype(np.int64) - ref)
    print("RTL 与模型: 最大偏差 %d LSB, 平均偏差 %.1f LSB" % (d.max(), d.mean()))
    print("RTL  峰值 bin %d = %d" % (int(np.argmax(rtl)), int(rtl.max())))
    print("模型 峰值 bin %d = %d" % (int(np.argmax(ref)), int(ref.max())))

    bad = np.where(d > 4)[0]
    if len(bad):
        print("偏差 >4 LSB 的频点 %d 个, 前几个: %s" % (len(bad), bad[:10]))
        for k in bad[:5]:
            print("   bin %4d  RTL %5d  模型 %5d" % (k, rtl[k], ref[k]))
        return 1
    print("OK: FFT 结果与定点模型一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())

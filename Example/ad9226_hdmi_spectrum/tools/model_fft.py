# -*- coding: utf-8 -*-
"""
model_fft.py -- AD9226 + Hann 窗 + 4096 点定点 FFT 的比特精确模型

用途:
  1. 验证 DIF 基 2 定点算法本身正确 (与 numpy FFT 对比)
  2. 确定各级缩放, 保证不溢出, 并让满量程单音落在 65535 (0 dBFS)
  3. 生成 RTL 需要的 Hann 窗 ROM 与旋转因子 ROM (src/fft_tables.v)

固定点约定 (与 RTL 完全一致):
  x[n]  = (adc_unsigned - 2048) << 4          16bit 有符号, 满量程 ±32752
  xw[n] = (x[n] * hann[n]) >>> 12             hann 为 12bit 无符号 (0..4095)
  FFT   : 每级蝶形输出 >>> 1 (除 2), 共 12 级 -> 输出 = DFT / 4096
  幅度  : mag = (sqrt(re^2+im^2) * G[k]) >> 7, 饱和到 65535
           G[k] 是抽取滤波器的逆 sinc 补偿 (Q7, 1024~1608), 见 gen_magcomp()
  显示  : 2048 个频点 -> 1024 列, 每列取相邻两点的较大值 (peak detector)

  ★ 定标与 N 无关: 窗归一后 sum(w)/N = 0.5, 逐级除 2 共 N 倍,
    峰值幅度 = (A/2) * (N/2) / N = A/4, 所以 2048 点和 4096 点结果相同。
"""
import numpy as np
import os

N     = 4096          # FFT 点数
NLOG  = 12
NCOL  = 1024          # display 列数 (= N/2/2)
MDEC  = 27            # 抽取比 (决定 boxcar 的通带倾斜; 三档 27/54/108 的曲线一致)
HERE  = os.path.dirname(os.path.abspath(__file__))
OUT   = os.path.join(HERE, "..", "src")

# ----------------------------------------------------------------- 表
def gen_hann():
    n = np.arange(N)
    w = 0.5 * (1.0 - np.cos(2 * np.pi * n / N))     # 周期 Hann
    return np.round(w * 4095).astype(np.int64)

def gen_twiddle():
    k = np.arange(N // 2)
    c = np.round(32767 * np.cos(2 * np.pi * k / N)).astype(np.int64)
    s = np.round(32767 * np.sin(2 * np.pi * k / N)).astype(np.int64)
    return c, s

def gen_magcomp():
    """抽取 (M 点滑动平均) 的逆 sinc 补偿, Q7 定标:
         |H(f)| = |sin(pi*f_n)/(M*sin(pi*f_n/M))|, f_n = 归一化频率 (0~0.5)
         G = round(1024 / |H|), 1024 = 1.000 倍, 1608 = 1.570 倍 (+3.9dB)
       实测 M=27 与 M=108 在同一 f_n 上差 < 0.01dB, 所以三档共用一张表。"""
    k = np.arange(NCOL)
    f_n = (2.0 * k + 0.5) / N
    d = np.abs(np.sin(np.pi * f_n) / (MDEC * np.sin(np.pi * f_n / MDEC)))
    return np.round(1024.0 / d).astype(np.int64)

HANN = gen_hann()
TWC, TWS = gen_twiddle()
MAGCOMP = gen_magcomp()

def gen_win_rom():
    """Blackman / Flat Top 窗, 半表 (对称: w[4095-n] = w[n]), Q12 峰值归一.
       刻度与 hann/twiddle 一致: 2*pi*n/4096. Flat Top 边缘负值截 0."""
    n = np.arange(N // 2)
    theta = 2 * np.pi * n / N
    black = 0.42 - 0.5 * np.cos(theta) + 0.08 * np.cos(2 * theta)
    flat  = (0.21557895 - 0.41663158 * np.cos(theta) + 0.277263158 * np.cos(2 * theta)
             - 0.083578947 * np.cos(3 * theta))
    black = np.round(4095 * black).astype(np.int64).clip(0, 4095)
    flat  = np.round(4095 * flat ).astype(np.int64).clip(0, 4095)
    return black, flat

WINROM_B, WINROM_F = gen_win_rom()

arshift = np.right_shift

BITREV = np.array([int(format(k, "0%db" % NLOG)[::-1], 2) for k in range(N)])


def window_samples(x16):
    return arshift(np.asarray(x16, dtype=np.int64) * HANN, 12)


def fft_dif(xw):
    """定点 DIF FFT (向量化, 逐级 >>>1), 返回 bit-reverse 顺序的 (re, im)"""
    re = np.array(xw, dtype=np.int64)
    im = np.zeros(N, dtype=np.int64)
    for s in range(NLOG):
        half = N >> (s + 1)
        blk = np.arange(N).reshape(-1, 2 * half)
        ia = blk[:, :half].ravel()
        ib = blk[:, half:].ravel()
        j = np.tile(np.arange(half), N // (2 * half))
        k = j << s
        c, sn = TWC[k], TWS[k]

        ar, ai = re[ia], im[ia]
        br, bi = re[ib], im[ib]
        sr, si = ar + br, ai + bi
        dr, di = ar - br, ai - bi
        re[ia] = sr >> 1
        im[ia] = si >> 1
        re[ib] = (arshift(dr * c, 15) + arshift(di * sn, 15)) >> 1
        im[ib] = (arshift(di * c, 15) - arshift(dr * sn, 15)) >> 1
    return re, im


def mag_natural(re, im):
    """按位倒序存储的 (re,im) -> 自然顺序的 sqrt(re^2+im^2) (未定标, 长度 N)"""
    sq = re * re + im * im
    m = np.floor(np.sqrt(sq.astype(np.float64))).astype(np.int64)
    nat = np.zeros(N, dtype=np.int64)
    nat[:] = m[BITREV]
    return nat


def mag_cols(re, im):
    """2048 个正频率点 -> 1024 列: 每列取相邻两点较大值, 再乘逆 sinc 补偿"""
    half = mag_natural(re, im)[:N // 2]
    peak = np.maximum(half[0::2], half[1::2])
    return np.minimum((peak * MAGCOMP) >> 7, 65535)


def adc_of(sig_fs, fs=2e6, amp=1.0, phase=0.0):
    n = np.arange(N)
    v = amp * 2047.0 * np.sin(2 * np.pi * sig_fs / fs * n + phase)
    return np.clip(np.round(v + 2048.0), 0, 4095).astype(np.int64)


def spectrum(adc, verbose=True):
    x16 = (adc - 2048) << 4
    xw = window_samples(x16)
    re, im = fft_dif(xw)
    cols = mag_cols(re, im)
    if verbose:
        print("  定点 FFT 峰值 |re|,|im| max = %d / %d (16bit 上限 32767)"
              % (np.abs(re).max(), np.abs(im).max()))
        print("  幅度列最大值 = %d (65535 = 0 dBFS, 误差 %.2f dB)"
              % (cols.max(), 20 * np.log10(max(cols.max(), 1) / 65535.0)))
    return cols


def write_tables():
    lines = []
    lines.append("// ============================================================================")
    lines.append("// fft_tables.v  --  Hann 窗 / 旋转因子 ROM (由 tools/model_fft.py 生成, 请勿手改)")
    lines.append("//")
    lines.append("//   hann_rom    : 4096 x 12,  w[n] = round(4095 * 0.5 * (1 - cos(2*pi*n/4096)))")
    lines.append("//   twiddle_rom : 2048 x 16, cos Q15 (省 2 块 BSRAM);")
    lines.append("//   magcomp_rom : 1024 x 11,  抽取滤波器的逆 sinc 补偿 (Q7, 1024~1608)")
    lines.append("//   均为同步读 (1 拍延迟), 推断成 BSRAM")
    lines.append("// ============================================================================")
    lines.append("")
    lines.append("module hann_rom (")
    lines.append("    input             I_clk  ,")
    lines.append("    input      [11:0] I_addr ,")
    lines.append("    output reg [11:0] O_w")
    lines.append(");")
    lines.append("    reg [11:0] rom [0:%d];" % (N - 1))
    lines.append("    initial begin")
    for i in range(N):
        lines.append("        rom[%4d] = 12'd%4d;" % (i, HANN[i]))
    lines.append("    end")
    lines.append("    always @(posedge I_clk) O_w <= rom[I_addr];")
    lines.append("endmodule")
    lines.append("")
    lines.append("//   sin 由 cos[(k+1536) & 2047] 读出: cos(t - pi/2) = sin(t), 数值与")
    lines.append("//   原 {cos,sin} 表逐位相同 (fft4096 在 ph1 换地址, ph3 收 sin)")
    lines.append("module twiddle_rom (")
    lines.append("    input             I_clk  ,")
    lines.append("    input      [10:0] I_addr ,")
    lines.append("    output reg [15:0] O_cos")
    lines.append(");")
    lines.append("    reg [15:0] rom [0:%d];" % (N // 2 - 1))
    lines.append("    initial begin")
    for i in range(N // 2):
        lines.append("        rom[%4d] = 16'h%04X;   // cos=%6d"
                     % (i, int(TWC[i]) & 0xFFFF, TWC[i]))
    lines.append("    end")
    lines.append("    always @(posedge I_clk) O_cos <= rom[I_addr];")
    lines.append("endmodule")
    lines.append("")
    lines.append("module magcomp_rom (")
    lines.append("    input             I_clk  ,")
    lines.append("    input      [9:0]  I_addr ,")
    lines.append("    output reg [10:0] O_g")
    lines.append(");")
    lines.append("    reg [10:0] rom [0:%d];" % (NCOL - 1))
    lines.append("    initial begin")
    for i in range(NCOL):
        lines.append("        rom[%4d] = 11'd%4d;" % (i, MAGCOMP[i]))
    lines.append("    end")
    lines.append("    always @(posedge I_clk) O_g <= rom[I_addr];")
    lines.append("endmodule")
    lines.append("")
    lines.append("module win_rom (")
    lines.append("    input             I_clk  ,")
    lines.append("    input      [11:0] I_addr ,   // {sector, a[10:0]}: 0=Blackman 1=FlatTop")
    lines.append("    output reg [11:0] O_w")
    lines.append(");")
    lines.append("    reg [11:0] rom [0:%d];" % (N - 1))
    lines.append("    initial begin")
    for i in range(N // 2):
        lines.append("        rom[%4d] = 12'd%4d;   // black" % (i, WINROM_B[i]))
    for i in range(N // 2):
        lines.append("        rom[%4d] = 12'd%4d;   // flat"  % ((N // 2) + i, WINROM_F[i]))
    lines.append("    end")
    lines.append("    always @(posedge I_clk) O_w <= rom[I_addr];")
    lines.append("endmodule")
    lines.append("")
    with open(os.path.join(OUT, "fft_tables.v"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("已生成 src/fft_tables.v  (hann %d, twiddle %d, win_rom %d)" % (N, N // 2, N // 2))


if __name__ == "__main__":
    fs = 2e6
    for f0, amp in [(250e3, 1.0), (250e3, 0.5), (1e3, 1.0), (999e3, 1.0)]:
        print("输入 %.4f MHz, 幅度 %.2f FS" % (f0 / 1e6, amp))
        cols = spectrum(adc_of(f0, fs, amp))
        k = int(np.argmax(cols))
        print("  峰值在第 %d 列 (%.4f MHz), mag=%d\n" % (k, k * fs * 2.0 / N / 1e6, cols[k]))

    # 与 numpy 浮点 FFT 对比谱形
    adc = adc_of(250e3, fs, 1.0)
    xw = window_samples((adc - 2048) << 4)
    ref = np.abs(np.fft.rfft(xw, N))[:N // 2]
    ref = ref / ref.max() * 65535.0
    mine = mag_cols(*fft_dif(xw))
    err = np.abs(mine - np.maximum(ref[0::2], ref[1::2]))
    print("与 numpy 浮点 FFT 对比: 最大偏差 %.1f LSB" % err.max())

    write_tables()

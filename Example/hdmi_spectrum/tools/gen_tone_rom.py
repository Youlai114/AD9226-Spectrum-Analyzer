# -*- coding: utf-8 -*-
"""
生成"单音正弦输入"的多量程频谱测试数据 ROM。

模型: 12bit ADC 采样 -> NFFT 点 FFT (Hann 窗) -> 取前 NBIN 个频点 -> 16bit 线性幅度
      (65535 = 满量程 0dBFS)

每个显示跨度 (Span) 一层数据, 采样率 = 2 x Span:
    层0: Span =   500 kHz, fs =  1 MHz, bin = 488.28 Hz, 基波在 40% 处
    层1: Span =     1 MHz, fs =  2 MHz, bin = 976.56 Hz, 基波在 20% 处
    层2: Span =    10 MHz, fs = 20 MHz, bin = 9.77  kHz, 基波在  2% 处
超过奈奎斯特频率的谐波会被丢弃 (真实 ADC + 数字滤波后的表现)。

输出:
    src/spec_demo_gen.v 里 TONE_ROM_BEGIN..END 区间的 tone_rom 模块
      地址 = {span[1:0], bin[9:0]}, 深度 4096 (3 层 x 1024 + 补齐)
    src/tone_rom.hex  (备用: 换成 $readmemh)

用法:
    python tools/gen_tone_rom.py --f0 200e3
"""
import argparse
import io
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "src")

# (span_hz, 显示文字)  顺序即按键循环顺序, 层 0 为上电默认
SPANS = [(500e3, "500 kHz"), (1e6, "1 MHz"), (10e6, "10 MHz")]
HARM = [(2, -55.0), (3, -62.0), (4, -78.0), (5, -82.0)]


def make_spectrum(f0, fs, nfft, nbin, floor, rng):
    """返回 (mag[nbin] 0..65535, bin_hz, 信息 dict)"""
    n = np.arange(nfft)
    win = 0.5 - 0.5 * np.cos(2 * np.pi * n / nfft)          # 周期 Hann

    sig = np.sin(2 * np.pi * f0 * n / fs)
    used = []
    for k, dbc in HARM:
        if k * f0 < fs / 2:                                  # 只保留奈奎斯特内的谐波
            sig += 10 ** (dbc / 20.0) * np.sin(
                2 * np.pi * k * f0 * n / fs + 0.7 * k)
            used.append((k, dbc))

    ref = np.abs(np.fft.rfft(sig * win)).max()

    nz = rng.standard_normal(nfft)
    nz_sp = np.abs(np.fft.rfft(nz * win))[1:nbin]
    sigma = (ref * 10 ** (floor / 20.0)) / np.sqrt(np.mean(nz_sp ** 2))
    x = sig + sigma * rng.standard_normal(nfft)

    sp = np.abs(np.fft.rfft(x * win))[:nbin]
    sp = sp / sp.max()
    sp[0] = sp[1:16].mean()                                  # DC 压到噪声底
    mag = np.clip(np.round(sp * 65535.0), 0, 65535).astype(int)

    bin_hz = fs / nfft

    def db_at(f):
        k = int(round(f / bin_hz))
        v = mag[max(0, k - 3):k + 4].max()
        return 20 * np.log10(max(v, 1) / 65535.0)

    info = dict(bin_hz=bin_hz, harm=used, db_at=db_at)
    return mag, info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--f0", type=float, default=200e3, help="输入正弦频率 Hz")
    ap.add_argument("--nbin", type=int, default=1024, help="每层频点数")
    ap.add_argument("--floor", type=float, default=-72.0, help="每 bin 噪声底 dBFS")
    ap.add_argument("--seed", type=int, default=2024)
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)
    layers = []
    for span, name in SPANS:
        fs = 2 * span                                        # 显示 0..Span => fs = 2*Span
        mag, info = make_spectrum(args.f0, fs, 2048, args.nbin, args.floor, rng)
        layers.append((span, name, fs, mag, info))
        print("层 Span=%9g Hz  fs=%6g MHz  bin=%9.2f Hz  基波在 bin %7.1f (%.1f%%)"
              % (span, fs / 1e6, info["bin_hz"], args.f0 / info["bin_hz"],
                 100.0 * args.f0 / info["bin_hz"] / args.nbin))
        for k, dbc in info["harm"]:
            print("    HD%d %8.1f kHz -> bin %6.0f, %6.1f dBFS (设计 %.0f dBc)"
                  % (k, k * args.f0 / 1e3, k * args.f0 / info["bin_hz"],
                     info["db_at"](k * args.f0), dbc))

    # ---- 生成 tone_rom 模块, 写回 spec_demo_gen.v 的标记区间 ----
    depth = 4096                                             # {span[1:0], bin[9:0]}
    lines = []
    lines.append("// ===== TONE_ROM_BEGIN (由 tools/gen_tone_rom.py 生成, 请勿手改) =====")
    lines.append("//   输入: %g kHz 正弦, 每个显示跨度一层, fs = 2 x Span, FFT 2048 点 (Hann 窗)"
                 % (args.f0 / 1e3))
    for span, name, fs, mag, info in layers:
        lines.append("//   Span %10g Hz: fs = %6g MHz, bin = %9.2f Hz, 谐波 %s"
                     % (span, fs / 1e6, info["bin_hz"],
                        "/".join("HD%d" % k for k, _ in info["harm"]) or "无"))
    lines.append("//   幅度 16bit, 65535 = 0dBFS, 噪声底 %.0f dBFS" % args.floor)
    lines.append("module tone_rom (")
    lines.append("    input             I_clk  ,")
    lines.append("    input      [11:0] I_addr ,   // {span[1:0], bin[9:0]}")
    lines.append("    output reg [15:0] O_mag")
    lines.append(");")
    lines.append("")
    lines.append("    reg [15:0] rom [0:%d];" % (depth - 1))
    lines.append("")
    lines.append("    initial begin")
    for si, (span, name, fs, mag, info) in enumerate(layers):
        lines.append("        // ---- Span %s ----" % name)
        for i in range(args.nbin):
            lines.append("        rom[%5d] = 16'd%d;" % (si * args.nbin + i, mag[i]))
    lines.append("    end")
    lines.append("")
    lines.append("    always @(posedge I_clk) O_mag <= rom[I_addr];   // 同步读 -> BSRAM")
    lines.append("")
    lines.append("endmodule")
    lines.append("// ===== TONE_ROM_END =====")
    rom_text = "\n".join(lines)

    target = os.path.join(OUT, "spec_demo_gen.v")
    src = io.open(target, encoding="utf-8").read()
    mb = "// ===== TONE_ROM_BEGIN"
    me = "// ===== TONE_ROM_END ====="
    a = src.index(mb)
    b = src.index(me) + len(me)
    src = src[:a] + rom_text + src[b:]
    io.open(target, "w", encoding="utf-8", newline="\n").write(src)

    with open(os.path.join(OUT, "tone_rom.hex"), "w", encoding="utf-8", newline="\n") as f:
        for si, (span, name, fs, mag, info) in enumerate(layers):
            f.write("// Span %s\n" % name)
            for i in range(args.nbin):
                f.write("%04x\n" % mag[i])

    print("已写回 src/spec_demo_gen.v (tone_rom 模块, %d 层) / src/tone_rom.hex" % len(layers))


if __name__ == "__main__":
    main()

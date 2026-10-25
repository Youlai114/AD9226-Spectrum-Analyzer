# -*- coding: utf-8 -*-
"""
gen_test_wav.py -- 生成"循环无缝"的单音 WAV，用来喂 AD9226 频谱仪

为什么要专门生成：
  1. 用播放器循环播放时，如果文件不是整数个周期，接缝处会有咔哒声，
     频谱上会多出一堆谐波 —— 看起来像 ADC 坏了，其实是音源的问题；
  2. 频率必须精确，否则屏幕上谱线位置对不上（1 kHz 在 Span 1 MHz 上只有 2 列宽，
     差 5% 就偏出去 0.1 列了，肉眼看不出来但会让你怀疑人生）；
  3. 幅度用 WAV 里的数字幅度控制，比拧系统音量精确（系统音量曲线不是线性的）。

做法：取整数个周期 cycles，精确频率 = cycles / 时长，相位按 cycles 累加，
      保证首尾相位连续，循环播放不会爆音。

用法：
  python gen_test_wav.py                        # 1 kHz, 48 kHz, 幅度 0.3, 5 秒
  python gen_test_wav.py -f 10000 -a 0.5        # 10 kHz, 半幅
  python gen_test_wav.py -f 1000 -fs 192000     # 192 kHz 声卡（上限更高）
  python gen_test_wav.py -f 1000 --stereo       # 立体声
"""
import argparse, math, struct, wave


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-f", "--freq", type=float, default=1000.0, help="目标频率 Hz (默认 1000)")
    ap.add_argument("-fs", "--rate", type=int, default=48000, help="采样率 (默认 48000)")
    ap.add_argument("-a", "--amp", type=float, default=0.3, help="幅度 0~1 (1 = 数字满幅, 默认 0.3)")
    ap.add_argument("-d", "--dur", type=float, default=5.0, help="时长 秒 (默认 5)")
    ap.add_argument("-o", "--out", default=None, help="输出文件名")
    ap.add_argument("--stereo", action="store_true", help="输出立体声")
    args = ap.parse_args()

    fs = args.rate
    nsamp = int(round(fs * args.dur))
    cycles = max(1, int(round(args.freq * args.dur)))     # 整数个周期
    f_exact = cycles * fs / nsamp                         # 严格落在采样栅格上的频率

    amp = max(0.0, min(1.0, args.amp))
    peak = int(round(amp * 32767))
    ch = 2 if args.stereo else 1

    frames = bytearray()
    for i in range(nsamp):
        v = int(round(peak * math.sin(2.0 * math.pi * cycles * i / nsamp)))
        v = max(-32768, min(32767, v))
        for _ in range(ch):
            frames += struct.pack("<h", v)

    out = args.out or ("test_%gkHz.wav" % (f_exact / 1e3))
    with wave.open(out, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(fs)
        w.writeframes(bytes(frames))

    print("已生成: %s" % out)
    print("  精确频率   : %.3f Hz  (要求 %.1f Hz, 偏差 %.3f%%)"
          % (f_exact, args.freq, (f_exact - args.freq) / args.freq * 100))
    print("  整数周期数 : %d  (循环无缝, 接缝不会有咔哒声)" % cycles)
    print("  采样率/时长: %d Hz / %.2f s" % (fs, nsamp / fs))
    print("  数字幅度   : %.0f%% 满幅 (%d/32767)" % (amp * 100, peak))
    if f_exact > fs / 2 * 0.9:
        print("  !! 频率接近 Nyquist (%.0f Hz), 声卡输出会被抗镜像滤波器压掉" % (fs / 2))
    print("\n播放: 用系统播放器循环播放, 并把「音量」固定在 100%, 幅度靠上面的数字幅度控制。")
    print("      记得关掉音效增强(Dolby/空间音频/响度均衡/均衡器), 否则频谱上全是它们加的东西。")


if __name__ == "__main__":
    main()

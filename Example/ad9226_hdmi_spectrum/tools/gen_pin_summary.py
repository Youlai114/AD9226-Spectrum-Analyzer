# -*- coding: utf-8 -*-
"""
gen_pin_summary.py -- 从 .cst 解析出全部引脚约束, 生成汇总表 (CSV)

  改完 ad9226_hdmi_spectrum.cst 后跑一遍, 保证文档/表格和代码一致:
      python tools/gen_pin_summary.py
  输出:  doc/引脚约束汇总.csv  (UTF-8 BOM, 可直接以 Excel/WPS 打开)

  说明: doc/引脚约束汇总.md 里"按功能""按排针"两张表是本脚本数据的排版版本,
        改了 cst 之后两处都要更新 (md 是手写的可读版)。
"""
import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CST  = os.path.join(ROOT, "src", "ad9226_hdmi_spectrum.cst")
OUT  = os.path.join(ROOT, "doc", "引脚约束汇总.csv")

# 管脚功能描述 (改约束时同步改这里)
USE = {
    "I_clk":            "板载 27MHz 晶振",
    "I_rst":            "板载 S2 复位键",
    "I_key[0]":         "KEY1  Span 循环",
    "I_key[1]":         "KEY2  预留(Ref)",
    "I_key[2]":         "KEY3  预留(RBW)",
    "I_key[3]":         "KEY4  预留(Marker)",
    "I_key[4]":         "KEY5  Preset",
    "I_enc_a":          "EC11 A 相",
    "I_enc_b":          "EC11 B 相",
    "I_enc_sw":         "EC11 按压 SW",
    "O_led[0]":         "LED_STAT 心跳",
    "O_led[1]":         "LED_OVR  过载",
    "O_clk_adc":        "AD9226 CLK (54MHz)",
    "I_adc_otr":        "AD9226 OTR",
    "O_tmds_clk_p":     "HDMI CLK 差分对",
    "O_tmds_data_p[0]": "HDMI D0 差分对",
    "O_tmds_data_p[1]": "HDMI D1 差分对",
    "O_tmds_data_p[2]": "HDMI D2 差分对",
}
for _i in range(12):
    USE["I_adc_d[%d]" % _i] = "AD9226 D%d" % _i

DIR = {"I_clk": "in", "I_rst": "in", "I_enc_a": "in", "I_enc_b": "in", "I_enc_sw": "in",
       "I_adc_otr": "in", "O_clk_adc": "out", "O_led[0]": "out", "O_led[1]": "out",
       "O_tmds_clk_p": "out", "O_tmds_data_p[0]": "out",
       "O_tmds_data_p[1]": "out", "O_tmds_data_p[2]": "out"}
for _i in range(12):
    DIR["I_adc_d[%d]" % _i] = "in"
for _i in range(5):
    DIR["I_key[%d]" % _i] = "in"

# 排针孔位 (从 USB-C 端数, 每排 20 孔)
J5 = [73, 74, 75, 85, 77, 15, 16, 27, 28, 25, 26, 29, 30, 31, 17, 20, 19, 18, "3V3", "GND"]
J6 = ["5V", "GND", 76, 80, 42, 41, 56, 54, 51, 48, 55, 49, 86, 79, "GND", "3V3", 72, 71, 53, 52]

# 未使用脚的禁用原因
BLOCK = {85: "Flash SDIO_D1", 80: "Flash SDIO_D2",
         56: "SSPI 专用脚", 54: "SSPI 专用脚", 55: "SSPI 专用脚",
         51: "功放 PA_EN", 86: "紧邻 Flash 组", 79: "WS2812 数据",
         53: "HDMI EDID_CLK", 52: "HDMI EDID_DAT"}


def parse_prop(s):
    d = {}
    for tok in s.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            d[k] = v
    return d


def main():
    cst = io.open(CST, encoding="utf-8").read()
    loc = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+([0-9,]+);', cst))
    prt = dict(re.findall(r'IO_PORT\s+"([^"]+)"\s+([^;]+);', cst))

    pin = {}
    for net, l in loc.items():
        p0 = int(l.split(",")[0])
        pin[p0] = (net, parse_prop(prt.get(net, "")))

    rows = []
    for hdr, seq in (("J5", J5), ("J6", J6)):
        for idx, p in enumerate(seq, 1):
            if p == "3V3":
                rows.append([hdr, idx, "-", "3V3", "电源 3.3V 输出(上拉/LED 用)", "pwr", "", "", "", "3.3V"])
            elif p == "GND":
                rows.append([hdr, idx, "-", "GND", "地", "pwr", "", "", "", "0V"])
            elif p == "5V":
                rows.append([hdr, idx, "-", "5V", "5V 输入(接 USB VBUS, 注意倒灌)", "pwr", "", "", "", "5V"])
            elif p in pin:
                net, pr = pin[p]
                rows.append([hdr, idx, p, net, USE.get(net, ""), DIR.get(net, ""),
                             pr.get("IO_TYPE", ""), pr.get("PULL_MODE", ""),
                             pr.get("DRIVE", ""), pr.get("BANK_VCCIO", "") + "V"])
            else:
                rows.append([hdr, idx, p, "(未使用)", "禁用: " + BLOCK.get(p, "-"),
                             "", "", "", "", "3.3V"])

    board = [
        ["板载", "-", 4,  "I_clk",   "27MHz 晶振(不可改)", "in",  "LVCMOS33", "UP",   "",    "3.3V"],
        ["板载", "-", 88, "I_rst",   "S2 复位键",          "in",  "LVCMOS33", "DOWN", "-",   "3.3V"],
        ["板载", "-", 87, "(未使用)", "S1 按键, 已弃用",     "",    "",         "",     "",    "3.3V"],
    ]
    for p, nm in ((33, "O_tmds_clk_p"), (35, "O_tmds_data_p[0]"),
                  (37, "O_tmds_data_p[1]"), (39, "O_tmds_data_p[2]")):
        board.append(["板载", "-", "%d+%d" % (p, p + 1), nm,
                      "HDMI 差分对(不可改)", "out", "LVDS25", "NONE", "3.5", "3.3V"])

    allrows = rows + board
    hdr = ["排针", "孔号", "FPGA管脚", "网络名", "用途", "方向", "IO类型", "上下拉", "驱动mA", "IO电压"]
    with io.open(OUT, "w", encoding="utf-8-sig", newline="") as f:
        f.write(",".join(hdr) + "\n")
        for r in allrows:
            f.write(",".join('"%s"' % str(x) for x in r) + "\n")

    used = len(pin)
    print("已生成 %s" % OUT)
    print("  cst 里的 IO_LOC 条目: %d (差分对算 1 条)" % used)
    print("  表格行数: %d (排针 40 孔 + 板载 %d)" % (len(allrows), len(board)))
    print("  排针 IO: 已用 %d / 可用 34, 余量 %d"
          % (sum(1 for p in J5 + J6 if isinstance(p, int) and p in pin),
             34 - sum(1 for p in J5 + J6 if isinstance(p, int) and p in pin)))


if __name__ == "__main__":
    main()

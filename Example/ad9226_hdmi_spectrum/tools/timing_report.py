# -*- coding: utf-8 -*-
"""汇总 Gowin 布线后的时序: 打印 Max Frequency / TNS 表 + 最差若干条路径。

用法:
    python tools/timing_report.py [impl/pnr 目录]

读两个文件:
    ad9226_hdmi_spectrum_tr_content.html   -> Max Frequency Summary / TNS
    ad9226_hdmi_spectrum.timing_paths      -> 每条路径 (SETUP|HOLD / slack / arr / req / 节点三元组)
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, '..', 'impl', 'pnr')


def html_tables(pnr):
    p = os.path.join(pnr, 'ad9226_hdmi_spectrum_tr_content.html')
    h = io.open(p, encoding='utf-8', errors='ignore').read()
    t = re.sub('<[^>]+>', ' ', h)
    t = re.sub(r'\s+', ' ', t)
    for key, span in (('Max Frequency Summary', 230), ('Total Negative Slack Summary', 300)):
        i = t.find(key)
        if i >= 0:
            print(t[i:i + span].strip())
            print()


def worst_paths(pnr, n=6):
    p = os.path.join(pnr, 'ad9226_hdmi_spectrum.timing_paths')
    txt = io.open(p, encoding='utf-8', errors='ignore').read()
    out = []
    for blk in txt.split('====='):
        lines = [x.strip() for x in blk.strip().splitlines() if x.strip()]
        if len(lines) < 6:
            continue
        try:
            slack = float(lines[1])
        except ValueError:
            continue
        nodes = [lines[i] for i in range(4, len(lines), 3)]
        out.append((slack, lines[0], nodes[0], nodes[-1], len(nodes)))
    out.sort()
    print('%-5s %8s %4s  first -> last' % ('type', 'slack', 'node'))
    for slack, typ, a, z, cnt in out[:n]:
        print('%-5s %+8.3f %4d  %s -> %s' % (typ, slack, cnt, a, z))


if __name__ == '__main__':
    pnr = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    if not os.path.isdir(pnr):
        sys.exit('no such dir: ' + pnr)
    html_tables(pnr)
    worst_paths(pnr)

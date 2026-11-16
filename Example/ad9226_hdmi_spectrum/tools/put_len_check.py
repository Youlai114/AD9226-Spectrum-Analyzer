# -*- coding: utf-8 -*-
"""检查 put(r, c, len, "字面量", col) 的 len 是否等于字面量字符数。

put 任务里 k=(len-1)-(cell_col-c0), 字符串在 288bit 内右对齐:
len 偏小 -> 丢首字符; len 偏大 -> 左侧补空格错位。
"""
import io
import re
import sys

FILES = [
    r'D:\code\AD9226_Nano20K_Slink\ad9226_hdmi_spectrum\src\spec_display.v',
    r'D:\code\AD9226_Nano20K_Slink\ad9226_hdmi_spectrum\src\wave_display.v',
]

# 匹配 put( a, b, LEN, "字面量", ...
PAT = re.compile(r'put\(\s*([^,]+?),\s*([^,]+?),\s*([0-9]+)\s*,\s*"((?:[^"\\]|\\.)*)"')

bad = 0
total = 0
for path in FILES:
    src = io.open(path, encoding='utf-8', errors='ignore').read()
    for m in PAT.finditer(src):
        total += 1
        ln = int(m.group(3))
        lit = m.group(4).encode().decode('unicode_escape')
        if len(lit) != ln:
            line = src[:m.start()].count('\n') + 1
            print('%s:%d  len=%d  实际=%d  "%s"' % (path.rsplit('\\', 1)[-1], line, ln, len(lit), lit))
            bad += 1

print('检查 %d 处 put, len 不符 %d 处' % (total, bad))
sys.exit(1 if bad else 0)

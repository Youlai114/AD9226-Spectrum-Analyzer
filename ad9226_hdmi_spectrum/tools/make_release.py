# -*- coding: utf-8 -*-
"""打包发布 zip: 比特流 + 文档 + 源码 (按 VERSION 命名, 排除中间产物).
   用法: python tools/make_release.py   (在任意目录可运行)"""
import os
import glob
import time
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
OUT_DIR = os.path.join(ROOT, 'release')

VER = open(os.path.join(ROOT, 'VERSION')).read().strip()
DATE = time.strftime('%Y%m%d')
OUT = os.path.join(OUT_DIR, 'spectrum_v%s_%s.zip' % (VER, DATE))

# ---- 显式清单 (比特流 + 文档 + 源码 + 脚本) ----
files = [
    'ad9226_hdmi_spectrum/impl/pnr/ad9226_hdmi_spectrum.fs',
    'ad9226_hdmi_spectrum/README.md',
    'ad9226_hdmi_spectrum/CODE_GUIDE.md',
    'ad9226_hdmi_spectrum/src/ad9226_hdmi_spectrum.cst',
    'ad9226_hdmi_spectrum/src/ad9226_spectrum.sdc',
    '文档/操作手册.docx',
    '文档/代码阅读引导.docx',
    '文档/程序对照注释手册.docx',
    '文档/交接文档.docx',
    'CHANGELOG.md',
    'VERSION',
]
files += sorted(glob.glob(os.path.join(ROOT, 'ad9226_hdmi_spectrum/src/*.v')))
files += sorted(glob.glob(os.path.join(ROOT, 'ad9226_hdmi_spectrum/src/dvi_tx/*.v')))
files += sorted(glob.glob(os.path.join(ROOT, 'ad9226_hdmi_spectrum/src/gowin_rpll/*.v')))
files += sorted(glob.glob(os.path.join(ROOT, 'ad9226_hdmi_spectrum/sim/*.v')))
files += sorted(glob.glob(os.path.join(ROOT, 'ad9226_hdmi_spectrum/tools/*.py')))
files += sorted(glob.glob(os.path.join(ROOT, 'ad9226_hdmi_spectrum/tools/*.sh')))
files += sorted(glob.glob(os.path.join(ROOT, 'ad9226_hdmi_spectrum/doc/*.md')))

os.makedirs(OUT_DIR, exist_ok=True)
missing = []
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
    for rel in files:
        full = os.path.join(ROOT, rel)
        if not os.path.isfile(full):
            missing.append(rel)
            continue
        z.write(full, rel)
    z.writestr('RELEASE.txt',
               'AD9226 数字频谱分析仪\n版本: %s\n打包: %s\n'
               '烧录: ad9226_hdmi_spectrum/impl/pnr/*.fs\n'
               '文档: 文档/ 下全部 docx\n回归: bash ad9226_hdmi_spectrum/tools/run_regression.sh\n'
               % (VER, time.strftime('%Y-%m-%d %H:%M')))

print('OK:', OUT)
print('文件数: %d, 大小: %.1f MB' % (len(files) - len(missing),
                                     os.path.getsize(OUT) / 1048576.0))
if missing:
    print('!! 缺失 (未打包):')
    for m in missing:
        print('   ', m)

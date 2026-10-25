# -*- coding: utf-8 -*-
"""生成《上板测试记录表》docx —— 板到后逐项填写实测数据, 直供论文第 5 章."""
import os
from docx import Document
from docx.shared import Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '文档'))


def cn(run, name='宋体', size=10, bold=False):
    run.font.name = name
    run.font.size = Pt(size)
    run.bold = bold
    run._element.rPr.rFonts.set(qn('w:eastAsia'), name)


def h1(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12)
    p.paragraph_format.space_after = Pt(5)
    cn(p.add_run(text), '黑体', 13, True)


def para(doc, text='', size=10.5):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    cn(p.add_run(text), '宋体', size)


def form_table(doc, rows, widths):
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, w in enumerate(widths):
        for row in t.rows:
            row.cells[i].width = Cm(w)
    for ri, row in enumerate(rows):
        for ci, val in enumerate(row):
            c = t.cell(ri, ci)
            c.text = ''
            p = c.paragraphs[0]
            p.paragraph_format.space_after = Pt(1)
            cn(p.add_run(str(val)), '黑体' if ri == 0 else '宋体', 9)
    doc.add_paragraph().paragraph_format.space_after = Pt(3)


def check_section(doc, title, rows):
    """rows: [项目, 条件, 期望]; 实测/判定/备注 留空"""
    h1(doc, title)
    all_rows = [['#', '项目', '测试条件', '期望', '实测', '判定', '备注']]
    for i, r in enumerate(rows, 1):
        all_rows.append([str(i)] + r + ['', '□OK □NG', ''])
    form_table(doc, all_rows, [0.8, 3.2, 4.0, 3.6, 2.2, 1.8, 2.6])


def build():
    doc = Document()
    for s in doc.sections:
        s.top_margin, s.bottom_margin = Cm(1.8), Cm(1.8)
        s.left_margin, s.right_margin = Cm(1.8), Cm(1.8)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('上板测试记录表\nAD9226 数字频谱分析仪'), '黑体', 16, True)

    # 表头信息
    form_table(doc, [
        ['固件版本 (VERSION)', '测试日期', '测试人', '信号源型号', '显示器型号'],
        ['', '', '', '', ''],
    ], [3.6, 2.8, 2.4, 3.6, 3.6])
    para(doc, '判定标准: OK = 实测符合期望; NG = 偏差超限 (备注栏写明数值); '
              'NA = 条件不具备未测。全部项目完成后本表扫描件随论文归档。')

    check_section(doc, 'A  上电与自检', [
        ['心跳灯 (脚20)', '上电', '1 Hz 闪烁'],
        ['默认界面', 'HDMI 接入', '频谱+瀑布+菜单, Span 1 MHz'],
        ['F0 读数', '接入 100 kHz 信号', 'F0: 100000 HZ (绿字)'],
        ['谐波标记', '同上', '5 色三角位于 100k~500k'],
        ['谐波电平表', '同上', 'H2~H5 读数与信号源谐波设置一致'],
    ])

    check_section(doc, 'B  频率精度', [
        ['10 kHz', '正弦 10 kHz, Span 50 kHz', '读数偏差 ≤±0.1%'],
        ['100 kHz', '正弦 100 kHz, Span 1 MHz', '读数偏差 ≤±0.1%'],
        ['250 kHz', '正弦 250 kHz, Span 1 MHz', '读数偏差 ≤±0.1%'],
        ['500 kHz', '正弦 500 kHz, Span 1 MHz', '读数偏差 ≤±0.1%'],
        ['900 kHz', '正弦 900 kHz, Span 1 MHz', '读数偏差 ≤±0.1%'],
        ['5 MHz (宽频)', '正弦 5 MHz, Span 27 MHz (F0/kHz)', '读数偏差 ≤±0.1%'],
    ])

    check_section(doc, 'C  幅度与平坦度', [
        ['满量程定标', '正弦 1Vpp ≈ -6 dBFS', '读数 -6±0.5 dB'],
        ['平坦度 1', '100 kHz, -6 dBFS', '±0.5 dB'],
        ['平坦度 2', '250 kHz, -6 dBFS', '±0.5 dB'],
        ['平坦度 3', '500 kHz, -6 dBFS', '±0.5 dB'],
        ['平坦度 4', '900 kHz, -6 dBFS', '±0.5 dB'],
        ['过载指示', '输入 >2Vpp', 'LED2 常亮'],
    ])

    check_section(doc, 'D  谐波测量', [
        ['HD2', '100 kHz 基波 -6 dBFS, 二次谐波 -26 dB', '读数偏差 ≤±1 dB'],
        ['HD3', '同上, 三次谐波 -30 dB', '读数偏差 ≤±1 dB'],
        ['H 表 vs Δ 光标', '基波跳峰后进 Δ, 移到 HD2', 'ΔF=100 kHz, ΔdB 与 H2 一致'],
        ['增量符号', '向低频方向移动光标', '符号变 -'],
    ])

    check_section(doc, 'E  时域波形', [
        ['100 kHz 触发', 'Span 1 MHz + 时域视图', '波形静止 (每周期 8 点)'],
        ['窗口换档', 'Span 250 kHz', '窗口 512 us, 波形变疏'],
        ['触发一致性', '连续观察 30 s', '无左右跑动'],
    ])

    check_section(doc, 'F  窗函数', [
        ['RBW 联动', '切 Rect', 'RBW 显示 488 Hz (Span 1M)'],
        ['幅度一致', '四窗下同信号', '读数偏差 ≤±0.1 dB'],
        ['主瓣宽度', 'Flat Top 目视', '主瓣明显宽于 Hann'],
    ])

    check_section(doc, 'G  交互与瀑布', [
        ['KEY2 三模式', '循环按键', '三视图切换无撕裂'],
        ['AUTO', '信号 >500 kHz', '自动进宽频档'],
        ['编码器方向', '顺时针旋转', '跨度 +1 / 光标右移'],
        ['瀑布滚动', '观察 30 s', '新行在顶, 逐行下移'],
        ['瀑布漂移', '手调信号源频率', '亮带随频率倾斜'],
    ])

    check_section(doc, 'H  异常项 (记录用)', [
        ['0Hz 大峰', '检查直流偏置', '如有: 记偏置码值, 改 13\'sd2048'],
        ['镜像峰', '宽频档 >27 MHz 输入', '记录折叠位置 (无抗混叠, 预期)'],
        ['过零瞬变', '波形过零处', '如出现: 记录截图 (预期无)'],
    ])

    para(doc, '测试完毕后: 将本表 + 截图 + 信号源配置整理进论文第 5 章; '
              'NG 项回到《代码阅读引导》7.1/7.2 对照处理。')

    out = os.path.join(OUT_DIR, '上板测试记录表.docx')
    doc.save(out)
    print('OK:', out)


if __name__ == '__main__':
    build()

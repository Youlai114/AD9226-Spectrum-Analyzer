# -*- coding: utf-8 -*-
"""生成《操作手册》(用户视角: 接线/按键/读数/排障)"""
import os
from docx import Document
from docx.shared import Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import re

OUT_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '文档'))


def cn(run, name='宋体', size=11, bold=False):
    run.font.name = name
    run.font.size = Pt(size)
    run.bold = bold
    run._element.rPr.rFonts.set(qn('w:eastAsia'), name)


def para(doc, text='', size=11, bold=False, indent=True, space_after=5, line=1.4, align=None):
    p = doc.add_paragraph()
    if align is not None:
        p.alignment = align
    pf = p.paragraph_format
    pf.space_after = Pt(space_after)
    pf.line_spacing = line
    if indent and text:
        pf.first_line_indent = Pt(size * 2)
    if text:
        for part in re.split(r'(\*\*.+?\*\*)', text):
            if not part:
                continue
            if part.startswith('**') and part.endswith('**') and len(part) > 4:
                cn(p.add_run(part[2:-2]), '宋体', size, True)
            else:
                cn(p.add_run(part), '宋体', size, bold)
    return p


def h1(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14)
    p.paragraph_format.space_after = Pt(6)
    cn(p.add_run(text), '黑体', 15, True)


def h2(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(9)
    p.paragraph_format.space_after = Pt(4)
    cn(p.add_run(text), '黑体', 12, True)


def table(doc, rows, widths=None, header=True):
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    t.style = 'Table Grid'
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    if widths:
        for i, w in enumerate(widths):
            for row in t.rows:
                row.cells[i].width = Cm(w)
    for ri, row in enumerate(rows):
        for ci, val in enumerate(row):
            c = t.cell(ri, ci)
            c.text = ''
            p = c.paragraphs[0]
            p.paragraph_format.space_after = Pt(1)
            cn(p.add_run(str(val)), '黑体' if (header and ri == 0) else '宋体', 10)
    doc.add_paragraph().paragraph_format.space_after = Pt(3)


def build():
    doc = Document()
    for s in doc.sections:
        s.top_margin, s.bottom_margin = Cm(2.2), Cm(2.2)
        s.left_margin, s.right_margin = Cm(2.4), Cm(2.4)

    # ---------------- 封面标题 ----------------
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('AD9226 数字频谱分析仪\n操作手册'), '黑体', 20, True)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('Tang Nano 20K (GW2AR-18) + AD9226 模块 + HDMI 输出'), '宋体', 11)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('固件: ad9226_hdmi_spectrum.fs   版本: 2026-10-24'), '宋体', 10)
    doc.add_paragraph()

    # ---------------- 1 概述 ----------------
    h1(doc, '1  仪器概述')
    para(doc, '本仪器是一台基于 FPGA 的实时频谱分析仪, 通过 AD9226 模块 (12bit, 54 MSPS) '
              '采样信号, 在 FPGA 内完成抽取、加窗、4096 点 FFT 与幅度谱计算, 通过 HDMI '
              '在显示器上实时显示频谱、时域波形和瀑布图。')
    table(doc, [
        ['项目', '指标'],
        ['频率跨度', '1 MHz / 250 kHz / 50 kHz / 10 kHz / 27 MHz (宽频, 覆盖 0~10 MHz)'],
        ['RBW (分辨率带宽)', '732 Hz / 183 Hz / 36.6 Hz / 7.3 Hz / 19.8 kHz (Hann 窗)'],
        ['幅度量程', '0 ~ -80 dBFS (10 dB/格), 满量程 = AD9226 满摆幅 (约 2 Vpp)'],
        ['时域波形', '1024 点采集, 边沿触发, 屏幕显示前 256 点 (4 倍内插)'],
        ['瀑布图', '256 列 x 128 行历史, 8 级热色, 每帧滚动一行'],
        ['输入', 'AD9226 模块 SMA (VINA), 内部偏置 2V, 输入约 1Vpp 不削顶'],
    ], [4.0, 11.5])

    # ---------------- 2 快速上手 ----------------
    h1(doc, '2  快速上手')
    h2(doc, '2.1 连接')
    para(doc, '(1) 将 Tang Nano 20K 插到底板双排排针上 (注意方向, USB 口朝外);')
    para(doc, '(2) AD9226 模块接底板 H1 插座 (5V/GND/CLK/OTR/D0~D11, 丝印一一对应);')
    para(doc, '(3) 信号从 SMA 探头/电缆接入 AD9226 模块 VINA;')
    para(doc, '(4) HDMI 线接显示器; USB 线接电脑 (供电 + 烧录)。')
    h2(doc, '2.2 烧录与开机')
    para(doc, '打开高云 Programmer, 选 impl/pnr/ad9226_hdmi_spectrum.fs, 点烧录 (固化到 '
              'SPI Flash 请勾选 "固化" 并烧 .bin/.fs)。上电后:')
    para(doc, '(1) LED_STAT (引脚 20) 每秒闪烁一次 = 系统运行正常;')
    para(doc, '(2) 显示器出现频谱界面, 默认 Span 1 MHz;')
    para(doc, '(3) 输入信号后迹线出现谱峰, 谐波标记 (绿/青/紫/橙/紫红五色小三角) '
              '自动标在基波及其 2~5 次谐波位置。')
    h2(doc, '2.3 30 秒上手流程')
    table(doc, [
        ['步骤', '操作', '现象'],
        ['接信号', '接入约 100 kHz 正弦 (0.5~1Vpp)', '黄色迹线在 100 kHz 处出现谱峰'],
        ['选档', '按 KEY1 选 Span 1 MHz', '100 kHz 峰在屏幕左侧 1/10 处'],
        ['自动定档', '按 KEY3 (AUTO)', '仪器自动选最窄能容纳 5 次谐波的档'],
        ['测读数', '按 KEY4 开光标, 转编码器', '光标线移动, 顶栏右侧显示频率/dB'],
        ['看稳定度', '再按 KEY2 回到频谱+瀑布', '背景瀑布显示信号随时间的变化'],
        ['看波形', '按 KEY2 切到时域', '绿色波形, 上升沿触发, 静止不跑'],
    ], [2.5, 6.5, 6.5])

    # ---------------- 3 键位 ----------------
    h1(doc, '3  按键与编码器')
    table(doc, [
        ['输入', '功能', '说明'],
        ['KEY1', '循环切跨度', '1M → 250k → 50k → 10k → 27M(宽频) → 1M'],
        ['KEY2', '显示模式循环', '频谱+瀑布+菜单 → 纯净频谱 → 时域波形 → 回'],
        ['KEY3', 'AUTO 自动定档', '按基波位置选"能容纳 5 次谐波"的最窄档; f0>500kHz 进宽频'],
        ['KEY4', '光标开/关', '开启后白虚线光标出现在频谱上'],
        ['KEY5', '窗函数循环', 'Hann(默认) → Rect → Blackman → FlatTop, 菜单高亮显示'],
        ['编码器旋转', '调跨度 / 移光标', '光标关: 每格 1 档, 到头停; 光标开: 每格移动 4 列'],
        ['编码器按压', 'Preset / 跳峰', '光标关: Preset (回 Span 1MHz); 光标开: 光标跳到基波峰值'],
        ['S2 (板载)', '硬件复位', '整机重启, 显示设置回到默认'],
    ], [3.0, 4.0, 8.5])

    # ---------------- 4 显示模式 ----------------
    h1(doc, '4  三种显示模式 (KEY2 切换)')
    h2(doc, '4.1 模式一: 频谱 + 瀑布 + 菜单 (默认)')
    para(doc, '主工作界面。左侧纵轴 dBFS, 底部横轴频率, 黄色迹线为当前频谱, 橙色为峰值保持 '
              '(缓慢跌落), 彩色三角为 1~5 次谐波标记, 背景瀑布图记录最近 128 帧的频谱历史 '
              '(白=强, 蓝=弱, 黑=无)。右侧菜单为预留功能区 (当前仅显示参数)。')
    h2(doc, '4.2 模式二: 纯净频谱')
    para(doc, '右侧菜单整体折叠, 瀑布关闭, 黑底黄线最干净, 适合截图/演示/仔细观察弱谱线。'
              '顶栏光标读数保留。')
    h2(doc, '4.3 模式三: 时域波形')
    para(doc, '示波器风格: 绿色波形, 0V 中线, 上升沿 0V 触发。每格时基随跨度档自动变化 '
              '(Span 1MHz 档窗口 128us, 约 12.8 个 100kHz 周期)。波形左右不动 = 触发正常; '
              '看高频信号请配合调跨度档 (窗口 = 256 点 / fs)。')

    # ---------------- 5 跨度档位 ----------------
    h1(doc, '5  跨度档位与选档建议')
    table(doc, [
        ['档', 'Span', '采样率 fs', 'RBW', '扫一次', '适用'],
        ['0', '1 MHz', '2 MSPS', '732 Hz', '2.05 ms', '音频以上~500kHz, 默认档'],
        ['1', '250 kHz', '500 kSPS', '183 Hz', '8.19 ms', '低频细看'],
        ['2', '50 kHz', '100 kSPS', '36.6 Hz', '41.0 ms', '音频精细分析'],
        ['3', '10 kHz', '20 kSPS', '7.3 Hz', '204.8 ms', '极低频/慢信号'],
        ['4', '27 MHz', '54 MSPS 直采', '19.8 kHz', '75.9 us', '宽频: 覆盖 0~10 MHz'],
    ], [1.2, 2.6, 3.0, 2.6, 2.6, 3.5])
    para(doc, '选档口诀: **先估信号频率, 再留 1.5 倍余量**。例如测 100 kHz 信号并关心其 '
              '3 次谐波 (300 kHz), 选 Span 1 MHz; 只看基波本身可选 250 kHz 档获得 4 倍 '
              '频率分辨率。拿不准就按 KEY3 让仪器自动选。')

    # ---------------- 6 光标与读数 ----------------
    h1(doc, '6  光标与读数解释')
    para(doc, '按 KEY4 开启光标后, 顶栏右侧显示: **MKR  250000 HZ  -12.3 DB**')
    table(doc, [
        ['字段', '含义'],
        ['MKR 250000 HZ', '光标所在位置的频率 (Hz; 宽频档自动改 kHz, 单位显示 KHZ)'],
        ['-12.3 DB', '光标处谱线幅度, 单位 dBFS (0 = 满量程), 0.1dB 分辨率'],
        ['-96.4 下限', '该列幅度为 0 (纯噪底以下) 时显示的下限值'],
    ], [5.0, 10.5])
    para(doc, '**dBFS 含义**: 0 dBFS = AD9226 满量程 (输入约 2Vpp)。-10dB = 满量程的 '
              '31.6%。日常正弦约 1Vpp ≈ -6dBFS。读数与屏幕迹线严格同源 (同一份数据)。')
    para(doc, '**光标跳峰**: 光标开启时按一下编码器, 光标自动跳到当前最强谱峰 (基波) '
              '位置, 立即读出主信号的频率和幅度。')
    h2(doc, '6a  F0 基波频率大读数 (自动, 顶栏第 2 行右侧)')
    para(doc, '信号有效时仪器自动识别最强谱峰 (基波) 并在顶栏第 2 行右侧用绿字'
              '显示其频率: "F0: 100000 HZ" (宽频档自动改 kHz)。这是仪器对'
              '"当前测的是什么信号"的直接回答, 演示和记录时先看它。')

    h2(doc, '6b  谐波电平表 (自动, 顶栏左侧)')
    para(doc, '信号有效时顶栏第 4 行左侧自动显示 2~5 次谐波电平 (绿字), 例如 '
              '"H2 -12.2  H3 -18.2  H4 -24.2  H5 -28.3"。仪器自动在基波频率的 2~5 倍处 '
              '搜索峰值——接上信号直接抄数, 毕设的谐波指标可直接引用这行读数 '
              '(含义: 各次谐波相对满量程的 dB 值)。')
    h2(doc, '6c  增量模式: 谐波/频率差测量')
    para(doc, 'KEY4 为三态: 关 → 普通读数 → 增量 Δ。标准流程: (1) 光标开启后按一下编码器 '
              '跳到基波峰; (2) 按 KEY4 进入增量模式 (读数变 DLT, 暗青虚线标出参考位置); '
              '(3) 转编码器移到目标处。读数 ΔF 为频率差、ΔdB 为幅度差——例如移到 '
              '200kHz 峰处应显示 DLT +100000 HZ, ΔdB 即二次谐波相对基波的强度。')

    # ---------------- 7 瀑布图 ----------------
    h1(doc, '7  瀑布图解读')
    para(doc, '瀑布图纵向是时间 (顶=最新, 底=最旧, 共 128 帧), 横向是频率, 颜色是幅度:')
    table(doc, [
        ['颜色', '幅度'],
        ['白 / 橙', '接近满量程 (0 ~ -15 dBFS)'],
        ['黄 / 绿', '中等 (-15 ~ -40 dBFS)'],
        ['蓝 / 深蓝', '弱 (-40 ~ -70 dBFS)'],
        ['黑', '噪底以下 (-70 dBFS 以下)'],
    ], [4.0, 11.5])
    para(doc, '用法: 频率轴上**竖直亮带** = 稳定信号; **斜线** = 频率漂移 (VCO 扫频/失稳); '
              '**断续竖线** = 间歇信号; 整屏缓慢变亮 = 前端过载或干扰进入。')

    # ---------------- 7b 窗函数 ----------------
    h1(doc, '7b  窗函数选择 (KEY5)')
    para(doc, '窗函数决定 FFT 频域滤波的形状, 影响分辨率 (RBW)、谱线泄漏和幅度精度。'
              '按 KEY5 循环切换, 右侧菜单 Window 按钮 (蓝色高亮) 显示当前窗, '
              '三处 RBW 读数自动联动。同一信号四种窗的幅度读数一致 (已校准)。')
    table(doc, [
        ['窗', 'RBW 因子', '旁瓣', '什么时候用'],
        ['Hann (默认)', '1.5', '-31.5 dB', '通用测量, 不知道选什么就用它'],
        ['Rect (矩形)', '1.0', '-13 dB', '信号正好对准谱线时幅度最准; 瞬态/脉冲'],
        ['Blackman', '1.73', '-58 dB', '大信号旁边找小信号 (动态范围优先)'],
        ['Flat Top', '3.77', '-93 dB', '精确测量幅度 (±0.01dB), 主瓣最宽'],
    ], [3.0, 2.6, 2.6, 7.3])
    para(doc, '注意: 换窗后 RBW 变化 (Rect 最细, Flat Top 最宽); 换窗从下一帧生效, '
              '约 1~2 帧过渡。窗对瀑布图和谐波标记同样生效。')

    # ---------------- 8 指示灯 ----------------
    h1(doc, '8  指示灯')
    table(doc, [
        ['灯', '引脚', '含义'],
        ['LED_STAT (心跳)', '20', '1Hz 闪烁 = 运行正常; 常亮/常灭 = 异常'],
        ['LED_OVR (过载)', '71', '常亮 = 本帧内 AD 出现过压 (OTR), 输入幅度超量程'],
    ], [4.5, 2.0, 9.0])
    para(doc, '过载灯亮时读数偏低且谐波异常增多, 请减小输入幅度 (加衰减器或调信号源)。')

    # ---------------- 9 已知限制 ----------------
    h1(doc, '9  已知限制 (正常现象, 非故障)')
    para(doc, '(1) **无模拟抗混叠滤波器**: 带外强信号会折叠进显示带宽。宽频档测 0~10 MHz '
              '时, 27~54 MHz 的干扰会镜像出现, 请保证信号源干净;')
    para(doc, '(2) **栅栏损失 ≤1.42 dB**: 信号落在两根谱线正中间时读数偏低最多 1.42dB '
              '(Hann 窗固有);')
    para(doc, '(3) **宽频档噪底高约 14 dB**: 直采无抽取增益, 噪底更靠近显示下限;')
    para(doc, '(4) **换档后 1~2 帧过渡**: 换跨度瞬间画面仍是旧数据, 谐波标记自动隐藏, '
              '随后恢复;')
    para(doc, '(5) **瀑布图冷启动**: 上电/切档后瀑布从顶部开始逐行填充, 约 2~14 秒填满;')
    para(doc, '(6) **直流偏置假设**: 模块输出以 2048 码为中心。若 0 Hz 处出现异常大峰, '
              '说明模块偏置偏离 2V。')
    para(doc, '(7) **换档/换窗后的过渡**: 1~2 帧内谱线仍是旧参数的数据, 谐波标记/'
              'H表/F0 会自动隐藏到新数据就绪, 属正常; 瀑布图的历史最长 128 帧'
              '含有旧档频率 (Span 10k 档约 27 秒), 会逐行滚出。')
    para(doc, '(8) **H5 读数的边界**: 信号频率恰好落在两根谱线正中时, 5 次谐波的'
              '搜索窗可能偏差, H5 读数偏低 (H2~H4 不受影响); 微调信号频率即可。')
    para(doc, '(9) **增量模式的参考快照**: 跳峰后立即 (0.1 秒内) 按键进入增量, '
              '参考幅度可能取旧值; 等一帧再进入即正确, 或退出重进。')

    # ---------------- 10 排障 ----------------
    h1(doc, '10  故障排查')
    table(doc, [
        ['现象', '检查'],
        ['无画面', 'HDMI 线/显示器输入源; 心跳灯是否闪烁; 重新烧录'],
        ['心跳灯不闪', '检查 27MHz 时钟/复位 S2; 重烧固件'],
        ['有画面无谱峰', '信号是否接入 VINA; 幅度是否 >5mV; 按 KEY3 AUTO 搜索'],
        ['谱峰位置不对', '确认当前跨度档 (KEY1); 宽频档 10M 以上信号会镜像'],
        ['读数偏低 ~1.4dB', '栅栏损失, 微调信号频率或换更宽的档'],
        ['底部阶梯状杂波', '旧固件噪底量化现象; 2026-10-25 固件已加视频平均修复, 重烧即可'],
        ['过载灯常亮', '输入幅度超 2Vpp, 加衰减'],
        ['波形乱跑不触发', '波形视图触发固定 0V 上升沿, 信号需过 0V; 调跨度档改变采样率'],
        ['按键无反应', '查底板按键焊接 (低有效, 对地导通); 引脚 15~19/48/49/72'],
    ], [5.0, 10.5])

    # ---------------- 11 指标速查 ----------------
    h1(doc, '11  底层指标速查 (供答辩/报告引用)')
    table(doc, [
        ['项', '值'],
        ['FFT', '4096 点, 基-2 DIF, 单蝶形串行, Hann 窗'],
        ['幅度精度', '通带平坦度 ±0.02 dB (含逆 sinc 补偿), 与定点模型 0 LSB 偏差'],
        ['资源 (GW2AR-18)', 'Logic ~18%, BSRAM ~40%, DSP 8/24'],
        ['时序', '全部时钟域 setup/hold 违例 0'],
        ['刷新率', 'Span 0 档约 150 fps, 最低档约 4.8 fps'],
    ], [5.0, 10.5])

    out = os.path.join(OUT_DIR, '操作手册.docx')
    doc.save(out)
    print('OK:', out)


if __name__ == '__main__':
    build()

# -*- coding: utf-8 -*-
"""生成《代码阅读引导》docx —— 回答"这份代码从哪里开始读、每个文件为什么存在"."""
import os
from docx import Document
from docx.shared import Pt, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

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
        import re
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


def code(doc, text):
    for line in text.split('\n'):
        p = doc.add_paragraph()
        pf = p.paragraph_format
        pf.space_after = Pt(0)
        pf.space_before = Pt(0)
        pf.left_indent = Cm(0.7)
        pf.line_spacing = 1.0
        r = p.add_run(line if line else ' ')
        r.font.name = 'Consolas'
        r.font.size = Pt(8.5)
        r._element.rPr.rFonts.set(qn('w:eastAsia'), '宋体')
        shd = OxmlElement('w:shd')
        shd.set(qn('w:val'), 'clear')
        shd.set(qn('w:color'), 'auto')
        shd.set(qn('w:fill'), 'F4F4F4')
        p._p.get_or_add_pPr().append(shd)
    doc.add_paragraph().paragraph_format.space_after = Pt(3)


def table(doc, rows, widths=None, header=True, size=9):
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
            cn(p.add_run(str(val)), '黑体' if (header and ri == 0) else '宋体', size)
    doc.add_paragraph().paragraph_format.space_after = Pt(3)


def build():
    doc = Document()
    for s in doc.sections:
        s.top_margin, s.bottom_margin = Cm(2.2), Cm(2.2)
        s.left_margin, s.right_margin = Cm(2.2), Cm(2.2)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('代码阅读引导\nAD9226 数字频谱分析仪 (Tang Nano 20K / GW2AR-18)'), '黑体', 18, True)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('配套: 程序对照注释手册 (逐模块细节) / 操作手册 (用户视角) / CODE_GUIDE.md (在线版)'), '宋体', 10)

    h1(doc, '1  一张图看懂全部数据流')
    para(doc, '整个工程只有两个时钟域。测量在 54MHz 域算完, 经乒乓 RAM 或 toggle 握手'
              '跨到 74.25MHz 像素域显示 —— 凡是跨域的地方代码里都有注释标明。')
    code(doc,
         '27MHz 晶振\n'
         '  |- TMDS_rPLL -> 371.25MHz - CLKDIV/5 -> 74.25MHz (像素时钟)\n'
         '  +- ad9226_pll -> 54MHz -- O_clk_adc(脚76) -> AD9226\n'
         '                        \\- I_adc_d[11:0] 回来 (54MHz 采样/FFT 域)\n'
         '\n'
         '[54MHz 测量链]\n'
         '  ad9226_capture  抽取 27/108/540/2700/1 -> fs=2M/500k/100k/20k/54M\n'
         '    | Q4 样点 (+-32768 = +-1V)\n'
         '  fft4096         加窗(Hann/Rect/Black/Flat) -> 4096点FFT -> 开方\n'
         '    |            -> 逆sinc补偿 -> 16帧平均 -> 1024列x16bit (65535=0dBFS)\n'
         '    \\- 基波列检测 + HD2~HD5 谐波窗口峰\n'
         '  spec_data_if + spec_ram   乒乓双时钟缓存\n'
         '\n'
         '[74.25MHz 显示链]\n'
         '  spec_display    频谱页: 迹线/瀑布/谐波标记/光标/F0与H表读数/菜单\n'
         '  wave_cap + wave_display  时域页: 边沿触发, 前256点4倍内插\n'
         '  video_top       模式选择 + 全部按键逻辑 + CDC 枢纽\n'
         '  DVI_TX (高云IP) -> HDMI')

    h1(doc, '2  三条阅读路线')
    h2(doc, '路线 A: 30 分钟全局 (答辩速览)')
    para(doc, 'README.md 指标表 -> video_top.v 头 50 行注释(全工程地图) -> 上图 -> '
              'sim/frames/top_004.png (顶层仿真渲染的真实界面, F0/谐波表/瀑布全在)。')
    h2(doc, '路线 B: 完整理解 (2~3 小时, 按依赖顺序)')
    table(doc, [
        ['顺序', '文件', '要点'],
        ['1', 'ad9226_pll.v', '30 行热身, 27->54MHz'],
        ['2', 'ad9226_capture.v', '采样+抽取, 注意"为什么 27 抽 1"的注释'],
        ['3', 'fft4096.v', '最核心, 先读头部定标注释再读状态机'],
        ['4', 'spec_data_if.v + spec_ram.v', '跨时钟域的标准范式 (乒乓)'],
        ['5', 'spec_display.v', '按"第 1 级..第 6 级"流水线注释分段读'],
        ['6', 'wave_cap.v + wave_display.v', '时域页, 含 $signed 教训'],
        ['7', 'key_enc_ctrl.v + auto_span.v', '人机交互, 单时钟无 CDC 问题'],
        ['8', 'video_top.v', '回顶层把所有线对上'],
    ], [1.3, 5.2, 9.0])
    h2(doc, '路线 C: 验证者 (怀疑某处有 bug)')
    para(doc, '直接查第 5 节对应表, 跑对应测试即可定位到模块。')

    h1(doc, '3  关键数据格式 (读代码前先记住)')
    table(doc, [
        ['信号', '格式', '含义'],
        ['ADC 原始', '12bit 无符号', '0..4095, 2048 = 0V'],
        ['样点 O_smp', 'Q4 有符号 16bit', '+-32768 = +-1V (x16)'],
        ['旋转因子', 'Q15 有符号', 'cos/sin'],
        ['补偿系数', 'Q7 无符号 11bit', '1024 = 1.000 倍'],
        ['幅度谱', '16bit 线性', '65535 = 0 dBFS'],
        ['dB 读数', '12bit', '|dB| x10 (964 = -96.4dB)'],
    ], [3.2, 4.2, 8.0])
    para(doc, '定点换算链的完整推导在 tools/model_fft.py 头部; RTL 与它逐位一致 '
              '(cmp_fft 0 LSB)。')

    h1(doc, '4  每个文件一句话 (删掉它会怎样)')
    table(doc, [
        ['文件', '删掉的后果'],
        ['ad9226_capture.v', '没有样点 (ADC 接口+抽取+去直流)'],
        ['fft4096.v', '没有频谱 (窗/FFT/开方/补偿/平均/基波+谐波检测)'],
        ['fft_tables.v', '没有窗和旋转因子 (脚本生成, 勿手改)'],
        ['spec_data_if.v', '换帧瞬间画面撕裂'],
        ['spec_ram.v', '没有跨时钟缓存'],
        ['spec_display.v', '频谱页整页消失'],
        ['wave_cap.v', '波形左右乱跑 (无触发)'],
        ['wave_display.v', '没有时域页'],
        ['key_enc_ctrl.v', '按键/编码器全失效'],
        ['auto_span.v', '没有 AUTO 定档'],
        ['video_top.v', '散件没有连线 (例化+CDC 枢纽)'],
        ['ui_font_rom.v', '所有文字消失'],
        ['gw_stubs.v (sim)', '顶层仿真无法运行 (高云原语行为桩)'],
    ], [4.5, 11.0])

    h1(doc, '5  验证对应表 (想验证什么 -> 跑什么)')
    table(doc, [
        ['想确认', '命令 (sim/ 下)', '期望'],
        ['FFT 数学', 'vsim ... tb_fft +F0=250e3 后跑 cmp_fft.py', '0 LSB'],
        ['四窗校准', 'tb_fft +WIN=1/2/3', 'peak 约 65480 (+-1%)'],
        ['基波检测', 'tb_fft +F0=100e3', 'hrm_col=102'],
        ['按键/编码器', 'vsim ... tb_key_enc', 'ALL PASS (11 项)'],
        ['波形逐列', 'vsim ... tb_wave_frame + 对拍', '0 列偏差'],
        ['整机三时钟域', 'vsim ... tb_top +DUMP1=3 +DUMP2=4', '渲染含 F0/H表/标记'],
        ['一键全跑', 'bash tools/run_regression.sh', 'ALL PASS'],
    ], [3.0, 7.2, 5.0])

    h1(doc, '6  带 * 号的注释 = 踩过坑的教训 (改前必读)')
    para(doc, '全工程 9 处 "★" 注释, 每处都是真实调试结论: wave_display 的拼接无符号'
              '陷阱 (过零瞬变)、fft4096 的乘积宽度回绕、spec_display 的 double-dabble '
              '步数与字段宽度、build.tcl 的 SDC 静默失效等。搜索 "★" 定位全部。')

    h1(doc, '7  已知边界与潜在 BUG 清单 (维护者必读)')
    h2(doc, '7.1 仍存在的设计边界 (已知、可解释、未修)')
    table(doc, [
        ['现象/风险', '原因与量级', '规避'],
        ['换档/换窗后 1~2 帧过渡', '谱线为旧参数数据; 标记/H表/F0 已加跨度门控自动隐藏, 文字立即切换', '等 1~2 帧即恢复, 无需处理'],
        ['瀑布历史跨档混合', '换档后最长 128 帧历史行含旧档频率 (Span 10k 档约 27 秒)', '等历史滚出, 或记录前多等一会'],
        ['H5 窗口边界', '基波恰在两 bin 正中时 5 次谐波列误差可达 +-2.5 列, 超出 +-2 列搜索窗, H5 可能读低', 'H2~H4 不受影响; 微调信号频率即可'],
        ['增量参考快照', '跳峰后 17ms 内按 KEY4, 参考幅度可能取到旧列值并冻结', '等一帧再进增量; 或退出重进'],
        ['光标读数滞后 1 帧', '抓幅机制固有 (扫描经过光标列时抓)', '无需处理'],
        ['Flat Top 满量程微饱和', '+0.08dB, 在 0.1dB 显示分辨率的边界', '用 -1dBFS 以下的信号校准'],
        ['宽频档镜像', '27~54MHz 带外信号折叠进显示 (无模拟抗混叠)', '保证信号源干净'],
        ['平均响应时间常数', '16 帧 (Span1M 约 0.1s; 慢档 4 帧约 0.8s)', '测瞬变信号时注意'],
    ], [3.2, 7.0, 4.2], size=8)
    h2(doc, '7.2 上板才能确认的硬件风险 (仿真覆盖不到)')
    table(doc, [
        ['风险点', '现象', '调整点'],
        ['AD9226 直流偏置', '0Hz 异常大峰', "ad9226_capture.v 的 13'sd2048"],
        ['编码器机械抖动', '偶发方向反转/连跳', 'key_enc_ctrl.v 的 ENC_STEP (4->2)'],
        ['HDMI 显示器兼容', '个别显示器黑屏', '换线/换口; 时序参数勿改'],
        ['杜邦线接触', '数据位跳变/花屏', '压紧/换线, CLK 线最短'],
    ], [3.6, 5.0, 6.0], size=8)
    h2(doc, '7.3 测试平台 (TB) 已知怪癖')
    para(doc, 'tb_fft 的 +FRAMES 多帧驱动在部分帧数下节奏异常 (单帧模式 0 LSB 回归'
              '完全可靠); 多帧验证一律用 tb_top (真实三时钟域、vsync 节拍)。'
              '另: PPM 落盘有 1 列采样偏移 (已在 TB 内补偿); 直接在 initial 里发'
              ' frame_req 脉冲会与 ST_MAG 收尾竞态 (需等忙再等闲)。')
    h2(doc, '7.4 历史已修的坑 (改动相关代码前先搜 * 号注释)')
    para(doc, '拼接无符号陷阱 / 乘积宽度回绕 / double-dabble 步数 / twiddle 半表刻度 / '
              'BSRAM X 污染 / 文字参数顺序转置 / 前缀拼接移位 / FSM else 误删 / '
              '多驱动 / gw_sh SDC 静默失效 / license U+202A —— 全部在代码内以 '
              '★ 注释留档, 共 10 处。')

    h1(doc, '8  硬件事实 (读代码容易忘的)')
    para(doc, '(1) 板载晶振 27MHz (不是 50), PLL 参数由此而来; (2) AD9226 模块 5V 供电、'
              '内部偏置 2V、满量程约 2Vpp; (3) 引脚 54/55/56 是高云 SSPI 专用脚, 永不占用; '
              '(4) 按键/编码器低有效 (内部上拉), S2(脚88) 是唯一硬件复位。')

    out = os.path.join(OUT_DIR, '代码阅读引导.docx')
    doc.save(out)
    print('OK:', out)


if __name__ == '__main__':
    build()

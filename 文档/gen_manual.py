# -*- coding: utf-8 -*-
"""生成《程序对照注释手册》"""
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


def para(doc, text='', size=11, bold=False, font='宋体', indent=True,
         space_after=5, line=1.4, align=None):
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
                cn(p.add_run(part[2:-2]), font, size, True)
            else:
                cn(p.add_run(part), font, size, bold)
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
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
    sec.left_margin = sec.right_margin = Cm(2.2)
    sec.top_margin = sec.bottom_margin = Cm(2.2)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('AD9226 数字频谱分析仪'), '黑体', 18, True)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('程序对照注释手册'), '黑体', 20, True)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('配套工程：ad9226_hdmi_spectrum'), '宋体', 11)
    doc.add_paragraph()

    para(doc, '说明：本手册按"数据流顺序"逐个文件讲解，每节的结构是——这个文件负责什么、'
              '接口长什么样、关键代码在做什么、为什么这么写。建议对照源码一起看，'
              '先读第 1 章建立整体印象，再按需翻到具体模块。', indent=True)

    # ================= 1 =================
    h1(doc, '第 1 章  先看整体：数据是怎么流动的')

    h2(doc, '1.1 一条数据通路')
    para(doc, '整台仪器只有一条主数据通路，其他都是为它服务的：')
    code(doc,
         'AD9226 ──12bit 并行──> 采集 54MSPS ──抽取──> fs=2M/500k/100k/20k\n'
         '                                        │\n'
         '                                        ├──> 4096 点 FFT ──> 1024 列幅度 ──> 显示（下半屏）\n'
         '                                        │\n'
         '                                        └──> 1024 点时域 ──> 波形缓冲 ──> 显示（上半屏）')
    para(doc, '要点：FFT 和时域波形用的是**同一份抽取后数据**，只是走两条不同的出口。'
              '所以采集模块只需要一份，不用做两遍。')

    h2(doc, '1.2 三个时钟域')
    table(doc, [
        ['时钟', '频率', '谁在用', '跨域方式'],
        ['I_clk', '27 MHz', '板载晶振，PLL 的输入', '—'],
        ['adc_clk', '54 MHz', 'AD9226 采样、抽取、FFT 全程', '主时钟，大部分逻辑在这'],
        ['pix_clk', '74.25 MHz', 'HDMI 像素输出、显示扫描、按键', '通过乒乓 RAM 与主时钟隔离'],
    ], [2.6, 2.4, 6.2, 4.0])
    para(doc, '初学者最容易卡住的地方：FFT 在 54 MHz 域算完，显示在 74.25 MHz 域读，'
              '两边频率不同、相位无关。**不能直接连线**，必须用双口 RAM（乒乓）过渡，'
              '否则会出现"读到一半数据被改写"的撕裂。')

    h2(doc, '1.3 文件清单：谁负责什么')
    table(doc, [
        ['文件', '行数', '职责', '要不要细看'],
        ['ad9226_pll.v', '~30', '27 MHz ×2 出 54 MHz', '扫一眼即可'],
        ['ad9226_capture.v', '127', '采样、抽取 27/108/540/2700、去直流', '★ 必看'],
        ['fft4096.v', '464', '4096 点定点 FFT + 幅度谱 + 补偿', '★ 必看'],
        ['fft_tables.v', '7213', 'Hann 窗、旋转因子、补偿表（脚本生成）', '不用看，看生成脚本'],
        ['spec_data_if.v', '82', '把幅度流打包成 RAM 写时序', '看'],
        ['spec_ram.v', '~40', '双口 RAM，乒乓两个 bank', '看'],
        ['spec_display.v', '~1100', '版面/迹线/运行时文字/瀑布图/谐波标记/光标读数', '看第 5 章'],
        ['key_enc_ctrl.v', '~210', '按键消抖 + 编码器 + 跨度/光标模式管理', '可选'],
        ['auto_span.v', '~90', 'AUTO（KEY3）：按基波位置自动选最窄跨度', '新增，很短'],
        ['wave_cap.v', '108', '时域波形采集 + 边沿触发', '新增，看第 6 章'],
        ['wave_display.v', '480', '时域波形显示（4 倍内插、示波器风格）', '新增，看第 6 章'],
        ['video_top.v', '355', '顶层：例化所有模块、连时钟域', '看第 2 章'],
        ['ui_font_rom.v', '1 块 BSRAM', '5x7 字模（脚本生成）；文字网格已改运行时解码', '不用看'],
        ['spec_demo_gen.v', '3286', '不接 ADC 时的假数据', '不用看'],
    ], [4.2, 1.5, 6.8, 3.2])

    # ================= 2 =================
    doc.add_page_break()
    h1(doc, '第 2 章  ad9226_capture.v —— 采集与抽取')

    h2(doc, '2.1 它要解决什么')
    para(doc, 'AD9226 以 54 MSPS 连续输出 12 位数据。但我们最终要的采样率是 2 MHz'
              '（跨度 1 MHz 时）。把 54 MHz 降到 2 MHz 有两种办法：')
    table(doc, [
        ['办法', '做法', '问题'],
        ['降 ADC 时钟', '让 ADC 直接跑 2 MHz', '流水线 ADC 低时钟时采样保持会 droop，且抖动变大'],
        ['数字抽取（采用）', 'ADC 照常 54 MSPS，数字域平均 27 个点出一个', '要多一块逻辑，但白赚 14.3 dB 噪声处理增益'],
    ], [3.0, 5.4, 6.6])
    para(doc, '27 个点平均等价于一个 27 点的滑动平均滤波器（也叫 boxcar / 一阶 CIC），'
              '它在 2 MHz 处正好是零点，天然抑制了部分带外信号。')

    h2(doc, '2.2 三级流水')
    code(doc,
         '// 第 1 级：累加\n'
         'if (take_now) begin\n'
         '    dec_cnt <= 12\'d0;\n'
         '    acc     <= 24\'sd0;          // 累加器清零\n'
         '    sum_l   <= sum_now[23:0];    // 把 2700 个样点的和打一拍\n'
         'end else begin\n'
         '    dec_cnt <= dec_cnt + 12\'d1;\n'
         '    acc     <= sum_now[23:0];    // 一直累加\n'
         'end\n'
         '\n'
         '// 第 2 级：乘 Q20 倒数\n'
         'mul  <= sum_l * inv_n;           // 24bit × 16bit → 40bit\n'
         '\n'
         '// 第 3 级：右移 20 位还原幅度，再左移 4 位对齐 Q4\n'
         'O_smp <= mul[35:20] <<< 4;')
    para(doc, '为什么分成三级而不是一口气算完？')
    para(doc, '因为每两级之间插了一级寄存器，组合逻辑被切短，54 MHz 才收敛得下来。'
              '如果写成 `O_smp <= (acc * inv_n) >>> 20 <<< 4;` 一行，综合出来的路径会很长，'
              '时序直接挂。这是 FPGA 设计的通用手法——**用寄存器换频率**。')

    h2(doc, '2.3 为什么用乘倒数，不用除法')
    para(doc, 'Verilog 里的 `/` 如果除数是变量，会综合出真除法器，面积大、速度慢；'
              '即使除数是常数，不同综合器的优化程度也不一样。'
              '而乘一个常数再右移，稳定地映射到 DSP 乘法器上，又快又小。')
    table(doc, [
        ['抽取比', '等效 fs', '倒数（Q20）', '误差'],
        ['27', '2.000 MHz', '38836', '< 0.001%'],
        ['108', '500 kHz', '9709', '< 0.01%'],
        ['540', '100 kHz', '1942', '< 0.03%'],
        ['2700', '20 kHz', '388', '< 0.1%'],
    ], [2.4, 3.2, 3.6, 3.2])
    para(doc, 'Q20 的意思是把 1/N 放大 2^20 倍存成整数，乘完再右移 20 位。'
              '以 1/2700 为例：2^20 / 2700 = 388.4，取整 388，误差 0.1%，'
              '对幅度来说只差 0.009 dB，完全够用。')

    h2(doc, '2.4 为什么还要左移 4 位')
    para(doc, 'AD9226 输出是无符号 0~4095，中点 2048。代码先减 2048 变成有符号 ±2048，'
              '再左移 4 位变成 ±32768（Q4 格式）。这样后续 FFT 用 16 位有符号运算时，'
              '小数点位置统一，定标不用来回换。')

    h2(doc, '2.4 宽频直采 (第 5 档) —— 抽取比 1')
    para(doc, '跨度 27 MHz 档 (覆盖 0~10 MHz 需求) 用 54 MSPS 直采: 抽取比 1 时累加器 '
              '每拍清零, sum_l 就是样点本身, 乘法旁路, 输出 = 样点 << 4 对齐 Q4。'
              '注意直采路径与乘法路径必须等延迟 (补一拍 sum_l_d), 否则样点错一位。'
              'FFT 侧的逆 sinc 补偿同步切平 (无箱化 = 无倾斜), 见 3.4。')

    # ================= 3 =================
    doc.add_page_break()
    h1(doc, '第 3 章  fft4096.v —— 4096 点 FFT')

    h2(doc, '3.1 四个状态')
    code(doc,
         'localparam ST_IDLE = 0,   // 等开始\n'
         '           ST_CAP  = 1,   // 采集 4096 个样点（倒序写入）\n'
         '           ST_STG  = 2,   // 12 级蝶形运算\n'
         '           ST_MAG  = 3;   // 幅度谱：两 bin 合一列 + 开方 + 补偿')
    para(doc, '这是典型的"一次性算完一帧"结构，不是流水线式的连续处理。'
              '好处是控制简单，坏处是一帧算完才能算下一帧，刷新率等于 1/(采集+运算)。')

    h2(doc, '3.2 采集阶段：为什么倒序写')
    para(doc, 'Cooley-Tukey 基 2 FFT 要求输入的样点按"位倒序"排列。'
              '两种做法：'
              '（1）按顺序写、蝶形时算倒序地址；'
              '（2）写的时候就把顺序打乱，蝶形时顺序读。')
    code(doc,
         'wire [11:0] bin_rev = bitrev12(cap_cnt);   // 12 位地址按位翻转\n'
         '// 例如 cap_cnt=1 (000000000001) -> bin_rev=2048 (100000000000)')
    para(doc, '本案选（2）。因为蝶形要读 12 级、每级 2048 次，共 24576 次读；'
              '而写入只有 4096 次。把"麻烦"放在次数少的那一侧，总体更省。')

    h2(doc, '3.3 蝶形：地址怎么算')
    code(doc,
         '// 第 stg 级，共 2048 个蝶形，每级分 2^stg 组\n'
         'wire [11:0] addr_a = g * (2*half) + j;   // 上半个蝶形\n'
         'wire [11:0] addr_b = addr_a + half;      // 下半个蝶形\n'
         'wire [11:0] tw_idx = j << stg;           // 旋转因子索引\n'
         '\n'
         '// 蝶形本体：a\' = a + b·W,  b\' = a - b·W\n'
         'p1 <= da_re * tc;  p2 <= da_im * ts;\n'
         'p3 <= db_re * tc;  p4 <= db_im * ts;\n'
         'dre <= da_re + (p3 - p4);   // 实部：a + b·W\n'
         'dim <= da_im + (p3 + p4);')
    para(doc, '`half` 每级减半（2048→1024→…→1），`stg` 每级加一（0→11）。'
              '`tw_idx` 每次跳 2^stg，正好对应该级该组要用的旋转因子下标。')

    h2(doc, '3.4 为什么每级要右移 1 位')
    para(doc, '蝶形输出 |a ± b·W| 最大可能是输入的两倍。如果不缩小，12 级下来会溢出。'
              '所以每级末尾统一除 2（算术右移一位），12 级总共除 4096。')
    para(doc, '这正好和 FFT 定义里的 1/N 抵消掉——标准 DFT 公式是 X[k] = (1/N)·Σ…，'
              '硬件里靠"逐级除 2"实现了这个 1/4096。所以最后幅度值可以直接用，不用再除 N。')

    h2(doc, '3.5 幅度阶段：三个动作')
    code(doc,
         '// 动作 1：每列取相邻两个 bin 中较大的（等效峰值检波）\n'
         'xq <= (sq0 >= mag_sq) ? sq0 : mag_sq;\n'
         '\n'
         '// 动作 2：开方（逐位逼近，19 拍）\n'
         'rem  <= ge ? (rem2 - trial19) : rem2;\n'
         'root <= ge ? {root[14:0], 1\'b1} : {root[14:0], 1\'b0};\n'
         '\n'
         '// 动作 3：乘逆 sinc 补偿系数（Q7），再右移 7 位\n'
         'O_mag <= (mag_sh > 21\'h0FFFF) ? 16\'hFFFF : mag_sh[15:0];')
    para(doc, '为什么要"两个 bin 合一列"：FFT 出 2048 个正频率 bin，屏幕只有 1024 列，'
              '必须两两合并。取**平方和较大者**而不是平均，是因为开方是单调函数，'
              '先比大小再开一次方 = 先分别开方再比大小，但省了一半开方时间。'
              '效果上等于频谱仪的"峰值检波"。')

    h2(doc, '3.4b 视频平均 —— 修掉噪底的"阶梯杂波"')
    para(doc, '现象: 早期上板时频谱底部出现从低频到高频的分段阶梯杂波。根因: 噪底是 '
              '1~16 的小整数, 对数显示下每跨一个整数跳 3~6dB, 叠加逆 sinc 的平滑上斜'
              '就成了阶梯。修法: 幅度输出流上加 16 帧指数平均 (avg_mem 1024x21bit, '
              '4 位小数), 首帧直通 (与定点模型 0 LSB), 慢档自动改 1/4 深度。')
    code(doc,
         '// avg_new = avg + (mag*16 - avg) >>> 4   (凸组合, 21bit 内)\n'
         'O_mag <= (avg_new + 8) >> 4;              // 四舍五入回整数')
    para(doc, '读写在同一列的 mph0 (读) 与 mph21 (写) 两拍, 单口 BSRAM 无冲突。'
              '代价: 信号突变显示响应 ~16 帧 (Span 1MHz 档约 0.1s)。')

    h2(doc, '3.5 twiddle ROM 压缩 —— 半张表省 2 块 BSRAM')
    para(doc, '旋转因子表原为 2048 x 32 {cos, sin} 双表。注意到表的角度刻度是 '
              '2*pi*k/4096 (k=0..2047, 覆盖 0~pi 半圆), sin 与 cos 相差四分之一周期, '
              '且 cos 是偶函数: sin(k) = cos[|k-1024|]。于是只存 cos 单表 (2048x16), '
              '蝶形在 ph1 拍换读第二个地址, ph3 拍收 sin——与原双表逐位等价, '
              'cmp_fft 保持 0 LSB, 省 2 块 BSRAM 给瀑布图。')
    code(doc,
         'wire [10:0] tw_sin_a = (tw_idx > 1024) ? (tw_idx - 1024)\n'
         '                                      : (1024 - tw_idx);\n'
         'ph1: tw_addr <= tw_sin_a;   // ph0 读的是 cos(k)\n'
         'ph3: ts <= tw_cos_w;        // 此时 ROM 出的是 cos(|k-1024|) = sin(k)')
    para(doc, '★ 教训: 第一版用了 +1536 (=3/4 周期) 的直觉偏移——那只在整圆刻度 '
              '(2*pi*k/2048) 下成立。仿真对比发现泄漏抬高, 直接探测 ROM 才发现这张表 '
              '是半圆刻度。**看表先看刻度**。')

    # ================= 4 =================
    h1(doc, '第 4 章  spec_data_if.v / spec_ram.v —— 跨时钟域')

    h2(doc, '4.1 为什么需要乒乓')
    para(doc, '写侧每 6.6 ms 算完一帧（1024 列），读侧每 16.7 ms 扫一屏。'
              '如果只有一块 RAM，读的时候正好在写，屏幕就会出现"上半截新数据、下半截旧数据"的撕裂。')
    para(doc, '乒乓的做法是准备两块 RAM：写 bank0 时读 bank1，写完翻转。'
              '读侧永远读"写完的那块"，不会读到半途数据。')

    h2(doc, '4.2 接口')
    code(doc,
         'spec_ram u_spec_ram (\n'
         '    .I_wr_clk  (spec_wr_clk),   // 54 MHz 域\n'
         '    .I_wr_bank (spec_wr_bank),\n'
         '    .I_rd_clk  (pix_clk),       // 74.25 MHz 域\n'
         '    .I_rd_bank (spec_rd_bank),\n'
         '    ...);')
    para(doc, '注意：写端口和读端口用**不同的时钟**，这是双口 RAM（DPB）的标准用法。'
              'bank 选择信号跨时钟域时只传递一位，且只在帧边界变化，'
              '实际工程里可以不加同步器（最坏情况是晚一帧切换）。')

    # ================= 5 =================
    doc.add_page_break()
    h1(doc, '第 5 章  spec_display.v —— 显示子系统')

    h2(doc, '5.1 版面是"坐标硬编码"的')
    code(doc,
         'localparam PX0 = 12\'d64;    // 绘图区左边界\n'
         'localparam PX1 = 12\'d1087;  // 右边界，宽度 1024 列\n'
         'localparam PY0 = 12\'d104;   // 上边界\n'
         'localparam PY1 = 12\'d615;   // 下边界，高度 512 行')
    para(doc, '显示器是 1280×720，绘图区占 1024×512，右侧 160 px 是菜单，'
              '上方 96 px 是参数栏，下方 96 px 是状态栏。')

    h2(doc, '5.2 幅度怎么变成像素行')
    para(doc, '核心是一个"查表 + 插值"的过程：')
    code(doc,
         '// 把 16 位线性幅度转成 dB（左移 6 位换 Q6 精度）\n'
         'wire [21:0] q6 = {mag, 6\'d0};\n'
         '// log2 表查完得到 0.1 dB 单位的整数，再映射到行\n'
         'row = row_base - (db01 * row_scale);')
    para(doc, '纵轴是 0 ~ -80 dBFS，映射到 512 行，'
              '所以每行约 0.156 dB。dB 值越大，行号越小（越靠上）。')

    h2(doc, '5.3 为什么 de/hs/vs 要延迟 6 拍')
    para(doc, '显示逻辑本身有 6 级流水（取数、比较、上色、叠加文字……）。'
              '像素数据晚 6 拍出来，如果同步信号不跟着延迟 6 拍，'
              '图像整体会左移/上移 6 个像素。')
    code(doc,
         '// video_top.v 里\n'
         'always @(posedge pix_clk) begin\n'
         '    de_d <= {de_d[4:0], de};\n'
         '    hs_d <= {hs_d[4:0], hs};\n'
         '    vs_d <= {vs_d[4:0], vs};\n'
         'end\n'
         'assign O_de = de_d[5];   // 与像素数据对齐')

    h2(doc, '5.4 文字怎么显示')
    para(doc, '不是用字库渲染，而是"整屏文字预先画成点阵，存进 ROM"。'
              '屏幕被划成 80×45 个 16×16 的单元，每个单元存一个字符编码（11 位），'
              '像素扫描时按 (x>>4, y>>4) 取字符、按 (x&15, y&15) 取字模点。')
    para(doc, '好处是运行时零计算、零 RAM 占用；坏处是文字内容固定，'
              '改文字要重新生成 ROM（跑 `tools/gen_font.py`）。'
              '也正因为如此，跨度/参数这类"会变的数字"是通过 4 个 layer 预先做好的'
              '（每档一层），而不是动态渲染。')

    h2(doc, '5.4 瀑布图 —— 频谱的时间维度')
    para(doc, '瀑布图把"最近 128 帧的频谱"按时间从新到旧铺在绘图区背景上: 横向 256 列 '
              '(每列 4 像素, 由 4 根谱线取峰值降采样), 纵向 128 行环形缓冲 (新行在顶), '
              '每格存 3bit 色阶, 8 级热色按幅度 dB 段直接取 log_row 的高位段——不需要 '
              '除法器。写侧在采样时钟域 (54MHz 容得下 log 链), 读侧在像素时钟域, '
              '双时钟 BSRAM 98kbit 共 6 块。')
    code(doc,
         '// 写侧核心: 4:1 峰值降采样 + 色阶量化\n'
         'wf_max <= (wf_cnt == 3) ? 0 : max(I_wr_mag, wf_max);\n'
         'wf_cidx = 7 - log_row(log_split(wf_max_r))[8:6];  // 0dB 白, <-70dB 黑\n'
         'wf_mem[{wf_wrow, wf_col_r}] <= wf_cidx;            // 帧末 wrow+1 环形滚动')
    para(doc, '读侧行指针 wf_wrow 经两级同步过像素域, 首轮 128 帧绕满之前只显示已写行 '
              '(wf_full 门控)——否则 ModelSim 里未写行的 X 会经调色板 default 铺成满屏白。')
    h2(doc, '5.5 文字运行时解码 —— 用逻辑换 28 块 BSRAM')
    para(doc, '旧版界面文字放在 5 层 x 4096 项的字符网格 ROM 里, 占 28 块 pROM '
              '(225kbit), 是全设计 BSRAM 紧张的根源。实际上 80x45 个单元里只有约 15% '
              '有字, 且字符串都是编译期已知常量——改成 wave_display 同款的 put 任务: '
              '组合逻辑按 (行,列) 判定该格属于哪个字符串并给出字符, 打一拍进原文字 '
              '管线。**渲染结果与 ROM 版逐像素相同** (tb_frame 双模式 diff 为 0)。')
    para(doc, '★ 教训: gen_font.py 的 put 参数是 (列, 行), 而自写任务签名是 (行, 列)——'
              '照抄调用不换序, 整个版面转置 (y 轴刻度横着排到顶栏)。第一版 diff 有 2 万 '
              '像素差异, 按行带分布 5 分钟定位。')
    h2(doc, '5.6 三种显示模式')
    table(doc, [
        ['模式 (KEY2)', '内容', '用途'],
        ['0 频谱+瀑布', '迹线+标记+瀑布背景+菜单', '主工作界面'],
        ['1 纯净频谱', '菜单折叠成黑, 无瀑布', '截图/演示/看弱谱线'],
        ['2 时域波形', 'wave_display 全屏', '看波形形状'],
    ], [3.5, 7.0, 5.0])
    para(doc, '菜单折叠的门控要点: 面板底色、按钮、菜单文字 (文字管线优先级最高, '
              '必须单独门控)、分隔线四处都要盖到; 顶栏光标读数在第 4 行, 一半在菜单区, '
              '要豁免。')

    # ================= 6 =================
    h1(doc, '第 6 章  wave_cap.v —— 时域波形采集')

    h2(doc, '6.1 触发是干什么的')
    para(doc, '如果只是"每帧抓 1024 点"，由于抓取起点和信号相位没有关系，'
              '每次抓到的波形起点都不一样，屏幕上就会看到波形左右乱跳。'
              '触发起的作用是：等到信号穿过某个电平的瞬间才开始记录，'
              '这样每次记录的起点都对应同一个相位，波形就能"站住"。')

    h2(doc, '6.2 实现')
    code(doc,
         '// 边沿判断：用"上一个点"和"当前点"夹住触发电平\n'
         'wire cross_up = (prv <  lvl) && (cur >= lvl);\n'
         'wire cross_dn = (prv >  lvl) && (cur <= lvl);\n'
         'wire cross    = I_edge ? cross_dn : cross_up;')
    para(doc, '注意必须用 `<=` 和 `>=` 而不是 `==`：实际样点几乎不可能正好等于触发电平，'
              '用等号会永远触发不了。')

    h2(doc, '6.3 wave_display.v —— 波形是怎么画到屏幕上的')
    para(doc, '1024 点记录只显示前 256 点，每点占 4 列，列与列之间做线性内插，'
              '相当于示波器的"时基放大"。100kHz 信号在 Span 1MHz 档约 12.8 个周期、'
              '每周期 80 像素，肉眼能直接分辨正弦/三角/方波。')
    code(doc,
         '// 相邻样点线性内插: sub = 列号低 2 位 (0..3)\n'
         'wire signed [17:0] d_qua  = d_nxt_c >>> 2;   // (nxt-cur)/4\n'
         'case (x3[1:0])\n'
         "  2'd0: dsub = 18'sd0;\n"
         "  2'd1: dsub = d_qua;                       // + 1/4\n"
         "  2'd2: dsub = d_qua <<< 1;                 // + 2/4\n"
         "  default: dsub = d_qua + (d_qua <<< 1);    // + 3/4\n"
         'endcase')
    para(doc, '★ 教训：`{nxt2[15], nxt2}` 这种拼接在 Verilog 里是无符号的，做减法前'
              '必须先 `$signed()` 转回有符号，否则样点对只要跨越正负（波形过零），'
              '差值就被零扩展成垃圾，屏幕上出现满幅瞬变。这个 bug 仿真对拍查了三轮才定位。')
    para(doc, 'KEY2 在频谱/波形两种视图间切换，两路显示流水线都是 6 级、延迟相同，'
              '顶层直接按模式选一路 RGB，切换瞬间不会撕裂。')

    # ================= 7 =================
    doc.add_page_break()
    h1(doc, '第 7 章  几个绕不过去的概念')

    h2(doc, '7.1 定点数的 Q 格式')
    para(doc, 'Q4 表示"低 4 位是小数"，即真实值 = 整数 / 16。'
              'Q15 表示低 15 位是小数。这样做的好处是只用整数运算就能表示小数，'
              '代价是要自己记住小数点在哪。')
    table(doc, [
        ['信号', '格式', '含义', '范围'],
        ['ADC 样点', 'Q4（16 位）', '整数=真实值×16', '±2048'],
        ['FFT 内部', 'Q15（32 位）', '整数=真实值×32768', '±1'],
        ['幅度谱', 'Q0（16 位）', '纯整数', '0~65535'],
        ['补偿系数', 'Q7', '整数=增益×128', '1024~1608'],
    ], [3.0, 3.4, 5.6, 3.2])

    h2(doc, '7.2 为什么满量程是 65480 而不是 65535')
    para(doc, '满量程正弦输入时，FFT 峰值 = (A/2)·(N/2)/N = A/4（A 是 16 位满幅 32768），'
              '再乘补偿系数后约等于 65480。这个数字和 FFT 点数无关，'
              '所以换点数不用重新定标——这是 4096 点版本能顺利替换 2048 点的原因之一。')

    h2(doc, '7.3 窗函数为什么让谱线变宽')
    para(doc, '不加窗等于对信号做了矩形截断，频谱会"泄漏"：一根单音会拖出一串旁瓣。'
              'Hann 窗把两端压到零，泄漏小得多，代价是主瓣变宽（约 1.5 个 bin）。'
              '所以 RBW 定义为 1.5·fs/N，而不是 fs/N。')
    table(doc, [
        ['窗', '主瓣宽度', '旁瓣', '适用'],
        ['矩形', '1 bin', '-13 dB', '瞬态、短记录'],
        ['Hann（采用）', '1.5 bin', '-31 dB', '通用频谱测量'],
        ['Blackman', '2 bin', '-58 dB', '大动态范围'],
    ], [2.6, 2.8, 3.0, 5.6])

    h2(doc, '7.4 逆 sinc 补偿在补什么')
    para(doc, '27 点滑动平均在通带内不是平的，带边（1 MHz）处衰减 3.9 dB。'
              '如果不补，900 kHz 的信号会比 100 kHz 的信号低 3 dB 多，看起来像"高频增益不足"。')
    para(doc, '补偿表存的是每个频点需要的增益倍数（1024/|H(k)|，Q7 格式），'
              '幅度算完乘一下就行。补偿后端到端平坦度做到 ±0.02 dB。')

    # ================= 8 =================
    h1(doc, '第 8 章  参数速查')
    table(doc, [
        ['档', '抽取', 'fs', '跨度', 'bin', 'RBW', 'SWT'],
        ['0', '27', '2.000 MHz', '1.000 MHz', '488.3 Hz', '732 Hz', '2.048 ms'],
        ['1', '108', '500 kHz', '250 kHz', '122.1 Hz', '183 Hz', '8.192 ms'],
        ['2', '540', '100 kHz', '50 kHz', '24.4 Hz', '36.6 Hz', '40.96 ms'],
        ['3', '2700', '20 kHz', '10 kHz', '4.88 Hz', '7.3 Hz', '204.8 ms'],
        ['4', '1', '54 MHz', '27 MHz', '13.2 kHz', '19.8 kHz', '75.9 us'],
    ], [1.2, 1.5, 2.8, 2.6, 2.4, 2.2, 2.6])
    para(doc, 'RBW = 1.5 × fs / 4096；SWT = 4096 / fs。两个公式记住，'
              '任何一档都能自己推出来。')

    h1(doc, '第 9 章  自己动手验证')
    para(doc, '（1）只关心 FFT 对不对：跑 `sim/tb_fft.v`，再用 `tools/cmp_fft.py` '
              '把 RTL 结果和 Python 定点模型逐点比，应该是 0 偏差。')
    para(doc, '（2）关心幅度准不准：跑 `tools/check_flat.py -d 27`，看通带平坦度表。')
    para(doc, '（3）关心界面：跑 `sim/tb_frame.v`，会渲染出一整帧 PPM/PNG，不用接显示器。')
    para(doc, '（4）关心人机界面：跑 `sim/tb_key_enc.v`，9 项检查覆盖消抖、方向、边界。')
    para(doc, '（5）关心波形视图：跑 `sim/tb_wave_frame.v`，ADC 谐波模型整链路渲染一帧，'
              '并逐列和期望内插值对拍（应 0 偏差）。')
    para(doc, '（6）顶层联调：跑 `sim/tb_top.v`（配 `gw_stubs.v` 里的 rPLL/CLKDIV/DVI '
              '行为桩），真实三个时钟域一起转，能分别落盘频谱帧和 KEY2 切换后的波形帧，'
              '不用上板就能确认整机行为。')
    para(doc, '（7）关心光标读数：`tb_frame.v` 加 `+CSR=256` 渲染一帧，顶栏出现 MKR 频率/dB 读数，光标虚线落在第 256 列；换 `+CSR=51` 可验证频率前导零消隐。')
    para(doc, '（8）关心 AUTO：`tb_top.v` 加 `+AUTO +F0=20000` 再跑一遍，会自动按'
              ' KEY3 并断言跨度切到 250 kHz 档（5·f0 ≤ 0.92·Span 的选档规则）。')

    out = os.path.join(OUT_DIR, '程序对照注释手册.docx')
    doc.save(out)
    print('OK:', out)


if __name__ == '__main__':
    build()

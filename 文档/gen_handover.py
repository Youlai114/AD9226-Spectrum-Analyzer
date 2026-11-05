# -*- coding: utf-8 -*-
"""生成《交接文档》—— 项目状态/环境/验证矩阵/待办/恢复手册."""
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
    cn(p.add_run('项目交接文档\nAD9226 数字频谱分析仪 (FPGA 固件)'), '黑体', 18, True)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cn(p.add_run('交接日期: 2026-10-27    工程目录: D:/code/AD9226_Nano20K_Slink'), '宋体', 10)

    # ================= 1 项目状态 =================
    h1(doc, '1  项目状态总览')
    para(doc, '**一句话**: FPGA 固件功能完整、仿真验证闭环 (回归 8 步 7 项 ALL PASS)。'
              'v1.1.0 已完成**首轮上板实测** (2026-10-27, 未接前端抗混叠小板, 信号源 = '
              '电脑声卡 20 kHz) 并修复全部固件侧问题 (见 CHANGELOG 1.1.0 与《上板测试'
              '记录表》)；同日又做了一轮**逐文件代码通读**, 再修掉 8 处静默缺陷 (宽频档'
              '选不到/Δ 模式不通/底栏标签丢字/谐波窗口回绕/回归假通过/生成脚本崩溃/'
              '仓库卫生), 并**重跑综合布线 (TNS 全 0)**；定量指标测试受信号源限制未做, '
              '待办清单见 5.2。')
    table(doc, [
        ['模块/功能', '状态', '验证方式'],
        ['AD9226 采集 + 27 点抽取 (2 MHz)', '完成', 'cmp_fft 0 LSB'],
        ['4096 点 FFT + 4 窗切换 + 逆 sinc 补偿', '完成', 'cmp_fft 0 LSB + 四窗校准 ±0.065dB'],
        ['16 帧视频平均 (阶梯杂波修复)', '完成', '多帧仿真 + 顶层渲染'],
        ['频谱显示 (迹线/网格/谐波标记/瀑布)', '完成', '顶层渲染逐要素检查'],
        ['时域波形 (1024 点边沿触发 + 4 倍内插)', '完成', '逐列对拍 0 偏差'],
        ['时域谐波分解 (1~5 次分量正弦, 幅度/时基可调)', '完成 (v1.2.0 新增)', 'tb_harm 5 lane 行值 ≤3 行误差'],
        ['F0 基波频率 / HD2~HD5 谐波电平表', '完成', '与理论值逐位一致'],
        ['光标三态 (普通/增量 Δ/关) + 跳峰', '完成', 'ΔF=99609Hz 精确 + 跳峰端到端'],
        ['按键 5 个 + EC11 编码器 (短按/长按) + AUTO 定档', '完成', 'tb_key_enc 13/13'],
        ['综合 + 布线 + 时序 (TNS 全 0 / tmds 74.33MHz / BSRAM 81%)', '完成 (1.2.0 已重跑)', 'Gowin 时序报告'],
        ['板端实测 (交互/显示/读数)', 'v1.1.0 首轮已做', '见《上板测试记录表》'],
        ['板端定量指标 (频率精度/平坦度/谐波)', '未做 (缺信号源)', '见 5.2'],
        ['THD 数值计算', '未做 (见 5.2)', '—'],
    ], [7.5, 2.5, 5.5])

    # ================= 2 交付物清单 =================
    h1(doc, '2  交付物与文件地图')
    table(doc, [
        ['路径 (工程根 D:/code/AD9226_Nano20K_Slink)', '内容'],
        ['ad9226_hdmi_spectrum/impl/pnr/*.fs', '最终比特流 (烧录用), 随每次重建更新'],
        ['ad9226_hdmi_spectrum/src/*.v', '全部 RTL (13 个模块, 见代码阅读引导第 4 节)'],
        ['ad9226_hdmi_spectrum/tools/*.py', '定点模型/比对/渲染/文档生成脚本'],
        ['ad9226_hdmi_spectrum/tools/run_regression.sh', '一键回归 (8 步 7 项)'],
        ['ad9226_hdmi_spectrum/sim/*.v', '全部 testbench + 高云原语行为桩'],
        ['ad9226_hdmi_spectrum/sim/frames/*.png', '顶层仿真渲染的真实界面帧'],
        ['ad9226_hdmi_spectrum/doc/*.md', '引脚对照/打板说明/PCB 布线规则'],
        ['ad9226_hdmi_spectrum/CODE_GUIDE.md', '代码阅读引导 (在线版)'],
        ['文档/操作手册.docx', '用户视角: 接线/键位/读数/排障'],
        ['文档/代码阅读引导.docx', '代码从哪读起 + 已知边界与 BUG 清单'],
        ['文档/程序对照注释手册.docx', '逐模块实现细节与取舍'],
        ['文档/上板测试记录表.docx', '上板实测记录与待复测项'],
        ['AD9226_FPGA_V1.1_65M/, hdmi_spectrum/, ad9226_tangnano20k/', '历史参考工程 (前者 Altera 原厂例程, 后两者为前身), 可只读'],
        ['VERSION / CHANGELOG.md', '版本号 (当前 1.1.0) 与变更记录; 发布打包见 4.6'],
        ['git 仓库 (v1.0.0 标签)', '全工程版本管理; release/ 为发布 zip'],
        ['ad9226_hdmi_spectrum/doc/hardware/', '硬件设计文件归档位 (原理图/PCB 待原作者放入)'],
    ], [10.5, 5.0], size=9)

    # ================= 3 环境与工具链 =================
    h1(doc, '3  环境与工具链 (本机已配好, 换机器按此重装)')
    table(doc, [
        ['工具', '本机路径 / 版本', '用途'],
        ['高云 IDE (Education)', 'D:/Gowin/Gowin_V1.9.11.03_Education_x64', '综合/布线/比特流 (gw_sh.exe)'],
        ['ModelSim SE', 'D:/modeltech_10.1a (win32/vlog, vsim)', '全部仿真'],
        ['ModelSim license', 'D:/modeltech_10.1a/License.txt', '见下方 U+202A 坑'],
        ['Python (Anaconda)', 'D:/Anaconda/python.exe (含 Pillow)', '定点模型/比对/PPM 转 PNG'],
        ['工程目录', 'D:/code/AD9226_Nano20K_Slink', '见第 2 节文件地图'],
    ], [4.0, 6.5, 5.0])

    h2(doc, '3.1 三个环境坑 (新机器必看)')
    para(doc, '(1) **ModelSim license 的 U+202A 陷阱**: 用户环境变量里的 LM_LICENSE_FILE '
              '可能含不可见字符导致 "Invalid license"。无条件覆盖即可：'
              'export LM_LICENSE_FILE="D:/modeltech_10.1a/License.txt"（回归脚本已内置）。'
              '另外同一台机器只允许一个 ModelSim 实例, 挂死后 taskkill 按 PID 杀。')
    para(doc, '(2) **gw_sh 必须用 open_project**: build.tcl 用 open_project 打开 .gprj, '
              '若改成 add_file 逐个加文件, SDC 约束会静默失效——表面时序通过实际没约束。')
    para(doc, '(3) **路径必须对**: 仿真在 sim/ 目录跑 (work 库/相对路径), 综合在工程根 '
              '目录跑 (build.tcl); 曾因在错误目录启动而误用过期报告。')

    # ================= 4 常用操作手册 (恢复场景) =================
    h1(doc, '4  常用操作 (恢复场景手册)')
    h2(doc, '4.1 改了 RTL 之后的标准流程')
    code(doc,
         'bash tools/run_regression.sh          # 8 步回归, 期望 ALL PASS\n'
         'gw_sh build.tcl                       # 综合布线出比特流 (工程根目录)\n'
         '# 检查: 违例端点 0; timing_paths 首行 slack 为正; BSRAM <= 70%')
    h2(doc, '4.2 烧录')
    code(doc,
         '高云 Programmer -> 选 impl/pnr/ad9226_hdmi_spectrum.fs -> 烧录\n'
         '(固化到 SPI Flash 请按 Programmer 的固化流程, 产物另出)')
    h2(doc, '4.3 只想看界面效果 (不接板)')
    code(doc,
         'cd sim && vsim -c -do "run -all; quit -f" work.tb_top +DUMP1=3 +DUMP2=4\n'
         'python ../tools/ppm2png.py frames/top_004.ppm   # 转成 PNG 查看')
    h2(doc, '4.4 重新生成全部文档')
    code(doc,
         'python 文档/gen_user_manual.py     # 操作手册\n'
         'python 文档/gen_manual.py          # 程序对照注释手册\n'
         'python 文档/gen_reading_guide.py   # 代码阅读引导\n'
         'python 文档/gen_reading_guide.py 的内容源为 CODE_GUIDE.md 之前的手写版,'
         ' 改内容请直接编辑本脚本')
    h2(doc, '4.5 改了界面文字/版面 (spec_display 的 put 调用)')
    para(doc, '文字全部在 spec_display.v 的运行时解码器里 (按 cell_row 分组的 put 调用), '
              '参数顺序为 (列, 行, 长度, 字符串, 颜色)——与 gen_font.py 一致。'
              '**★ wave_display.v 的 put 参数顺序相反, 是 (行, 列)**——v1.1.0 曾因此把'
              '面板标题误写到顶栏右上, 改时域页面文字务必先看清 task 声明。改完必须：'
              '跑 tb_frame 渲染 + 与改动前帧做像素 diff (方法见 5.3), 再跑回归。')
    h2(doc, '4.6 发布打包')
    code(doc,
         'python ad9226_hdmi_spectrum/tools/make_release.py\n'
         '# 产出 release/spectrum_v<版本>_<日期>.zip (比特流+全部文档+源码+脚本)\n'
         '# 版本号在根目录 VERSION; 每次发布须在 CHANGELOG.md 追加条目并 git 提交')
    h2(doc, '4.7 版本管理规范')
    para(doc, '工程为 git 仓库, 基线标签 v1.0.0。改动流程: 改 RTL -> bash '
              'tools/run_regression.sh (ALL PASS) -> gw_sh build.tcl -> 更新 VERSION 与 '
              'CHANGELOG.md -> git commit -> 需要发布时打标签并跑 make_release.py。'
              '注意: 版本号语义为 主.次.修 (主=架构大改, 次=新功能, 修=缺陷修复); '
              'git 身份为本机占位配置 (AD9226-project@local), 接手者请改为本人信息: '
              'git config user.name/user.email。')

    # ================= 5 验证矩阵 =================
    h1(doc, '5  验证矩阵与已知边界')
    h2(doc, '5.1 当前验证矩阵 (截至交接日, 全部通过)')
    table(doc, [
        ['测试', '内容', '结果'],
        ['cmp_fft', 'RTL vs Python 定点模型, 4096 点全列', '0 LSB'],
        ['四窗校准', '满幅 bin 中心单音, 四种窗读数', '偏差 ≤0.065 dB'],
        ['基波检测', '100 kHz 单音列位置', 'col 102 精确'],
        ['tb_key_enc', '消抖/方向/边界/短按精细/长按Preset/窗键', '13/13'],
        ['tb_wave_frame', '波形逐列对拍', '0 偏差'],
        ['tb_top 渲染', 'F0/H表/谐波标记/迹线/瀑布', '逐要素通过'],
        ['tb_top 跳峰', 'KEY4 + 短按编码器, 光标跳回基波峰列', '列精确'],
        ['Gowin 时序', '全部时钟域 setup/hold (1.2.0 布线后)', '0 违例 (三个时钟 TNS 全 0, 最差 +0.015ns)'],
    ], [3.5, 7.5, 4.5])
    h2(doc, '5.2 未完成与未验证事项 (接手者的待办)')
    para(doc, '**v1.1.0 首轮上板实测结论 (2026-10-27, 未接前端抗混叠小板, 信号源 = '
              '电脑声卡 20 kHz)**: 交互链路全部正常——心跳灯、KEY2 三视图切换无撕裂、'
              '瀑布滚动与频率漂移、边沿触发稳定不跑动、编码器方向正确; 实测发现的固件'
              '问题已全部修复: RBW 查表编码错位 (Rect@1M 误显 7.3 Hz)、F0/H 表绿字偏蓝、'
              '瀑布全屏遮挡频谱、编码器一次跳 4 列不精细、跳峰与 Preset 键位冲突、'
              'AUTO 在折叠档卡死、时域右侧菜单空白、宽频档 hrm_span 截断——'
              '详见 CHANGELOG 1.1.0 与《上板测试记录表》。')
    para(doc, '**本轮代码通读复查 (同日, 仿真 + 综合已验证、未上板) 修掉的 8 处静默缺陷**: '
              '(a) 27MHz 宽频档按键永远选不到——顶层 `SPAN_NUM(4)` 只循环 4 档, 且 '
              'span_auto/I_span_load_val 只有 2bit, AUTO 判 f0>500kHz 时给 4 被截成 0; '
              '(b) 光标增量 Δ 模式形同不存在——`spec_display.I_csr_mode` 是 2bit, 实际'
              '只接了 1bit 的 mode_csr; (c) 底栏 "Win:"/"RBW:" 标签被 put 顶出 288bit; '
              '(d) 谐波窗口列号 10bit 回绕, 基波列大时 H2~H5 读到不相干谱线 (扩到 13bit); '
              '(e) 一键回归是假通过——从不建 work 库、漏编译 spec_demo_gen.v、不删旧 '
              'out/*.txt; (f) 回归判据 GBK 与 UTF-8 冲突永不匹配 (cmp_fft 加 ASCII '
              'MAXDEV 行); (g) gen_font.py/make_release.py 两处崩溃与 zip 残形; '
              '(h) .gitignore 层级写错导致 443 个可再生产物被跟踪 (已 git rm --cached, '
              '并加 .gitattributes 钉 eol=lf)。详见 CHANGELOG 1.1.0 "代码通读复查" 段。')
    para(doc, '**待复测 (重新综合烧录 v1.1.0 后, 编号对应测试表)**: A2 瀑布只占底部 1/4 '
              '不再遮挡; A3 F0 纯绿 + 短按编码器切 FINE (光标步进 1 列) + KEY4 开光标后'
              '短按跳峰; F1 切 Rect 后 RBW 应显 488 Hz (Hann 732 Hz); E2 时域右侧 '
              'Span/Trig/NPTS 菜单; G2 20 kHz 信号在 10k 档按 AUTO 应上浮一档; '
              '底栏应同时看到 "Win: Hann" 与 "RBW: 732 Hz"; KEY1 循环到第 5 档应真进 '
              '27MHz 宽频 (此前按不到); KEY4 按第二下应出现 ΔF/ΔdB 读数 (此前不出现); '
              '5 次谐波表在基波列较大时也应与谱线对齐; 增量 Δ 模式下移动光标后 ΔF 读数; '
              '**综合布线已重跑**: 三个时钟 TNS 全 0, tmds 域 Fmax 78.67 / 约束 74.25 '
              '(余量 5.6%, 最差 setup +0.757ns); `build.tcl` 已固定开启时序驱动布局布线, '
              '后续往像素域加逻辑前仍应先跑综合看 Fmax。')
    para(doc, '**需设计决策后再做 (测试表 A4/A5 提出的改型, 已记 CHANGELOG Deferred)**: '
              '(a) 谐波标记移入时域视图, 从上到下显示 1~5 次谐波并扩展时域按键功能——'
              '工作量大且交互形态未定; (b) 谐波电平表加幅度挡位切换与光标; '
              '(c) "长按编码器切分贝挡"与现长按 = Preset 冲突, 需先定按键预算。')
    para(doc, '**缺仪器未测 (需 ≥100 kHz~5 MHz 正弦信号源, 测试表 B/C/D/H 组)**: '
              'B 组 250k/500k/900k/5M 频率精度; C 组满量程定标 (1Vpp≈-6dBFS)、平坦度、'
              '过载 LED; D 组 HD2/HD3 定量与 Δ 光标对照; H 组 0Hz 偏置码值、'
              '>27 MHz 镜像折叠位置 (无抗混叠小板, 属预期现象, 记录即可)。')
    para(doc, '**代码侧 (小工作量)**: (a) THD 数值计算——需求清单里有此条, 现仅显示各次'
              '谐波电平, THD=sqrt(ΣHk²)/H1 未算, 可在显示端或 PC 端后处理; '
              '(b) 触发电平可调——当前固定 0V 上升沿, 编码器短按/长按已占, 需再排键位。')
    para(doc, '**硬件侧剩余**: (1) 0Hz 大峰检查 -> 必要时改 ad9226_capture 的 '
              '13\'sd2048 偏置; (2) HDMI 兼容性 (多台显示器验证); (3) 编码器手感 -> '
              '必要时 ENC_STEP 4->2; (4) 信号源到位后按上表补测定量指标; '
              '(5) 前端抗混叠小板 (硬件设计项, 若继续使用宽频档则建议做)。')
    h2(doc, '5.3 渲染像素 diff 方法 (显示改动的标准自检)')
    code(doc,
         '改前: 跑 tb_frame/tb_top 落盘 PNG 存为参考\\n'
         '改后: 同 plusargs 再跑一遍, numpy 逐像素比较\\n'
         '判据: significant-diff px = 0 (文字/版面重构类改动);'
         ' 或仅预期要素变化 (功能改动)')
    para(doc, '本工程所有显示层改动 (瀑布/文字解码/窗/H 表/F0) 均用此方法验证, '
              '曾三次靠它抓出转置/截断/覆盖类 bug。')

    # ================= 6 已知边界 =================
    h1(doc, '6  已知边界与潜在 BUG (详见代码阅读引导第 7 节)')
    para(doc, '完整清单已写入《代码阅读引导》第 7 节与 README 已知限制 1~16 条, '
              '此处仅列接手者最容易踩的六条：')
    para(doc, '(1) 换档/换窗后 1~2 帧过渡：测量数据是旧参数的, 标记/H表/F0 自动隐藏, '
              '文字立即切换——不是 bug;')
    para(doc, '(2) 瀑布历史跨档混合：换档后最长 128 帧历史含旧档频率 (Span 10k 档约 '
              '27 秒), 逐行滚出;')
    para(doc, '(3) H5 搜索窗边界：基波恰在两 bin 正中时 H5 可能读低 (H2~H4 不受影响);')
    para(doc, '(4) Δ 参考快照时机：跳峰后一帧内进增量, 参考可能取旧值 (等一帧或重进);')
    para(doc, '(5) 平均响应时间常数 16 帧：信号突变显示要等约 0.1s (慢档 4 帧约 0.8s);')
    para(doc, '(6) AUTO 折叠逃逸是启发式 (v1.1.0)：峰贴 DC 列 (col<4) 时窄档内无法区分'
              '"直流偏置"与"信号折叠", 一律上浮一档; 连按 AUTO 可逐级找到信号所在档。')

    # ================= 7 时间线 =================
    h1(doc, '7  关键决策时间线 (为什么是现在这个样子)')
    table(doc, [
        ['日期', '决策/事件'],
        ['10-19', '移植 Altera 例程 + 合并 HDMI 显示; 发现晶振实为 27MHz (非 50); '
                  '确定 54MSPS 恒速 + ÷27 抽取 = 2MHz 整数采样率的总体方案'],
        ['10-19', '确定引脚: 避开 SSPI(54/55/56)/Flash/WS2812, ADC 14 线落位两侧排针'],
        ['10-23', 'wave_cap 边沿触发采集完成'],
        ['10-24', '四窗切换 + Δ 光标 + 自动谐波表 + F0 读数 + 瀑布图 + 三显示模式; '
                  '文字 ROM 改运行时解码 (BSRAM 98%->66%); twiddle 半表压缩; '
                  '修复符号扩展/乘积回绕/扇区编码等 8+ bug'],
        ['10-25', '视频平均 (修噪底阶梯); 平均参数指纹复位; 风险清单入档; '
                  '一键回归脚本; 本交接文档; v1.0.0 基线'],
        ['10-27', 'v1.1.0 首轮上板实测 (声卡 20 kHz): 修 RBW 查表编码错位/宽频档 '
                  'hrm_span 截断/绿字偏蓝/AUTO 折叠逃逸; 瀑布缩至底部 1/4; 编码器'
                  '短按切精细 (FINE)/长按 Preset; 时域右侧菜单补全; 回归新增跳峰项'],
        ['11-05', 'v1.2.0 时域谐波分解: 新增 harm_est/harm_ram/sincos_rom, 时域视图同时画 1~5 次分量正弦, 编码器切时基/幅度档, 回归扩到 9 步 8 项, 比特流重出 TNS 全 0'],
        ['10-27', 'v1.1.0 代码通读复查: SPAN_NUM 4->5 (27MHz 宽频档首次真正可选)/'
                  'Δ 模式 2bit 透传/底栏 put 拆 5 条/谐波窗口 13bit/回归脚本自建 work 库/'
                  '443 个可再生产物去跟踪; 综合布线重跑, TNS 全 0'],
    ], [1.8, 13.5], size=9)

    # ================= 8 上板速查 =================
    h1(doc, '8  上板速查卡')
    table(doc, [
        ['操作', '结果'],
        ['KEY1', '跨度循环 1M→250k→50k→10k→27M'],
        ['KEY2', '显示: 频谱+瀑布+菜单 → 纯净频谱 → 时域'],
        ['KEY3', 'AUTO 自动定档 (按基波位置)'],
        ['KEY4', '光标: 关 → 普通 (MKR 读数) → 增量 (DLT 读数)'],
        ['KEY5', '窗: Hann → Rect → Blackman → FlatTop'],
        ['编码器旋转', '调跨度 (光标关) / 移光标 (光标开, FINE 时 1 列/格)'],
        ['编码器短按', '光标关: 切精细 (FINE, 步进 4->1 列) / 光标开: 跳到基波峰'],
        ['编码器长按', 'Preset (回 Span 1 MHz)'],
        ['LED1 (脚20)', '1Hz 心跳 = 正常'],
        ['LED2 (脚71)', '常亮 = ADC 过压 (输入超 2Vpp)'],
    ], [3.5, 12.0])

    out = os.path.join(OUT_DIR, '交接文档.docx')
    doc.save(out)
    print('OK:', out)


if __name__ == '__main__':
    build()

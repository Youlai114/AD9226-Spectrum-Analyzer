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
    cn(p.add_run('交接日期: 2025-10-25    工程目录: D:/code/AD9226_Nano20K_Slink'), '宋体', 10)

    # ================= 1 项目状态 =================
    h1(doc, '1  项目状态总览')
    para(doc, '**一句话**: FPGA 固件已功能完整、仿真验证闭环 (回归 6/6)、比特流已产出并随'
              '每次变更重建；**硬件未上板验证**——连接板未到，全部板端测试待做。'
              '核心测量链路 (采集/FFT/显示) 已冻结，接手者只需按第 6 节清单上板核对。')
    table(doc, [
        ['模块/功能', '状态', '验证方式'],
        ['AD9226 采集 + 27 点抽取 (2 MHz)', '完成', 'cmp_fft 0 LSB'],
        ['4096 点 FFT + 4 窗切换 + 逆 sinc 补偿', '完成', 'cmp_fft 0 LSB + 四窗校准 ±0.065dB'],
        ['16 帧视频平均 (阶梯杂波修复)', '完成', '多帧仿真 + 顶层渲染'],
        ['频谱显示 (迹线/网格/谐波标记/瀑布)', '完成', '顶层渲染逐要素检查'],
        ['时域波形 (1024 点边沿触发 + 4 倍内插)', '完成', '逐列对拍 0 偏差'],
        ['F0 基波频率 / HD2~HD5 谐波电平表', '完成', '与理论值逐位一致'],
        ['光标三态 (普通/增量 Δ/关) + 跳峰', '完成', 'ΔF=99609Hz 精确命中'],
        ['按键 5 个 + EC11 编码器 + AUTO 定档', '完成', 'tb_key_enc 11/11'],
        ['综合 (0 违例 / +0.20ns / BSRAM 70%)', '完成', 'Gowin 时序报告'],
        ['板端实测 (偏置/抖动/显示器/实测指标)', '未做', '见第 6 节清单'],
        ['THD 数值计算', '未做 (见 5.2)', '—'],
    ], [7.5, 2.5, 5.5])

    # ================= 2 交付物清单 =================
    h1(doc, '2  交付物与文件地图')
    table(doc, [
        ['路径 (工程根 D:/code/AD9226_Nano20K_Slink)', '内容'],
        ['ad9226_hdmi_spectrum/impl/pnr/*.fs', '最终比特流 (烧录用), 随每次重建更新'],
        ['ad9226_hdmi_spectrum/src/*.v', '全部 RTL (13 个模块, 见代码阅读引导第 4 节)'],
        ['ad9226_hdmi_spectrum/tools/*.py', '定点模型/比对/渲染/文档生成脚本'],
        ['ad9226_hdmi_spectrum/tools/run_regression.sh', '一键回归 (6 项)'],
        ['ad9226_hdmi_spectrum/sim/*.v', '全部 testbench + 高云原语行为桩'],
        ['ad9226_hdmi_spectrum/sim/frames/*.png', '顶层仿真渲染的真实界面帧'],
        ['ad9226_hdmi_spectrum/doc/*.md', '引脚对照/打板说明/PCB 布线规则'],
        ['ad9226_hdmi_spectrum/CODE_GUIDE.md', '代码阅读引导 (在线版)'],
        ['文档/操作手册.docx', '用户视角: 接线/键位/读数/排障'],
        ['文档/代码阅读引导.docx', '代码从哪读起 + 已知边界与 BUG 清单'],
        ['文档/程序对照注释手册.docx', '逐模块实现细节与取舍'],
        ['AD9226_FPGA_V1.1_65M/, hdmi_spectrum/, ad9226_tangnano20k/', '历史参考工程 (前者 Altera 原厂例程, 后两者为前身), 可只读'],
        ['VERSION / CHANGELOG.md', '版本号 (当前 1.0.0) 与变更记录; 发布打包见 4.6'],
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
         'bash tools/run_regression.sh          # 6 项回归, 期望 ALL PASS\n'
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
    h2(doc, '4.6 发布打包')
    code(doc,
         'python ad9226_hdmi_spectrum/tools/make_release.py\n'
         '# 产出 release/spectrum_v<版本>_<日期>.zip (比特流+全部文档+源码+脚本)\n'
         '# 版本号在根目录 VERSION; 每次发布须在 CHANGELOG.md 追加条目并 git 提交')
    h2(doc, '4.7 版本管理规范')
    para(doc, '工程为 git 仓库, 基线标签 v1.0.0。改动流程: 改 RTL -> bash '
              'tools/run_regression.sh (6/6) -> gw_sh build.tcl -> 更新 VERSION 与 '
              'CHANGELOG.md -> git commit -> 需要发布时打标签并跑 make_release.py。'
              '注意: 版本号语义为 主.次.修 (主=架构大改, 次=新功能, 修=缺陷修复); '
              'git 身份为本机占位配置 (AD9226-project@local), 接手者请改为本人信息: '
              'git config user.name/user.email。')
    h2(doc, '4.5 改了界面文字/版面 (spec_display 的 put 调用)')
    para(doc, '文字全部在 spec_display.v 的运行时解码器里 (按 cell_row 分组的 put 调用), '
              '参数顺序为 (列, 行, 长度, 字符串, 颜色)——与 gen_font.py 一致。改完必须：'
              '跑 tb_frame 渲染 + 与改动前帧做像素 diff (方法见 5.3), 再跑回归。')

    # ================= 5 验证矩阵 =================
    h1(doc, '5  验证矩阵与已知边界')
    h2(doc, '5.1 当前验证矩阵 (截至交接日, 全部通过)')
    table(doc, [
        ['测试', '内容', '结果'],
        ['cmp_fft', 'RTL vs Python 定点模型, 4096 点全列', '0 LSB'],
        ['四窗校准', '满幅 bin 中心单音, 四种窗读数', '偏差 ≤0.065 dB'],
        ['基波检测', '100 kHz 单音列位置', 'col 102 精确'],
        ['tb_key_enc', '消抖/方向/边界/Preset/窗键', '11/11'],
        ['tb_wave_frame', '波形逐列对拍', '0 偏差'],
        ['tb_top 渲染', 'F0/H表/谐波标记/迹线/瀑布', '逐要素通过'],
        ['Gowin 时序', '全部时钟域 setup/hold', '0 违例 (+0.20ns)'],
    ], [3.5, 7.5, 4.5])
    h2(doc, '5.2 未完成与未验证事项 (接手者的待办)')
    para(doc, '**代码侧 (小工作量)**: (a) THD 数值计算——需求清单里有此条, 现仅显示各次'
              '谐波电平, THD=sqrt(ΣHk²)/H1 未算, 可在显示端或 PC 端后处理; '
              '(b) 触发电平可调——当前固定 0V 上升沿, 编码器在光标模式外的绑定已满; '
              '(c) 上板实测读数尚未回填到指标表。')
    para(doc, '**硬件侧 (板到后做, 按顺序)**: (1) 按操作手册 2.1~2.2 连接烧录, 确认'
              '心跳灯; (2) 0Hz 大峰检查 -> 必要时改 ad9226_capture 的 13\'sd2048 偏置; '
              '(3) 编码器手感 -> 必要时 ENC_STEP 4->2; (4) HDMI 兼容性; '
              '(5) 用信号源实测频率精度/幅度平坦度/动态范围/谐波电平, 与 H 表读数对照; '
              '(6) 抗混叠小卡 (硬件设计项, 若继续使用宽频档则可选)。')
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
              '此处仅列接手者最容易踩的五条：')
    para(doc, '(1) 换档/换窗后 1~2 帧过渡：测量数据是旧参数的, 标记/H表/F0 自动隐藏, '
              '文字立即切换——不是 bug;')
    para(doc, '(2) 瀑布历史跨档混合：换档后最长 128 帧历史含旧档频率 (Span 10k 档约 '
              '27 秒), 逐行滚出;')
    para(doc, '(3) H5 搜索窗边界：基波恰在两 bin 正中时 H5 可能读低 (H2~H4 不受影响);')
    para(doc, '(4) Δ 参考快照时机：跳峰后一帧内进增量, 参考可能取旧值 (等一帧或重进);')
    para(doc, '(5) 平均响应时间常数 16 帧：信号突变显示要等约 0.1s (慢档 4 帧约 0.8s)。')

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
                  '一键回归脚本; 本交接文档'],
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
        ['编码器旋转', '调跨度 (光标关) / 移光标 (光标开)'],
        ['编码器按压', 'Preset (光标关) / 跳到基波峰 (光标开)'],
        ['LED1 (脚20)', '1Hz 心跳 = 正常'],
        ['LED2 (脚71)', '常亮 = ADC 过压 (输入超 2Vpp)'],
    ], [3.5, 12.0])

    out = os.path.join(OUT_DIR, '交接文档.docx')
    doc.save(out)
    print('OK:', out)


if __name__ == '__main__':
    build()

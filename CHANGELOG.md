# Changelog

版本语义：**主.次.修**（主 = 接口/架构大改，次 = 新功能，修 = 缺陷修复）。
所有可复现验证见 `tools/run_regression.sh`；已知边界见 `代码阅读引导` 第 7 节与 `README` 已知限制 1~16 条。

## [1.1.1] - 2026-10-27

仓库清理版：RTL 与比特流和 v1.1.0 **完全相同**（同一份 `.fs`，时序结论不变），
只做历史与打包层面的清理。

### Changed
- **全部历史提交去除非公开材料引用**：v1.0.0 / v1.1.0 各版本的 `README.md`、`CHANGELOG.md`、
  `ad9226_hdmi_spectrum/README.md`、`tools/make_release.py`、`文档/gen_handover.py` 里
  涉及非公开材料的行全部删改；用 `git filter-repo` 重写全部提交后逐 blob 扫描禁用词，零命中
- **历史里的旧发布包整体剥离**：v1.0.0 / v1.1.0 早期 zip 内含非公开文档，这两个 blob 已从
  历史中彻底移除（发布包可由 `tools/make_release.py` 随时重打）
- **三个版本发布包全部重打**：`spectrum_v1.0.0_20261025.zip`、`spectrum_v1.1.0_20261027.zip`、
  `spectrum_v1.1.1_20261027.zip`，包内文本即清理后的版本

## [1.1.0] - 2026-10-27

首轮上板实测（未接前端抗混叠小板，信号源 = 电脑声卡 20 kHz）反馈修复，见《上板测试记录表》。

### Fixed
- **RBW 显示查表编码错位**（`spec_display.v`）：case 值误按每窗 5 档连排，实际编码为
  `{win,span}` = win×8+span —— Rect@1M 落到 "7.3 Hz" 行（上板实测抓到），Hann/Rect 两窗
  值互换；现按正确编码重排，各窗 ENBW 值（488/732/843/1841 Hz @1M）与文档一致
- **宽频档 F0/谐波表/标记全隐藏**（`spec_display.v`）：I_hrm_span 端口 2 位，span=4 截断
  成 0，与 I_span 比较恒假；扩为 3 位
- **绿字偏蓝**：F0/谐波表等 C_TXT1 由 0x3CD878 改纯绿 0x00E050（上板屏上偏青蓝）
- **AUTO 折叠档逃逸**（`auto_span.v`）：峰贴 DC 列（col<4，信号超出当前档 Nyquist 被折叠
  或直流偏置）时自动上浮一档，再按 AUTO 可逐级找到信号档

### Fixed（代码通读复查，同日；仿真 + 综合已验证，未上板）

上板实测之外又做了一轮逐文件通读，修掉 8 处"上板也不一定碰得到"的静默缺陷：

- **底栏 "Win:"/"RBW:" 标签被顶出屏外**（`spec_display.v`）：底栏一行原用 4 条 `put` 拼
  288bit，`put` 从高字节往低字节读，超出部分直接丢 —— 屏上只剩 "Hann "、丢了 "Win: "。
  改为 5 条 `put`（Win 标签 + 4 字符字、RBW 标签 + 3 字符字），并删掉 `rbw_s40_r`/
  `win_long40_r` 两个只用于拼接的 40bit 中间量
- **谐波窗口列号 10bit 回绕 → H2~H5 假读数**（`fft4096.v`）：`k*col` 在 10bit 下 ≥1024
  即回绕（基波 600 列时 H2 窗口落回 176 列），H2~H5 读到不相干谱线。窗口列扩到 13bit
  全宽（`hc2..hc5`、`mag_c`），≥1024 的谐波窗口自然不命中，电平表按"无信号"显示 -96.4
- **27 MHz 宽频档按键永远选不到**（`video_top.v`/`key_enc_ctrl.v`）：顶层实例
  `#(.SPAN_NUM(4))` 只循环 4 档（README/操作手册写的是 5 档），同时 `span_auto` 与
  `I_span_load_val` 都只有 2bit —— AUTO 判 f0>500 kHz 给出 4 时被截成 0，反而跳回 1 MHz。
  三处一并修：`SPAN_NUM=5`、两处扩到 3bit（tb_key_enc 本来就是按 5 档写的）
- **光标增量 Δ 模式形同不存在**（`video_top.v`）：`spec_display.I_csr_mode` 是 2bit
  （1=普通、2=增量 Δ），实际接的是 1bit 的 `mode_csr` —— 显示端永远看不到 2，
  KEY4 第二下没有 ΔF/ΔdB 读数。改接完整 `csr_mode`；tb_top JUMP 用例补一条
  "Δ 模式透传" 断言（`u_display.I_csr_mode == 2`），第 8 步判据改为两个 pass + 无 FAIL
- **编码器菜单热区错一行**（`spec_display.v`）：`btn_hi` 的 `row4` 区间 18..21 与
  `in_btn` 第 3 组 17..20 差一行，底行菜单点击判定整体错位
- **光标读数组合链时序违例**（`spec_display.v`）：把 Δ 模式接成 2bit 之后，`csr_col`
  → 列差/取绝对值 → ×跨度(35bit) → BCD 装载 `dd` 变成一条 18.1 ns 的纯组合链，
  tmds 域出现 **77 个端点、TNS −80.1 ns** 的 setup 违例（Fmax 掉到 62.9/74.25）。
  改成两级流水：S1 寄存列号/跨度/列差/幅度差，S2 寄存乘法结果，帧首 `csr_kick`
  再装载 —— 读数只在每帧第一个像素采样一次，多两拍无可见影响。修后 TNS 全 0；
  tb_top 追加数值断言 `ΔF=7812 Hz (Δcol=8)`（8 列 × 1 MHz / 1024）
- **一键回归本身是假通过**（`tools/run_regression.sh`）：脚本从不建 work 库（删掉仓库里
  提交的 `sim/work/` 立刻报 `(vlog-19) Failed to access library 'work'`），编译清单漏
  `spec_demo_gen.v`（靠旧库残留模块顶替，改错 RTL 也照样 PASS），且不删旧 `out/*.txt`
  —— 失败的 vsim 会读到上次产物被判通过。现每次 `rm -rf work` + `vlib work`（10.1a 的
  vlib 只吃位置参数，没有 `-work`）+ 删旧产物
- **回归判据遇 GBK 永不匹配**（`tools/cmp_fft.py`）：脚本是 UTF-8、cmp_fft 输出是 GBK，
  脚本里 grep 中文永远失败。cmp_fft 追加机器可读行 `MAXDEV=%d AVGDEV=%.2f`，脚本改
  grep ASCII
- **生成脚本两处崩溃/残形**（`tools/gen_font.py`、`tools/make_release.py`）：gen_font 的
  GEN_TEXT_ROM 分支 `newline="` 断行直接 SyntaxError；make_release 把绝对路径原样塞进
  zip（解包后多一层盘符目录）
- **仓库卫生**（`.gitignore`/`.gitattributes`）：5 条 ModelSim 路径少写
  `ad9226_hdmi_spectrum/` 前缀，443 个可再生产物（422 个 `sim/work/` + 日志 + `out/*.txt`
  + dvi_tx 中间件）一直被跟踪 —— 已 `git rm -r --cached`；另补 `.gitattributes` 钉
  `eol=lf`（Windows checkout 后 `.sh` 变 CRLF，Git Bash 直接
  `$'\r': command not found`）

### Build（v1.1.0 比特流重出，TNS 全 0）

- 综合 + 布线 + 时序（`gw_sh build.tcl`）：`I_clk` Fmax 161.3 MHz / 约束 27；
  `tmds_clk` **78.67 / 74.25（余量 5.6%）**；`adc_clk` 56.8 / 54.0；三个时钟
  setup/hold 负 slack 全 0；最差 setup +0.757 ns、最差 hold +0.074 ns
- 资源：LUT 5777（4740 LUT + 1037 ALU）、Register 2143/15552 = 14%、BSRAM 32/46 = 70%
- `build.tcl` 加 `set_option -place_option 2 / -route_option 2`（时序驱动布局布线）：
  不加时 tmds 最差 setup 只剩 +0.007 ns（同一份网表实测），加上后 +0.757 ns
- **tmds 域仍是最紧的域**，后续往像素域加逻辑（≥1 级 LUT）前先跑综合看 Fmax

### Changed
- **瀑布图只占绘图区底部 1/4**（128 行，1 行历史/像素行），上 3/4 黑底网格 —— 上板反馈
  瀑布全屏背景遮挡频谱视野
- **编码器短按/长按区分**（`key_enc_ctrl.v`）：短按 = 光标关时切精细（光标步进 4→1 列，
  顶栏右上 FINE 指示）/ 光标开时跳峰；长按（≥0.8s）= Preset；tb_key_enc 扩到 13 项
- **时域视图右侧菜单补文字**：Span/Trig/NPTS（上板反馈时域菜单区空白）
- **非公开材料移出仓库**：工程 `文档/` 只保留技术文档（交接文档、操作手册、代码阅读引导、
  程序对照注释手册、上板测试记录表）；非公开文档及其生成脚本移到工程目录之外
  单独存放，`.gitignore` 无需覆盖（不在工作区内），`tools/make_release.py` 发布清单与
  `文档/gen_handover.py` 里的相关措辞同步去掉
- **回归新增第 8 步**：tb_top +JUMP 光标跳峰端到端（KEY4 开光标 + 短按编码器 → 光标
  跳回基波峰列），一键回归扩为 8 步 7 项；本轮补 Δ 模式透传断言后仍为 7 项全通过

### Deferred（上板测试记录表 A4/A5，需设计确认）
- 谐波标记移到时域挡从上到下显示 1~5 次谐波 + 扩展时域按键功能
- 谐波电平表幅度挡位切换；长按编码器切"分贝挡"光标（现长按 = Preset）
- **本轮通读修复项全部只做过仿真/综合**：底栏 Win/RBW 排版、H2~H5 读数、27 MHz 宽频档
  （首次真正可选）、光标 Δ 模式 —— 需按下表补测后再算上板确认

## [1.0.0] - 2026-10-25

首个基线版本（就地建立：此前开发历史以日期记录于《交接文档》第 7 节）。

### Added
- **采集链**：AD9226 54 MSPS 直采，27 点滑动平均抽取（fs = 2 MHz），Q4 有符号样点
- **FFT 链**：4096 点基 2 DIF 定点 FFT（逐级 ÷2 定标）、4 窗切换（Hann/Rect/Blackman/FlatTop，半表 + 相干增益校准）、逆 sinc 补偿、16 帧视频平均（慢档 1/4）、逐位开方、1024 列峰值检波
- **测量**：基波检测（±2 列容差）、HD2~HD5 谐波窗口电平表、F0 基波频率读数、参数指纹换档复位
- **显示**：三视图（频谱+瀑布+菜单 / 纯净频谱 / 时域）、瀑布图（256×128×3bit 环形历史）、光标三态（普通/增量 Δ/关）+ 跳峰、五色谐波标记、运行时文字解码（替代 28 块 pROM）
- **人机**：5 按键 + EC11 编码器、AUTO 自动定档、Preset
- **验证**：一键回归 `tools/run_regression.sh`（cmp_fft 0 LSB / 四窗校准 / 基波检测 / tb_key_enc 11 项 / 波形完整性 / 顶层渲染六要素）
- **文档**：操作手册 / 代码阅读引导 / 程序对照注释手册 / 交接文档

### Fixed
- 换窗帧窗形混用（`win_lat` 于 cap_start 锁存）
- 视频平均换参数不复位（5 位参数指纹重装）
- 增益乘法 13bit 回绕（Verilog 上下文宽度规则，乘积先落宽 wire）
- twiddle 半表刻度错位（sin = cos[|k−1024|]）
- 纯净模式 F0 尾字符被菜单折叠误隐藏；H 表/F0 缺跨度门控
- 拼接无符号陷阱、BSRAM X 污染门控、文字 put 参数转置、前缀拼接移位、FSM else 误删、多驱动、SDC 静默失效、license U+202A（详见代码内 ★ 注释与《代码阅读引导》7.4）

### Known limits
- 见 `README.md` 已知限制 1~16 条与《代码阅读引导》7.1~7.3
- 板端实测（偏置/编码器抖动/显示器兼容/实测指标）待连接板到位后执行

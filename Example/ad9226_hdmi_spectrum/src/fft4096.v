// ============================================================================
// fft4096.v  --  4096 点定点 FFT + 幅度谱输出 (GW2AR-18 / Tang Nano 20K)
//
//   用途: 测量 0 ~ 1 MHz 的低频信号
//     采样率 fs = 2.000 MHz (由 54MHz 采样时钟 27 抽 1 得到)
//     4096 点 FFT -> bin = 488.28 Hz, Hann 窗 RBW = 732.4 Hz
//     0 .. fs/2 (1 MHz) 共 2048 个频点 -> 显示 1024 列, 每列取相邻两点的较大值
//
//   结构:
//     - 就地 (in-place) 基 2 DIF, 单蝶形单元, 4096 x 32bit 单读单写 BSRAM
//     - 采集阶段: 样点 x Hann 窗 -> (x*w)>>>12 -> 实部, 虚部 = 0
//     - 运算阶段: 12 级 x 2048 蝶形, 每个蝶形 9 拍, 每级输出算术右移 1 位
//                 (逐级除 2 保证 16bit 不溢出, 总增益 1/4096)
//     - 输出阶段: DIF 结果是位倒序存放, 读地址取 bitrev12(bin), 写地址用列号
//                 每列读两个 bin, 先比平方和再开一次方 —— sqrt 单调, 等价于取大
//
//   ★ BSRAM 是"地址打一拍 + 数据打一拍", 给地址到拿到数据要 2 拍,
//     下面的相位编号已按此编排, 改动时务必对齐 (见各段注释)。
//
//   定点格式 (与 tools/model_fft.py 完全一致, 逐点比对 0 LSB):
//     x[n]   = (adc - 2048) << 4            16bit 有符号
//     xw[n]  = (x[n] * hann[n]) >>> 12      hann: 12bit 无符号 (0..4095)
//     旋转因子 Q15: W^k = cos - j*sin
//     幅度   = sqrt(re^2 + im^2) << 3, 饱和 65535 (65535 = 0 dBFS)
//             满量程单音 = 65480 (-0.01 dBFS); 定标与 N 无关 (见 model_fft.py 注释)
//
//   一帧 (54MHz) @fs=2MHz: 采集 2.05ms + 蝶形 4.10ms + 幅度 0.42ms ≈ 6.6ms
// ============================================================================
module fft4096 #(
    parameter N    = 4096,
    parameter NLOG = 12
)(
    input             I_clk ,
    input             I_rst_n,

    // ---- 采集控制 ----
    input             I_frame_req,      // 单拍: 请求算一帧 (顶层按显示帧同步给)
    output reg        O_cap_start,      // 单拍: 通知前端开始采 N 点
    output            O_busy,           // 1: 正在算

    // ---- 低频中间帧: 用已采样的前 K 点 + 补零跑一次完整 FFT, 慢档先出谱 ----
    //   I_mid_en 由顶层按跨度档给 (只慢档使能); O_mid 标记本帧是中间帧;
    //   O_mid_sh 是幅度补偿左移位数 (= 12 - log2 K), 由顶层在写侧左移.
    input             I_mid_en,
    output reg        O_mid,
    output reg [2:0]  O_mid_sh,

    // ---- 样点输入 (I_clk 域, 已抽取到 fs) ----
    input      [15:0] I_smp,
    input             I_smp_en,

    // ---- 幅度谱输出 (写 spec_data_if, 1024 列) ----
    output reg        O_frame_start,    // 一帧起始单拍
    output reg        O_mag_en,
    output reg [9:0]  O_mag_addr,       // 显示列 0..1023
    output reg [15:0] O_mag,

    // ---- 基波峰值检测 (给 1~5 次谐波标记 + 谐波电平表) ----
    //   每帧找幅度最大的列 (排除 DC 附近 8 列和最高 8 列),
    //   幅度 >= 512 (约 -42 dBFS) 才认为有效, 否则 O_hrm_valid=0
    output reg [9:0]  O_hrm_col,        // 基波所在列
    output reg        O_hrm_valid,      // 本帧检测结果有效
    output reg        O_hrm_tog,        // 每次更新翻转一次 (跨时钟域握手)

    // ---- 2~5 次谐波电平 (顶栏 H2..H5 读数): 基波列锁定后的下一帧,
    //      在 k*基波列 ±2 列窗口内取幅度峰 (k 次谐波未必正好落在整数列) ----
    output reg [15:0] O_h2, O_h3, O_h4, O_h5,
    output reg [15:0] O_h1,            // 基波峰幅度 (THD/SNR 分母)
    output reg [35:0] O_pwr,           // 全带功率累加 sum(mag^2 >> 6) (SINAD 用)

    // ---- 宽频模式 (直采, 无抽取): 无箱化倾斜, 补偿切平 ----
    input             I_mag_flat,

    // ---- 窗函数选择 (KEY5 循环): 0=Hann(默认) 1=Rect 2=Blackman 3=FlatTop ----
    input      [1:0]  I_win,

    // ---- 检波方式 (菜单 Detector): 0=正峰 1=平均 2=负峰 3=取样 ----
    //   每列对应 2 个 bin (2k, 2k+1): 正峰取大、平均取均值、负峰取小、
    //   取样只取 2k 那个 bin (标准频谱仪的 Sample 检波)
    input      [1:0]  I_det_sel,

    // ---- 视频平均深度 (菜单 Avg): 0=1 帧(直通) 1=4 帧 2=16 帧 3=64 帧 ----
    //   没有平均时噪底是 1~16 的小整数, 对数显示下每跨一个整数跳 3~6dB,
    //   叠加逆 sinc 的平滑上斜就成了"从低频到高频的分段阶梯"。
    //   指数平均 + 4 位小数把噪底估计平滑到 0.1dB 以下。
    input      [1:0]  I_avg_sel,

    // ---- 配置指纹 {span(3), win(2), det(2)}: 变化时下一帧重新预装平均 ----
    //   (真实仪器换参数即重启扫描; 否则旧谱以 1/16 指数拖尾混入新谱 ~16 帧)
    input      [6:0]  I_cfg_id
);

    localparam ST_IDLE = 3'd0,
               ST_CAP  = 3'd1,
               ST_STG  = 3'd2,
               ST_MAG  = 3'd3,
               ST_WIN  = 3'd4,      // 中间帧: 用 K 点相对窗重写 ram[0..K)
               ST_ZERO = 3'd5,      // 中间帧: ram[K..4095] 补零
               ST_FIX  = 3'd6;      // 中间帧后: 用原窗把 ram[0..cap_n) 逐点重算补回

    reg  [2:0] st;
    assign O_busy = (st != ST_IDLE);

    // 各阶段完成标志 (Verilog 要求先声明后使用)
    reg cap_done;
    reg stg_done;
    reg mag_done;

    //==================================================================
    // 样点 RAM: 4096 x 32 (实部低 16 位, 虚部高 16 位)
    //==================================================================
    reg [31:0] ram [0:4095];
    reg [31:0] rd_data;

    wire [11:0] ram_raddr;
    wire        ram_we;
    wire [11:0] ram_waddr;
    wire [31:0] ram_wdata;

    always @(posedge I_clk) begin
        if (ram_we) ram[ram_waddr] <= ram_wdata;
    end
    always @(posedge I_clk) begin
        rd_data <= ram[ram_raddr];
    end

    wire signed [15:0] rd_re = rd_data[15:0];
    wire signed [15:0] rd_im = rd_data[31:16];

    //==================================================================
    // Hann 窗 / 旋转因子 ROM (同步读, 1 拍延迟)
    //   ★ win_lat 在 O_cap_start 锁存 I_win (与顶层锁 dec_sel 同一拍):
    //     若直接用 I_win, 换窗落在"采集后/幅度前"时本帧会前半旧窗后半新窗,
    //     而增益按新窗算, 读数错一帧。锁存后整帧一致, 下一帧起生效。
    //==================================================================
    reg  [1:0]  win_lat;
    reg  [11:0] hann_addr;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)         win_lat <= 2'd0;
        else if (O_cap_start) win_lat <= I_win;
    end

    wire [11:0] hann_rom_w, win_hw;
    // 窗函数多路: 0=Hann(默认) 1=Rect(常数 4095) 2/3=Blackman/FlatTop 半表
    wire [11:0] hann_w = (win_lat == 2'd0) ? hann_rom_w :
                         (win_lat == 2'd1) ? 12'd4095 : win_hw;

    hann_rom u_hann (
        .I_clk  (I_clk      ),
        .I_addr (hann_addr  ),
        .O_w    (hann_rom_w )
    );

    // Blackman/FlatTop 半表: 窗对称于 n=2047.5, a>=2048 时读 4095-a (=按位取反)
    wire [11:0] win_mirror = hann_addr[11] ? (~hann_addr) : hann_addr;

    win_rom u_win (
        .I_clk  (I_clk    ),
        .I_addr ({win_lat[0], win_mirror[10:0]}),   // sector: win2=Blackman win3=FlatTop
        .O_w    (win_hw   )
    );

    reg  [10:0] tw_addr;
    wire [15:0] tw_cos_w;

    twiddle_rom u_tw (
        .I_clk  (I_clk   ),
        .I_addr (tw_addr ),
        .O_cos  (tw_cos_w)
    );

    // 抽取滤波器 (boxcar) 的逆 sinc 补偿, Q7: 1024 = 1.000x, 1608 = 1.570x
    reg  [9:0]  g_addr;
    wire [10:0] g_w;

    magcomp_rom u_gain (
        .I_clk  (I_clk  ),
        .I_addr (g_addr ),
        .O_g    (g_w    )
    );

    //==================================================================
    // 低频中间帧支持
    //   ★ 为什么不在中间帧后重启采集: 慢档一帧 0.2~8.2s, 重启等于整帧
    //     时间翻倍; 也不能在中间帧期间丢样点 —— 会在完整帧中间留下相位
    //     断点, 噪声底和杂散全变。
    //   ★ 做法: snap 存本帧原始样点; 中间帧用 K 点相对窗重写前缀 + 补零
    //     跑完一次 FFT; 结束后再用"原窗 + 原样点"把前缀逐点重算写回,
    //     于是完整帧与不开中间帧时逐位一致 (重算复用同一条加窗流水)。
    //==================================================================
    reg  [11:0]        cap_n;
    reg                cap_last;
    reg                v0, v1, v2;
    reg  signed [15:0] s0, s1, s2;
    reg  [11:0]        a0, a1, a2;
    reg  signed [27:0] prod;

    reg                cap_run;       // 采集流水运行 (帧起始打开, 采满 N 点关闭)
    reg                mid_seen;      // 本帧有中间帧 (采集解状态 / 清 mag_done)
    reg                mid_en_lat;    // O_cap_start 时锁存 I_mid_en
    reg                mid_pend;      // 本帧已插入中间帧 (等补回)
    reg  [3:0]         mid_idx;       // 本帧已插入的中间帧次数 (0..7)
    reg  [11:0]        k_lat;         // 本次中间帧点数 K
    reg  [2:0]         sh_lat;        // 本次中间帧幅度补偿移位
    reg                rw_kick;       // 进入 ST_WIN / ST_FIX 的预取复位
    reg  [11:0]        fa;            // 重写/补写预取地址
    reg                inj_pend;      // 预取数据就绪
    reg  [15:0]        snap_q;        // 预取读出的快照样点
    reg  [11:0]        za;            // 补零地址
    reg                inj0, inj1, inj2;  // 流水标记: 1=注入点 0=采集样点

    // 快照 RAM: 本帧原始样点 (未加窗), 4096x16 -> 4 块 BSRAM
    reg [15:0] snap [0:4095];

    // 中间帧阶梯: rung 0..4 -> K = 128 << rung = 128/256/512/1024/2048,
    // 显示侧补偿 = N/K 左移 sh = 5 - rung
    wire [2:0]  rung      = mid_idx[2:0];
    wire [11:0] mid_k_c   = 12'd128 << rung;
    wire [2:0]  mid_sh_c  = 3'd5 - rung;
    wire        mid_valid = (mid_idx <= 4'd4);

    // 采集使能: 与状态解耦 —— ST_WIN/ST_ZERO/ST_FIX/ST_MAG 期间照样接样点
    //   * 无中间帧的帧只允许在 ST_CAP 采集 (与 v1.6.0 逐拍一致);
    //     有中间帧的帧全程采集, 样点先进 snap, 帧末 ST_FIX 再补回 ram
    wire cap_en = (st == ST_CAP || mid_seen) && cap_run && I_smp_en && !cap_last;

    // 中间帧触发点: 采满 K 点就插一次 (K 最大 2048, 离 cap_done 仍有余量)
    //   * 用 >= 而不是 ==: 快的慢速档一次中间帧期间也会进几十上百个样点,
    //     用相等判断会漏掉后面的阶梯点, >= 保证阶梯逐级推进
    wire mid_go = (st == ST_CAP) && mid_en_lat && mid_valid &&
                  (cap_n >= mid_k_c) && !cap_done;

    // 重写注入: ST_WIN 用 K 点窗重写前缀, ST_FIX 用原窗逐点补回
    //   ★ 与采集样点共用一条乘法流水: 采集优先, 注入让路 (2 拍 1 点)
    //   cap_done 已置 (中间帧跨过了帧尾) -> 补满 4096 点: 期间被丢弃的尾部样点
    //   也在 snap 里, 补回来才和不开中间帧时逐位一致
    wire [12:0] fix_stop  = cap_done ? 13'd4096 : ({1'b0, cap_n} - 13'd4);
    wire        rw_active = ((st == ST_WIN) && (fa < k_lat)) ||
                            ((st == ST_FIX) && ({1'b0, fa} < fix_stop));
    wire        inj_en    = inj_pend && !cap_en;
    wire [11:0] fa_cur    = fa - 12'd1;
    wire [11:0] win_addr  = (st == ST_WIN) ? (fa_cur << sh_lat) : fa_cur;
    // ★ !rw_kick: 进入 ST_FIX 的那一拍 fa 还是上一轮的旧值, 必须让它先归零
    wire        fix_done  = (st == ST_FIX) && !rw_kick && !inj_pend &&
                            ({1'b0, fa} >= fix_stop) && !v0 && !v1 && !v2;

    // 采集/注入样点写 ram: ST_CAP 正常写, ST_FIX 期间同步补写 (地址已错开)
    wire ram_pipe_we = v2 && (inj2 ? ((st == ST_WIN) || (st == ST_FIX))
                                 : ((st == ST_CAP) || (st == ST_FIX)));
    // 快照只记普通采集样点 (重写注入点不再写回快照)
    wire snap_we = v2 && !inj2;

    //==================================================================
    // 主状态机 (只负责 st 与各类 kick 脉冲)
    //==================================================================
    reg frame_kick, stg_kick, mag_kick;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            st            <= ST_IDLE;
            O_cap_start   <= 1'b0;
            frame_kick    <= 1'b0;
            stg_kick      <= 1'b0;
            mag_kick      <= 1'b0;
            rw_kick       <= 1'b0;
            O_frame_start <= 1'b0;
            O_mid         <= 1'b0;
            O_mid_sh      <= 3'd0;
            mid_en_lat    <= 1'b0;
            mid_pend      <= 1'b0;
            mid_idx       <= 4'd0;
            k_lat         <= 12'd0;
            sh_lat        <= 3'd0;
            za            <= 12'd0;
        end else begin
            O_cap_start   <= 1'b0;
            frame_kick    <= 1'b0;
            stg_kick      <= 1'b0;
            mag_kick      <= 1'b0;
            rw_kick       <= 1'b0;
            O_frame_start <= 1'b0;

            case (st)
            ST_IDLE: begin
                if (I_frame_req) begin
                    st          <= ST_CAP;
                    O_cap_start <= 1'b1;
                    frame_kick  <= 1'b1;
                    mid_en_lat  <= I_mid_en;
                    mid_idx     <= 4'd0;
                    mid_pend    <= 1'b0;
                    O_mid       <= 1'b0;
                end
            end
            ST_CAP: begin
                if (cap_done) begin
                    st       <= ST_STG;
                    stg_kick <= 1'b1;
                end else if (mid_go) begin
                    st       <= ST_WIN;        // 插中间帧: 先重写前缀
                    mid_pend <= 1'b1;
                    k_lat    <= mid_k_c;
                    sh_lat   <= mid_sh_c;
                    O_mid_sh <= mid_sh_c;
                    rw_kick  <= 1'b1;
                end
            end
            ST_WIN: begin
                // 前缀重写完且流水排空 -> 补零
                // ★ !rw_kick: 进来那一拍 fa 还是上一轮的旧值 (> k_lat), 否则 1 拍就跳走
                if (!rw_kick && !inj_pend && (fa >= k_lat) && !v0 && !v1 && !v2) begin
                    st <= ST_ZERO;
                    za <= k_lat;
                end
            end
            ST_ZERO: begin
                if (za == 12'd4095) begin
                    st       <= ST_STG;
                    stg_kick <= 1'b1;
                end else begin
                    za <= za + 12'd1;
                end
            end
            ST_STG: begin
                if (stg_done) begin
                    st            <= ST_MAG;
                    mag_kick      <= 1'b1;
                    O_frame_start <= 1'b1;
                    if (mid_pend) O_mid <= 1'b1;   // 与 O_frame_start 同拍起
                end
            end
            ST_MAG: begin
                if (mag_done) begin
                    if (mid_pend) begin
                        st      <= ST_FIX;         // 中间帧出完 -> 逐点补回
                        rw_kick <= 1'b1;
                        mid_idx <= mid_idx + 4'd1;
                        O_mid   <= 1'b0;
                    end else begin
                        st <= ST_IDLE;
                    end
                end
            end
            ST_FIX: begin
                if (fix_done) begin
                    st       <= ST_CAP;            // 接着采本帧剩下的样点
                    mid_pend <= 1'b0;              // 下一次 mid_go 再置
                end
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

    // 采集流水运行标志 (与 st 解耦: 算 FFT / 重写期间也要接样点)
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)        cap_run <= 1'b0;
        else if (frame_kick) cap_run <= 1'b1;
        else if (cap_done)   cap_run <= 1'b0;
    end

    // 本帧是否出现过中间帧 (sticky, 帧开始清零)
    //   * 没中间帧 -> 行为与 v1.6.0 完全相同, 包括 cap_done/mag_done
    //     陈旧导致的跳帧
    //   * 有中间帧 -> 采集不停 + 本帧照常出谱
    always @(posedge I_clk or negedge I_rst_n)
        if (!I_rst_n)        mid_seen <= 1'b0;
        else if (frame_kick) mid_seen <= 1'b0;
        else if (mid_go)     mid_seen <= 1'b1;
    //==================================================================
    // 采集 + 加窗 (3 级流水; 声明见上。ST_WIN/ST_FIX 期间同一条流水改喂
    //   "快照重写注入点", inj0/1/2 标记区分采集样点与注入点)
    //   T  : cap_en=1, 采样 -> s0, 同时给窗地址
    //   T+1: s1 = s0
    //   T+2: hann_w 对应 s1 的样点 -> prod = s1*w
    //   T+3: 写 ram[a2] = prod>>>12
    //==================================================================
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cap_n     <= 12'd0;
            cap_last  <= 1'b0;
            hann_addr <= 12'd0;
            v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0;
            inj0 <= 1'b0; inj1 <= 1'b0; inj2 <= 1'b0;
            s0 <= 16'sd0; s1 <= 16'sd0; s2 <= 16'sd0;
            a0 <= 12'd0; a1 <= 12'd0; a2 <= 12'd0;
            prod <= 28'sd0;
        end else if (frame_kick) begin
            cap_n    <= 12'd0;
            cap_last <= 1'b0;
            v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0;
            inj0 <= 1'b0; inj1 <= 1'b0; inj2 <= 1'b0;
        end else begin
            // 采集样点与重写注入点合流: 注入让路 (cap_en 优先), 不丢样点
            v0        <= cap_en | inj_en;
            inj0      <= inj_en;
            s0        <= inj_en ? snap_q : I_smp;
            a0        <= inj_en ? fa_cur : cap_n;
            hann_addr <= inj_en ? win_addr : cap_n;
            if (cap_en) begin
                cap_n <= cap_n + 12'd1;
                if (cap_n == N - 1) cap_last <= 1'b1;
            end

            v1 <= v0;
            s1 <= s0;
            a1 <= a0;
            inj1 <= inj0;

            v2   <= v1;
            prod <= s1 * $signed({1'b0, hann_w});   // 与 a2 / v2 同拍有效
            a2   <= a1;
            inj2 <= inj1;
            s2   <= s1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)                 cap_done <= 1'b0;
        else if (frame_kick)          cap_done <= 1'b0;
        else if (v2 && (a2 == N - 1)) cap_done <= 1'b1;
    end

    // 快照写口: 与 ram 采集写同拍, 记原始样点 (未加窗), 供中间帧重算
    always @(posedge I_clk) begin
        if (snap_we) snap[a2] <= s2;
    end

    // 重写/补写预取 (snap 同步读有 1 拍延迟, 2 拍取一个点)
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            fa       <= 12'd0;
            inj_pend <= 1'b0;
            snap_q   <= 16'd0;
        end else if (rw_kick) begin
            fa       <= 12'd0;
            inj_pend <= 1'b0;
        end else if (!inj_pend) begin
            if (rw_active) begin
                snap_q   <= snap[fa];
                fa       <= fa + 12'd1;
                inj_pend <= 1'b1;
            end
        end else if (inj_en) begin
            inj_pend <= 1'b0;
        end
    end

    //==================================================================
    // 蝶形运算: 每个蝶形 9 拍 (ph 0..8)
    //   ph0: 发 addr_a 读地址 + cos 地址(k)    ph1: 发 addr_b + sin 地址(k+1536)
    //   ph2: 收 da / cos(k)                   ph3: 收 db / sin(k)=cos(k+1536)
    //   ph4: 和 / 差                          ph5: 4 个乘法
    //   ph6: 写回和                           ph7: (a-b)*W
    //   ph8: 写回差
    //==================================================================
    reg [3:0]  ph;
    reg [3:0]  stg;                 // 0..11
    reg [11:0] half;                // 2048 >> stg
    reg [11:0] addr_a, addr_b;
    reg [11:0] j;
    reg [11:0] bf_cnt;              // 0..2047

    reg signed [15:0] da_re, da_im, db_re, db_im, tc, ts;
    reg signed [16:0] sre, sim, dre, dim;
    reg signed [32:0] p1, p2, p3, p4;
    reg signed [18:0] mre, mim;

    reg        bf_we;
    reg [11:0] bf_waddr;
    reg [31:0] bf_wdata;
    reg [11:0] bf_raddr;

    wire [11:0] tw_idx = j << stg;

    // sin(k) = cos(|k-1024|): 表刻度是 2*pi*k/4096 (0..pi 半圆), cos 为偶函数,
    //   与原 {cos,sin} 双表逐位等价 (sin(k) = 32767*sin(2*pi*k/4096) >= 0)
    wire [10:0] tw_sin_a = (tw_idx > 11'd1024) ? (tw_idx - 11'd1024)
                                               : (11'd1024 - tw_idx);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ph     <= 4'd0;
            stg    <= 4'd0;
            half   <= 12'd2048;
            addr_a <= 12'd0;
            addr_b <= 12'd2048;
            j      <= 12'd0;
            bf_cnt <= 12'd0;
            bf_we    <= 1'b0;
            bf_waddr <= 12'd0;
            bf_wdata <= 32'd0;
            bf_raddr <= 12'd0;
            tw_addr  <= 11'd0;
            stg_done <= 1'b0;
            da_re <= 0; da_im <= 0; db_re <= 0; db_im <= 0;
            tc <= 0; ts <= 0;
            sre <= 0; sim <= 0; dre <= 0; dim <= 0;
            p1 <= 0; p2 <= 0; p3 <= 0; p4 <= 0;
            mre <= 0; mim <= 0;
        end else if (stg_kick) begin
            ph       <= 4'd0;
            stg      <= 4'd0;
            half     <= 12'd2048;
            addr_a   <= 12'd0;
            addr_b   <= 12'd2048;
            j        <= 12'd0;
            bf_cnt   <= 12'd0;
            bf_we    <= 1'b0;
            stg_done <= 1'b0;
        end else if (st == ST_STG) begin
            bf_we    <= 1'b0;
            stg_done <= 1'b0;
            ph       <= (ph == 4'd8) ? 4'd0 : (ph + 4'd1);

            case (ph)
            4'd0: begin
                bf_raddr <= addr_a;
                tw_addr  <= tw_idx[10:0];
            end
            4'd1: begin
                bf_raddr <= addr_b;
                tw_addr  <= tw_sin_a;             // 第二拍读 sin
            end
            4'd2: begin
                da_re <= rd_re;
                da_im <= rd_im;
                tc    <= $signed(tw_cos_w);       // cos(k)
            end
            4'd3: begin
                db_re <= rd_re;
                db_im <= rd_im;
                ts    <= $signed(tw_cos_w);       // cos(k+1536) = sin(k)
            end
            4'd4: begin
                sre <= da_re + db_re;
                sim <= da_im + db_im;
                dre <= da_re - db_re;
                dim <= da_im - db_im;
            end
            4'd5: begin
                p1 <= dre * tc;
                p2 <= dim * ts;
                p3 <= dim * tc;
                p4 <= dre * ts;
            end
            4'd6: begin
                bf_we    <= 1'b1;
                bf_waddr <= addr_a;
                bf_wdata <= {sim[16:1], sre[16:1]};       // (a+b)/2
            end
            4'd7: begin
                mre <= (p1 >>> 15) + (p2 >>> 15);
                mim <= (p3 >>> 15) - (p4 >>> 15);
            end
            4'd8: begin
                bf_we    <= 1'b1;
                bf_waddr <= addr_b;
                bf_wdata <= {mim[16:1], mre[16:1]};       // (a-b)*W/2
            end
            default: bf_we <= 1'b0;
            endcase

            if (ph == 4'd8) begin
                if (j == half - 12'd1) begin
                    j      <= 12'd0;
                    addr_a <= addr_a + half + 12'd1;
                    addr_b <= addr_a + half + 12'd1 + half;
                end else begin
                    j      <= j + 12'd1;
                    addr_a <= addr_a + 12'd1;
                    addr_b <= addr_b + 12'd1;
                end

                if (bf_cnt == 12'd2047) begin
                    bf_cnt <= 12'd0;
                    addr_a <= 12'd0;
                    j      <= 12'd0;
                    if (stg == NLOG - 1) begin
                        stg_done <= 1'b1;
                    end else begin
                        stg    <= stg + 4'd1;
                        half   <= half >> 1;
                        addr_b <= (half >> 1);
                    end
                end else begin
                    bf_cnt <= bf_cnt + 12'd1;
                end
            end
        end else begin
            bf_we <= 1'b0;
        end
    end

    //==================================================================
    // 幅度: 每列读 2 个 bin -> 取平方和较大者 -> 16 次逐位开方
    //   mph0: 发 bin 2k 地址   mph1: 等   mph2: 算 re^2/im^2 (bin 2k)
    //   mph3: 平方和 -> m0, 发 bin 2k+1 地址   mph4: 算 re^2/im^2   mph5: m1
    //   mph6: 检波取大 -> xq   mph7..22: 16 次开方迭代
    //   mph23: 锁存 avg_new_r   mph24: 取整+饱和 -> O_mag
    //   (乘法与加法分开寄存: 旧版一拍里做 2 乘法+加法+比较, 38 节点全设计最差)
    //==================================================================
    reg [9:0]  m_cnt;
    reg [4:0]  mph;
    reg [32:0] xq, sq0;
    // 幅度通路两级流水: 乘法结果 / 平方和
    reg [32:0] qr0, qi0, qr1, qi1, m0, m1;
    reg [18:0] rem;
    reg [15:0] root;
    reg [11:0] mag_raddr;
    reg [10:0] base_gain;
    reg [12:0] gain_r;
    // 窗相干增益校准 (Q7, 相对 Hann 0.5): 同一信号四种窗读数一致
    //   ★ 用 win_lat (采集时锁存的窗), 与实际乘的窗形匹配
    wire [8:0]  win_gain = (win_lat == 2'd0) ? 9'd128 :
                           (win_lat == 2'd1) ? 9'd64  :
                           (win_lat == 2'd2) ? 9'd152 : 9'd296;
    // ★ 乘积必须先落在足够宽的 wire 上再移位: 直接写
    //   gain_r <= (base_gain * win_gain) >>> 7 会按 LHS 13bit 求值乘法而回绕
    wire [19:0] gain_prod = (I_mag_flat ? 11'd1024 : g_w) * win_gain;

    function [11:0] bitrev12;
        input [11:0] v;
        integer i;
        begin
            for (i = 0; i < 12; i = i + 1)
                bitrev12[i] = v[11 - i];
        end
    endfunction

    wire signed [32:0] sq_re = rd_re;
    wire signed [32:0] sq_im = rd_im;
    wire [32:0] mag_sq = sq_re * sq_re + sq_im * sq_im;
    // 平均检波: 两个 bin 的平方和取均值 (34bit 防溢出, 均值必 <=33bit)
    wire [33:0] sq_sum = {1'b0, sq0} + {1'b0, mag_sq};
    wire [32:0] sq_avg = sq_sum[33:1];

    wire [11:0] bin0 = {m_cnt, 1'b0};      // 第 2k 个 bin
    wire [11:0] bin1 = {m_cnt, 1'b1};      // 第 2k+1 个 bin

    wire [18:0] rem2    = {rem[16:0], xq[31:30]};
    wire [18:0] trial19 = {root[15:0], 2'b00} | 19'd1;
    wire        ge      = (rem2 >= trial19);
    wire [28:0] mag_gain = root * gain_r;                // 16bit x 13bit
    wire [21:0] mag_sh   = mag_gain >> 7;                // Q7 归一 (满量程 -> 65535)

    //==================================================================
    // 视频平均 (指数 IIR): avg_mem 1024x21bit (mag x16, 4 位小数)
    //   读: 每列 mph0 发地址, mph2 数据到; 写: mph24 (与 O_mag 同拍), 无端口冲突
    //   首帧 (avg_init=0) 直接装载, 保证 cmp_fft 首帧 0 LSB 不变
    //==================================================================
    reg  [20:0] avg_mem [0:1023];
    reg  [20:0] avg_dat;
    reg  [9:0]  avg_raddr;
    reg         avg_we;
    reg  [9:0]  avg_waddr;
    reg  [20:0] avg_wdata;
    reg         avg_init;                    // 首帧后置 1, 此后走混合
    reg  [1:0]  avg_sel_lat;                 // cap_start 锁存 I_avg_sel
    reg  [20:0] avg_new_r;                   // mph23 锁存, mph24 再取整/饱和 -> 砍 6~7 级
    reg  [1:0]  det_lat;                     // cap_start 锁存 I_det_sel

    always @(posedge I_clk) avg_dat <= avg_mem[avg_raddr];

    // 饱和后的当前值 (与旧 O_mag 相同口径) -> x16
    // 饱和判断用高位或树 (与 22bit 比较器等价, 少一级进位链)
    wire        msat     = |mag_sh[21:16];
    wire [15:0] mag_sat  = msat ? 16'hFFFF : mag_sh[15:0];
    wire [21:0] mag_ext  = {6'd0, mag_sat} << 4;
    // diff = mag_ext - avg_dat (凸组合结果必在两者之间, 21bit 内)
    wire signed [22:0] avg_dif = $signed({1'b0, mag_ext[21:0]})
                                - $signed({1'b0, avg_dat});
    // 指数平均系数 1/2^k, k=2/4/6 对应时间常数 4/16/64 帧; 1 帧时直通
    // 用三个定长移位 + 末尾 mux: 变量移位在 GW2AR 上要 3 级 2^sh 移位链,
    // 这一条曾把 adc_clk 拉到 53.5MHz (TNS -0.81)
    wire signed [22:0] dsh2 = avg_dif >>> 2;
    wire signed [22:0] dsh4 = avg_dif >>> 4;
    wire signed [22:0] dsh6 = avg_dif >>> 6;
    wire        avg_byp = (avg_sel_lat == 2'd0);
    wire signed [22:0] avg_dsh = (avg_sel_lat == 2'd1) ? dsh2 :
                                 (avg_sel_lat == 2'd2) ? dsh4 : dsh6;
    wire [20:0] avg_new  = (avg_byp || !avg_init) ? mag_ext[20:0]
                                                  : (avg_dat + avg_dsh[20:0]);
    // 取整/饱和改在 mph24 做, 吃 mph23 锁存下来的 avg_new_r (少 6~7 级组合)
    wire [21:0] avg_rd   = (avg_new_r + 21'd8) >> 4;          // 四舍五入回整数
    wire [15:0] mag_avg  = (|avg_rd[21:16]) ? 16'hFFFF : avg_rd[15:0];

    reg [6:0] avg_cfg_lat;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            avg_raddr   <= 10'd0;
            avg_we      <= 1'b0;
            avg_waddr   <= 10'd0;
            avg_wdata   <= 21'd0;
            avg_init    <= 1'b0;
            avg_sel_lat <= 2'd0;
            det_lat     <= 2'd0;
            avg_cfg_lat <= 7'h7F;
            avg_new_r   <= 21'd0;
        end else begin
            avg_we <= 1'b0;
            if (O_cap_start) begin
                avg_sel_lat <= I_avg_sel;
                det_lat     <= I_det_sel;
                if (I_cfg_id != avg_cfg_lat) begin
                    avg_cfg_lat <= I_cfg_id;
                    avg_init    <= 1'b0;      // 参数变了: 下一帧重新预装
                end
            end
            // 中间帧: 输出直通 (avg_sel_lat=0), 帧末恢复用户设置
            if (mid_go)   avg_sel_lat <= 2'd0;
            if (fix_done) avg_sel_lat <= I_avg_sel;
            // 中间帧不写平均记忆 (也就不清 avg_init): 平均记忆保持上一次
            // 完整帧的值, 中间帧结束后继续按原设置累加
            if (st == ST_MAG) begin
                if (mph == 5'd0)
                    avg_raddr <= m_cnt;
                // 每列都锁存 (中间帧也要! 否则中间帧的 O_mag 走 x)
                if (mph == 5'd23)
                    avg_new_r <= avg_new;
                // 写平均记忆仍只在完整帧做 (mph24 与 O_mag 同拍)
                if ((mph == 5'd24) && !mid_pend) begin
                    avg_we    <= 1'b1;
                    avg_waddr <= m_cnt;
                    avg_wdata <= avg_new_r;
                    if (m_cnt == 10'd1023)
                        avg_init <= 1'b1;
                end
            end
        end
    end

    always @(posedge I_clk) begin
        if (avg_we) avg_mem[avg_waddr] <= avg_wdata;
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            m_cnt      <= 10'd0;
            mph        <= 5'd0;
            xq         <= 33'd0;
            sq0        <= 33'd0;
            qr0 <= 33'd0;  qi0 <= 33'd0;  qr1 <= 33'd0;  qi1 <= 33'd0;
            m0  <= 33'd0;  m1  <= 33'd0;
            gain_r     <= 13'd1024;
            base_gain  <= 11'd1024;
            rem        <= 19'd0;
            root       <= 16'd0;
            mag_raddr  <= 12'd0;
            O_mag_en   <= 1'b0;
            O_mag      <= 16'd0;
            O_mag_addr <= 10'd0;
            mag_done   <= 1'b0;
        end else if (stg_kick && mid_seen) begin
            // ★ 进 STG 就先清 mag_done: 中间帧让一帧内进两次 ST_MAG, 否则第二次
            //   进 ST_MAG 会读到上一轮遗留的 mag_done=1 而直接跳出 (不出谱)
            mag_done <= 1'b0;
        end else if (mag_kick) begin
            m_cnt    <= 10'd0;
            mph      <= 5'd0;
            mag_done <= 1'b0;
            O_mag_en <= 1'b0;
        end else if (st == ST_MAG) begin
            O_mag_en <= 1'b0;

            if (mph == 5'd0) begin
                mag_raddr <= bitrev12(bin0);
                g_addr    <= m_cnt;
                mph       <= 5'd1;
            end else if (mph == 5'd1) begin
                mph <= 5'd2;
            end else if (mph == 5'd2) begin
                qr0       <= rd_re * rd_re;                // 只做乘法
                qi0       <= rd_im * rd_im;
                mag_raddr <= bitrev12(bin1);               // 仍在 mph2 发 bin1 地址
                mph       <= 5'd3;
            end else if (mph == 5'd3) begin
                m0  <= qr0 + qi0;                          // 只做加法
                mph <= 5'd4;
            end else if (mph == 5'd4) begin
                qr1 <= rd_re * rd_re;
                qi1 <= rd_im * rd_im;
                mph <= 5'd5;
            end else if (mph == 5'd5) begin
                m1  <= qr1 + qi1;
                mph <= 5'd6;
            end else if (mph == 5'd6) begin
                sq0 <= m0;
                // 检波 (菜单 Detector): 0=正峰 1=平均 2=负峰 3=取样(2k)
                xq     <= (det_lat == 2'd1) ? (({1'b0, m0} + {1'b0, m1}) >> 1) :
                          (det_lat == 2'd2) ? ((m0 <= m1) ? m0 : m1) :
                          (det_lat == 2'd3) ? m0 :
                                              ((m0 >= m1) ? m0 : m1);
                rem    <= 19'd0;
                root   <= 16'd0;
                gain_r <= gain_prod[19:7];                 // x 窗校准 (Q7 x Q7)
                mph    <= 5'd7;
            end else if (mph <= 5'd22) begin
                rem  <= ge ? (rem2 - trial19) : rem2;
                root <= ge ? {root[14:0], 1'b1} : {root[14:0], 1'b0};
                xq   <= xq << 2;
                mph  <= mph + 5'd1;
            end else if (mph == 5'd23) begin      // mph23: 等 avg_new_r 落寄存器
                mph <= 5'd24;
            end else begin                        // mph == 24: 输出 (补偿+视频平均)
                O_mag_en   <= 1'b1;
                O_mag_addr <= m_cnt;
                O_mag      <= mag_avg;
                mph        <= 5'd0;
                if (m_cnt == 10'd1023) mag_done <= 1'b1;
                else                   m_cnt <= m_cnt + 10'd1;
            end
        end
    end


    //==================================================================
    // 基波峰值检测: 幅度输出流 (O_mag_en) 上做一次遍历找最大列
    //   O_mag_* 是上一拍寄存出的输出, 本块看到的 (en, addr, mag) 恒为同一拍的三元组
    //==================================================================
    reg [15:0] pk_max;
    reg [15:0] h2_max, h3_max, h4_max, h5_max;   // 本帧谐波窗口峰
    reg [9:0]  hcol_lat;                          // 上一帧锁定的基波列
    reg        hcol_vld;

    // k*基波列: 必须按 13bit 全宽算 (5*1023=5115). 旧版用 10bit 移位,
    // k*col>=1024 时对 1024 回绕 —— 例如基波 600 列时 H2 窗口落回 176 列,
    // H2..H5 会读到毫不相干的谱线并当成真实谐波电平显示.
    // k*col>1023 表示该次谐波在显示带宽外, 窗口直接关掉 (峰值保持 0,
    // 谐波表按无信号显示), 与标记 hv1..hv5 的判定保持一致.
    wire [12:0] hcol_x = {3'd0, hcol_lat};
    wire [12:0] hc2 = hcol_x << 1;                  // 2x
    wire [12:0] hc3 = (hcol_x << 1) + hcol_x;       // 3x
    wire [12:0] hc4 = hcol_x << 2;                  // 4x
    wire [12:0] hc5 = (hcol_x << 2) + hcol_x;       // 5x
    wire [12:0] mag_c = {3'd0, O_mag_addr};

    wire in_w2 = hcol_vld && (hc2 <= 13'd1023) && (mag_c >= hc2 - 13'd2) && (mag_c <= hc2 + 13'd2);
    wire in_w3 = hcol_vld && (hc3 <= 13'd1023) && (mag_c >= hc3 - 13'd2) && (mag_c <= hc3 + 13'd2);
    wire in_w4 = hcol_vld && (hc4 <= 13'd1023) && (mag_c >= hc4 - 13'd2) && (mag_c <= hc4 + 13'd2);
    wire in_w5 = hcol_vld && (hc5 <= 13'd1023) && (mag_c >= hc5 - 13'd2) && (mag_c <= hc5 + 13'd2);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pk_max     <= 16'd0;
            O_hrm_col  <= 10'd0;
            O_hrm_valid <= 1'b0;
            O_hrm_tog  <= 1'b0;
            h2_max <= 16'd0;  h3_max <= 16'd0;  h4_max <= 16'd0;  h5_max <= 16'd0;
            hcol_lat  <= 10'd0;
            hcol_vld  <= 1'b0;
            O_h2 <= 16'd0;  O_h3 <= 16'd0;  O_h4 <= 16'd0;  O_h5 <= 16'd0;
            O_h1 <= 16'd0;
        end else if (mag_kick) begin
            pk_max <= 16'd0;
            h2_max <= 16'd0;  h3_max <= 16'd0;  h4_max <= 16'd0;  h5_max <= 16'd0;
        end else if (O_mag_en && !mid_pend) begin
            // 中间帧不参与基波/谐波搜索: O_hrm_tog 不翻转, 顶栏 H2..H5 /
            // THD / SNR / F0 全部保持上一次完整帧的读数 (冻结)
            if ((O_mag_addr >= 10'd5) && (O_mag_addr <= 10'd1015) &&
                (O_mag > pk_max)) begin
                pk_max <= O_mag;
                O_hrm_col <= O_mag_addr;
            end
            if (in_w2 && (O_mag > h2_max)) h2_max <= O_mag;
            if (in_w3 && (O_mag > h3_max)) h3_max <= O_mag;
            if (in_w4 && (O_mag > h4_max)) h4_max <= O_mag;
            if (in_w5 && (O_mag > h5_max)) h5_max <= O_mag;
            if (O_mag_addr == 10'd1023) begin
                O_hrm_valid <= (pk_max >= 16'd512);     // -42 dBFS 门限 (声卡等小信号源也能认基波)
                O_hrm_tog   <= ~O_hrm_tog;
                O_h2 <= h2_max;  O_h3 <= h3_max;
                O_h4 <= h4_max;  O_h5 <= h5_max;
                O_h1 <= pk_max;
                hcol_lat  <= O_hrm_col;                 // 下一帧的谐波窗口基准
                hcol_vld  <= (pk_max >= 16'd512);
            end
        end
    end

    //==================================================================
    // 全带功率累加 (SINAD 用): sum(mag^2 >> 6), 输出 36bit
    //   mq1 与 O_mag 同拍 -> mq2 乘法 -> 累加; mad* 同步延迟地址用于末列锁存
    //==================================================================
    reg [15:0] mq1;
    reg [25:0] mq2;
    reg        mv1, mv2, mv3;
    reg [9:0]  mad1, mad2, mad3;
    reg [35:0] pwr_acc;
    wire [31:0] mq_prod = mq1 * mq1;       // ★ 必须在 32 位上下文里乘, 直接用 (mq1*mq1)>>6 会按 26 位截断
    wire [35:0] pwr_nxt = pwr_acc + {10'd0, mq2};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            mq1 <= 16'd0;  mq2 <= 26'd0;
            mv1 <= 1'b0;   mv2 <= 1'b0;   mv3 <= 1'b0;
            mad1 <= 10'd0; mad2 <= 10'd0; mad3 <= 10'd0;
            pwr_acc <= 36'd0;  O_pwr <= 36'd0;
        end else begin
            mq1  <= O_mag;          // 必须是已寄存的 O_mag; 取导线 mag_avg 会在 mph 回绕时采到垃圾值
            mq2  <= mq_prod[31:6];
            mv1  <= O_mag_en && !mid_pend;   // 中间帧不计入全带功率 (SNR 冻结)
            mv2  <= mv1;
            mv3  <= mv2;
            mad1 <= O_mag_addr;
            mad2 <= mad1;
            mad3 <= mad2;
            if (mag_kick) begin
                pwr_acc <= 36'd0;
            end else if (mv2) begin
                pwr_acc <= pwr_nxt;
            end
            // TEMPDBG
            if (mv3 && (mad3 == 10'd1023))
                O_pwr <= pwr_nxt;      // 末列: 本帧总和
        end
    end

    //==================================================================
    // RAM 端口共用
    //==================================================================
    assign ram_we    = ram_pipe_we ? 1'b1 :
                       (st == ST_ZERO) ? 1'b1 :
                       ((st == ST_STG) ? bf_we : 1'b0);
    assign ram_waddr = ram_pipe_we ? a2 :
                       (st == ST_ZERO) ? za : bf_waddr;
    assign ram_wdata = ram_pipe_we ? {16'd0, prod[27:12]} :
                       (st == ST_ZERO) ? 32'd0 : bf_wdata;
    assign ram_raddr = (st == ST_MAG) ? mag_raddr : bf_raddr;

endmodule

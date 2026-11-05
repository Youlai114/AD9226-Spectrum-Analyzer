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
    //   幅度 >= 16384 (约 -12 dBFS) 才认为有效, 否则 O_hrm_valid=0
    output reg [9:0]  O_hrm_col,        // 基波所在列
    output reg        O_hrm_valid,      // 本帧检测结果有效
    output reg        O_hrm_tog,        // 每次更新翻转一次 (跨时钟域握手)

    // ---- 2~5 次谐波电平 (顶栏 H2..H5 读数): 基波列锁定后的下一帧,
    //      在 k*基波列 ±2 列窗口内取幅度峰 (k 次谐波未必正好落在整数列) ----
    output reg [15:0] O_h2, O_h3, O_h4, O_h5,

    // ---- 宽频模式 (直采, 无抽取): 无箱化倾斜, 补偿切平 ----
    input             I_mag_flat,

    // ---- 窗函数选择 (KEY5 循环): 0=Hann(默认) 1=Rect 2=Blackman 3=FlatTop ----
    input      [1:0]  I_win,

    // ---- 视频平均深度: 1=1/4 (慢档, 帧率低响应优先), 0=1/16 ----
    //   没有平均时噪底是 1~16 的小整数, 对数显示下每跨一个整数跳 3~6dB,
    //   叠加逆 sinc 的平滑上斜就成了"从低频到高频的分段阶梯"。
    //   指数平均 + 4 位小数把噪底估计平滑到 0.1dB 以下。
    input             I_avg_fast,

    // ---- 配置指纹 {span(3), win(2)}: 变化时下一帧重新预装平均 ----
    //   (真实仪器换参数即重启扫描; 否则旧谱以 1/16 指数拖尾混入新谱 ~16 帧)
    input      [4:0]  I_cfg_id
);

    localparam ST_IDLE = 3'd0,
               ST_CAP  = 3'd1,
               ST_STG  = 3'd2,
               ST_MAG  = 3'd3;

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
            O_frame_start <= 1'b0;
        end else begin
            O_cap_start   <= 1'b0;
            frame_kick    <= 1'b0;
            stg_kick      <= 1'b0;
            mag_kick      <= 1'b0;
            O_frame_start <= 1'b0;

            case (st)
            ST_IDLE: begin
                if (I_frame_req) begin
                    st          <= ST_CAP;
                    O_cap_start <= 1'b1;
                    frame_kick  <= 1'b1;
                end
            end
            ST_CAP: begin
                if (cap_done) begin
                    st       <= ST_STG;
                    stg_kick <= 1'b1;
                end
            end
            ST_STG: begin
                if (stg_done) begin
                    st            <= ST_MAG;
                    mag_kick      <= 1'b1;
                    O_frame_start <= 1'b1;
                end
            end
            ST_MAG: begin
                if (mag_done) st <= ST_IDLE;
            end
            default: st <= ST_IDLE;
            endcase
        end
    end

    //==================================================================
    // 采集 + 加窗 (3 级流水)
    //   T  : cap_en=1, 采样 -> s0, 同时给窗地址
    //   T+1: s1 = s0
    //   T+2: hann_w 对应 s1 的样点 -> prod = s1*w
    //   T+3: 写 ram[a2] = prod>>>12
    //==================================================================
    reg  [11:0]        cap_n;
    reg                cap_last;
    reg                v0, v1, v2;
    reg  signed [15:0] s0, s1;
    reg  [11:0]        a0, a1, a2;
    reg  signed [27:0] prod;

    wire cap_en = (st == ST_CAP) && I_smp_en && !cap_last;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            cap_n     <= 12'd0;
            cap_last  <= 1'b0;
            hann_addr <= 12'd0;
            v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0;
            s0 <= 16'sd0; s1 <= 16'sd0;
            a0 <= 12'd0; a1 <= 12'd0; a2 <= 12'd0;
            prod <= 28'sd0;
        end else if (frame_kick) begin
            cap_n    <= 12'd0;
            cap_last <= 1'b0;
            v0 <= 1'b0; v1 <= 1'b0; v2 <= 1'b0;
        end else begin
            v0        <= cap_en;
            s0        <= I_smp;
            a0        <= cap_n;
            hann_addr <= cap_n;
            if (cap_en) begin
                cap_n <= cap_n + 12'd1;
                if (cap_n == N - 1) cap_last <= 1'b1;
            end

            v1 <= v0;
            s1 <= s0;
            a1 <= a0;

            v2   <= v1;
            prod <= s1 * $signed({1'b0, hann_w});   // 与 a2 / v2 同拍有效
            a2   <= a1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)                 cap_done <= 1'b0;
        else if (frame_kick)          cap_done <= 1'b0;
        else if (v2 && (a2 == N - 1)) cap_done <= 1'b1;
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
    //   mph0: 发 bin 2k 地址   mph1: 等
    //   mph2: 收 sq0 + 发 bin 2k+1 地址   mph3: 等
    //   mph4: 收 sq1, 取大       mph5..20: 16 次迭代   mph21: 输出
    //==================================================================
    reg [9:0]  m_cnt;
    reg [4:0]  mph;
    reg [32:0] xq, sq0;
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

    wire [11:0] bin0 = {m_cnt, 1'b0};      // 第 2k 个 bin
    wire [11:0] bin1 = {m_cnt, 1'b1};      // 第 2k+1 个 bin

    wire [18:0] rem2    = {rem[16:0], xq[31:30]};
    wire [18:0] trial19 = {root[15:0], 2'b00} | 19'd1;
    wire        ge      = (rem2 >= trial19);
    wire [28:0] mag_gain = root * gain_r;                // 16bit x 13bit
    wire [21:0] mag_sh   = mag_gain >> 7;                // Q7 归一 (满量程 -> 65535)

    //==================================================================
    // 视频平均 (指数 IIR): avg_mem 1024x21bit (mag x16, 4 位小数)
    //   读: 每列 mph0 发地址, mph2 数据到; 写: mph21 (与 O_mag 同拍), 无端口冲突
    //   首帧 (avg_init=0) 直接装载, 保证 cmp_fft 首帧 0 LSB 不变
    //==================================================================
    reg  [20:0] avg_mem [0:1023];
    reg  [20:0] avg_dat;
    reg  [9:0]  avg_raddr;
    reg         avg_we;
    reg  [9:0]  avg_waddr;
    reg  [20:0] avg_wdata;
    reg         avg_init;                    // 首帧后置 1, 此后走混合
    reg         avg_fast_lat;                // cap_start 锁存 I_avg_fast

    always @(posedge I_clk) avg_dat <= avg_mem[avg_raddr];

    // 饱和后的当前值 (与旧 O_mag 相同口径) -> x16
    wire [15:0] mag_sat  = (mag_sh > 22'h0FFFF) ? 16'hFFFF : mag_sh[15:0];
    wire [21:0] mag_ext  = {6'd0, mag_sat} << 4;
    // diff = mag_ext - avg_dat (凸组合结果必在两者之间, 21bit 内)
    wire signed [22:0] avg_dif = $signed({1'b0, mag_ext[21:0]})
                                - $signed({1'b0, avg_dat});
    wire signed [22:0] avg_dsh = avg_dif >>> (avg_fast_lat ? 2 : 4);
    wire [20:0] avg_new  = avg_init ? (avg_dat + avg_dsh[20:0])
                                    : mag_ext[20:0];
    wire [21:0] avg_rd   = (avg_new + 21'd8) >> 4;            // 四舍五入回整数
    wire [15:0] mag_avg  = (avg_rd > 22'd65535) ? 16'hFFFF : avg_rd[15:0];

    reg [4:0] avg_cfg_lat;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            avg_raddr   <= 10'd0;
            avg_we      <= 1'b0;
            avg_waddr   <= 10'd0;
            avg_wdata   <= 21'd0;
            avg_init    <= 1'b0;
            avg_fast_lat <= 1'b0;
            avg_cfg_lat  <= 5'h1F;
        end else begin
            avg_we <= 1'b0;
            if (O_cap_start) begin
                avg_fast_lat <= I_avg_fast;
                if (I_cfg_id != avg_cfg_lat) begin
                    avg_cfg_lat <= I_cfg_id;
                    avg_init    <= 1'b0;      // 参数变了: 下一帧重新预装
                end
            end
            if (st == ST_MAG) begin
                if (mph == 5'd0)
                    avg_raddr <= m_cnt;
                if (mph == 5'd21) begin
                    avg_we    <= 1'b1;
                    avg_waddr <= m_cnt;
                    avg_wdata <= avg_new;
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
            gain_r     <= 13'd1024;
            base_gain  <= 11'd1024;
            rem        <= 19'd0;
            root       <= 16'd0;
            mag_raddr  <= 12'd0;
            O_mag_en   <= 1'b0;
            O_mag      <= 16'd0;
            O_mag_addr <= 10'd0;
            mag_done   <= 1'b0;
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
                sq0       <= mag_sq;
                mag_raddr <= bitrev12(bin1);
                mph       <= 5'd3;
            end else if (mph == 5'd3) begin
                mph <= 5'd4;
            end else if (mph == 5'd4) begin
                xq     <= (sq0 >= mag_sq) ? sq0 : mag_sq;  // 峰值检波: 取两 bin 较大者
                rem    <= 19'd0;
                root   <= 16'd0;
                gain_r <= gain_prod[19:7];                 // x 窗校准 (Q7 x Q7)
                mph    <= 5'd5;
            end else if (mph <= 5'd20) begin
                rem  <= ge ? (rem2 - trial19) : rem2;
                root <= ge ? {root[14:0], 1'b1} : {root[14:0], 1'b0};
                xq   <= xq << 2;
                mph  <= mph + 5'd1;
            end else begin                        // mph == 21: 输出 (补偿+视频平均)
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
        end else if (mag_kick) begin
            pk_max <= 16'd0;
            h2_max <= 16'd0;  h3_max <= 16'd0;  h4_max <= 16'd0;  h5_max <= 16'd0;
        end else if (O_mag_en) begin
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
                O_hrm_valid <= (pk_max >= 16'd8192);    // -18 dBFS 门限 (方波/小信号也能认基波)
                O_hrm_tog   <= ~O_hrm_tog;
                O_h2 <= h2_max;  O_h3 <= h3_max;
                O_h4 <= h4_max;  O_h5 <= h5_max;
                hcol_lat  <= O_hrm_col;                 // 下一帧的谐波窗口基准
                hcol_vld  <= (pk_max >= 16'd8192);
            end
        end
    end

    //==================================================================
    // RAM 端口共用
    //==================================================================
    wire cap_we = (st == ST_CAP) && v2;

    assign ram_we    = cap_we ? 1'b1 : ((st == ST_STG) ? bf_we : 1'b0);
    assign ram_waddr = cap_we ? a2 : bf_waddr;
    assign ram_wdata = cap_we ? {16'd0, prod[27:12]} : bf_wdata;
    assign ram_raddr = (st == ST_MAG) ? mag_raddr : bf_raddr;

endmodule

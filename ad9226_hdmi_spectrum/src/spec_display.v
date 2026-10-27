// ============================================================================
// spec_display.v  --  频谱分析仪显示子系统 (RIGOL DSA 风格)
//
//   版面 (1280x720):
//     +-----------------------------------------------+----------+
//     | RIGOL  Center Freq: 500.000 kHz   Attn: ...   |  菜单    |  y 0..95
//     | LXI    Span: 1.000000 MHz         RBW: ...    |  按钮    |
//     +-----------------------------------------------+          |
//     | 0 |                                           |  [BW]    |
//     |-10|        /\                                 | [Res BW] |  y 104..615
//     |   |      /    \       黄色迹线 + 黑底网格      | [Avg]    |
//     |-80|                                           | [Scale]  |
//     +-----------------------------------------------+----------+
//     | Center Freq: ...  RBW: ...  VBW: ...  SWT: ...            |  y 624..719
//     +-----------------------------------------------------------+
//
//   文字: 屏幕按 16x16 像素划成 80x45 个单元, 运行时组合解码 (put 任务,
//         字符串与旧 gen_font 版本逐字一致), 省 28 块 pROM
//         (char + color + 字号), 改版面只改 tools/gen_font.py 的布局
//
//   显示流水线共 6 级, video_top 里 de/hs/vs 相应延迟 6 拍
//   数据接口: I_wr_* (写时钟域), 协议见 spec_data_if.v
// ============================================================================
module spec_display (
    input             I_pix_clk    ,
    input             I_pix_rst_n  ,
    input      [11:0] I_x          ,   // 像素列
    input      [11:0] I_y          ,   // 像素行
    input      [2:0]  I_span       ,   // 跨度档 0..4 (1M/250k/50k/10k/27M)
    // ---- 1~5 次谐波标记 (来自 fft4096 的基波峰值检测, 像素时钟域) ----
    input             I_hrm_valid  ,
    input      [9:0]  I_hrm_col    ,   // 基波列, 谐波 k 在 k*I_hrm_col 列
    input      [2:0]  I_hrm_span   ,   // 测量该列时的跨度档; != I_span 时隐藏标记
                                           // (换档后 1~2 帧内旧列不画到新轴上)
                                           // ★ 必须 3 位: 2 位时宽频档(4)截断成 0,
                                           //   与 I_span 比较恒假, F0/谐波表全隐藏
    // ---- 光标 (KEY4 三态: 0=关 1=普通 2=增量; 编码器移动; 像素时钟域) ----
    input             I_csr_en     ,
    input      [1:0]  I_csr_mode   ,   // 2=增量: 读 ΔF/ΔdB, 参考线在进入时刻的光标位
    input      [9:0]  I_csr_col    ,   // 光标列 0..1023
    // ---- 2~5 次谐波电平表 (fft4096 波峰搜索结果, 顶栏第 4 行左侧) ----
    input      [15:0] I_h2,
    input      [15:0] I_h3,
    input      [15:0] I_h4,
    input      [15:0] I_h5,

    // ---- 显示模式 (KEY2 循环): 0=频谱+菜单+瀑布 1=纯净频谱(菜单折叠) ----
    input             I_wf_en      ,   // 1: 绘图区背景显示瀑布图
    input             I_menu_hide  ,   // 1: 右侧菜单折叠成纯黑
    // ---- 窗函数 (KEY5 循环): RBW 显示与菜单 Window 值随窗联动 ----
    input      [1:0]  I_win        ,   // 0=Hann 1=Rect 2=Blackman 3=FlatTop
    // ---- 编码器精细模式 (短按编码器切换): 光标步进 1 列, 顶栏右上加 FINE ----
    input             I_fine       ,
    // ---- 数据写入接口 (与像素时钟可异步) ----
    input             I_wr_clk     ,
    input             I_wr_rst_n   ,
    input             I_frame_start,
    input             I_wr_en      ,
    input      [9:0]  I_wr_addr    ,
    input      [15:0] I_wr_mag     ,
    // ---- 像素输出 ----
    output reg [7:0]  O_r          ,
    output reg [7:0]  O_g          ,
    output reg [7:0]  O_b
);

    //==================================================================
    // 版面参数
    //==================================================================
    localparam [11:0] PX0      = 12'd64;      // 绘图区左边界
    localparam [11:0] PX1      = 12'd1087;    // 绘图区右边界 (1024 列)
    localparam [11:0] PY0      = 12'd104;     // 绘图区上边界
    localparam [11:0] PY1      = 12'd615;     // 绘图区下边界 (512 行)
    localparam [11:0] PANEL_X  = 12'd1104;    // 右侧菜单左边界
    localparam [11:0] TOP_H    = 12'd96;      // 顶栏高度
    localparam [11:0] BOT_Y    = 12'd624;     // 底栏上边界

    // 配色
    localparam [23:0] C_BG      = 24'h00_00_00;
    localparam [23:0] C_CHROME  = 24'h0C_12_1A;
    localparam [23:0] C_PANEL   = 24'h0E_16_22;
    localparam [23:0] C_BTN     = 24'h20_34_52;
    localparam [23:0] C_BTN_HI  = 24'h1B_5F_BF;
    localparam [23:0] C_SEP     = 24'h28_38_50;
    localparam [23:0] C_GRID    = 24'h22_30_40;
    localparam [23:0] C_PLOT_BG = 24'h00_00_00;
    localparam [23:0] C_TRACE   = 24'hFF_D8_00;   // RIGOL 黄
    localparam [23:0] C_PEAK    = 24'hFF_6A_3A;
    localparam [23:0] C_TXT0    = 24'hC8_D8_E8;   // 白
    localparam [23:0] C_TXT1    = 24'h00_E0_50;   // 绿 (F0/谐波表/Span 值;
                                                  //   旧 3C_D8_78 蓝分量偏高, 屏上偏青蓝)
    localparam [23:0] C_TXT2    = 24'h66_E8_FF;   // 青
    localparam [23:0] C_TXT3    = 24'h8C_B8_E8;   // 蓝

    //==================================================================
    // 幅度 -> 对数行坐标 (参考坐标: 10dB/div, 参考 0dB, 6.4 像素/dB)
    //==================================================================
    function [5:0] log_fraclut;
        input [4:0] f;
        begin
            case (f)
                5'd0 : log_fraclut = 6'd0;   5'd1 : log_fraclut = 6'd1;
                5'd2 : log_fraclut = 6'd3;   5'd3 : log_fraclut = 6'd4;
                5'd4 : log_fraclut = 6'd5;   5'd5 : log_fraclut = 6'd7;
                5'd6 : log_fraclut = 6'd8;   5'd7 : log_fraclut = 6'd9;
                5'd8 : log_fraclut = 6'd10;  5'd9 : log_fraclut = 6'd11;
                5'd10: log_fraclut = 6'd13;  5'd11: log_fraclut = 6'd14;
                5'd12: log_fraclut = 6'd15;  5'd13: log_fraclut = 6'd16;
                5'd14: log_fraclut = 6'd17;  5'd15: log_fraclut = 6'd18;
                5'd16: log_fraclut = 6'd19;  5'd17: log_fraclut = 6'd20;
                5'd18: log_fraclut = 6'd21;  5'd19: log_fraclut = 6'd22;
                5'd20: log_fraclut = 6'd22;  5'd21: log_fraclut = 6'd23;
                5'd22: log_fraclut = 6'd24;  5'd23: log_fraclut = 6'd25;
                5'd24: log_fraclut = 6'd26;  5'd25: log_fraclut = 6'd27;
                5'd26: log_fraclut = 6'd27;  5'd27: log_fraclut = 6'd28;
                5'd28: log_fraclut = 6'd29;  5'd29: log_fraclut = 6'd30;
                5'd30: log_fraclut = 6'd31;  default: log_fraclut = 6'd31;
            endcase
        end
    endfunction

    // 前半: 最高有效位位置 k + 5bit 尾数 f
    function [8:0] log_split;
        input [15:0] mag;
        reg [3:0] k;
        reg [4:0] f;
        begin
            if      (mag[15]) k = 4'd15;
            else if (mag[14]) k = 4'd14;
            else if (mag[13]) k = 4'd13;
            else if (mag[12]) k = 4'd12;
            else if (mag[11]) k = 4'd11;
            else if (mag[10]) k = 4'd10;
            else if (mag[9])  k = 4'd9;
            else if (mag[8])  k = 4'd8;
            else if (mag[7])  k = 4'd7;
            else if (mag[6])  k = 4'd6;
            else if (mag[5])  k = 4'd5;
            else if (mag[4])  k = 4'd4;
            else if (mag[3])  k = 4'd3;
            else if (mag[2])  k = 4'd2;
            else if (mag[1])  k = 4'd1;
            else              k = 4'd0;

            case (k)
                4'd0 : f = 5'd0;
                4'd1 : f = (mag - 16'd2)  << 4;
                4'd2 : f = (mag - 16'd4)  << 3;
                4'd3 : f = (mag - 16'd8)  << 2;
                4'd4 : f = (mag - 16'd16) << 1;
                4'd5 : f = mag[4:0];
                default : f = (mag >> (k - 4'd5)) & 5'h1F;
            endcase

            log_split = {k, f};
        end
    endfunction

    // 后半: log2 定点 -> 参考行坐标
    function [9:0] log_row;
        input [3:0] k;
        input [4:0] f;
        reg [5:0]  lg;
        reg [9:0]  lv, x, r;
        begin
            lg = log_fraclut(f);
            lv = {k, 5'd0} + {4'd0, lg};
            x  = 10'd511 - lv;
            r  = x + (x >> 3) + (x >> 4) + (x >> 6);   // x * 1.203125
            log_row = (r > 10'd511) ? 10'd511 : r;
        end
    endfunction


    //==================================================================
    // 数据通路: 写接口 -> 乒乓缓存 -> 读
    //==================================================================
    wire        wr_en;
    wire        wr_bank;
    wire [9:0]  wr_addr;
    wire [15:0] wr_mag;
    wire        rd_bank;

    spec_data_if u_data_if (
        .I_wr_clk      (I_wr_clk      ),
        .I_wr_rst_n    (I_wr_rst_n    ),
        .I_frame_start (I_frame_start ),
        .I_wr_en       (I_wr_en       ),
        .I_wr_addr     (I_wr_addr     ),
        .I_wr_mag      (I_wr_mag      ),
        .I_rd_clk      (I_pix_clk     ),
        .I_rd_rst_n    (I_pix_rst_n   ),
        .O_wr_en       (wr_en         ),
        .O_wr_bank     (wr_bank       ),
        .O_wr_addr     (wr_addr       ),
        .O_wr_mag      (wr_mag        ),
        .O_rd_bank     (rd_bank       ),
        .O_frame_cnt   (              ),
        .O_frame_tog   (              )
    );

    // 像素列 -> 频点地址 (绘图区内恰好 1024 列)
    wire [9:0] bin_addr = I_x[9:0] - 10'd64;

    wire [15:0] mag_ram;

    spec_ram u_spec_ram (
        .I_wr_clk  (I_wr_clk  ),
        .I_wr_en   (wr_en     ),
        .I_wr_bank (wr_bank   ),
        .I_wr_addr (wr_addr   ),
        .I_wr_data (wr_mag    ),
        .I_rd_clk  (I_pix_clk ),
        .I_rd_bank (rd_bank   ),
        .I_rd_addr (bin_addr  ),
        .O_rd_data (mag_ram   )
    );

    //==================================================================
    // 峰值保持
    //==================================================================
    reg [15:0] peak_mem [0:1023];
    reg [15:0] peak_ram;

    always @(posedge I_pix_clk) begin
        peak_ram <= peak_mem[bin_addr];
    end

    // mag_ram/peak_ram 是 1 拍后的数据, 对应的是上一拍的地址
    // 所以写入地址也要延一拍, 否则 peak[k] 会拿到 mag[k-1], 峰值线被"拖"成下坡
    wire pk_upd = (I_y == PY0) && (I_x >= PX0) && (I_x <= PX1);
    reg        pk_upd_d;
    reg [9:0]  bin_d;
    reg        pk_ready;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            pk_upd_d <= 1'b0;  bin_d <= 10'd0;  pk_ready <= 1'b0;
        end else begin
            pk_upd_d <= pk_upd;
            bin_d    <= bin_addr;
            if (pk_upd_d && (bin_d == 10'd1023))        // 第一帧装载完成
                pk_ready <= 1'b1;
        end
    end

    wire [15:0] peak_ref = pk_ready ? peak_ram : 16'd0;
    wire [15:0] pk_decay = (peak_ref >> 6) | 16'd1;
    wire [15:0] pk_new   = (mag_ram >= peak_ref) ? mag_ram : (peak_ref - pk_decay);

    always @(posedge I_pix_clk) begin
        if (pk_upd_d)
            peak_mem[bin_d] <= pk_new;
    end

    //==================================================================
    // 瀑布图: 256 列 x 128 行 x 3bit 色阶, 环形滚动 (新行在顶)
    //   写侧 (I_wr_clk 域): 幅度流 4:1 峰值降采样 -> log 后取 3bit 色阶
    //   读侧 (像素域):      只占绘图区底部 128 行 (1/4), 上 3/4 黑底网格;
    //                       显示行 d = yr-384, 历史行 = (wrow-1-d) mod 128
    //   RAM  98kbit = 6 块 BSRAM (twiddle 压缩省出的额度)
    //==================================================================
    reg [2:0] wf_mem [0:32767];         // {行[6:0], 列[7:0]}
    reg [2:0] wf_rdata;

    reg [1:0]  wf_cnt;                  // 4:1 降采样计数
    reg [15:0] wf_max, wf_max_r;        // 4 列峰值
    reg [7:0]  wf_col_r;
    reg        wf_we_r, wf_we;
    reg [14:0] wf_waddr;
    reg [2:0]  wf_wdata;
    reg [6:0]  wf_wrow;                 // 写行指针 (帧末 +1)
    reg        wf_full;                 // 首轮绕完后整屏有效

    wire [8:0]  wf_lg   = log_split(wf_max_r);
    wire [9:0]  wf_lrow = log_row(wf_lg[8:5], wf_lg[4:0]);
    wire [2:0]  wf_cidx = 3'd7 - wf_lrow[8:6];      // 0dB->7(白), -70dB 以下->0(黑)

    always @(posedge I_wr_clk or negedge I_wr_rst_n) begin
        if (!I_wr_rst_n) begin
            wf_cnt <= 2'd0;  wf_max <= 16'd0;  wf_max_r <= 16'd0;
            wf_col_r <= 8'd0;  wf_we_r <= 1'b0;  wf_we <= 1'b0;
            wf_waddr <= 15'd0;  wf_wdata <= 3'd0;
            wf_wrow <= 7'd0;  wf_full <= 1'b0;
        end else begin
            wf_we_r <= 1'b0;  wf_we <= 1'b0;
            if (I_wr_en) begin
                wf_max <= (wf_cnt == 2'd3) ? 16'd0
                        : ((I_wr_mag > wf_max) ? I_wr_mag : wf_max);
                wf_cnt <= wf_cnt + 2'd1;
                if (wf_cnt == 2'd3) begin
                    wf_we_r  <= 1'b1;
                    wf_max_r <= (I_wr_mag > wf_max) ? I_wr_mag : wf_max;
                    wf_col_r <= I_wr_addr[9:2];
                end
                if (I_wr_addr == 10'd1023) begin
                    wf_wrow <= wf_wrow + 7'd1;
                    if (wf_wrow == 7'd127)           // 128 帧绕满, 整屏有效
                        wf_full <= 1'b1;
                end
            end
            wf_we    <= wf_we_r;
            wf_waddr <= {wf_wrow, wf_col_r};
            wf_wdata <= wf_cidx;
        end
    end

    always @(posedge I_wr_clk) begin
        if (wf_we) wf_mem[wf_waddr] <= wf_wdata;
    end

    // 读侧行指针同步 (2 级), 首轮绕满前只显示已写行
    reg [6:0] wf_rrow_s0, wf_rrow_s1;
    reg       wf_full_s0, wf_full_s1;

    always @(posedge I_pix_clk) begin
        wf_rrow_s0 <= wf_wrow;   wf_rrow_s1 <= wf_rrow_s0;
        wf_full_s0 <= wf_full;   wf_full_s1 <= wf_full_s0;
    end

    //==================================================================
    // 光标读数 (KEY4 开关, 编码器移动, 见 video_top)
    //   扫描经过光标列时抓一次该列幅度 (与迹线同源, 上一帧的值),
    //   每帧用小 double-dabble FSM 把 频率(Hz)/幅度(0.1dB) 转成 BCD。
    //==================================================================
    reg [15:0] csr_mag;

    always @(posedge I_pix_clk) begin
        if (pk_upd_d && (bin_d == I_csr_col))
            csr_mag <= mag_ram;
    end

    function [51:0] dabble;                    // 一步 double-dabble: >=5 的 BCD 位 +3 再整体左移
        input [51:0] d;
        reg [51:0] r;
        integer i;
        begin
            r = d;
            for (i = 0; i < 8; i = i + 1)
                if (r[20 + 4*i +: 4] > 4'd4)
                    r[20 + 4*i +: 4] = r[20 + 4*i +: 4] + 4'd3;
            dabble = {r[50:0], 1'b0};
        end
    endfunction

    reg  [51:0] dd;
    reg  [5:0]  dd_cnt;
    reg  [3:0]  dd_ph;                           // 0..6: IDLE/FREQ/DB/H2..H5
    localparam [3:0] DP_IDLE = 4'd0, DP_FREQ = 4'd1, DP_DB = 4'd2,
                     DP_H2 = 4'd3, DP_H3 = 4'd4, DP_H4 = 4'd5, DP_H5 = 4'd6,
                     DP_F0 = 4'd7;

    reg [19:0] freq_val;                       // 光标处频率 (Hz)
    reg [11:0] db_abs;                         // |dB| x10 (0..964)
    reg [23:0] freq_bcd;                       // 6 位 BCD (d5..d0)
    reg [15:0] db_bcd;                         // 4 位 BCD

    // 谐波电平表: 4 路 dBFS x10, 两级流水 (单拍 log+乘 -3.8ns 违例, 拆开即过;
    //   值每帧才变一次, 多两拍延迟无影响)
    reg [8:0] h2_lg_r, h3_lg_r, h4_lg_r, h5_lg_r;
    always @(posedge I_pix_clk) begin
        h2_lg_r <= log_split(I_h2);
        h3_lg_r <= log_split(I_h3);
        h4_lg_r <= log_split(I_h4);
        h5_lg_r <= log_split(I_h5);
    end
    wire signed [9:0] h2_lm = $signed({1'b0, h2_lg_r}) - 10'sd512;
    wire signed [9:0] h3_lm = $signed({1'b0, h3_lg_r}) - 10'sd512;
    wire signed [9:0] h4_lm = $signed({1'b0, h4_lg_r}) - 10'sd512;
    wire signed [9:0] h5_lm = $signed({1'b0, h5_lg_r}) - 10'sd512;
    reg [10:0] h2_db, h3_db, h4_db, h5_db;
    always @(posedge I_pix_clk) begin
        h2_db <= -((21'sd1927 * h2_lm) >>> 10);
        h3_db <= -((21'sd1927 * h3_lm) >>> 10);
        h4_db <= -((21'sd1927 * h4_lm) >>> 10);
        h5_db <= -((21'sd1927 * h5_lm) >>> 10);
    end
    reg  [11:0] h2_bcd, h3_bcd, h4_bcd, h5_bcd;

    // 基波频率大读数 F0 (顶栏第 2 行右侧, 与 MKR 同一刻度; 数据同谐波标记)
    wire [34:0] f0_prod   = I_hrm_col * span_hz20(I_span);
    wire [24:0] f0_prod_k = I_hrm_col * 15'd27000;
    wire [19:0] f0_freq   = (I_span == 3'd4) ? {5'd0, f0_prod_k[24:10]}
                                             : f0_prod[34:10];
    reg  [19:0] f0_val;
    reg  [23:0] f0_bcd;

    function [24:0] span_hz20;                 // 每档跨度 (与 auto_span.v 一致)
        input [2:0] s;
        begin
            case (s)
            3'd0:    span_hz20 = 25'd1000000;
            3'd1:    span_hz20 = 25'd250000;
            3'd2:    span_hz20 = 25'd50000;
            3'd3:    span_hz20 = 25'd10000;
            default: span_hz20 = 25'd27000000; // 宽频档
            endcase
        end
    endfunction

    wire         csr_kick = (I_x == 12'd0) && (I_y == 12'd0);   // 每帧一次
    // 宽频档 27MHz 超出 6 位 Hz 读数, 改显示 kHz (col x 27000 >> 10, 最大 26999)
    // 读数计算已改为流水线 (见下方 增量光标 段), csr_freq/dfreq 均取自寄存值


    // 幅度 -> 0.1dB 单位: db = 6.02 x (log2(mag)-16),
    //   用 log_split 的 k+f/32 近似: db10 = 1.8814 x (32k+f-512), 恒为负
    //   ★ log_split 是 16 级优先链, 后面还挂乘法 —— 打一拍寄存打断,
    //     csr_mag 整帧稳定, 多这一拍毫无影响 (否则这是全设计最差路径)
    reg [8:0] csr_lg_r;

    always @(posedge I_pix_clk) csr_lg_r <= log_split(csr_mag);

    wire signed [9:0]  csr_lm    = $signed({1'b0, csr_lg_r}) - 10'sd512;
    wire signed [20:0] csr_db10  = (21'sd1927 * csr_lm) >>> 10;
    wire [10:0]        csr_dbabs = -csr_db10;                   // 0..964

    //------------------------------------------------------------------
    // 增量光标: 进入模式 2 的瞬间快照 (参考列 + 参考幅度),
    //   读数 = 当前 - 参考 (ΔF 由列差 x 跨度算, ΔdB 由两幅度 dB 值相减)
    //------------------------------------------------------------------
    reg  [9:0]  csr_ref_col;
    reg  [10:0] csr_ref_db;
    reg  [1:0]  csr_mode_d;
    reg         dfr_sign, ddb_sign;      // 打进 BCD FSM 前的符号 (供字符层)

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            csr_ref_col <= 10'd0;
            csr_ref_db  <= 11'd0;
            csr_mode_d  <= 2'd0;
        end else begin
            csr_mode_d <= I_csr_mode;
            if (I_csr_mode == 2'd2 && csr_mode_d == 2'd1) begin
                csr_ref_col <= I_csr_col;      // 快照时刻 csr_mag 即参考列幅度
                csr_ref_db  <= csr_dbabs;
            end
        end
    end

    wire signed [10:0] dcol_s = $signed({1'b0, I_csr_col})
                               - $signed({1'b0, csr_ref_col});
    wire        [10:0] ddb_s  = csr_dbabs - csr_ref_db;   // 差恒 |..|<=964

    // ★ 读数流水线: csr_col -> 减法/绝对值 -> 乘法 -> 装载 dd 原本是一条 18.1ns
    //   的纯组合链 (时序违例 -2.44ns, 77 个端点), 现拆成两级:
    //     S1 寄存列号/跨度/列差/幅度差  ->  S2 寄存乘法结果  ->  帧首装载 dd
    //   读数只在 csr_kick (每帧第一个像素) 采样一次, 多两拍无任何可见影响
    reg  [9:0]  csr_col_s1;
    reg  [2:0]  span_s1, span_s2;
    reg  [10:0] dcol_s_s1, ddb_s_s1;
    reg  [34:0] csr_prod_s2, dprod_s2;
    reg  [24:0] csr_prod_k_s2, dprod_k_s2;

    wire        [10:0] dcol_a = dcol_s_s1[10] ? (-dcol_s_s1) : dcol_s_s1;
    wire        [10:0] ddb_a  = ddb_s_s1[10]  ? (-ddb_s_s1)  : ddb_s_s1;
    wire        [34:0] csr_prod_p   = csr_col_s1 * span_hz20(span_s1);
    wire        [24:0] csr_prod_k_p = csr_col_s1 * 15'd27000;
    wire        [34:0] dprod_p      = dcol_a * span_hz20(span_s1);
    wire        [24:0] dprod_k_p    = dcol_a * 15'd27000;

    always @(posedge I_pix_clk) begin
        csr_col_s1 <= I_csr_col;
        span_s1    <= I_span;
        dcol_s_s1  <= dcol_s;
        ddb_s_s1   <= ddb_s;
        // 第二级: 乘法 (宽频档同用 kHz 刻度)
        span_s2       <= span_s1;
        csr_prod_s2   <= csr_prod_p;
        csr_prod_k_s2 <= csr_prod_k_p;
        dprod_s2      <= dprod_p;
        dprod_k_s2    <= dprod_k_p;
    end

    wire [19:0] csr_freq = (span_s2 == 3'd4) ? {5'd0, csr_prod_k_s2[24:10]}
                                             : csr_prod_s2[34:10];
    wire [19:0] dfreq    = (span_s2 == 3'd4) ? {5'd0, dprod_k_s2[24:10]}
                                             : dprod_s2[34:10];

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            dd <= 52'd0;  dd_cnt <= 6'd0;  dd_ph <= DP_IDLE;
            freq_val <= 20'd0;  db_abs <= 12'd0;
            freq_bcd <= 24'd0;  db_bcd <= 16'd0;
        end else begin
            case (dd_ph)
            // 光标关着也要跑: 谐波表/F0 读数依赖这条 BCD 链
            DP_IDLE: if (csr_kick && (I_csr_en || I_hrm_valid)) begin
                if (I_csr_mode == 2'd2) begin
                    freq_val <= dfreq;
                    db_abs   <= {1'b0, ddb_a};
                    dd       <= {32'd0, dfreq};
                    dfr_sign <= dcol_s_s1[10];
                    ddb_sign <= ddb_s_s1[10];
                end else begin
                    freq_val <= csr_freq;
                    db_abs   <= csr_dbabs;
                    dd       <= {32'd0, csr_freq};
                    dfr_sign <= 1'b0;
                    ddb_sign <= 1'b1;          // 普通模式幅度恒为负 (0dBFS 满量程)
                end
                dd_cnt <= 6'd20;
                dd_ph  <= DP_FREQ;
            end
            DP_FREQ: begin
                if (dd_cnt == 6'd0) begin
                    freq_bcd <= dd[43:20];             // 20 步后的 6 位 BCD
                    dd       <= {32'd0, db_abs};
                    dd_cnt   <= 6'd20;                 // 与频率相同: 必须走满 20 位
                    dd_ph    <= DP_DB;
                end else begin
                    dd     <= dabble(dd);
                    dd_cnt <= dd_cnt - 6'd1;
                end
            end
            DP_DB: begin
                if (dd_cnt == 6'd0) begin
                    db_bcd <= dd[35:20];               // 4 位 BCD
                    dd     <= {32'd0, 8'd0, h2_db};    // 接着转 H2 (帧内时间充裕)
                    dd_cnt <= 6'd20;
                    dd_ph  <= DP_H2;
                end else begin
                    dd     <= dabble(dd);
                    dd_cnt <= dd_cnt - 6'd1;
                end
            end
            DP_H2: begin
                if (dd_cnt == 6'd0) begin
                    h2_bcd <= dd[31:20];               // 3 位 BCD (0..964)
                    dd     <= {32'd0, 8'd0, h3_db};
                    dd_cnt <= 6'd20;
                    dd_ph  <= DP_H3;
                end else begin dd <= dabble(dd); dd_cnt <= dd_cnt - 6'd1; end
            end
            DP_H3: begin
                if (dd_cnt == 6'd0) begin
                    h3_bcd <= dd[31:20];
                    dd     <= {32'd0, 8'd0, h4_db};
                    dd_cnt <= 6'd20;
                    dd_ph  <= DP_H4;
                end else begin dd <= dabble(dd); dd_cnt <= dd_cnt - 6'd1; end
            end
            DP_H4: begin
                if (dd_cnt == 6'd0) begin
                    h4_bcd <= dd[31:20];
                    dd     <= {32'd0, 8'd0, h5_db};
                    dd_cnt <= 6'd20;
                    dd_ph  <= DP_H5;
                end else begin dd <= dabble(dd); dd_cnt <= dd_cnt - 6'd1; end
            end
            DP_H5: begin
                if (dd_cnt == 6'd0) begin
                    h5_bcd <= dd[31:20];
                    dd     <= {32'd0, f0_freq};
                    dd_cnt <= 6'd20;
                    dd_ph  <= DP_F0;
                end else begin dd <= dabble(dd); dd_cnt <= dd_cnt - 6'd1; end
            end
            DP_F0: begin
                if (dd_cnt == 6'd0) begin
                    f0_bcd <= dd[43:20];
                    f0_val <= f0_freq;
                    dd_ph  <= DP_IDLE;
                end else begin dd <= dabble(dd); dd_cnt <= dd_cnt - 6'd1; end
            end
            default: dd_ph <= DP_IDLE;
            endcase
        end
    end

    //==================================================================
    // 第 1 级: 字符网格 ROM (80 x 45 单元, 3 个量程层)
    //==================================================================
    wire [5:0]  cell_row = I_y[9:4];                 // 0..44
    wire [6:0]  cell_col = I_x[10:4];                // 0..79
    wire [11:0] cell_idx = (cell_row << 6) + (cell_row << 4) + cell_col;

    //------------------------------------------------------------------
    // 文字解码 (运行时组合, 代替 28 块 pROM 的 ui_text_rom):
    //   80x45 单元格 -> {color[1:0], ch[7:0]}, 打一拍进原文字管线, 与旧
    //   ROM 版逐像素相同 (cell_idx 不再需要)。字符串与 gen_font.py 的
    //   layer() 逐字一致, 改版面直接改这里的 put() 调用。
    //------------------------------------------------------------------
    reg [7:0] t_ch;
    reg [1:0] t_co;

    // 参数顺序与 gen_font.py 的 put(列, 行, ...) 一致, 调用可直接照抄
    task put;
        input integer c0;
        input integer r0;
        input integer len;
        input [287:0] s;                   // 最多 36 字符
        input [1:0]   colr;
        integer i;
        begin
            if ((cell_row == r0[5:0]) && (cell_col >= c0[7:0]) &&
                (cell_col < c0[7:0] + len[7:0])) begin
                i    = (len - 1) - (cell_col - c0);
                t_ch = s[i*8 +: 8];
                t_co = colr;
            end
        end
    endtask

    //------------------------------------------------------------------
    // RBW 随窗联动: ENBW 因子 Rect 1.0 / Hann 1.5 / Blackman 1.73 / FlatTop 3.77
    //   RBW = 因子 x fs/4096, 三个显示位置共用一组字符串
    //------------------------------------------------------------------
    reg [287:0] rbw_s;
    reg [3:0]   rbw_len;
    // ★ 寄存一拍切断 O_span->RBW 选择->行解码 的长组合链 (值仅按键时变,
    //   延迟一帧不可见; 否则该链是全设计最差路径)
    reg [287:0] rbw_s_r;
    reg [3:0]   rbw_len_r;
    always @(posedge I_pix_clk) begin
        rbw_s_r   <= rbw_s;
        rbw_len_r <= rbw_len;
    end

    // 窗名: 菜单值 + 底栏 Win:
    reg [287:0] win_name;      // 菜单 4~5 字符
    reg [3:0]   win_len;
    reg [287:0] win_long;      // 底栏 "Hann " 等 (统一 5 字符, 底栏 len 固定 10)
    reg [287:0] win_name_r, win_long_r;
    reg [3:0]   win_len_r;
    always @(posedge I_pix_clk) begin
        win_name_r <= win_name;
        win_long_r <= win_long;
        win_len_r  <= win_len;
    end

    // ★ case 值 = {I_win, I_span} 即 win*8+span (span 是低 3 位), 每窗占 8 个
    //   值域; 此前误写成每窗 5 个连排, Rect@1M 落到 "7.3 Hz" 行 (上板实测抓到)
    always @(I_win or I_span) begin
        case ({I_win, I_span})
        // Hann: ENBW 1.5 x fs/4096
        5'd00: begin rbw_s = "732 Hz";    rbw_len = 4'd6;  end  // Hann  @1M
        5'd01: begin rbw_s = "183 Hz";    rbw_len = 4'd6;  end
        5'd02: begin rbw_s = "36.6 Hz";   rbw_len = 4'd7;  end
        5'd03: begin rbw_s = "7.3 Hz";    rbw_len = 4'd6;  end
        5'd04: begin rbw_s = "19.78 kHz"; rbw_len = 4'd9;  end
        // Rect: ENBW 1.0
        5'd08: begin rbw_s = "488 Hz";    rbw_len = 4'd6;  end  // Rect  @1M
        5'd09: begin rbw_s = "122 Hz";    rbw_len = 4'd6;  end
        5'd10: begin rbw_s = "24.4 Hz";   rbw_len = 4'd7;  end
        5'd11: begin rbw_s = "4.9 Hz";    rbw_len = 4'd6;  end
        5'd12: begin rbw_s = "13.18 kHz"; rbw_len = 4'd9;  end
        // Blackman: ENBW 1.73
        5'd16: begin rbw_s = "843 Hz";    rbw_len = 4'd6;  end  // Black @1M
        5'd17: begin rbw_s = "211 Hz";    rbw_len = 4'd6;  end
        5'd18: begin rbw_s = "42.2 Hz";   rbw_len = 4'd7;  end
        5'd19: begin rbw_s = "8.4 Hz";    rbw_len = 4'd6;  end
        5'd20: begin rbw_s = "22.77 kHz"; rbw_len = 4'd9;  end
        // FlatTop: ENBW 3.77
        5'd24: begin rbw_s = "1.84 kHz";  rbw_len = 4'd8;  end  // Flat  @1M
        5'd25: begin rbw_s = "460 Hz";    rbw_len = 4'd6;  end
        5'd26: begin rbw_s = "92.0 Hz";   rbw_len = 4'd7;  end
        5'd27: begin rbw_s = "18.4 Hz";   rbw_len = 4'd7;  end
        5'd28: begin rbw_s = "49.70 kHz"; rbw_len = 4'd9;  end
        default: begin rbw_s = "732 Hz";  rbw_len = 4'd6;  end
        endcase
    end

    always @(I_win) begin
        case (I_win)
        2'd0: begin win_name = "HANN";  win_len = 4'd4;  win_long = "Hann "; end
        2'd1: begin win_name = "RECT";  win_len = 4'd4;  win_long = "Rect "; end
        2'd2: begin win_name = "BLACK"; win_len = 4'd5;  win_long = "Black"; end
        default: begin win_name = "FLAT"; win_len = 4'd4; win_long = "Flat "; end
        endcase
    end

    // ★ 按 cell_row 分组 (case 并行), 行内最多 5 个 put —— 否则 40 个顺序 put
    //   构成 12 级优先链, 是全设计最差路径 (put 参数 = (列, 行) 与 gen_font 一致)
    always @(cell_row or cell_col or I_span or I_fine or rbw_s_r or rbw_len_r
             or win_name_r or win_len_r or win_long_r) begin
        t_ch = 8'd0;
        t_co = 2'd0;
        case (cell_row)
        6'd0: if (I_fine) put(76, 0, 4, "FINE", 2'd2);
        6'd1: begin
            put( 1, 1,  8, "SPECTRUM", 2'd2);
            put(11, 1, 12, "Center Freq:", 2'd0);
            case (I_span)
            3'd0:    put(24, 1, 11, "500.000 kHz", 2'd1);
            3'd1:    put(24, 1, 11, "125.000 kHz", 2'd1);
            3'd2:    put(24, 1, 10, "25.000 kHz", 2'd1);
            3'd3:    put(24, 1,  9, "5.000 kHz", 2'd1);
            default: put(24, 1, 10, "13.500 MHz", 2'd1);
            endcase
            put(37, 1, 10, "Ref Level:", 2'd0);
            put(48, 1,  9, "0.00 dBFS", 2'd1);
        end
        6'd3: begin
            put( 1, 3, 8, "ANALYZER", 2'd2);
            put(11, 3, 5, "Span:", 2'd0);
            case (I_span)
            3'd0:    put(24, 3,  9, "1.000 MHz", 2'd1);
            3'd1:    put(24, 3, 11, "250.000 kHz", 2'd1);
            3'd2:    put(24, 3, 10, "50.000 kHz", 2'd1);
            3'd3:    put(24, 3, 10, "10.000 kHz", 2'd1);
            default: put(24, 3, 10, "27.000 MHz", 2'd1);
            endcase
            put(38, 3, 4, "RBW:", 2'd0);
            put(48, 3, {1'b0, rbw_len_r}, rbw_s_r, 2'd1);
        end
        6'd6:  put(0, 6, 4, "   0", 2'd0);
        6'd8:  put(74, 8, 2, "BW", 2'd3);
        6'd10: put(0, 10, 4, " -10", 2'd0);
        6'd13: put(71, 13, 6, "Res BW", 2'd3);
        6'd14: begin
            put(0, 14, 4, " -20", 2'd0);
            put(69, 14, {1'b0, rbw_len_r}, rbw_s_r, 2'd3);
        end
        6'd18: begin
            put(0, 18, 4, " -30", 2'd0);
            put(71, 18, 6, "Window", 2'd3);
        end
        6'd19: put(71, 19, {1'b0, win_len_r}, win_name_r, 2'd3);
        6'd22: put(0, 22, 4, " -40", 2'd0);
        6'd23: put(71, 23, 8, "Detector", 2'd3);
        6'd24: put(71, 24, 8, "Pos Peak", 2'd3);
        6'd26: put(0, 26, 4, " -50", 2'd0);
        6'd28: put(72, 28, 5, "Trace", 2'd3);
        6'd29: put(69, 29, 11, "Clear Write", 2'd3);
        6'd30: put(0, 30, 4, " -60", 2'd0);
        6'd33: put(74, 33, 3, "Avg", 2'd3);
        6'd34: begin
            put(0, 34, 4, " -70", 2'd0);
            put(75, 34, 1, "1", 2'd3);
        end
        6'd38: begin
            put(0, 38, 4, " -80", 2'd0);
            put(5, 38, 4, "dBFS", 2'd0);
            put(72, 38, 4, "Span", 2'd3);
        end
        6'd39: begin
            case (I_span)
            3'd0: begin
                put( 4, 39, 1, "0", 2'd0);
                put(18, 39, 4, "250k", 2'd0);
                put(34, 39, 4, "500k", 2'd0);
                put(50, 39, 4, "750k", 2'd0);
                put(65, 39, 2, "1M", 2'd0);
            end
            3'd1: begin
                put( 4, 39, 1, "0", 2'd0);
                put(18, 39, 5, "62.5k", 2'd0);
                put(34, 39, 4, "125k", 2'd0);
                put(49, 39, 6, "187.5k", 2'd0);
                put(63, 39, 4, "250k", 2'd0);
            end
            3'd2: begin
                put( 4, 39, 1, "0", 2'd0);
                put(18, 39, 5, "12.5k", 2'd0);
                put(35, 39, 3, "25k", 2'd0);
                put(50, 39, 5, "37.5k", 2'd0);
                put(64, 39, 3, "50k", 2'd0);
            end
            3'd3: begin
                put( 4, 39, 1, "0", 2'd0);
                put(18, 39, 4, "2.5k", 2'd0);
                put(35, 39, 2, "5k", 2'd0);
                put(50, 39, 4, "7.5k", 2'd0);
                put(64, 39, 3, "10k", 2'd0);
            end
            default: begin
                put( 4, 39, 1, "0", 2'd0);
                put(18, 39, 5, "6.75M", 2'd0);
                put(34, 39, 5, "13.5M", 2'd0);
                put(49, 39, 6, "20.25M", 2'd0);
                put(64, 39, 3, "27M", 2'd0);
            end
            endcase
        end
        6'd40: begin
            case (I_span)
            3'd0:    put( 1, 40, 13, "SWT: 2.048 ms", 2'd0);
            3'd1:    put( 1, 40, 13, "SWT: 8.192 ms", 2'd0);
            3'd2:    put( 1, 40, 14, "SWT: 40.960 ms", 2'd0);
            3'd3:    put( 1, 40, 15, "SWT: 204.800 ms", 2'd0);
            default: put( 1, 40, 12, "SWT: 75.9 us", 2'd0);
            endcase
            put(17, 40, 11, "Start: 0 Hz", 2'd0);
            case (I_span)
            3'd0:    put(29, 40, 15, "Stop: 1.000 MHz", 2'd0);
            3'd1:    put(29, 40, 17, "Stop: 250.000 kHz", 2'd0);
            3'd2:    put(29, 40, 16, "Stop: 50.000 kHz", 2'd0);
            3'd3:    put(29, 40, 16, "Stop: 10.000 kHz", 2'd0);
            default: put(29, 40, 16, "Stop: 27.000 MHz", 2'd0);
            endcase
            put(47, 40, 13, "Det: Pos Peak", 2'd0);
            case (I_span)
            3'd0:    put(69, 40, 5, "1 MHz", 2'd3);
            3'd1:    put(69, 40, 7, "250 kHz", 2'd3);
            3'd2:    put(69, 40, 6, "50 kHz", 2'd3);
            3'd3:    put(69, 40, 6, "10 kHz", 2'd3);
            default: put(69, 40, 6, "27 MHz", 2'd3);
            endcase
        end
        6'd42: begin
            // 底栏三处都是 "标签 + 值": put 从高字节往低字节读, 所以标签必须
            // 拼在值的**高位**且整体右对齐到 bit0, 不能靠 <<40 去挪 (旧写法
            // 把标签顶到 288bit 之外, 屏幕上只剩 "Hann" 丢了 "Win: ")
            put( 1, 42, 10, {"Win: ", win_long_r[39:0]}, 2'd0);
            put(12, 42, 10, "NFFT: 4096", 2'd0);
            case (I_span)
            3'd0:    put(23, 42, 15, "Span: 1.000 MHz", 2'd0);
            3'd1:    put(23, 42, 17, "Span: 250.000 kHz", 2'd0);
            3'd2:    put(23, 42, 16, "Span: 50.000 kHz", 2'd0);
            3'd3:    put(23, 42, 16, "Span: 10.000 kHz", 2'd0);
            default: put(23, 42, 16, "Span: 27.000 MHz", 2'd0);
            endcase
            put(43, 42, 5, "RBW: ", 2'd0);
            put(48, 42, {1'b0, rbw_len_r}, rbw_s_r, 2'd0);
        end
        6'd43: put(74, 43, 3, "1/2", 2'd3);
        default: ;
        endcase
    end

    reg [10:0] map_d;                                // {scale=0, color[1:0], ch[7:0]}

    always @(posedge I_pix_clk) map_d <= {1'b0, t_co, t_ch};

    //------------------------------------------------------------------
    // 光标读数字符: 顶栏第 4 行 (y=64..79, ROM 里整行为空) 的 22 个单元
    //   "MKR NNNNNN HZ -NN.N DB", 频率前导零消隐, dB 十位为 0 时消隐
    //   cell:  57..59=MKR  61..66=频率  68..69=HZ  71=负号  72..75=dB  77..78=DB
    //------------------------------------------------------------------
    wire csr_cell = I_csr_en && (cell_row == 6'd4) &&
                    (cell_col >= 7'd57) && (cell_col <= 7'd78);

    wire fv5 = (freq_val >= 20'd100000);
    wire fv4 = (freq_val >= 20'd10000);
    wire fv3 = (freq_val >= 20'd1000);
    wire fv2 = (freq_val >= 20'd100);
    wire fv1 = (freq_val >= 20'd10);

    reg [7:0] csr_ch;

    always @(freq_val or freq_bcd or db_bcd or cell_col or I_span
             or I_csr_mode or dfr_sign or ddb_sign) begin
        csr_ch = 8'd0;
        case (cell_col)
        7'd57: csr_ch = (I_csr_mode == 2'd2) ? "D" : "M";
        7'd58: csr_ch = (I_csr_mode == 2'd2) ? "L" : "K";
        7'd59: csr_ch = (I_csr_mode == 2'd2) ? "T" : "R";
        7'd60: csr_ch = (I_csr_mode == 2'd2) ? (dfr_sign ? "-" : "+") : 8'd32;
        7'd61: csr_ch = fv5 ? 8'h30 + {4'd0, freq_bcd[23:20]} : 8'd32;
        7'd62: csr_ch = fv4 ? 8'h30 + {4'd0, freq_bcd[19:16]} : 8'd32;
        7'd63: csr_ch = fv3 ? 8'h30 + {4'd0, freq_bcd[15:12]} : 8'd32;
        7'd64: csr_ch = fv2 ? 8'h30 + {4'd0, freq_bcd[11:8]}  : 8'd32;
        7'd65: csr_ch = fv1 ? 8'h30 + {4'd0, freq_bcd[7:4]}   : 8'd32;
        7'd66: csr_ch = 8'h30 + {4'd0, freq_bcd[3:0]};
        7'd67: csr_ch = (I_span == 3'd4) ? "K" : 8'd32;   // 宽频档单位 KHZ
        7'd68: csr_ch = "H";
        7'd69: csr_ch = "Z";
        7'd71: csr_ch = (I_csr_mode == 2'd2) ? (ddb_sign ? "-" : "+") : "-";
        7'd72: csr_ch = (db_bcd[11:8] == 4'd0) ? 8'd32
                                               : 8'h30 + {4'd0, db_bcd[11:8]};
        7'd73: csr_ch = 8'h30 + {4'd0, db_bcd[7:4]};
        7'd74: csr_ch = ".";
        7'd75: csr_ch = 8'h30 + {4'd0, db_bcd[3:0]};
        7'd77: csr_ch = "D";
        7'd78: csr_ch = "B";
        default: ;
        endcase
    end

    // 谐波表单元: 行 4 格 1..35, "H2 -12.2  H3 -18.2  H4 -24.2  H5 -28.3"
    // 跨度门控: 换档后 1~2 帧测量值还是旧档坐标, 先隐藏 (与标记同一策略)
    wire hrm_span_disp = (I_hrm_span == I_span);

    wire h_cell = I_hrm_valid && hrm_span_disp && (cell_row == 6'd4) &&
                  (cell_col >= 7'd1) && (cell_col <= 7'd35);

    // F0 大读数: 行 2 格 57..69, "F0 100000 HZ" (kHz 刻度同 MKR)
    wire f0_cell = I_hrm_valid && hrm_span_disp && (cell_row == 6'd2) &&
                   (cell_col >= 7'd57) && (cell_col <= 7'd69);
    wire f0v5 = (f0_val >= 20'd100000);
    wire f0v4 = (f0_val >= 20'd10000);
    wire f0v3 = (f0_val >= 20'd1000);
    wire f0v2 = (f0_val >= 20'd100);
    wire f0v1 = (f0_val >= 20'd10);
    reg  [7:0] f0_ch;

    always @(cell_col or f0_val or f0_bcd or I_span) begin
        f0_ch = 8'd0;
        case (cell_col)
        7'd57: f0_ch = "F";
        7'd58: f0_ch = "0";
        7'd60: f0_ch = ":";
        7'd61: f0_ch = f0v5 ? 8'h30 + {4'd0, f0_bcd[23:20]} : 8'd32;
        7'd62: f0_ch = f0v4 ? 8'h30 + {4'd0, f0_bcd[19:16]} : 8'd32;
        7'd63: f0_ch = f0v3 ? 8'h30 + {4'd0, f0_bcd[15:12]} : 8'd32;
        7'd64: f0_ch = f0v2 ? 8'h30 + {4'd0, f0_bcd[11:8]}  : 8'd32;
        7'd65: f0_ch = f0v1 ? 8'h30 + {4'd0, f0_bcd[7:4]}   : 8'd32;
        7'd66: f0_ch = 8'h30 + {4'd0, f0_bcd[3:0]};
        7'd67: f0_ch = (I_span == 3'd4) ? "K" : 8'd32;
        7'd68: f0_ch = "H";
        7'd69: f0_ch = "Z";
        default: ;
        endcase
    end

    reg [7:0] h_ch;

    always @(cell_col or h2_bcd or h3_bcd or h4_bcd or h5_bcd) begin
        h_ch = 8'd0;
        case (cell_col)
        // H2 标签 + 值 (4..8)
        7'd1:  h_ch = "H";
        7'd2:  h_ch = "2";
        7'd4:  h_ch = "-";
        7'd5:  h_ch = (h2_bcd[11:8] == 4'd0) ? 8'd32 : 8'h30 + {4'd0, h2_bcd[11:8]};
        7'd6:  h_ch = 8'h30 + {4'd0, h2_bcd[7:4]};
        7'd7:  h_ch = ".";
        7'd8:  h_ch = 8'h30 + {4'd0, h2_bcd[3:0]};
        // H3 (10..17)
        7'd10: h_ch = "H";
        7'd11: h_ch = "3";
        7'd13: h_ch = "-";
        7'd14: h_ch = (h3_bcd[11:8] == 4'd0) ? 8'd32 : 8'h30 + {4'd0, h3_bcd[11:8]};
        7'd15: h_ch = 8'h30 + {4'd0, h3_bcd[7:4]};
        7'd16: h_ch = ".";
        7'd17: h_ch = 8'h30 + {4'd0, h3_bcd[3:0]};
        // H4 (19..26)
        7'd19: h_ch = "H";
        7'd20: h_ch = "4";
        7'd22: h_ch = "-";
        7'd23: h_ch = (h4_bcd[11:8] == 4'd0) ? 8'd32 : 8'h30 + {4'd0, h4_bcd[11:8]};
        7'd24: h_ch = 8'h30 + {4'd0, h4_bcd[7:4]};
        7'd25: h_ch = ".";
        7'd26: h_ch = 8'h30 + {4'd0, h4_bcd[3:0]};
        // H5 (28..35)
        7'd28: h_ch = "H";
        7'd29: h_ch = "5";
        7'd31: h_ch = "-";
        7'd32: h_ch = (h5_bcd[11:8] == 4'd0) ? 8'd32 : 8'h30 + {4'd0, h5_bcd[11:8]};
        7'd33: h_ch = 8'h30 + {4'd0, h5_bcd[7:4]};
        7'd34: h_ch = ".";
        7'd35: h_ch = 8'h30 + {4'd0, h5_bcd[3:0]};
        default: ;
        endcase
    end

    // 读数注入优先级: 光标读数 (青) > 谐波表 (绿), 其余走文字解码
    wire [10:0] map_d_eff = csr_cell ? {1'b0, 2'd2, csr_ch} :
                            h_cell   ? {1'b0, 2'd1, h_ch}   :
                            f0_cell  ? {1'b0, 2'd1, f0_ch}  : map_d;

    reg [11:0] x1, y1;
    reg [9:0]  bin1;
    reg [4:0]  px1, py1;
    reg        t_vld1;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x1 <= 12'd0;  y1 <= 12'd0;  bin1 <= 10'd0;
            px1 <= 5'd0;  py1 <= 5'd0;  t_vld1 <= 1'b0;
        end else begin
            x1 <= I_x;  y1 <= I_y;  bin1 <= bin_addr;
            px1 <= I_x[4:0];  py1 <= I_y[4:0];
            t_vld1 <= (map_d_eff[7:0] != 8'd0);
        end
    end

    //==================================================================
    // 第 2 级: 字模 ROM (同步读, BSRAM)
    //   scale=1 时字高 32, 行/列取 5bit 里的高 3 位; scale=0 时字高 16
    //==================================================================
    wire [2:0] glyph_row = map_d_eff[10] ? py1[4:2] : py1[3:1];

    wire [7:0] font_bits;

    ui_font_rom u_font_rom (
        .I_clk  (I_pix_clk   ),
        .I_ch   (map_d_eff[7:0]  ),
        .I_row  (glyph_row   ),
        .O_bits (font_bits   )
    );

    reg [11:0] x2, y2;
    reg [9:0]  bin2;
    reg [4:0]  px2;
    reg [1:0]  color2;
    reg        scale2, t_vld2;
    reg [15:0] mag2, peak2;
    reg [8:0]  lg2m, lg2p;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x2 <= 12'd0;  y2 <= 12'd0;  bin2 <= 10'd0;  px2 <= 5'd0;
            color2 <= 2'd0;  scale2 <= 1'b0;  t_vld2 <= 1'b0;
            mag2 <= 16'd0;  peak2 <= 16'd0;  lg2m <= 9'd0;  lg2p <= 9'd0;
        end else begin
            x2 <= x1;  y2 <= y1;  bin2 <= bin1;  px2 <= px1;
            color2 <= map_d_eff[9:8];
            scale2 <= map_d_eff[10];
            t_vld2 <= t_vld1;
            mag2  <= mag_ram;
            peak2 <= peak_ram;
            lg2m  <= log_split(mag_ram);
            lg2p  <= log_split(peak_ram);
        end
    end

    //==================================================================
    // 第 3 级: 对数换算后半 + 字模输出寄存
    //==================================================================
    reg [11:0] x3, y3;
    reg [9:0]  r3, rp3;
    reg [7:0]  fb3;
    reg [4:0]  px3;
    reg [1:0]  color3;
    reg        scale3, t_vld3, pk_vld3;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x3 <= 12'd0;  y3 <= 12'd0;
            r3 <= 10'd511;  rp3 <= 10'd511;
            fb3 <= 8'd0;  px3 <= 5'd0;  color3 <= 2'd0;
            scale3 <= 1'b0;  t_vld3 <= 1'b0;  pk_vld3 <= 1'b0;
        end else begin
            x3 <= x2;  y3 <= y2;
            r3 <= log_row(lg2m[8:5], lg2m[4:0]);
            rp3 <= log_row(lg2p[8:5], lg2p[4:0]);
            fb3 <= font_bits;
            px3 <= px2;
            color3 <= color2;
            scale3 <= scale2;
            t_vld3 <= t_vld2;
            pk_vld3 <= (peak2 != 16'd0);
        end
    end

    //==================================================================
    // 第 4 级: 量程换算 + 字模取位
    //==================================================================
    wire [2:0] glyph_col = scale3 ? px3[4:2] : px3[3:1];
    wire       t_bit     = (fb3 >> (3'd7 - glyph_col)) & 1'b1;

    reg [11:0] x4, y4;
    reg [9:0]  bar4, pk4, prev4;
    reg        tbit4, tvld4, pkvld4;
    reg [1:0]  color4;
    reg        hrm_v1, hrm_v2, hrm_v3, hrm_v4, hrm_v5;   // 谐波命中 (提前一级算好)
    reg        csr_v;                                    // 光标竖线 (同上)
    reg        cref_v;                                   // 增量参考虚线
    reg [2:0]  wf_d5;                                    // 瀑布色阶 (滞后 x4 一拍见上)
    reg        wf_ok5;

    //------------------------------------------------------------------
    // 谐波命中判断 (组合, 基于第 3 级坐标 -> 第 4 级打拍):
    //   第 k 次谐波在 k*I_hrm_col 列 (列 = 2 个 bin)。
    //   顶部 6 行画向下的三角 (▼), 其下每 4 行一个点的竖虚线。
    //   提前一级寄存是为了把 5 路比较/求绝对差移出第 5 级关键路径。
    //------------------------------------------------------------------
    wire        in_plot3 = (x3 >= PX0) && (x3 <= PX1) && (y3 >= PY0) && (y3 <= PY1);
    wire [9:0]  xr3 = x3[9:0] - 10'd64;
    wire [9:0]  yr3 = y3[9:0] - 10'd104;

    wire [11:0] hc1 = {2'b00, I_hrm_col};
    wire [11:0] hc2 = {1'b0, I_hrm_col, 1'b0};
    wire [13:0] hc3 = {3'b000, I_hrm_col} * 14'd3;
    wire [13:0] hc4 = {3'b000, I_hrm_col} * 14'd4;
    wire [13:0] hc5 = {3'b000, I_hrm_col} * 14'd5;

    // 谐波列超出屏幕 (k*I_hrm_col > 1023) 时不画 (低位截断会产生假位置)
    wire hv1 = (hc1 <= 12'd1023);
    wire hv2 = (hc2 <= 12'd1023);
    wire hv3 = (hc3 <= 14'd1023);
    wire hv4 = (hc4 <= 14'd1023);
    wire hv5 = (hc5 <= 14'd1023);

    wire [10:0] dx1 = (xr3 > hc1[9:0]) ? (xr3 - hc1[9:0]) : (hc1[9:0] - xr3);
    wire [10:0] dx2 = (xr3 > hc2[9:0]) ? (xr3 - hc2[9:0]) : (hc2[9:0] - xr3);
    wire [10:0] dx3 = (xr3 > hc3[9:0]) ? (xr3 - hc3[9:0]) : (hc3[9:0] - xr3);
    wire [10:0] dx4 = (xr3 > hc4[9:0]) ? (xr3 - hc4[9:0]) : (hc4[9:0] - xr3);
    wire [10:0] dx5 = (xr3 > hc5[9:0]) ? (xr3 - hc5[9:0]) : (hc5[9:0] - xr3);

    wire hrm_top3  = (yr3 <= 10'd5);
    wire hrm_dash3 = (yr3 >= 10'd6) && (yr3[1:0] == 2'b00);

    wire hrm_span_ok = (I_hrm_span == I_span);

    wire hrm1_c = in_plot3 && I_hrm_valid && hrm_span_ok && hv1 && (hrm_top3 ? (dx1 <= {5'b0, yr3[4:0]}) : (hrm_dash3 && (xr3 == hc1[9:0])));
    wire hrm2_c = in_plot3 && I_hrm_valid && hrm_span_ok && hv2 && (hrm_top3 ? (dx2 <= {5'b0, yr3[4:0]}) : (hrm_dash3 && (xr3 == hc2[9:0])));
    wire hrm3_c = in_plot3 && I_hrm_valid && hrm_span_ok && hv3 && (hrm_top3 ? (dx3 <= {5'b0, yr3[4:0]}) : (hrm_dash3 && (xr3 == hc3[9:0])));
    wire hrm4_c = in_plot3 && I_hrm_valid && hrm_span_ok && hv4 && (hrm_top3 ? (dx4 <= {5'b0, yr3[4:0]}) : (hrm_dash3 && (xr3 == hc4[9:0])));
    wire hrm5_c = in_plot3 && I_hrm_valid && hrm_span_ok && hv5 && (hrm_top3 ? (dx5 <= {5'b0, yr3[4:0]}) : (hrm_dash3 && (xr3 == hc5[9:0])));

    // 光标竖线: 顶部 6 行实心小竖条 + 其下隔行虚线 (与谐波同法提前一级寄存)
    wire csr_line_c = I_csr_en && in_plot3 && (xr3 == I_csr_col) &&
                      ((yr3 <= 10'd5) || (yr3[0] == 1'b0));

    // 增量参考线: 隔行虚线 (无顶条, 与主光标区分)
    wire cref_line_c = (I_csr_mode == 2'd2) && in_plot3 &&
                       (xr3 == csr_ref_col) && (yr3[0] == 1'b0);

    //------------------------------------------------------------------
    // 瀑布图读侧: 第 3 级发地址, 第 4 级取数, 第 5 级寄存色阶
    //   只显示绘图区底部 128 行: yr3 in [384,511] (yr3[9:7]=3'b011),
    //   d = yr3[6:0] (0=最新), 历史行 = (wrow-1-d) mod 128
    //------------------------------------------------------------------
    wire        wf_in3   = (yr3[9:7] == 3'b011);
    wire [6:0]  wf_d     = yr3[6:0];
    wire [6:0]  wf_hist  = wf_rrow_s1 - 7'd1 - wf_d;      // 7bit 模 128
    wire [14:0] wf_raddr = {wf_hist, xr3[9:2]};
    wire        wf_row_ok = wf_in3 && (wf_full_s1 || (wf_d < wf_rrow_s1));

    always @(posedge I_pix_clk) begin
        wf_rdata <= wf_mem[wf_raddr];
    end

    function [23:0] wf_pal;                // 8 级热色
        input [2:0] i;
        begin
            case (i)
            3'd0:    wf_pal = 24'h00_00_00;
            3'd1:    wf_pal = 24'h18_18_50;
            3'd2:    wf_pal = 24'h00_60_C0;
            3'd3:    wf_pal = 24'h00_B0_B0;
            3'd4:    wf_pal = 24'h00_C0_00;
            3'd5:    wf_pal = 24'hC0_C0_00;
            3'd6:    wf_pal = 24'hF0_70_00;
            default: wf_pal = 24'hF8_F8_F8;
            endcase
        end
    endfunction

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x4 <= 12'd0;  y4 <= 12'd0;
            bar4 <= 10'd511;  pk4 <= 10'd511;  prev4 <= 10'd511;
            tbit4 <= 1'b0;  tvld4 <= 1'b0;  pkvld4 <= 1'b0;  color4 <= 2'd0;
            hrm_v1 <= 1'b0;  hrm_v2 <= 1'b0;  hrm_v3 <= 1'b0;
            hrm_v4 <= 1'b0;  hrm_v5 <= 1'b0;
            csr_v <= 1'b0;
        end else begin
            x4 <= x3;  y4 <= y3;
            bar4  <= r3;
            pk4   <= rp3;
            prev4 <= bar4;
            tbit4 <= t_vld3 & t_bit;
            tvld4 <= t_vld3;
            color4 <= color3;
            pkvld4 <= pk_vld3;
            hrm_v1 <= hrm1_c;
            hrm_v2 <= hrm2_c;
            hrm_v3 <= hrm3_c;
            hrm_v4 <= hrm4_c;
            hrm_v5 <= hrm5_c;
            csr_v <= csr_line_c;
            cref_v <= cref_line_c;
            wf_d5   <= wf_rdata;
            wf_ok5  <= wf_row_ok;
        end
    end

    //==================================================================
    // 第 5 级: 判定像素属于哪个元素, 输出 4bit 选择码
    //==================================================================
    wire in_plot  = (x4 >= PX0) && (x4 <= PX1) && (y4 >= PY0) && (y4 <= PY1);
    wire in_panel = (x4 >= PANEL_X);
    wire in_top   = (y4 < TOP_H);
    wire in_bot   = (y4 >= BOT_Y) && !in_panel;

    wire [9:0] xr = x4[9:0] - 10'd64;       // 0..1023
    wire [9:0] yr = y4[9:0] - 10'd104;      // 0..511

    wire grid_v = (xr[6:0] == 7'd0);        // 每 128 像素
    wire grid_h = (yr[5:0] == 6'd0);        // 每 64 像素
    wire grid   = grid_v || grid_h;

    wire [9:0] seg_lo = (bar4 < prev4) ? bar4 : prev4;
    wire [9:0] seg_hi = (bar4 < prev4) ? prev4 : bar4;

    wire wf_on = I_wf_en && !I_menu_hide && wf_ok5;

    // (谐波命中 hrm_v1..5 已在第 4 级寄存, 见上方)

    wire trace_cap = in_plot && (yr >= bar4) && (yr <= (bar4 + 10'd1));
    wire trace_seg = in_plot && (x4 > PX0) && (yr >= seg_lo) && (yr <= (seg_hi + 10'd1));
    wire on_trace  = trace_cap || trace_seg;
    wire on_peak   = in_plot && pkvld4 && ((yr == pk4) || (yr == (pk4 + 10'd1)));

    // 右侧按钮: 每 5 行一个按钮 (4 行按钮 + 1 行间隔), 从第 7 行开始
    wire [5:0] row4 = y4[9:4];
    wire in_btn = ((row4 >= 7)  && (row4 <= 10)) || ((row4 >= 12) && (row4 <= 15)) ||
                  ((row4 >= 17) && (row4 <= 20)) || ((row4 >= 22) && (row4 <= 25)) ||
                  ((row4 >= 27) && (row4 <= 30)) || ((row4 >= 32) && (row4 <= 35)) ||
                  ((row4 >= 37) && (row4 <= 40));
    // Window 按钮在 17..20 行 (in_btn 第 3 组), 高亮必须与按钮同区间;
    // 旧值 18..21 会让高亮压到 21 行 (按钮间空隙) 而漏掉首行
    wire btn_hi = (row4 >= 17) && (row4 <= 20);         // Window 按钮高亮 (=KEY5 可调)

    wire is_sep = ((y4 >= 12'd96)  && (y4 <= 12'd99))  ||
                  ((y4 >= 12'd618) && (y4 <= 12'd621)) ||
                  ((x4 >= 12'd1098) && (x4 <= 12'd1101) && !I_menu_hide);

    // 元素选择码
    localparam [4:0] S_TXT0  = 5'd0;
    localparam [4:0] S_TXT1  = 5'd1;
    localparam [4:0] S_TXT2  = 5'd2;
    localparam [4:0] S_TXT3  = 5'd3;
    localparam [4:0] S_TRACE = 5'd4;
    localparam [4:0] S_PEAK  = 5'd5;
    localparam [4:0] S_GRID  = 5'd6;
    localparam [4:0] S_PLOT  = 5'd7;
    localparam [4:0] S_BTN_H = 5'd8;
    localparam [4:0] S_BTN   = 5'd9;
    localparam [4:0] S_PANEL = 5'd10;
    localparam [4:0] S_SEP   = 5'd11;
    localparam [4:0] S_CHROME= 5'd12;
    localparam [4:0] S_BG    = 5'd13;
    localparam [4:0] S_HRM1  = 5'd14;    // 谐波 1~5 标记
    localparam [4:0] S_HRM2  = 5'd15;
    localparam [4:0] S_HRM3  = 5'd16;
    localparam [4:0] S_HRM4  = 5'd17;
    localparam [4:0] S_HRM5  = 5'd18;
    localparam [4:0] S_CSR   = 5'd19;    // 光标竖线
    localparam [4:0] S_WF    = 5'd20;    // 瀑布图色块
    localparam [4:0] S_CREF  = 5'd21;    // 增量参考虚线

    reg [4:0] sel_c;

    // 菜单折叠时不画菜单文字, 但顶栏光标读数 (57..78 行 4) 豁免
    wire [6:0] ccol4 = x4[10:4];
    wire [5:0] crow4 = y4[9:4];
    wire       csr_cell4 = (crow4 == 6'd4) && (ccol4 >= 7'd57) && (ccol4 <= 7'd78);
    wire       f0_cell4  = (crow4 == 6'd2) && (ccol4 >= 7'd57) && (ccol4 <= 7'd69);

    always @(*) begin
        if (tbit4 && !(I_menu_hide && in_panel && !csr_cell4 && !f0_cell4))
            sel_c = (color4 == 2'd1) ? S_TXT1 :
                    (color4 == 2'd2) ? S_TXT2 :
                    (color4 == 2'd3) ? S_TXT3 : S_TXT0;
        else if (hrm_v5)
            sel_c = S_HRM5;
        else if (hrm_v4)
            sel_c = S_HRM4;
        else if (hrm_v3)
            sel_c = S_HRM3;
        else if (hrm_v2)
            sel_c = S_HRM2;
        else if (hrm_v1)
            sel_c = S_HRM1;
        else if (in_plot)
            sel_c = csr_v    ? S_CSR   :
                    on_trace ? S_TRACE :
                    on_peak  ? S_PEAK  :
                    cref_v   ? S_CREF  :
                    wf_on    ? S_WF   :
                    grid     ? S_GRID  : S_PLOT;
        else if (in_panel)
            sel_c = I_menu_hide ? S_BG :
                    in_btn ? (btn_hi ? S_BTN_H : S_BTN) : S_PANEL;
        else if (is_sep)
            sel_c = S_SEP;
        else if (in_top || in_bot)
            sel_c = S_CHROME;
        else
            sel_c = S_BG;
    end

    reg [4:0] sel;
    reg [9:0] yr5;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            sel <= S_BG;
            yr5 <= 10'd0;
        end else begin
            sel <= sel_c;
            yr5 <= yr;
        end
    end

    //==================================================================
    // 第 6 级: 选择码 -> 24bit 颜色
    //==================================================================
    localparam [23:0] C_HRM1   = 24'h00_FF_00;   // 谐波 1: 绿
    localparam [23:0] C_HRM2   = 24'h00_FF_FF;   // 谐波 2: 青
    localparam [23:0] C_HRM3   = 24'hFF_00_FF;   // 谐波 3: 品红
    localparam [23:0] C_HRM4   = 24'hFF_A0_00;   // 谐波 4: 橙
    localparam [23:0] C_HRM5   = 24'hC0_60_FF;   // 谐波 5: 紫
    localparam [23:0] C_CSR    = 24'hE8_E8_E8;   // 光标: 亮灰白

    reg [23:0] rgb_c;

    always @(*) begin
        case (sel)
            S_TXT0  : rgb_c = C_TXT0;
            S_TXT1  : rgb_c = C_TXT1;
            S_TXT2  : rgb_c = C_TXT2;
            S_TXT3  : rgb_c = C_TXT3;
            S_TRACE : rgb_c = C_TRACE;
            S_PEAK  : rgb_c = C_PEAK;
            S_GRID  : rgb_c = C_GRID;
            S_PLOT  : rgb_c = C_PLOT_BG;
            S_BTN_H : rgb_c = C_BTN_HI;
            S_BTN   : rgb_c = C_BTN;
            S_PANEL : rgb_c = C_PANEL;
            S_SEP   : rgb_c = C_SEP;
            S_CHROME: rgb_c = C_CHROME;
            S_HRM1  : rgb_c = C_HRM1;
            S_HRM2  : rgb_c = C_HRM2;
            S_HRM3  : rgb_c = C_HRM3;
            S_HRM4  : rgb_c = C_HRM4;
            S_HRM5  : rgb_c = C_HRM5;
            S_CSR   : rgb_c = C_CSR;
            S_WF    : rgb_c = wf_pal(wf_d5);
            S_CREF  : rgb_c = 24'h39_90_B4;               // 参考线: 暗青
            default : rgb_c = C_BG;
        endcase
    end

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            O_r <= 8'd0;
            O_g <= 8'd0;
            O_b <= 8'd0;
        end else begin
            O_r <= rgb_c[23:16];
            O_g <= rgb_c[15:8];
            O_b <= rgb_c[7:0];
        end
    end

endmodule

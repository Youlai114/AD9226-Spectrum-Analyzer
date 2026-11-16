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
    input      [2:0]  I_span       ,   // 跨度档 0..6 (1M/250k/50k/10k/1k/250/27M)
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
    // ---- THD / SNR 测量输入 ----
    input      [15:0] I_h1,           // 基波峰幅度 (THD/SNR 参考)
    input      [35:0] I_pwr,          // 全带功率 sum(mag^2>>6) (SNR 用)

    // ---- 显示模式 (KEY2 循环): 0=频谱+菜单+瀑布 1=纯净频谱(菜单折叠) ----
    input             I_menu_hide  ,   // 1: 右侧菜单折叠成纯黑
    // ---- 窗函数 (KEY5 循环): RBW 显示与菜单 Window 值随窗联动 ----
    input      [1:0]  I_win        ,   // 0=Hann 1=Rect 2=Blackman 3=FlatTop
    // ---- 编码器精细模式 (短按编码器切换): 光标步进 1 列, 顶栏右上加 FINE ----
    input             I_fine       ,
    // ---- 右侧菜单 (KEY4 第 4 态): 选中项高亮 + 各项当前值 ----
    input             I_menu_on    ,   // 1=菜单态, 高亮 I_menu_sel 那一项
    input      [2:0]  I_menu_sel   ,   // 0=ResBW 1=Window 2=Detector 3=Trace 4=Avg 5=Span
    input      [1:0]  I_det_sel    ,   // Detector: 0=正峰 1=平均 2=负峰 3=取样
    input      [1:0]  I_trc_sel    ,   // Trace: 0=Clear Write 1=Max Hold 2=Min Hold 3=View
    input      [2:0]  I_avg_sel    ,   // Avg: 0=Auto 1=1 2=4 3=16 4=64
    // ---- 数据写入接口 (与像素时钟可异步) ----
    input             I_wr_clk     ,
    input             I_wr_rst_n   ,
    input             I_frame_start,
    input             I_mid        ,   // 本帧是中间帧: 峰值/保持/光标读数冻结 + 顶栏标记
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
    wire        rd_mid;                 // 当前显示的那一帧是不是中间帧

    spec_data_if u_data_if (
        .I_wr_clk      (I_wr_clk      ),
        .I_wr_rst_n    (I_wr_rst_n    ),
        .I_frame_start (I_frame_start ),
        .I_mid         (I_mid         ),
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
        .O_rd_mid      (rd_mid        ),
        .O_frame_cnt   (              ),
        .O_frame_tog   (              )
    );

    // 像素列 -> 频点地址 (绘图区内恰好 1024 列)
    wire [9:0] bin_addr = I_x[9:0] - 10'd64;

    wire [15:0] mag_raw;

    spec_ram u_spec_ram (
        .I_wr_clk  (I_wr_clk  ),
        .I_wr_en   (wr_en     ),
        .I_wr_bank (wr_bank   ),
        .I_wr_addr (wr_addr   ),
        .I_wr_data (wr_mag    ),
        .I_rd_clk  (I_pix_clk ),
        .I_rd_bank (rd_bank   ),
        .I_rd_addr (bin_addr  ),
        .O_rd_data (mag_raw   )
    );

    //==================================================================
    // 迹线 (菜单 Trace):
    //   0=Clear Write 直接显示本帧   1=Max Hold 逐列取历史最大
    //   2=Min Hold 取历史最小        3=View 冻结当前最大保持迹线
    // 保持 RAM 在像素域更新 (与峰值保持同拍: 只在绘图区首行扫一遍),
    // 切换模式时先把本帧整屏装载一遍 (trc_rdy), 避免旧值残留
    //==================================================================
    reg [15:0] trc_max_mem [0:1023];
    reg [15:0] trc_min_mem [0:1023];
    reg [15:0] trc_max_ram, trc_min_ram;

    always @(posedge I_pix_clk) begin
        trc_max_ram <= trc_max_mem[bin_addr];
        trc_min_ram <= trc_min_mem[bin_addr];
    end

    wire [15:0] mag_ram = (I_trc_sel == 2'd1 || I_trc_sel == 2'd3) ? trc_max_ram :
                          (I_trc_sel == 2'd2)                     ? trc_min_ram :
                                                                    mag_raw;

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
            // 中间帧冻结: 只在这一个寄存器上挡, 峰值/迹线/光标读数全部自动停更
            pk_upd_d <= pk_upd && !rd_mid;
            bin_d    <= bin_addr;
            if (pk_upd_d && (bin_d == 10'd1023))   // 第一帧装载完成
                pk_ready <= 1'b1;
        end
    end

    wire [15:0] peak_ref = pk_ready ? peak_ram : 16'd0;
    wire [15:0] pk_decay = (peak_ref >> 6) | 16'd1;
    wire [15:0] pk_new   = (mag_ram >= peak_ref) ? mag_ram : (peak_ref - pk_decay);

    // 中间帧是"补零帧"的读数 (分辨率粗), 不进峰值保持/迹线保持/光标读数,
    // 否则慢档刚换档时峰值线会被中间帧的低分辨率读数拖花 (见 pk_upd_d 门控)
    always @(posedge I_pix_clk) begin
        if (pk_upd_d)
            peak_mem[bin_d] <= pk_new;
    end

    // 迹线保持: 与峰值同拍 (pk_upd_d 时 mag_ram 与 bin_d 对应同一列)
    reg [1:0] trc_d;
    reg       trc_rdy;                        // 0=首次装载中 (直接覆盖)
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            trc_d <= 2'd0;  trc_rdy <= 1'b0;
        end else begin
            if (I_trc_sel != trc_d) begin
                trc_d   <= I_trc_sel;
                trc_rdy <= 1'b0;              // 换模式: 重新装载
            end else if (pk_upd_d && (bin_d == 10'd1023)) begin
                trc_rdy <= 1'b1;
            end
        end
    end

    always @(posedge I_pix_clk) begin
        if (pk_upd_d && (I_trc_sel == 2'd1 || I_trc_sel == 2'd3)) begin
            if (!trc_rdy)
                trc_max_mem[bin_d] <= mag_raw;                 // 装载
            else if (mag_raw > trc_max_ram)
                trc_max_mem[bin_d] <= mag_raw;                 // 取大
        end
        if (pk_upd_d && (I_trc_sel == 2'd2)) begin
            if (!trc_rdy)
                trc_min_mem[bin_d] <= mag_raw;
            else if (mag_raw < trc_min_ram)
                trc_min_mem[bin_d] <= mag_raw;
        end
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
    wire [19:0] f0_freq   = (I_span == 3'd6) ? {5'd0, f0_prod_k[24:10]}
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
            3'd4:    span_hz20 = 25'd1000;      // 1 kHz 档 (fs 2 kSPS)
            3'd5:    span_hz20 = 25'd250;       // 250 Hz 档 (fs 500 SPS)
            default: span_hz20 = 25'd27000000; // 宽频档 (档 6)
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

    // ★ v1.7.4: 再打一拍。csr_lg_r -> 减 512 -> 乘 -> 取负 -> 减参考 原本是
    //   8 级 (实测 u_display/csr_lg_r_8_s0 -> u_display/ddb_s_s1_10_s0
    //   +0.643ns)。这些都是"每帧刷新一次"的量, 多一拍毫无影响。
    reg [10:0] csr_dbabs_r;
    always @(posedge I_pix_clk) csr_dbabs_r <= csr_dbabs;

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
                csr_ref_db  <= csr_dbabs_r;
            end
        end
    end

    wire signed [10:0] dcol_s = $signed({1'b0, I_csr_col})
                               - $signed({1'b0, csr_ref_col});
    wire        [10:0] ddb_s  = csr_dbabs_r - csr_ref_db; // 差恒 |..|<=964

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

    wire [19:0] csr_freq = (span_s2 == 3'd6) ? {5'd0, csr_prod_k_s2[24:10]}
                                             : csr_prod_s2[34:10];
    wire [19:0] dfreq    = (span_s2 == 3'd6) ? {5'd0, dprod_k_s2[24:10]}
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
                    db_abs   <= csr_dbabs_r;
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

    // 文字层单独打一拍 (v1.3.0 时序修复):
    //   原来 I_x 计数器 -> cell_col -> 288bit 变址 mux -> t_ch -> map_d 是一条
    //   ~15.8 ns 的链 (u_timing/O_x_* -> u_display/t_ch_* -> u_display/map_d_*),
    //   而 t_ch 后面紧跟 map_d 寄存器。把 cell_row/cell_col 先打一拍, 让这条链
    //   从寄存器出发, 组合深度只剩「变址 mux + 一个比较器」。
    //   代价: 文字整体右移 1 像素 (字形本身仍由 px1/py1 决定, 不会发虚)。
    reg  [5:0] cell_row_q = 6'd0;
    reg  [6:0] cell_col_q = 7'd0;
    always @(posedge I_pix_clk) begin
        cell_row_q <= cell_row;
        cell_col_q <= cell_col;
    end

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
            if ((cell_row_q == r0[5:0]) && (cell_col_q >= c0[7:0]) &&
                (cell_col_q < c0[7:0] + len[7:0])) begin
                i    = (len - 1) - (cell_col_q - c0);
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
        5'd04: begin rbw_s = "0.73 Hz";   rbw_len = 4'd7;  end  // Hann @1k
        5'd05: begin rbw_s = "0.18 Hz";   rbw_len = 4'd7;  end  // Hann @250
        5'd06: begin rbw_s = "19.78 kHz"; rbw_len = 4'd9;  end  // Hann @27M
        // Rect: ENBW 1.0
        5'd08: begin rbw_s = "488 Hz";    rbw_len = 4'd6;  end  // Rect  @1M
        5'd09: begin rbw_s = "122 Hz";    rbw_len = 4'd6;  end
        5'd10: begin rbw_s = "24.4 Hz";   rbw_len = 4'd7;  end
        5'd11: begin rbw_s = "4.9 Hz";    rbw_len = 4'd6;  end
        5'd12: begin rbw_s = "0.49 Hz";   rbw_len = 4'd7;  end  // Rect @1k
        5'd13: begin rbw_s = "0.12 Hz";   rbw_len = 4'd7;  end  // Rect @250
        5'd14: begin rbw_s = "13.18 kHz"; rbw_len = 4'd9;  end  // Rect @27M
        // Blackman: ENBW 1.73
        5'd16: begin rbw_s = "843 Hz";    rbw_len = 4'd6;  end  // Black @1M
        5'd17: begin rbw_s = "211 Hz";    rbw_len = 4'd6;  end
        5'd18: begin rbw_s = "42.2 Hz";   rbw_len = 4'd7;  end
        5'd19: begin rbw_s = "8.4 Hz";    rbw_len = 4'd6;  end
        5'd20: begin rbw_s = "0.84 Hz";   rbw_len = 4'd7;  end  // Black @1k
        5'd21: begin rbw_s = "0.21 Hz";   rbw_len = 4'd7;  end  // Black @250
        5'd22: begin rbw_s = "22.77 kHz"; rbw_len = 4'd9;  end  // Black @27M
        // FlatTop: ENBW 3.77
        5'd24: begin rbw_s = "1.84 kHz";  rbw_len = 4'd8;  end  // Flat  @1M
        5'd25: begin rbw_s = "460 Hz";    rbw_len = 4'd6;  end
        5'd26: begin rbw_s = "92.0 Hz";   rbw_len = 4'd7;  end
        5'd27: begin rbw_s = "18.4 Hz";   rbw_len = 4'd7;  end
        5'd28: begin rbw_s = "1.84 Hz";   rbw_len = 4'd7;  end  // Flat  @1k
        5'd29: begin rbw_s = "0.46 Hz";   rbw_len = 4'd7;  end  // Flat  @250
        5'd30: begin rbw_s = "49.70 kHz"; rbw_len = 4'd9;  end  // Flat  @27M
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
    always @(cell_row_q or cell_col_q or I_span or I_fine or rbw_s_r or rbw_len_r
            or I_det_sel or I_trc_sel or I_avg_sel
             or win_name_r or win_len_r or win_long_r or rd_mid) begin
        t_ch = 8'd0;
        t_co = 2'd0;
        case (cell_row_q)
        // 中间帧标记: FINE / MID 共用同一个 put (每多一个 put 就深一级优先链)
        6'd0: put(76, 0, 4, I_fine ? "FINE" : (rd_mid ? " MID" : "    "), 2'd2);
        6'd1: begin
            case (cell_col_q)
            7'd1: begin t_ch = 8'h53; t_co = 2'd2; end
            7'd2: begin t_ch = 8'h50; t_co = 2'd2; end
            7'd3: begin t_ch = 8'h45; t_co = 2'd2; end
            7'd4: begin t_ch = 8'h43; t_co = 2'd2; end
            7'd5: begin t_ch = 8'h54; t_co = 2'd2; end
            7'd6: begin t_ch = 8'h52; t_co = 2'd2; end
            7'd7: begin t_ch = 8'h55; t_co = 2'd2; end
            7'd8: begin t_ch = 8'h4D; t_co = 2'd2; end
            7'd11: begin t_ch = 8'h43; t_co = 2'd0; end
            7'd12: begin t_ch = 8'h65; t_co = 2'd0; end
            7'd13: begin t_ch = 8'h6E; t_co = 2'd0; end
            7'd14: begin t_ch = 8'h74; t_co = 2'd0; end
            7'd15: begin t_ch = 8'h65; t_co = 2'd0; end
            7'd16: begin t_ch = 8'h72; t_co = 2'd0; end
            7'd17: begin t_ch = 8'h20; t_co = 2'd0; end
            7'd18: begin t_ch = 8'h46; t_co = 2'd0; end
            7'd19: begin t_ch = 8'h72; t_co = 2'd0; end
            7'd20: begin t_ch = 8'h65; t_co = 2'd0; end
            7'd21: begin t_ch = 8'h71; t_co = 2'd0; end
            7'd22: begin t_ch = 8'h3A; t_co = 2'd0; end
            7'd24: begin
                case (I_span)
                3'd0: t_ch = 8'h35;
                3'd1: t_ch = 8'h31;
                3'd2: t_ch = 8'h32;
                3'd3: t_ch = 8'h35;
                3'd4: t_ch = 8'h35;
                3'd5: t_ch = 8'h31;
                3'd6: t_ch = 8'h31;
                endcase
                t_co = 2'd1;
            end
            7'd25: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h2E;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'h33;
                endcase
                t_co = 2'd1;
            end
            7'd26: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h2E;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd1;
            end
            7'd27: begin
                case (I_span)
                3'd0: t_ch = 8'h2E;
                3'd1: t_ch = 8'h2E;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h2E;
                3'd5: t_ch = 8'h2E;
                3'd6: t_ch = 8'h35;
                endcase
                t_co = 2'd1;
            end
            7'd28: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd1;
            end
            7'd29: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd1;
            end
            7'd30: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd1;
            end
            7'd31: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'h48;
                3'd4: t_ch = 8'h48;
                3'd5: t_ch = 8'h48;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd1;
            end
            7'd32: begin
                case (I_span)
                3'd0: t_ch = 8'h6B;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h48;
                3'd3: t_ch = 8'h7A;
                3'd4: t_ch = 8'h7A;
                3'd5: t_ch = 8'h7A;
                3'd6: t_ch = 8'h48;
                endcase
                t_co = 2'd1;
            end
            7'd33: begin
                case (I_span)
                3'd0: t_ch = 8'h48;
                3'd1: t_ch = 8'h48;
                3'd2: t_ch = 8'h7A;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h7A;
                endcase
                t_co = 2'd1;
            end
            7'd34: begin
                case (I_span)
                3'd0: t_ch = 8'h7A;
                3'd1: t_ch = 8'h7A;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd1;
            end
            7'd37: begin t_ch = 8'h52; t_co = 2'd0; end
            7'd38: begin t_ch = 8'h65; t_co = 2'd0; end
            7'd39: begin t_ch = 8'h66; t_co = 2'd0; end
            7'd40: begin t_ch = 8'h20; t_co = 2'd0; end
            7'd41: begin t_ch = 8'h4C; t_co = 2'd0; end
            7'd42: begin t_ch = 8'h65; t_co = 2'd0; end
            7'd43: begin t_ch = 8'h76; t_co = 2'd0; end
            7'd44: begin t_ch = 8'h65; t_co = 2'd0; end
            7'd45: begin t_ch = 8'h6C; t_co = 2'd0; end
            7'd46: begin t_ch = 8'h3A; t_co = 2'd0; end
            7'd48: begin t_ch = 8'h30; t_co = 2'd1; end
            7'd49: begin t_ch = 8'h2E; t_co = 2'd1; end
            7'd50: begin t_ch = 8'h30; t_co = 2'd1; end
            7'd51: begin t_ch = 8'h30; t_co = 2'd1; end
            7'd52: begin t_ch = 8'h20; t_co = 2'd1; end
            7'd53: begin t_ch = 8'h64; t_co = 2'd1; end
            7'd54: begin t_ch = 8'h42; t_co = 2'd1; end
            7'd55: begin t_ch = 8'h46; t_co = 2'd1; end
            7'd56: begin t_ch = 8'h53; t_co = 2'd1; end
            endcase
        end
        6'd3: begin
            case (cell_col_q)
            7'd1: begin t_ch = 8'h41; t_co = 2'd2; end
            7'd2: begin t_ch = 8'h4E; t_co = 2'd2; end
            7'd3: begin t_ch = 8'h41; t_co = 2'd2; end
            7'd4: begin t_ch = 8'h4C; t_co = 2'd2; end
            7'd5: begin t_ch = 8'h59; t_co = 2'd2; end
            7'd6: begin t_ch = 8'h5A; t_co = 2'd2; end
            7'd7: begin t_ch = 8'h45; t_co = 2'd2; end
            7'd8: begin t_ch = 8'h52; t_co = 2'd2; end
            7'd11: begin t_ch = 8'h53; t_co = 2'd0; end
            7'd12: begin t_ch = 8'h70; t_co = 2'd0; end
            7'd13: begin t_ch = 8'h61; t_co = 2'd0; end
            7'd14: begin t_ch = 8'h6E; t_co = 2'd0; end
            7'd15: begin t_ch = 8'h3A; t_co = 2'd0; end
            7'd24: begin
                case (I_span)
                3'd0: t_ch = 8'h31;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h31;
                3'd4: t_ch = 8'h31;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'h32;
                endcase
                t_co = 2'd1;
            end
            7'd25: begin
                case (I_span)
                3'd0: t_ch = 8'h2E;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h2E;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'h37;
                endcase
                t_co = 2'd1;
            end
            7'd26: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h2E;
                3'd3: t_ch = 8'h2E;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd1;
            end
            7'd27: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h2E;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h2E;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd1;
            end
            7'd28: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd1;
            end
            7'd29: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd1;
            end
            7'd30: begin
                case (I_span)
                3'd0: t_ch = 8'h4D;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'h6B;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd1;
            end
            7'd31: begin
                case (I_span)
                3'd0: t_ch = 8'h48;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'h48;
                3'd5: t_ch = 8'h48;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd1;
            end
            7'd32: begin
                case (I_span)
                3'd0: t_ch = 8'h7A;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h48;
                3'd3: t_ch = 8'h48;
                3'd4: t_ch = 8'h7A;
                3'd5: t_ch = 8'h7A;
                3'd6: t_ch = 8'h48;
                endcase
                t_co = 2'd1;
            end
            7'd33: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h48;
                3'd2: t_ch = 8'h7A;
                3'd3: t_ch = 8'h7A;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h7A;
                endcase
                t_co = 2'd1;
            end
            7'd34: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h7A;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd1;
            end
            7'd38: begin t_ch = 8'h52; t_co = 2'd0; end
            7'd39: begin t_ch = 8'h42; t_co = 2'd0; end
            7'd40: begin t_ch = 8'h57; t_co = 2'd0; end
            7'd41: begin t_ch = 8'h3A; t_co = 2'd0; end
            endcase
            put(48, 3, {1'b0, rbw_len_r}, rbw_s_r, 2'd1);
        end
        6'd6: begin
            put(0, 6, 4, "   0", 2'd0);
            put(71, 6, 6, "Res BW", 2'd3);
        end
        6'd8:  put(71, 8, {1'b0, rbw_len_r}, rbw_s_r, 2'd3);
        6'd10: put(0, 10, 4, " -10", 2'd0);
        6'd11: put(71, 11, 6, "Window", 2'd3);
        6'd13: put(72, 13, {1'b0, win_len_r}, win_name_r, 2'd3);
        6'd14: put(0, 14, 4, " -20", 2'd0);
        6'd16: put(70, 16, 8, "Detector", 2'd3);
        6'd18: begin
            put(0, 18, 4, " -30", 2'd0);
            case (I_det_sel)
            2'd0: put(70, 18, 8, "Pos Peak", 2'd3);
            2'd1: put(71, 18, 6, "Sample", 2'd3);
            2'd2: put(71, 18, 7, "Average", 2'd3);
            default: put(70, 18, 8, "Neg Peak", 2'd3);
            endcase
        end
        6'd22: put(0, 22, 4, " -40", 2'd0);
        6'd21: put(72, 21, 5, "Trace", 2'd3);
        6'd23: begin
            case (I_trc_sel)
            2'd0: put(70, 23, 11, "Clear Write", 2'd3);
            2'd1: put(71, 23, 8, "Max Hold", 2'd3);
            2'd2: put(71, 23, 8, "Min Hold", 2'd3);
            default: put(73, 23, 4, "View", 2'd3);
            endcase
        end
        6'd26: begin
            put(0, 26, 4, " -50", 2'd0);
            put(73, 26, 3, "Avg", 2'd3);
        end
        6'd28: begin
            case (I_avg_sel)
            3'd0: put(72, 28, 4, "Auto", 2'd3);
            3'd1: put(74, 28, 1, "1", 2'd3);
            3'd2: put(74, 28, 1, "4", 2'd3);
            3'd3: put(73, 28, 2, "16", 2'd3);
            default: put(73, 28, 2, "64", 2'd3);
            endcase
        end
        6'd30: put(0, 30, 4, " -60", 2'd0);
        6'd31: put(72, 31, 4, "Span", 2'd3);
        6'd33: begin
            case (I_span)
            3'd0:    put(72, 33, 5, "1 MHz", 2'd3);
            3'd1:    put(71, 33, 7, "250 kHz", 2'd3);
            3'd2:    put(71, 33, 6, "50 kHz", 2'd3);
            3'd3:    put(71, 33, 6, "10 kHz", 2'd3);
            3'd4:    put(72, 33, 5, "1 kHz", 2'd3);
            3'd5:    put(71, 33, 6, "250 Hz", 2'd3);
            default: put(71, 33, 6, "27 MHz", 2'd3);
            endcase
        end
        6'd34: put(0, 34, 4, " -70", 2'd0);
        6'd36: if (I_menu_on) put(72, 36, 4, "MENU", 2'd2);
        6'd38: begin
            put(0, 38, 4, " -80", 2'd0);
            put(5, 38, 4, "dBFS", 2'd0);
        end
        6'd39: begin
            case (cell_col_q)
            7'd4: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd17: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h36;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd18: begin
                case (I_span)
                3'd0: t_ch = 8'h32;
                3'd1: t_ch = 8'h36;
                3'd2: t_ch = 8'h31;
                3'd3: t_ch = 8'h32;
                3'd4: t_ch = 8'h32;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'h36;
                endcase
                t_co = 2'd0;
            end
            7'd19: begin
                case (I_span)
                3'd0: t_ch = 8'h35;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'h32;
                3'd3: t_ch = 8'h2E;
                3'd4: t_ch = 8'h35;
                3'd5: t_ch = 8'h2E;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd0;
            end
            7'd20: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h2E;
                3'd2: t_ch = 8'h2E;
                3'd3: t_ch = 8'h35;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'h37;
                endcase
                t_co = 2'd0;
            end
            7'd21: begin
                case (I_span)
                3'd0: t_ch = 8'h6B;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h35;
                endcase
                t_co = 2'd0;
            end
            7'd22: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd0;
            end
            7'd33: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h31;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd34: begin
                case (I_span)
                3'd0: t_ch = 8'h35;
                3'd1: t_ch = 8'h31;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'h35;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'h31;
                endcase
                t_co = 2'd0;
            end
            7'd35: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'h32;
                3'd3: t_ch = 8'h35;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'h33;
                endcase
                t_co = 2'd0;
            end
            7'd36: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd0;
            end
            7'd37: begin
                case (I_span)
                3'd0: t_ch = 8'h6B;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h35;
                endcase
                t_co = 2'd0;
            end
            7'd38: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd0;
            end
            7'd47: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h31;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd48: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h38;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd49: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h31;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h37;
                3'd6: t_ch = 8'h32;
                endcase
                t_co = 2'd0;
            end
            7'd50: begin
                case (I_span)
                3'd0: t_ch = 8'h37;
                3'd1: t_ch = 8'h38;
                3'd2: t_ch = 8'h33;
                3'd3: t_ch = 8'h37;
                3'd4: t_ch = 8'h37;
                3'd5: t_ch = 8'h2E;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd51: begin
                case (I_span)
                3'd0: t_ch = 8'h35;
                3'd1: t_ch = 8'h37;
                3'd2: t_ch = 8'h37;
                3'd3: t_ch = 8'h2E;
                3'd4: t_ch = 8'h35;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd0;
            end
            7'd52: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h2E;
                3'd2: t_ch = 8'h2E;
                3'd3: t_ch = 8'h35;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h32;
                endcase
                t_co = 2'd0;
            end
            7'd53: begin
                case (I_span)
                3'd0: t_ch = 8'h6B;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h35;
                endcase
                t_co = 2'd0;
            end
            7'd54: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd0;
            end
            7'd62: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd63: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd64: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h31;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h32;
                endcase
                t_co = 2'd0;
            end
            7'd65: begin
                case (I_span)
                3'd0: t_ch = 8'h31;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h31;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h37;
                endcase
                t_co = 2'd0;
            end
            7'd66: begin
                case (I_span)
                3'd0: t_ch = 8'h4D;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'h6B;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd0;
            end
            endcase
        end
        6'd40: begin
            case (cell_col_q)
            7'd1: begin
                case (I_span)
                3'd0: t_ch = 8'h53;
                3'd1: t_ch = 8'h53;
                3'd2: t_ch = 8'h53;
                3'd3: t_ch = 8'h53;
                3'd4: t_ch = 8'h53;
                3'd5: t_ch = 8'h53;
                3'd6: t_ch = 8'h53;
                endcase
                t_co = 2'd0;
            end
            7'd2: begin
                case (I_span)
                3'd0: t_ch = 8'h57;
                3'd1: t_ch = 8'h57;
                3'd2: t_ch = 8'h57;
                3'd3: t_ch = 8'h57;
                3'd4: t_ch = 8'h57;
                3'd5: t_ch = 8'h57;
                3'd6: t_ch = 8'h57;
                endcase
                t_co = 2'd0;
            end
            7'd3: begin
                case (I_span)
                3'd0: t_ch = 8'h54;
                3'd1: t_ch = 8'h54;
                3'd2: t_ch = 8'h54;
                3'd3: t_ch = 8'h54;
                3'd4: t_ch = 8'h54;
                3'd5: t_ch = 8'h54;
                3'd6: t_ch = 8'h54;
                endcase
                t_co = 2'd0;
            end
            7'd4: begin
                case (I_span)
                3'd0: t_ch = 8'h3A;
                3'd1: t_ch = 8'h3A;
                3'd2: t_ch = 8'h3A;
                3'd3: t_ch = 8'h3A;
                3'd4: t_ch = 8'h3A;
                3'd5: t_ch = 8'h3A;
                3'd6: t_ch = 8'h3A;
                endcase
                t_co = 2'd0;
            end
            7'd5: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd6: begin
                case (I_span)
                3'd0: t_ch = 8'h32;
                3'd1: t_ch = 8'h38;
                3'd2: t_ch = 8'h34;
                3'd3: t_ch = 8'h32;
                3'd4: t_ch = 8'h32;
                3'd5: t_ch = 8'h38;
                3'd6: t_ch = 8'h37;
                endcase
                t_co = 2'd0;
            end
            7'd7: begin
                case (I_span)
                3'd0: t_ch = 8'h2E;
                3'd1: t_ch = 8'h2E;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h2E;
                3'd5: t_ch = 8'h2E;
                3'd6: t_ch = 8'h35;
                endcase
                t_co = 2'd0;
            end
            7'd8: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h31;
                3'd2: t_ch = 8'h2E;
                3'd3: t_ch = 8'h34;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h31;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd0;
            end
            7'd9: begin
                case (I_span)
                3'd0: t_ch = 8'h34;
                3'd1: t_ch = 8'h39;
                3'd2: t_ch = 8'h39;
                3'd3: t_ch = 8'h2E;
                3'd4: t_ch = 8'h34;
                3'd5: t_ch = 8'h39;
                3'd6: t_ch = 8'h39;
                endcase
                t_co = 2'd0;
            end
            7'd10: begin
                case (I_span)
                3'd0: t_ch = 8'h38;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'h36;
                3'd3: t_ch = 8'h38;
                3'd4: t_ch = 8'h38;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd11: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h75;
                endcase
                t_co = 2'd0;
            end
            7'd12: begin
                case (I_span)
                3'd0: t_ch = 8'h6D;
                3'd1: t_ch = 8'h6D;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h73;
                3'd5: t_ch = 8'h73;
                3'd6: t_ch = 8'h73;
                endcase
                t_co = 2'd0;
            end
            7'd13: begin
                case (I_span)
                3'd0: t_ch = 8'h73;
                3'd1: t_ch = 8'h73;
                3'd2: t_ch = 8'h6D;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd14: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'h73;
                3'd3: t_ch = 8'h6D;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd15: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'd0;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'h73;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd17: begin t_ch = 8'h53; t_co = 2'd0; end
            7'd18: begin t_ch = 8'h74; t_co = 2'd0; end
            7'd19: begin t_ch = 8'h61; t_co = 2'd0; end
            7'd20: begin t_ch = 8'h72; t_co = 2'd0; end
            7'd21: begin t_ch = 8'h74; t_co = 2'd0; end
            7'd22: begin t_ch = 8'h3A; t_co = 2'd0; end
            7'd23: begin t_ch = 8'h20; t_co = 2'd0; end
            7'd24: begin t_ch = 8'h30; t_co = 2'd0; end
            7'd29: begin
                case (I_span)
                3'd0: t_ch = 8'h53;
                3'd1: t_ch = 8'h53;
                3'd2: t_ch = 8'h53;
                3'd3: t_ch = 8'h53;
                3'd4: t_ch = 8'h53;
                3'd5: t_ch = 8'h53;
                3'd6: t_ch = 8'h53;
                endcase
                t_co = 2'd0;
            end
            7'd30: begin
                case (I_span)
                3'd0: t_ch = 8'h74;
                3'd1: t_ch = 8'h74;
                3'd2: t_ch = 8'h74;
                3'd3: t_ch = 8'h74;
                3'd4: t_ch = 8'h74;
                3'd5: t_ch = 8'h74;
                3'd6: t_ch = 8'h74;
                endcase
                t_co = 2'd0;
            end
            7'd31: begin
                case (I_span)
                3'd0: t_ch = 8'h6F;
                3'd1: t_ch = 8'h6F;
                3'd2: t_ch = 8'h6F;
                3'd3: t_ch = 8'h6F;
                3'd4: t_ch = 8'h6F;
                3'd5: t_ch = 8'h6F;
                3'd6: t_ch = 8'h6F;
                endcase
                t_co = 2'd0;
            end
            7'd32: begin
                case (I_span)
                3'd0: t_ch = 8'h70;
                3'd1: t_ch = 8'h70;
                3'd2: t_ch = 8'h70;
                3'd3: t_ch = 8'h70;
                3'd4: t_ch = 8'h70;
                3'd5: t_ch = 8'h70;
                3'd6: t_ch = 8'h70;
                endcase
                t_co = 2'd0;
            end
            7'd33: begin
                case (I_span)
                3'd0: t_ch = 8'h3A;
                3'd1: t_ch = 8'h3A;
                3'd2: t_ch = 8'h3A;
                3'd3: t_ch = 8'h3A;
                3'd4: t_ch = 8'h3A;
                3'd5: t_ch = 8'h3A;
                3'd6: t_ch = 8'h3A;
                endcase
                t_co = 2'd0;
            end
            7'd34: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd35: begin
                case (I_span)
                3'd0: t_ch = 8'h31;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h31;
                3'd4: t_ch = 8'h31;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'h32;
                endcase
                t_co = 2'd0;
            end
            7'd36: begin
                case (I_span)
                3'd0: t_ch = 8'h2E;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h2E;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'h37;
                endcase
                t_co = 2'd0;
            end
            7'd37: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h2E;
                3'd3: t_ch = 8'h2E;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd0;
            end
            7'd38: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h2E;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h2E;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd39: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd40: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd41: begin
                case (I_span)
                3'd0: t_ch = 8'h4D;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'h6B;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd42: begin
                case (I_span)
                3'd0: t_ch = 8'h48;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'h48;
                3'd5: t_ch = 8'h48;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd0;
            end
            7'd43: begin
                case (I_span)
                3'd0: t_ch = 8'h7A;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h48;
                3'd3: t_ch = 8'h48;
                3'd4: t_ch = 8'h7A;
                3'd5: t_ch = 8'h7A;
                3'd6: t_ch = 8'h48;
                endcase
                t_co = 2'd0;
            end
            7'd44: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h48;
                3'd2: t_ch = 8'h7A;
                3'd3: t_ch = 8'h7A;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h7A;
                endcase
                t_co = 2'd0;
            end
            7'd45: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h7A;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd47: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h44;
                2'd1: t_ch = 8'h44;
                2'd2: t_ch = 8'h44;
                2'd3: t_ch = 8'h44;
                endcase
                t_co = 2'd0;
            end
            7'd48: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h65;
                2'd1: t_ch = 8'h65;
                2'd2: t_ch = 8'h65;
                2'd3: t_ch = 8'h65;
                endcase
                t_co = 2'd0;
            end
            7'd49: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h74;
                2'd1: t_ch = 8'h74;
                2'd2: t_ch = 8'h74;
                2'd3: t_ch = 8'h74;
                endcase
                t_co = 2'd0;
            end
            7'd50: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h3A;
                2'd1: t_ch = 8'h3A;
                2'd2: t_ch = 8'h3A;
                2'd3: t_ch = 8'h3A;
                endcase
                t_co = 2'd0;
            end
            7'd51: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h20;
                2'd1: t_ch = 8'h20;
                2'd2: t_ch = 8'h20;
                2'd3: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd52: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h50;
                2'd1: t_ch = 8'h53;
                2'd2: t_ch = 8'h41;
                2'd3: t_ch = 8'h4E;
                endcase
                t_co = 2'd0;
            end
            7'd53: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h6F;
                2'd1: t_ch = 8'h61;
                2'd2: t_ch = 8'h76;
                2'd3: t_ch = 8'h65;
                endcase
                t_co = 2'd0;
            end
            7'd54: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h73;
                2'd1: t_ch = 8'h6D;
                2'd2: t_ch = 8'h65;
                2'd3: t_ch = 8'h67;
                endcase
                t_co = 2'd0;
            end
            7'd55: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h20;
                2'd1: t_ch = 8'h70;
                2'd2: t_ch = 8'h72;
                2'd3: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd56: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h50;
                2'd1: t_ch = 8'h6C;
                2'd2: t_ch = 8'h61;
                2'd3: t_ch = 8'h50;
                endcase
                t_co = 2'd0;
            end
            7'd57: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h65;
                2'd1: t_ch = 8'h65;
                2'd2: t_ch = 8'h67;
                2'd3: t_ch = 8'h65;
                endcase
                t_co = 2'd0;
            end
            7'd58: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h61;
                2'd1: t_ch = 8'd0;
                2'd2: t_ch = 8'h65;
                2'd3: t_ch = 8'h61;
                endcase
                t_co = 2'd0;
            end
            7'd59: begin
                case (I_det_sel)
                2'd0: t_ch = 8'h6B;
                2'd1: t_ch = 8'd0;
                2'd2: t_ch = 8'd0;
                2'd3: t_ch = 8'h6B;
                endcase
                t_co = 2'd0;
            end
            endcase
        end
        6'd42: begin
            case (cell_col_q)
            7'd12: begin t_ch = 8'h4E; t_co = 2'd0; end
            7'd13: begin t_ch = 8'h46; t_co = 2'd0; end
            7'd14: begin t_ch = 8'h46; t_co = 2'd0; end
            7'd15: begin t_ch = 8'h54; t_co = 2'd0; end
            7'd16: begin t_ch = 8'h3A; t_co = 2'd0; end
            7'd17: begin t_ch = 8'h20; t_co = 2'd0; end
            7'd18: begin t_ch = 8'h34; t_co = 2'd0; end
            7'd19: begin t_ch = 8'h30; t_co = 2'd0; end
            7'd20: begin t_ch = 8'h39; t_co = 2'd0; end
            7'd21: begin t_ch = 8'h36; t_co = 2'd0; end
            7'd23: begin
                case (I_span)
                3'd0: t_ch = 8'h53;
                3'd1: t_ch = 8'h53;
                3'd2: t_ch = 8'h53;
                3'd3: t_ch = 8'h53;
                3'd4: t_ch = 8'h53;
                3'd5: t_ch = 8'h53;
                3'd6: t_ch = 8'h53;
                endcase
                t_co = 2'd0;
            end
            7'd24: begin
                case (I_span)
                3'd0: t_ch = 8'h70;
                3'd1: t_ch = 8'h70;
                3'd2: t_ch = 8'h70;
                3'd3: t_ch = 8'h70;
                3'd4: t_ch = 8'h70;
                3'd5: t_ch = 8'h70;
                3'd6: t_ch = 8'h70;
                endcase
                t_co = 2'd0;
            end
            7'd25: begin
                case (I_span)
                3'd0: t_ch = 8'h61;
                3'd1: t_ch = 8'h61;
                3'd2: t_ch = 8'h61;
                3'd3: t_ch = 8'h61;
                3'd4: t_ch = 8'h61;
                3'd5: t_ch = 8'h61;
                3'd6: t_ch = 8'h61;
                endcase
                t_co = 2'd0;
            end
            7'd26: begin
                case (I_span)
                3'd0: t_ch = 8'h6E;
                3'd1: t_ch = 8'h6E;
                3'd2: t_ch = 8'h6E;
                3'd3: t_ch = 8'h6E;
                3'd4: t_ch = 8'h6E;
                3'd5: t_ch = 8'h6E;
                3'd6: t_ch = 8'h6E;
                endcase
                t_co = 2'd0;
            end
            7'd27: begin
                case (I_span)
                3'd0: t_ch = 8'h3A;
                3'd1: t_ch = 8'h3A;
                3'd2: t_ch = 8'h3A;
                3'd3: t_ch = 8'h3A;
                3'd4: t_ch = 8'h3A;
                3'd5: t_ch = 8'h3A;
                3'd6: t_ch = 8'h3A;
                endcase
                t_co = 2'd0;
            end
            7'd28: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd29: begin
                case (I_span)
                3'd0: t_ch = 8'h31;
                3'd1: t_ch = 8'h32;
                3'd2: t_ch = 8'h35;
                3'd3: t_ch = 8'h31;
                3'd4: t_ch = 8'h31;
                3'd5: t_ch = 8'h32;
                3'd6: t_ch = 8'h32;
                endcase
                t_co = 2'd0;
            end
            7'd30: begin
                case (I_span)
                3'd0: t_ch = 8'h2E;
                3'd1: t_ch = 8'h35;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h2E;
                3'd5: t_ch = 8'h35;
                3'd6: t_ch = 8'h37;
                endcase
                t_co = 2'd0;
            end
            7'd31: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h2E;
                3'd3: t_ch = 8'h2E;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h2E;
                endcase
                t_co = 2'd0;
            end
            7'd32: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h2E;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h2E;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd33: begin
                case (I_span)
                3'd0: t_ch = 8'h30;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h30;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd34: begin
                case (I_span)
                3'd0: t_ch = 8'h20;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h30;
                3'd3: t_ch = 8'h30;
                3'd4: t_ch = 8'h20;
                3'd5: t_ch = 8'h30;
                3'd6: t_ch = 8'h30;
                endcase
                t_co = 2'd0;
            end
            7'd35: begin
                case (I_span)
                3'd0: t_ch = 8'h4D;
                3'd1: t_ch = 8'h30;
                3'd2: t_ch = 8'h20;
                3'd3: t_ch = 8'h20;
                3'd4: t_ch = 8'h6B;
                3'd5: t_ch = 8'h20;
                3'd6: t_ch = 8'h20;
                endcase
                t_co = 2'd0;
            end
            7'd36: begin
                case (I_span)
                3'd0: t_ch = 8'h48;
                3'd1: t_ch = 8'h20;
                3'd2: t_ch = 8'h6B;
                3'd3: t_ch = 8'h6B;
                3'd4: t_ch = 8'h48;
                3'd5: t_ch = 8'h48;
                3'd6: t_ch = 8'h4D;
                endcase
                t_co = 2'd0;
            end
            7'd37: begin
                case (I_span)
                3'd0: t_ch = 8'h7A;
                3'd1: t_ch = 8'h6B;
                3'd2: t_ch = 8'h48;
                3'd3: t_ch = 8'h48;
                3'd4: t_ch = 8'h7A;
                3'd5: t_ch = 8'h7A;
                3'd6: t_ch = 8'h48;
                endcase
                t_co = 2'd0;
            end
            7'd38: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h48;
                3'd2: t_ch = 8'h7A;
                3'd3: t_ch = 8'h7A;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'h7A;
                endcase
                t_co = 2'd0;
            end
            7'd39: begin
                case (I_span)
                3'd0: t_ch = 8'd0;
                3'd1: t_ch = 8'h7A;
                3'd2: t_ch = 8'd0;
                3'd3: t_ch = 8'd0;
                3'd4: t_ch = 8'd0;
                3'd5: t_ch = 8'd0;
                3'd6: t_ch = 8'd0;
                endcase
                t_co = 2'd0;
            end
            7'd43: begin t_ch = 8'h52; t_co = 2'd0; end
            7'd44: begin t_ch = 8'h42; t_co = 2'd0; end
            7'd45: begin t_ch = 8'h57; t_co = 2'd0; end
            7'd46: begin t_ch = 8'h3A; t_co = 2'd0; end
            7'd47: begin t_ch = 8'h20; t_co = 2'd0; end
            endcase
            put( 1, 42, 10, {"Win: ", win_long_r[39:0]}, 2'd0);
            put(48, 42, {1'b0, rbw_len_r}, rbw_s_r, 2'd0);
        end        default: ;
        endcase
    end

    reg [10:0] map_d;                                // {scale=0, color[1:0], ch[7:0]}

    always @(posedge I_pix_clk) map_d <= {1'b0, t_co, t_ch};

    //------------------------------------------------------------------
    // 光标读数字符: 顶栏第 4 行 (y=64..79, ROM 里整行为空) 的 22 个单元
    //   "MKR NNNNNN HZ -NN.N DB", 频率前导零消隐, dB 十位为 0 时消隐
    //   cell:  57..59=MKR  61..66=频率  68..69=HZ  71=负号  72..75=dB  77..78=DB
    //------------------------------------------------------------------
    wire csr_cell = I_csr_en && (cell_row_q == 6'd4) &&
                    (cell_col_q >= 7'd57) && (cell_col_q <= 7'd78);

    wire fv5 = (freq_val >= 20'd100000);
    wire fv4 = (freq_val >= 20'd10000);
    wire fv3 = (freq_val >= 20'd1000);
    wire fv2 = (freq_val >= 20'd100);
    wire fv1 = (freq_val >= 20'd10);

    reg [7:0] csr_ch;

    always @(freq_val or freq_bcd or db_bcd or cell_col_q or I_span
             or I_csr_mode or dfr_sign or ddb_sign) begin
        csr_ch = 8'd0;
        case (cell_col_q)
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
        7'd67: csr_ch = (I_span == 3'd6) ? "K" : 8'd32;   // 宽频档单位 KHZ
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

    //==================================================================
    // THD / SNR 读数 (每帧自然刷新, 单 12x12 乘法器 + 单宽位宽 log 串行复用)
    //   THD = 10lg(sum h2^2..h5^2) - 10lg(h1^2)      -> 显示 -xx.x dB
    //   SNR = 10lg(P) - 10lg(P - h1^2<<6)           -> 显示 xx.x dB
    //   10log10(x) = (963 * lg) >> 10 , lg = 32*log2(x) = {k[5:0], f[4:0]}
    //==================================================================
    function [5:0] msb36;
        input [35:0] v;
        integer i;
        begin
            msb36 = 6'd0;
            for (i = 0; i < 36; i = i + 1)
                if (v[i]) msb36 = i[5:0];
        end
    endfunction

    reg  [35:0] lg_in;
    reg  [5:0]  lg_k;
    reg  [6:0]  lg_f;          // 7 位小数 -> 对数分辨率 1/128 (≈0.023 dB)

    always @(lg_in) begin
        lg_k = msb36(lg_in);
        lg_f = 7'd0;
        if (lg_in != 36'd0)
            lg_f = ((lg_in << (6'd35 - {1'b0, lg_k})) >> 28) & 7'h7F;   // MSB 对齐到 bit35, 取 [34:28]
    end

    reg  [11:0] tq_a, tq_b;
    reg  [11:0] tq_a_r, tq_b_r;                  // 乘法器输入打拍, 断开 tq_cyc -> case -> DSP 的长组合链
    wire [23:0] tq_mul = tq_a_r * tq_b_r;

    reg  [3:0]  tq_cyc;
    reg  [23:0] tq_h, tq_s;
    reg  [29:0] tq_hx6;
    reg  [12:0] tq_lg_s, tq_lg_h, tq_lg_n;   // {k[5:0], f[6:0]} = 128*log2(x)
    reg  [11:0] thd_db10, snr_db10;

    // 功率累加器每列加的是 mag^2>>6, 基波只贡献 h1^2/64
    // tq_h = (h1>>4)^2 = h1^2/256, 而功率累加的单位是 mag^2/64 -> 乘 4 对齐
    wire [35:0] tq_h_pwr = {6'd0, tq_h, 2'b00};
    wire [35:0] tq_n_w = (I_pwr > tq_h_pwr) ? (I_pwr - tq_h_pwr) : 36'd0;
    wire [12:0] tq_lg_hp = tq_lg_h + 13'd256;      // 基波在功率累加刻度下的对数 (h1^2/64 = tq_h * 4)

    always @(*) begin
        case (tq_cyc)
        4'd0:    begin tq_a = I_h1[15:4]; tq_b = I_h1[15:4]; end
        4'd1:    begin tq_a = I_h2[15:4]; tq_b = I_h2[15:4]; end
        4'd2:    begin tq_a = I_h3[15:4]; tq_b = I_h3[15:4]; end
        4'd3:    begin tq_a = I_h4[15:4]; tq_b = I_h4[15:4]; end
        4'd4:    begin tq_a = I_h5[15:4]; tq_b = I_h5[15:4]; end
        default: begin tq_a = 12'd0;      tq_b = 12'd0;      end
        endcase
    end

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            tq_cyc   <= 4'd0;
            tq_h     <= 24'd0;
            tq_s     <= 24'd0;
            tq_hx6   <= 30'd0;
            tq_lg_s  <= 13'd0;
            tq_lg_h  <= 13'd0;
            tq_lg_n  <= 13'd0;
            thd_db10 <= 12'd0;
            snr_db10 <= 12'd0;
            lg_in    <= 36'd0;
            tq_a_r   <= 12'd0;
            tq_b_r   <= 12'd0;
        end else begin
            tq_cyc <= (tq_cyc == 4'd13) ? 4'd0 : tq_cyc + 4'd1;
            tq_a_r <= tq_a;                          // 乘法器输入每拍打拍, 切断 tq_cyc -> case -> DSP 的长组合链
            tq_b_r <= tq_b;
            case (tq_cyc)
            4'd1: begin
                tq_h   <= tq_mul;
                tq_hx6 <= {tq_mul, 6'd0};
            end
            4'd2: tq_s <= tq_mul;
            4'd3: tq_s <= tq_s + tq_mul;
            4'd4: tq_s <= tq_s + tq_mul;
            4'd5: tq_s <= tq_s + tq_mul;
            4'd6: lg_in <= {12'd0, tq_s};
            4'd7: begin
                tq_lg_s <= {lg_k, lg_f};
                lg_in   <= {12'd0, tq_h};
            end
            4'd8: begin
                tq_lg_h <= {lg_k, lg_f};
                lg_in   <= tq_n_w;
            end
            4'd9: tq_lg_n <= {lg_k, lg_f};
            4'd10: begin
                if (tq_lg_s == 13'd0 || tq_lg_h <= tq_lg_s)
                    thd_db10 <= 12'd0;
                else if (tq_lg_h - tq_lg_s > 13'd4250)
                    thd_db10 <= 12'd999;
                else
                    thd_db10 <= (963 * (tq_lg_h - tq_lg_s)) >> 12;
            end
            4'd11: begin
                // SNR = 10lg(h1^2/64) - 10lg(N) = lg(h1^2/64) - lgN (lg = 128*log2)
                if (tq_lg_n == 13'd0)
                    snr_db10 <= 12'd0;
                else if (tq_lg_hp <= tq_lg_n)
                    snr_db10 <= 12'd0;
                else if ((tq_lg_hp - tq_lg_n) > 13'd4250)
                    snr_db10 <= 12'd999;
                else
                    snr_db10 <= (963 * (tq_lg_hp - tq_lg_n)) >> 12;
            end
            4'd13: tq_s <= 24'd0;
            default: ;
            endcase
        end
    end

    // 12bit (0..999, 单位 0.1dB) -> 百/十/个
    wire [9:0] thd_v  = {4'd0, thd_db10[11:0]};
    wire [9:0] snr_v  = {4'd0, snr_db10[11:0]};
    wire [3:0] thd_c  = thd_v / 10'd100;
    wire [3:0] thd_t  = (thd_v / 10'd10) - ((thd_v / 10'd100) * 4'd10);
    wire [3:0] thd_o  = thd_v - ((thd_v / 10'd10) * 4'd10);
    wire [3:0] snr_c  = snr_v / 10'd100;
    wire [3:0] snr_t  = (snr_v / 10'd10) - ((snr_v / 10'd100) * 4'd10);
    wire [3:0] snr_o  = snr_v - ((snr_v / 10'd10) * 4'd10);

    // 行 5: "THD -42.1 dB   SNR 61.2 dB" (格 1..23)
    wire tti_cell = I_hrm_valid && (I_hrm_span == I_span) && (cell_row_q == 6'd5) &&
                    (cell_col_q >= 7'd1) && (cell_col_q <= 7'd24);

    reg [7:0] tti_ch;

    always @(cell_col_q or thd_c or thd_t or thd_o or snr_c or snr_t or snr_o) begin
        tti_ch = 8'd0;
        case (cell_col_q)
        7'd1:  tti_ch = "T";
        7'd2:  tti_ch = "H";
        7'd3:  tti_ch = "D";
        7'd5:  tti_ch = "-";
        7'd6:  tti_ch = (thd_c == 4'd0) ? 8'd32 : (8'h30 + {4'd0, thd_c});
        7'd7:  tti_ch = 8'h30 + {4'd0, thd_t};
        7'd8:  tti_ch = ".";
        7'd9:  tti_ch = 8'h30 + {4'd0, thd_o};
        7'd11: tti_ch = "d";
        7'd12: tti_ch = "B";
        7'd14: tti_ch = "S";
        7'd15: tti_ch = "N";
        7'd16: tti_ch = "R";
        7'd18: tti_ch = (snr_c == 4'd0) ? 8'd32 : (8'h30 + {4'd0, snr_c});
        7'd19: tti_ch = 8'h30 + {4'd0, snr_t};
        7'd20: tti_ch = ".";
        7'd21: tti_ch = 8'h30 + {4'd0, snr_o};
        7'd23: tti_ch = "d";
        7'd24: tti_ch = "B";
        default: ;
        endcase
    end

    // 谐波表单元: 行 4 格 1..35, "H2 -12.2  H3 -18.2  H4 -24.2  H5 -28.3"
    // 跨度门控: 换档后 1~2 帧测量值还是旧档坐标, 先隐藏 (与标记同一策略)
    wire hrm_span_disp = (I_hrm_span == I_span);

    wire h_cell = I_hrm_valid && hrm_span_disp && (cell_row_q == 6'd4) &&
                  (cell_col_q >= 7'd1) && (cell_col_q <= 7'd35);

    // F0 大读数: 行 2 格 57..69, "F0 100000 HZ" (kHz 刻度同 MKR)
    wire f0_cell = I_hrm_valid && hrm_span_disp && (cell_row_q == 6'd2) &&
                   (cell_col_q >= 7'd57) && (cell_col_q <= 7'd69);
    wire f0v5 = (f0_val >= 20'd100000);
    wire f0v4 = (f0_val >= 20'd10000);
    wire f0v3 = (f0_val >= 20'd1000);
    wire f0v2 = (f0_val >= 20'd100);
    wire f0v1 = (f0_val >= 20'd10);
    reg  [7:0] f0_ch;

    always @(cell_col_q or f0_val or f0_bcd or I_span) begin
        f0_ch = 8'd0;
        case (cell_col_q)
        7'd57: f0_ch = "F";
        7'd58: f0_ch = "0";
        7'd60: f0_ch = ":";
        7'd61: f0_ch = f0v5 ? 8'h30 + {4'd0, f0_bcd[23:20]} : 8'd32;
        7'd62: f0_ch = f0v4 ? 8'h30 + {4'd0, f0_bcd[19:16]} : 8'd32;
        7'd63: f0_ch = f0v3 ? 8'h30 + {4'd0, f0_bcd[15:12]} : 8'd32;
        7'd64: f0_ch = f0v2 ? 8'h30 + {4'd0, f0_bcd[11:8]}  : 8'd32;
        7'd65: f0_ch = f0v1 ? 8'h30 + {4'd0, f0_bcd[7:4]}   : 8'd32;
        7'd66: f0_ch = 8'h30 + {4'd0, f0_bcd[3:0]};
        7'd67: f0_ch = (I_span == 3'd6) ? "K" : 8'd32;
        7'd68: f0_ch = "H";
        7'd69: f0_ch = "Z";
        default: ;
        endcase
    end

    reg [7:0] h_ch;

    always @(cell_col_q or h2_bcd or h3_bcd or h4_bcd or h5_bcd) begin
        h_ch = 8'd0;
        case (cell_col_q)
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
                            f0_cell  ? {1'b0, 2'd1, f0_ch}  :
                            tti_cell ? {1'b0, 2'd1, tti_ch} : map_d;

    reg [11:0] x1, y1;
    reg [9:0]  bin1;
    reg [4:0]  px1, py1;
    reg        t_vld1;
    reg [4:0]  px0, py0;          // 与 cell_*_q 同拍, 保证字形列相位对齐 (见上)

    // ★ 文字层再打一拍: map_d_eff 是 4 路 mux (光标/谐波表/F0/普通文字),
    //   它直接驱动字模 ROM 的 I_ch 与颜色/尺寸位, 构成像素域最差路径
    //   (u_display/cell_col_q -> map_d_eff -> 字模地址). 这里插一级 map_e,
    //   并把字形的行/列相位 (px_e/py_e) 同步延后一级.
    reg [10:0] map_e;
    reg [4:0]  px_e, py_e;
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            map_e <= 11'd0;  px_e <= 5'd0;  py_e <= 5'd0;
        end else begin
            map_e <= map_d_eff;
            px_e  <= px1;
            py_e  <= py1;
        end
    end

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x1 <= 12'd0;  y1 <= 12'd0;  bin1 <= 10'd0;
            px0 <= 5'd0;  py0 <= 5'd0;
            px1 <= 5'd0;  py1 <= 5'd0;  t_vld1 <= 1'b0;
        end else begin
            px0 <= I_x[4:0];  py0 <= I_y[4:0];
            x1 <= I_x;  y1 <= I_y;  bin1 <= bin_addr;
            px1 <= px0;  py1 <= py0;
            t_vld1 <= (map_d_eff[7:0] != 8'd0);
        end
    end

    //==================================================================
    // 第 2 级: 字模 ROM (同步读, BSRAM)
    //   scale=1 时字高 32, 行/列取 5bit 里的高 3 位; scale=0 时字高 16
    //==================================================================
    wire [2:0] glyph_row = map_e[10] ? py_e[4:2] : py_e[3:1];

    wire [7:0] font_bits;

    ui_font_rom u_font_rom (
        .I_clk  (I_pix_clk   ),
        .I_ch   (map_e[7:0]      ),
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
            x2 <= x1;  y2 <= y1;  bin2 <= bin1;  px2 <= px_e;
            color2 <= map_e[9:8];
            scale2 <= map_e[10];
            t_vld2 <= (map_e[7:0] != 8'd0);
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

    // ★ v1.7.4: 谐波标记改成"距离位图表" (1024 x 16, 占 1 块 BSRAM)。
    //   原来这里是 5 路 13bit 乘 (3/4/5 倍列号) + 5 路求绝对差 + 5 路比较
    //   + AND 树, 实测 u_display/px_e_2_s0 -> u_display/hrm_v4_s0 共 15 级 /
    //   +0.415ns 是全设计最差路径。改法: 每帧用 2048 拍把"本列到各次谐波列
    //   的距离"预先算好写进 hmtab (每列 5 个 3bit, 上限截到 7), 像素域只剩
    //   一个 3bit 比较。距离 >= 6 时三角 (yr<=5) 和虚线的判据都不会命中,
    //   所以截到 7 与原判据完全等价; 谐波列出屏 (HV=0) 时写 7 -> 永不命中。
    reg  [15:0] hmtab [0:1023];
    reg  [9:0]  hmsa;                 // 扫描地址
    reg         hmsa_ph;              // 0: 算距离  1: 写入
    reg  [9:0]  hmsa_d;
    reg  [2:0]  hm_d1, hm_d2, hm_d3, hm_d4, hm_d5;
    reg         hm_we;
    reg  [15:0] hm_wd;

    reg  [15:0] hm_rd;                // 像素域读出 (地址取 xr2, 数据在第 3 级可用)

    // 各次谐波列号 (列 = 2 个 bin)
    wire [13:0] hc1x = {4'b0000, I_hrm_col};
    wire [13:0] hc2x = {3'b000, I_hrm_col, 1'b0};
    wire [13:0] hc3x = ({3'b000, I_hrm_col} << 1) + {4'b0000, I_hrm_col};
    wire [13:0] hc4x = {2'b00, I_hrm_col, 2'b00};
    wire [13:0] hc5x = ({2'b00, I_hrm_col, 2'b00}) + {4'b0000, I_hrm_col};

    // 谐波列超出屏幕 (k*I_hrm_col > 1023) 时不画 (低位截断会产生假位置)
    wire hm_v1 = (hc1x <= 14'd1023);
    wire hm_v2 = (hc2x <= 14'd1023);
    wire hm_v3 = (hc3x <= 14'd1023);
    wire hm_v4 = (hc4x <= 14'd1023);
    wire hm_v5 = (hc5x <= 14'd1023);

    // |列 - 谐波列|, 截到 7
    function [2:0] hm_dist;
        input [13:0] c;
        input [13:0] h;
        input        v;
        reg   [13:0] d;
        begin
            d = (c > h) ? (c - h) : (h - c);
            if (!v || (d > 14'd7)) hm_dist = 3'd7;
            else                   hm_dist = d[2:0];
        end
    endfunction

    wire [13:0] hmsa_x = {4'b0000, hmsa};

    // 扫描: 2 拍一个 entry (拍 0 算 5 个距离 -> 拍 1 拼字写入), 自由运行
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            hmsa    <= 10'd0;
            hmsa_ph <= 1'b0;
            hmsa_d  <= 10'd0;
            hm_d1   <= 3'd7;  hm_d2 <= 3'd7;  hm_d3 <= 3'd7;  hm_d4 <= 3'd7;  hm_d5 <= 3'd7;
            hm_we   <= 1'b0;
            hm_wd   <= 16'd0;
        end else begin
            hm_we <= 1'b0;
            if (!hmsa_ph) begin
                hm_d1   <= hm_dist(hmsa_x, hc1x, hm_v1);
                hm_d2   <= hm_dist(hmsa_x, hc2x, hm_v2);
                hm_d3   <= hm_dist(hmsa_x, hc3x, hm_v3);
                hm_d4   <= hm_dist(hmsa_x, hc4x, hm_v4);
                hm_d5   <= hm_dist(hmsa_x, hc5x, hm_v5);
                hmsa_d  <= hmsa;
                hmsa_ph <= 1'b1;
            end else begin
                hm_we   <= 1'b1;
                hm_wd   <= {1'b0, hm_d5, hm_d4, hm_d3, hm_d2, hm_d1};
                hmsa    <= hmsa + 10'd1;
                hmsa_ph <= 1'b0;
            end
        end
    end

    always @(posedge I_pix_clk) if (hm_we) hmtab[hmsa_d] <= hm_wd;

    // 像素域读: 地址用第 2 级的列号 (xr2), 读出数据正好在第 3 级与 x3/y3 同拍
    wire [9:0] xr2 = x2[9:0] - 10'd64;
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) hm_rd <= 16'h7FFF;
        else              hm_rd <= hmtab[(xr2 <= 10'd1023) ? xr2 : 10'd0];
    end

    wire [2:0] hm1 = hm_rd[2:0];
    wire [2:0] hm2 = hm_rd[5:3];
    wire [2:0] hm3 = hm_rd[8:6];
    wire [2:0] hm4 = hm_rd[11:9];
    wire [2:0] hm5 = hm_rd[14:12];

    wire hrm_top3  = (yr3 <= 10'd5);
    wire hrm_dash3 = (yr3 >= 10'd6) && (yr3[1:0] == 2'b00);

    wire hrm_span_ok = (I_hrm_span == I_span);
    wire hrm_gate3   = in_plot3 && I_hrm_valid && hrm_span_ok;

    wire hrm1_c = hrm_gate3 && (hrm_top3 ? (hm1 <= yr3[2:0]) : (hrm_dash3 && (hm1 == 3'd0)));
    wire hrm2_c = hrm_gate3 && (hrm_top3 ? (hm2 <= yr3[2:0]) : (hrm_dash3 && (hm2 == 3'd0)));
    wire hrm3_c = hrm_gate3 && (hrm_top3 ? (hm3 <= yr3[2:0]) : (hrm_dash3 && (hm3 == 3'd0)));
    wire hrm4_c = hrm_gate3 && (hrm_top3 ? (hm4 <= yr3[2:0]) : (hrm_dash3 && (hm4 == 3'd0)));
    wire hrm5_c = hrm_gate3 && (hrm_top3 ? (hm5 <= yr3[2:0]) : (hrm_dash3 && (hm5 == 3'd0)));

    // 光标竖线: 顶部 6 行实心小竖条 + 其下隔行虚线 (与谐波同法提前一级寄存)
    wire csr_line_c = I_csr_en && in_plot3 && (xr3 == I_csr_col) &&
                      ((yr3 <= 10'd5) || (yr3[0] == 1'b0));

    // 增量参考线: 隔行虚线 (无顶条, 与主光标区分)
    wire cref_line_c = (I_csr_mode == 2'd2) && in_plot3 &&
                       (xr3 == csr_ref_col) && (yr3[0] == 1'b0);

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


    // (谐波命中 hrm_v1..5 已在第 4 级寄存, 见上方)

    wire trace_cap = in_plot && (yr >= bar4) && (yr <= (bar4 + 10'd1));
    wire trace_seg = in_plot && (x4 > PX0) && (yr >= seg_lo) && (yr <= (seg_hi + 10'd1));
    wire on_trace  = trace_cap || trace_seg;
    wire on_peak   = in_plot && pkvld4 && ((yr == pk4) || (yr == (pk4 + 10'd1)));

    // 右侧按钮: 每 5 行一个按钮 (4 行按钮 + 1 行间隔), 从第 7 行开始
    wire [5:0] row4 = y4[9:4];
    // 6 个按钮带 (4 行一节, 标签与数值之间空一行): Res BW/Window/Detector/Trace/Avg/Span
    // Res BW 6..9 / Window 11..14 / Detector 16..19 / Trace 21..24 / Avg 26..29 / Span 31..34
    wire in_btn = ((row4 >= 6)  && (row4 <= 9))  || ((row4 >= 11) && (row4 <= 14)) ||
                  ((row4 >= 16) && (row4 <= 19)) || ((row4 >= 21) && (row4 <= 24)) ||
                  ((row4 >= 26) && (row4 <= 29)) || ((row4 >= 31) && (row4 <= 34));
    // Window 按钮在 17..20 行 (in_btn 第 3 组), 高亮必须与按钮同区间;
    // 旧值 18..21 会让高亮压到 21 行 (按钮间空隙) 而漏掉首行
    // 菜单高亮: 选中项的行区间预先打拍 (避免在 row4 -> sel_c 这一拍加比较器树)
    reg [5:0] btn_lo_r, btn_hi_r;
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin btn_lo_r <= 6'd6; btn_hi_r <= 6'd9; end
        else case (I_menu_sel)
            3'd0: begin btn_lo_r <= 6'd6;  btn_hi_r <= 6'd9;  end
            3'd1: begin btn_lo_r <= 6'd11; btn_hi_r <= 6'd14; end
            3'd2: begin btn_lo_r <= 6'd16; btn_hi_r <= 6'd19; end
            3'd3: begin btn_lo_r <= 6'd21; btn_hi_r <= 6'd24; end
            3'd4: begin btn_lo_r <= 6'd26; btn_hi_r <= 6'd29; end
            default: begin btn_lo_r <= 6'd31; btn_hi_r <= 6'd34; end
        endcase
    end
    wire btn_hi = I_menu_on && (row4 >= btn_lo_r) && (row4 <= btn_hi_r);

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

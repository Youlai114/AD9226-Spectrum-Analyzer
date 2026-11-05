// ============================================================================
// wave_display.v  --  时域波形 (示波器) 显示子系统
//
//   与 spec_display 同构的 6 级像素流水线, 版面/网格位置一致,
//   在 video_top 里按显示模式二选一输出 RGB (两级流水线延迟相同, 可直接切换)。
//
//   数据: wave_cap 采集的 1024 点波形 (Q4 有符号, ±32768 = ±1V)
//         经 spec_data_if + spec_ram 乒乓双时钟缓存后按列读出绘制。
//
//   时基 (可缩放): 记录 1024 点, 屏幕画其中的前 NSEL 点, 每点占 4<<zoom 列
//     zoom 0: 256 点 (每点 4 列)   zoom 1: 128 点 (8 列)
//     zoom 2:  64 点 (16 列)       zoom 3:  32 点 (32 列)
//   相邻样点间线性内插。第 2 行显示的窗口 = 屏幕上实际看到的时间跨度。
//
//   纵轴: 幅度档 amp 0..3 = 满屏 ±2V / ±1V / ±0.5V / ±0.25V
//         行值 = 256 + (y >> (8-amp)); 0V 恒在正中
//         (本设计沿用原有时域映射: 正电压 -> 行值变大, 与既有刻度文字一致;
//          上板若发现极性与刻度相反, 只需把 v_row 与 harm_est 的 row_v 两处
//          的 "+" 改成 "-" 即可)
//
//   谐波迹线: harm_est 每帧算出 1~5 次谐波的行值 (5 lane x 10bit, 50bit/列),
//             存在 harm_ram 的乒乓 RAM 里, 每个像素只需 1 次读就拿全 5 条;
//             原始波形 (灰线) 可用 KEY4 单独关掉, 只留 5 条分量。
//
//   波形 RAM 读时序 (spec_ram 打一拍):
//     每拍固定发地址 widx+1; 列 X 第 2 级拿到 smp[w(X)+1] (下一样点),
//     其打一拍就是 smp[w(X)] (当前样点, 因为 sub=0 列的前一列 widx 恰为 w-1)。
//     于是在 sub=0 的列锁存 {cur, nxt} 样点对, 其余列复用。
//     谐波 RAM 用同一套地址/节拍, 只是每列多 5 个 lane。
// ============================================================================
module wave_display (
    input             I_pix_clk    ,
    input             I_pix_rst_n  ,
    input      [11:0] I_x          ,   // 像素列
    input      [11:0] I_y          ,   // 像素行
    input      [2:0]  I_span       ,   // 跨度档 (决定时基文字与采样率)
    input      [1:0]  I_amp        ,   // 幅度档: 0=±2V 1=±1V 2=±0.5V 3=±0.25V
    input      [1:0]  I_zoom       ,   // 时基缩放: 0=256pt 1=128pt 2=64pt 3=32pt
    input             I_orig       ,   // 1=画原始波形 (灰线)
    input             I_hvalid     ,   // 1=本帧检测到基波 (谐波迹线有效)
    // ---- 数据写入接口 (与像素时钟可异步, 来自 wave_cap) ----
    input             I_wr_clk     ,
    input             I_wr_rst_n   ,
    input             I_frame_start,   // 单拍: 本帧第一次写 (触发时刻)
    input             I_wr_en      ,
    input      [9:0]  I_wr_addr    ,
    input      [15:0] I_wr_mag     ,   // 样点 (Q4 有符号)
    // ---- 谐波行值写入流 (adc_clk 域, 来自 harm_est) ----
    input             I_hwe        ,
    input      [7:0]  I_haddr      ,
    input      [49:0] I_hrows      ,
    // ---- 像素输出 ----
    output reg [7:0]  O_r          ,
    output reg [7:0]  O_g          ,
    output reg [7:0]  O_b
);

    //==================================================================
    // 版面参数 (与 spec_display 完全一致)
    //==================================================================
    localparam [11:0] PX0     = 12'd64;
    localparam [11:0] PX1     = 12'd1087;
    localparam [11:0] PY0     = 12'd104;
    localparam [11:0] PY1     = 12'd615;
    localparam [11:0] PANEL_X = 12'd1104;
    localparam [11:0] TOP_H   = 12'd96;
    localparam [11:0] BOT_Y   = 12'd624;

    // 配色 (chrome/网格与频谱页一致; 5 条谐波用基波/谐波标记同款颜色)
    localparam [23:0] C_BG     = 24'h00_00_00;
    localparam [23:0] C_CHROME = 24'h0C_12_1A;
    localparam [23:0] C_PANEL  = 24'h0E_16_22;
    localparam [23:0] C_SEP    = 24'h28_38_50;
    localparam [23:0] C_GRID   = 24'h22_30_40;
    localparam [23:0] C_PLOT   = 24'h00_00_00;
    localparam [23:0] C_ZERO   = 24'h1E_5E_46;   // 0V 基准线 (暗绿)
    localparam [23:0] C_ORIG   = 24'h8A_9A_A8;   // 原始波形 (灰)
    localparam [23:0] C_H1     = 24'h00_E8_64;   // 基波 (绿)
    localparam [23:0] C_H2     = 24'h00_D0_FF;   // 2 次 (青)
    localparam [23:0] C_H3     = 24'hFF_60_D8;   // 3 次 (品红)
    localparam [23:0] C_H4     = 24'hFF_A0_20;   // 4 次 (橙)
    localparam [23:0] C_H5     = 24'hB0_70_FF;   // 5 次 (紫)
    localparam [23:0] C_TXT0   = 24'hC8_D8_E8;
    localparam [23:0] C_TXT1   = 24'h00_E0_50;   // 与 spec_display 一致 (纯绿)
    localparam [23:0] C_TXT2   = 24'h66_E8_FF;

    //==================================================================
    // 数据通路: wave_cap -> 乒乓缓存 -> 像素域按列读
    //==================================================================
    wire        wr_en;
    wire        wr_bank;
    wire [9:0]  wr_addr;
    wire [15:0] wr_data;
    wire        rd_bank;

    spec_data_if u_data_if (
        .I_wr_clk      (I_wr_clk     ),
        .I_wr_rst_n    (I_wr_rst_n   ),
        .I_frame_start (I_frame_start),
        .I_wr_en       (I_wr_en      ),
        .I_wr_addr     (I_wr_addr    ),
        .I_wr_mag      (I_wr_mag     ),
        .I_rd_clk      (I_pix_clk    ),
        .I_rd_rst_n    (I_pix_rst_n  ),
        .O_wr_en       (wr_en        ),
        .O_wr_bank     (wr_bank      ),
        .O_wr_addr     (wr_addr      ),
        .O_wr_mag      (wr_data      ),
        .O_rd_bank     (rd_bank      ),
        .O_frame_cnt   (             ),
        .O_frame_tog   (             )
    );

    reg  [9:0]  rd_addr;
    wire [15:0] wv_ram;

    spec_ram u_wave_ram (
        .I_wr_clk  (I_wr_clk ),
        .I_wr_en   (wr_en    ),
        .I_wr_bank (wr_bank  ),
        .I_wr_addr (wr_addr  ),
        .I_wr_data (wr_data  ),
        .I_rd_clk  (I_pix_clk),
        .I_rd_bank (rd_bank  ),
        .I_rd_addr (rd_addr  ),
        .O_rd_data (wv_ram   )
    );

    // ---- 谐波行值 RAM (与波形 RAM 共用 bank 与读出节拍) ----
    reg  [7:0]  h_addr;
    wire [49:0] h_ram;
    reg  [49:0] h_ram_d;

    harm_ram u_harm_ram (
        .I_wr_clk  (I_wr_clk ),
        .I_wr_en   (I_hwe    ),
        .I_wr_bank (wr_bank  ),
        .I_wr_addr (I_haddr  ),
        .I_wr_data (I_hrows  ),
        .I_rd_clk  (I_pix_clk),
        .I_rd_bank (rd_bank  ),
        .I_rd_addr (h_addr   ),
        .O_rd_data (h_ram    )
    );

    // 地址规则: 每拍发 widx+1 (widx = (x-64)>>(2+zoom)), 最后一列钉住
    wire [11:0] xoff = I_x - 12'd64;
    wire [9:0]  widx = xoff[9:0] >> (2 + I_zoom);
    wire [7:0]  hnxt = (widx[7:0] == 8'd255) ? 8'd255 : (widx[7:0] + 8'd1);

    always @(posedge I_pix_clk) rd_addr  <= widx + 10'd1;
    always @(posedge I_pix_clk) h_addr   <= hnxt;
    always @(posedge I_pix_clk) h_ram_d  <= h_ram;

    //==================================================================
    // 文字标签: 80x45 个 16px 单元, 组合逻辑判定 (行,列) 落在哪个标签里
    //   put(r0, c0, len, 字符串, 颜色): 命中则输出该列字符
    //   颜色码: 0/1/2 = 常规三色, 3..7 = H1..H5 的迹线色 (图例用)
    //==================================================================
    wire [5:0]  cell_row = (I_y[11:4] > 6'd44) ? 6'd44 : I_y[11:4];
    wire [6:0]  cell_col = (I_x[11:4] > 7'd79) ? 7'd79 : I_x[11:4];

    // 文字取字符要经过 "288bit 字符串 -> 变址移位 -> 8bit", 直接从 I_x 出发
    // 会有 (比较器 + 变量移位) 两级串联, 是像素域的时序瓶颈 (v1.2.0 布线
    // slack 只剩 +0.024ns). 把单元坐标打一拍再取字符, 文字整体右移 1 像素
    // (肉眼不可见), 关键路径就只剩移位器本身.
    reg [5:0] cell_row_d;
    reg [6:0] cell_col_d;
    always @(posedge I_pix_clk) begin
        cell_row_d <= cell_row;
        cell_col_d <= cell_col;
    end

    reg  [7:0]  t_ch;
    reg  [2:0]  t_co;
    reg         t_vld;

    task put;
        input integer  r0;
        input integer  c0;
        input integer  len;
        input [287:0]  s;
        input [2:0]    colr;
        integer k;
        begin
            if ((cell_row_d == r0[5:0]) && (cell_col_d >= c0) && (cell_col_d < c0 + len)) begin
                k    = (len - 1) - (cell_col_d - c0);
                t_ch = s[k*8 +: 8];
                t_co = colr;
                t_vld = 1'b1;
            end
        end
    endtask

    // 敏感列表必须显式列出 (任务内部读取的信号, always @(*) 对老工具不可靠)
    always @(cell_row_d or cell_col_d or I_span or I_amp or I_zoom or I_orig or I_hvalid) begin
        t_ch  = 8'd0;
        t_co  = 3'd0;
        t_vld = 1'b0;

        put(1, 2, 21, "WAVEFORM  TIME DOMAIN", 2'd0);

        // 纵轴电压刻度 (随幅度档; 0V 恒在正中)
        case (I_amp)
        2'd0: begin                                  // 满屏 ±2V
            put( 6, 0, 3, "+2V", 2'd2);
            put(14, 0, 3, "+1V", 2'd2);
            put(30, 0, 3, "-1V", 2'd2);
            put(38, 0, 3, "-2V", 2'd2);
        end
        2'd1: begin                                  // ±1V (默认)
            put( 6, 0, 3, "+1V", 2'd2);
            put(14, 0, 4, "+.5V", 2'd2);
            put(30, 0, 4, "-.5V", 2'd2);
            put(38, 0, 3, "-1V", 2'd2);
        end
        2'd2: begin                                  // ±0.5V
            put( 6, 0, 4, "+.5V", 2'd2);
            put(14, 0, 4, "+.25", 2'd2);
            put(30, 0, 4, "-.25", 2'd2);
            put(38, 0, 4, "-.5V", 2'd2);
        end
        default: begin                               // ±0.25V
            put( 6, 0, 4, "+.25", 2'd2);
            put(14, 0, 4, "+.12", 2'd2);
            put(30, 0, 4, "-.12", 2'd2);
            put(38, 0, 4, "-.25", 2'd2);
        end
        endcase
        put(22, 0, 2, "0V", 2'd2);

        // 第 2 行: 屏幕窗口 / 采样率 (随跨度 + 时基缩放)
        case ({I_span, I_zoom})
        5'd0 : put(2, 2, 31, "Window: 128us  Rate: 2.00MS/s", 2'd1);
        5'd1 : put(2, 2, 31, "Window:  64us  Rate: 2.00MS/s", 2'd1);
        5'd2 : put(2, 2, 31, "Window:  32us  Rate: 2.00MS/s", 2'd1);
        5'd3 : put(2, 2, 31, "Window:  16us  Rate: 2.00MS/s", 2'd1);
        5'd4 : put(2, 2, 31, "Window: 512us  Rate:  500KS/s", 2'd1);
        5'd5 : put(2, 2, 31, "Window: 256us  Rate:  500KS/s", 2'd1);
        5'd6 : put(2, 2, 31, "Window: 128us  Rate:  500KS/s", 2'd1);
        5'd7 : put(2, 2, 31, "Window:  64us  Rate:  500KS/s", 2'd1);
        5'd8 : put(2, 2, 31, "Window: 2.56ms Rate:  100KS/s", 2'd1);
        5'd9 : put(2, 2, 31, "Window: 1.28ms Rate:  100KS/s", 2'd1);
        5'd10: put(2, 2, 31, "Window: 640us  Rate:  100KS/s", 2'd1);
        5'd11: put(2, 2, 31, "Window: 320us  Rate:  100KS/s", 2'd1);
        5'd12: put(2, 2, 31, "Window: 12.8ms Rate:   20KS/s", 2'd1);
        5'd13: put(2, 2, 31, "Window: 6.4ms  Rate:   20KS/s", 2'd1);
        5'd14: put(2, 2, 31, "Window: 3.2ms  Rate:   20KS/s", 2'd1);
        5'd15: put(2, 2, 31, "Window: 1.6ms  Rate:   20KS/s", 2'd1);
        5'd16: put(2, 2, 31, "Window: 4.74us Rate: 54.0MS/s", 2'd1);
        5'd17: put(2, 2, 31, "Window: 2.37us Rate: 54.0MS/s", 2'd1);
        5'd18: put(2, 2, 31, "Window: 1.18us Rate: 54.0MS/s", 2'd1);
        default: put(2, 2, 31, "Window: 592ns  Rate: 54.0MS/s", 2'd1);
        endcase

        // 第 39 行 (底栏): 时间刻度 0 / 半屏 / 满屏
        put(39,  4, 1, "0", 2'd2);
        case ({I_span, I_zoom})
        5'd0 : begin put(39,36,4,"64us",  2'd2); put(39,66,5,"128us", 2'd2); end
        5'd1 : begin put(39,36,4,"32us",  2'd2); put(39,66,4,"64us",  2'd2); end
        5'd2 : begin put(39,36,4,"16us",  2'd2); put(39,66,4,"32us",  2'd2); end
        5'd3 : begin put(39,36,3,"8us",   2'd2); put(39,67,4,"16us",  2'd2); end
        5'd4 : begin put(39,36,5,"256us", 2'd2); put(39,66,5,"512us", 2'd2); end
        5'd5 : begin put(39,36,5,"128us", 2'd2); put(39,66,5,"256us", 2'd2); end
        5'd6 : begin put(39,36,4,"64us",  2'd2); put(39,66,5,"128us", 2'd2); end
        5'd7 : begin put(39,36,4,"32us",  2'd2); put(39,66,4,"64us",  2'd2); end
        5'd8 : begin put(39,36,6,"1.28ms",2'd2); put(39,66,6,"2.56ms",2'd2); end
        5'd9 : begin put(39,36,5,"640us", 2'd2); put(39,66,6,"1.28ms",2'd2); end
        5'd10: begin put(39,36,5,"320us", 2'd2); put(39,66,5,"640us", 2'd2); end
        5'd11: begin put(39,36,5,"160us", 2'd2); put(39,66,5,"320us", 2'd2); end
        5'd12: begin put(39,36,5,"6.4ms", 2'd2); put(39,66,5,"12.8ms",2'd2); end
        5'd13: begin put(39,36,5,"3.2ms", 2'd2); put(39,66,5,"6.4ms", 2'd2); end
        5'd14: begin put(39,36,5,"1.6ms", 2'd2); put(39,66,5,"3.2ms", 2'd2); end
        5'd15: begin put(39,36,4,"800us", 2'd2); put(39,66,5,"1.6ms", 2'd2); end
        5'd16: begin put(39,36,6,"2.37us",2'd2); put(39,66,6,"4.74us",2'd2); end
        5'd17: begin put(39,36,6,"1.18us",2'd2); put(39,66,6,"2.37us",2'd2); end
        5'd18: begin put(39,36,6,"592ns", 2'd2); put(39,66,6,"1.18us",2'd2); end
        default: begin put(39,36,5,"296ns", 2'd2); put(39,66,6,"592ns", 2'd2); end
        endcase

        put(41, 2, 35, "Trig: Rise 0V    KEY2: Spectrum View", 2'd0);

        // 右侧菜单面板
        // 注意本文件 put 参数为 (行, 列), 与 spec_display 的 (列, 行) 相反
        put( 6, 70, 4, "WAVE", 2'd2);
        put( 7, 70, 4, "Span", 2'd2);
        case (I_span)
        2'd0: put( 8, 70, 6, "1 MHz",  2'd1);
        2'd1: put( 8, 70, 7, "250 kHz", 2'd1);
        2'd2: put( 8, 70, 6, "50 kHz", 2'd1);
        2'd3: put( 8, 70, 6, "10 kHz", 2'd1);
        3'd4: put( 8, 70, 6, "27 MHz", 2'd1);
        endcase
        put(10, 70, 4, "Trig", 2'd2);
        put(11, 70, 8, "Rise 0V", 2'd1);
        put(13, 70, 4, "NPTS", 2'd2);
        put(14, 70, 5, "1024 ", 2'd1);

        put(16, 70, 5, "V/Div", 2'd2);
        case (I_amp)
        2'd0: put(17, 70, 3, "2 V",  2'd1);
        2'd1: put(17, 70, 3, "1 V",  2'd1);
        2'd2: put(17, 70, 4, ".5 V", 2'd1);
        default: put(17, 70, 4, ".25V", 2'd1);
        endcase

        put(19, 70, 4, "Zoom", 2'd2);
        case (I_zoom)
        2'd0: put(20, 70, 5, "256pt", 2'd1);
        2'd1: put(20, 70, 5, "128pt", 2'd1);
        2'd2: put(20, 70, 5, " 64pt", 2'd1);
        default: put(20, 70, 5, " 32pt", 2'd1);
        endcase

        put(22, 70, 4, "Orig", 2'd2);
        if (I_orig) put(23, 70, 2, "ON",  2'd1);
        else        put(23, 70, 3, "OFF", 2'd1);

        // 谐波图例 (与迹线同色)
        if (I_hvalid) begin
            put(25, 70, 2, "H1", 3'd3);
            put(26, 70, 2, "H2", 3'd4);
            put(27, 70, 2, "H3", 3'd5);
            put(28, 70, 2, "H4", 3'd6);
            put(29, 70, 2, "H5", 3'd7);
        end else begin
            put(25, 70, 6, "no f0 ", 2'd0);
        end
    end

    //==================================================================
    // 第 1 级: 文字结果打一拍 + 字模 ROM 读
    //==================================================================
    reg [11:0] x1, y1;
    reg [7:0]  ch1;
    reg [2:0]  co1;
    reg        vld1;
    reg        hv1;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x1 <= 12'd0;  y1 <= 12'd0;
            ch1 <= 8'd0;  co1 <= 3'd0;  vld1 <= 1'b0;  hv1 <= 1'b0;
        end else begin
            x1 <= I_x;  y1 <= I_y;
            ch1 <= t_ch;  co1 <= t_co;  vld1 <= t_vld;
            hv1 <= I_hvalid;
        end
    end

    wire [2:0] glyph_row = y1[3:1];                // 8px 字高, 单元内居中
    wire [7:0] font_bits;

    ui_font_rom u_font_rom (
        .I_clk  (I_pix_clk),
        .I_ch   (ch1      ),
        .I_row  (glyph_row),
        .O_bits (font_bits)
    );

    //==================================================================
    // 第 2 级: 锁存样点对 (sub=0 列) + 文字属性对齐
    //   一个样点占 4<<zoom 列, 列内 4 等分: sub = (x >> zoom) & 3
    //==================================================================
    reg [11:0] x2, y2;
    reg [2:0]  co2;
    reg        vld2;
    reg        hv2;
    reg [15:0] cur2, nxt2;
    reg [15:0] wv_ram_d;
    reg [49:0] h_cur2, h_nxt2;

    always @(posedge I_pix_clk) wv_ram_d <= wv_ram;

    wire [1:0] sub2 = (x2 >> I_zoom) & 2'b11;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x2 <= 12'd0;  y2 <= 12'd0;
            co2 <= 3'd0;  vld2 <= 1'b0;  hv2 <= 1'b0;
            cur2 <= 16'd0;  nxt2 <= 16'd0;
            h_cur2 <= 50'd0;  h_nxt2 <= 50'd0;
        end else begin
            x2 <= x1;  y2 <= y1;
            co2 <= co1;  vld2 <= vld1;
            hv2 <= hv1;
            if (sub2 == 2'd0) begin
                cur2 <= wv_ram_d;                  // D(X-1) = smp[w]
                nxt2 <= wv_ram;                    // D(X)   = smp[w+1]
                h_cur2 <= h_ram_d;
                h_nxt2 <= h_ram;
            end
        end
    end

    //==================================================================
    // 第 3 级: 线性内插 -> 行值
    //==================================================================
    reg [11:0] x3, y3;
    reg        vld3;
    reg        hv3;
    reg [7:0]  fb3;
    reg [2:0]  co3;
    reg [9:0]  row3;
    reg        orig3;

    // 拼接 {bit, reg} 是无符号的, 必须先 $signed 再做加减, 否则跨符号样点对
    // 的差值被零扩展成垃圾 (曾在过零处产生满屏瞬变, 教训)
    wire signed [16:0] nxt_se = $signed({nxt2[15], nxt2});
    wire signed [16:0] cur_se = $signed({cur2[15], cur2});
    wire signed [17:0] d_nxt_c = nxt_se - cur_se;
    wire signed [17:0] d_qua  = d_nxt_c >>> 2;     // (nxt-cur)/4

    wire [1:0] sub3 = (x3 >> I_zoom) & 2'b11;

    reg signed [17:0] dsub;
    always @(*) begin
        case (sub3)
        2'd0:    dsub = 18'sd0;
        2'd1:    dsub = d_qua;
        2'd2:    dsub = d_qua <<< 1;
        default: dsub = d_qua + (d_qua <<< 1);
        endcase
    end

    wire signed [17:0] v_interp = cur_se + dsub;

    // 幅度档: row = 256 + (v >> (8-amp)), 裁到 0..511
    //   amp=1 (±1V) 时 256+(v>>7) 与原实现 (v+32768)>>7 完全等价
    wire [3:0]         amp_sh = 4'd8 - {2'b00, I_amp};
    wire signed [17:0] v_amp  = v_interp >>> amp_sh;
    wire signed [18:0] v_row_s= 19'sd256 + {{1{v_amp[17]}}, v_amp};
    wire [9:0]         v_row  = (v_row_s < 19'sd0)   ? 10'd0 :
                                (v_row_s > 19'sd511) ? 10'd511 : v_row_s[9:0];

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x3 <= 12'd0;  y3 <= 12'd0;
            vld3 <= 1'b0;  hv3 <= 1'b0;  fb3 <= 8'd0;  co3 <= 3'd0;
            row3 <= 10'd256;
            orig3 <= 1'b1;
        end else begin
            x3 <= x2;  y3 <= y2;
            vld3 <= vld2;
            hv3  <= hv2;
            fb3  <= font_bits;
            co3  <= co2;
            row3 <= v_row;                          // 0..511, 相对绘图区顶 (与 yr 同系)
            orig3 <= I_orig;
        end
    end

    //------------------------------------------------------------------
    // 谐波 5 lane: 同样在第 3 级内插, 第 4 级对齐
    //   每 lane 取 h_cur2/h_nxt2 里对应的 10bit 段, 用同一个 sub3 做内插
    //------------------------------------------------------------------
    wire signed [11:0] hmul = $signed({10'd0, sub3});   // 0..3

    wire signed [10:0] hc1 = $signed({1'b0, h_cur2[ 9: 0]});
    wire signed [10:0] hn1 = $signed({1'b0, h_nxt2[ 9: 0]});
    wire signed [10:0] hc2 = $signed({1'b0, h_cur2[19:10]});
    wire signed [10:0] hn2 = $signed({1'b0, h_nxt2[19:10]});
    wire signed [10:0] hc3 = $signed({1'b0, h_cur2[29:20]});
    wire signed [10:0] hn3 = $signed({1'b0, h_nxt2[29:20]});
    wire signed [10:0] hc4 = $signed({1'b0, h_cur2[39:30]});
    wire signed [10:0] hn4 = $signed({1'b0, h_nxt2[39:30]});
    wire signed [10:0] hc5 = $signed({1'b0, h_cur2[49:40]});
    wire signed [10:0] hn5 = $signed({1'b0, h_nxt2[49:40]});

    wire signed [10:0] hq1 = (hn1 - hc1) >>> 2;
    wire signed [10:0] hq2 = (hn2 - hc2) >>> 2;
    wire signed [10:0] hq3 = (hn3 - hc3) >>> 2;
    wire signed [10:0] hq4 = (hn4 - hc4) >>> 2;
    wire signed [10:0] hq5 = (hn5 - hc5) >>> 2;

    wire signed [12:0] hp1 = hq1 * hmul;   // 11bit x 3bit -> 13bit 有符号 (原 14bit 取 [11:0] 会丢符号位)
    wire signed [12:0] hp2 = hq2 * hmul;   // 11bit x 3bit -> 13bit 有符号 (原 14bit 取 [11:0] 会丢符号位)
    wire signed [12:0] hp3 = hq3 * hmul;   // 11bit x 3bit -> 13bit 有符号 (原 14bit 取 [11:0] 会丢符号位)
    wire signed [12:0] hp4 = hq4 * hmul;   // 11bit x 3bit -> 13bit 有符号 (原 14bit 取 [11:0] 会丢符号位)
    wire signed [12:0] hp5 = hq5 * hmul;   // 11bit x 3bit -> 13bit 有符号 (原 14bit 取 [11:0] 会丢符号位)

    // 行值 = 当前样点行值 + 列内插值, 再裁到 0..511 (有符号比较!)
    wire signed [12:0] hs1 = hc1 + hp1;
    wire signed [12:0] hs2 = hc2 + hp2;
    wire signed [12:0] hs3 = hc3 + hp3;
    wire signed [12:0] hs4 = hc4 + hp4;
    wire signed [12:0] hs5 = hc5 + hp5;

    wire [9:0] hri1 = (hs1 < 13'sd0) ? 10'd0 : (hs1 > 13'sd511) ? 10'd511 : hs1[9:0];
    wire [9:0] hri2 = (hs2 < 13'sd0) ? 10'd0 : (hs2 > 13'sd511) ? 10'd511 : hs2[9:0];
    wire [9:0] hri3 = (hs3 < 13'sd0) ? 10'd0 : (hs3 > 13'sd511) ? 10'd511 : hs3[9:0];
    wire [9:0] hri4 = (hs4 < 13'sd0) ? 10'd0 : (hs4 > 13'sd511) ? 10'd511 : hs4[9:0];
    wire [9:0] hri5 = (hs5 < 13'sd0) ? 10'd0 : (hs5 > 13'sd511) ? 10'd511 : hs5[9:0];

    reg  [9:0] hrow4_1, hrow4_2, hrow4_3, hrow4_4, hrow4_5;
    reg  [9:0] hprev4_1, hprev4_2, hprev4_3, hprev4_4, hprev4_5;
    reg        hv4;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            hrow4_1 <= 10'd256; hrow4_2 <= 10'd256; hrow4_3 <= 10'd256;
            hrow4_4 <= 10'd256; hrow4_5 <= 10'd256;
            hprev4_1<= 10'd256; hprev4_2<= 10'd256; hprev4_3<= 10'd256;
            hprev4_4<= 10'd256; hprev4_5<= 10'd256;
            hv4 <= 1'b0;
        end else begin
            hrow4_1 <= hri1;  hprev4_1 <= hrow4_1;
            hrow4_2 <= hri2;  hprev4_2 <= hrow4_2;
            hrow4_3 <= hri3;  hprev4_3 <= hrow4_3;
            hrow4_4 <= hri4;  hprev4_4 <= hrow4_4;
            hrow4_5 <= hri5;  hprev4_5 <= hrow4_5;
            hv4     <= hv3;
        end
    end

    //==================================================================
    // 第 4 级: 字模取位 + 行值对齐 (prev4 = 前一列行值)
    //==================================================================
    wire [2:0] glyph_col = x3[3:1];
    wire       font_bit_sel = (fb3 >> (3'd7 - glyph_col)) & 1'b1;

    reg [11:0] x4, y4;
    reg        vld4;
    reg        tbit4;
    reg [2:0]  co4;
    reg [9:0]  row4, prev4;
    reg        orig4;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x4 <= 12'd0;  y4 <= 12'd0;
            vld4 <= 1'b0;  tbit4 <= 1'b0;  co4 <= 3'd0;
            row4 <= 10'd256;  prev4 <= 10'd256;
            orig4 <= 1'b1;
        end else begin
            x4 <= x3;  y4 <= y3;
            vld4 <= vld3;
            tbit4 <= vld3 & font_bit_sel;
            co4  <= co3;
            row4 <= row3;
            prev4 <= row4;
            orig4 <= orig3;
        end
    end

    //==================================================================
    // 第 5 级 (组合): 判定像素属于哪个元素
    //==================================================================
    wire in_plot  = (x4 >= PX0) && (x4 <= PX1) && (y4 >= PY0) && (y4 <= PY1);
    wire in_panel = (x4 >= PANEL_X);
    wire in_top   = (y4 < TOP_H);
    wire in_bot   = (y4 >= BOT_Y) && !in_panel;

    wire [9:0] xr = x4[9:0] - 10'd64;
    wire [9:0] yr = y4[9:0] - 10'd104;

    wire grid_v = (xr[6:0] == 7'd0);
    wire grid_h = (yr[5:0] == 6'd0);
    wire grid   = grid_v || grid_h;
    wire zeroline = in_plot && (yr == 10'd256);

    wire [9:0] seg_lo = (row4 < prev4) ? row4 : prev4;
    wire [9:0] seg_hi = (row4 < prev4) ? prev4 : row4;

    wire trace_cap = in_plot && orig4 && (yr >= row4) && (yr <= (row4 + 10'd1));
    wire trace_seg = in_plot && orig4 && (x4 > (PX0 + 12'd3)) &&
                     (yr >= seg_lo) && (yr <= (seg_hi + 10'd1));
    wire on_trace  = trace_cap || trace_seg;

    // 谐波迹线: 每 lane 2 像素粗 + 与前一列之间的竖直连线 (首列不连线免得画到左边缘)
    wire [9:0] hl1 = (hrow4_1 < hprev4_1) ? hrow4_1 : hprev4_1;
    wire [9:0] hh1 = (hrow4_1 < hprev4_1) ? hprev4_1 : hrow4_1;
    wire [9:0] hl2 = (hrow4_2 < hprev4_2) ? hrow4_2 : hprev4_2;
    wire [9:0] hh2 = (hrow4_2 < hprev4_2) ? hprev4_2 : hrow4_2;
    wire [9:0] hl3 = (hrow4_3 < hprev4_3) ? hrow4_3 : hprev4_3;
    wire [9:0] hh3 = (hrow4_3 < hprev4_3) ? hprev4_3 : hrow4_3;
    wire [9:0] hl4 = (hrow4_4 < hprev4_4) ? hrow4_4 : hprev4_4;
    wire [9:0] hh4 = (hrow4_4 < hprev4_4) ? hprev4_4 : hrow4_4;
    wire [9:0] hl5 = (hrow4_5 < hprev4_5) ? hrow4_5 : hprev4_5;
    wire [9:0] hh5 = (hrow4_5 < hprev4_5) ? hprev4_5 : hrow4_5;

    wire hhit1 = in_plot && hv4 &&
                 ( ((yr >= hrow4_1) && (yr <= (hrow4_1 + 10'd1))) ||
                   ((x4 > (PX0 + 12'd3)) && (yr >= hl1) && (yr <= hh1)) );
    wire hhit2 = in_plot && hv4 &&
                 ( ((yr >= hrow4_2) && (yr <= (hrow4_2 + 10'd1))) ||
                   ((x4 > (PX0 + 12'd3)) && (yr >= hl2) && (yr <= hh2)) );
    wire hhit3 = in_plot && hv4 &&
                 ( ((yr >= hrow4_3) && (yr <= (hrow4_3 + 10'd1))) ||
                   ((x4 > (PX0 + 12'd3)) && (yr >= hl3) && (yr <= hh3)) );
    wire hhit4 = in_plot && hv4 &&
                 ( ((yr >= hrow4_4) && (yr <= (hrow4_4 + 10'd1))) ||
                   ((x4 > (PX0 + 12'd3)) && (yr >= hl4) && (yr <= hh4)) );
    wire hhit5 = in_plot && hv4 &&
                 ( ((yr >= hrow4_5) && (yr <= (hrow4_5 + 10'd1))) ||
                   ((x4 > (PX0 + 12'd3)) && (yr >= hl5) && (yr <= hh5)) );

    wire is_sep = ((y4 >= 12'd96)  && (y4 <= 12'd99))  ||
                  ((y4 >= 12'd618) && (y4 <= 12'd621)) ||
                  ((x4 >= 12'd1098) && (x4 <= 12'd1101));

    localparam [4:0] S_TXT0  = 5'd0,  S_TXT1 = 5'd1,  S_TXT2 = 5'd2;
    localparam [4:0] S_TXT3  = 5'd3,  S_TXT4 = 5'd4,  S_TXT5 = 5'd5;
    localparam [4:0] S_TXT6  = 5'd6,  S_TXT7 = 5'd7;
    localparam [4:0] S_TRACE = 5'd8,  S_ZERO = 5'd9,  S_GRID = 5'd10;
    localparam [4:0] S_PLOT  = 5'd11, S_PANEL= 5'd12, S_SEP  = 5'd13;
    localparam [4:0] S_CHROME= 5'd14, S_BG   = 5'd15;
    localparam [4:0] S_H1    = 5'd16, S_H2   = 5'd17, S_H3   = 5'd18;
    localparam [4:0] S_H4    = 5'd19, S_H5   = 5'd20;

    reg [4:0] hsel;
    always @(*) begin
        if      (hhit1) hsel = S_H1;
        else if (hhit2) hsel = S_H2;
        else if (hhit3) hsel = S_H3;
        else if (hhit4) hsel = S_H4;
        else if (hhit5) hsel = S_H5;
        else            hsel = 5'd31;          // 无
    end

    wire any_h = (hsel != 5'd31);

    reg [4:0] sel_c;

    always @(*) begin
        if (tbit4)
            sel_c = (co4 == 3'd1) ? S_TXT1 :
                    (co4 == 3'd2) ? S_TXT2 :
                    (co4 == 3'd3) ? S_TXT3 :
                    (co4 == 3'd4) ? S_TXT4 :
                    (co4 == 3'd5) ? S_TXT5 :
                    (co4 == 3'd6) ? S_TXT6 :
                    (co4 == 3'd7) ? S_TXT7 : S_TXT0;
        else if (in_plot)
            sel_c = any_h   ? hsel     :
                    on_trace? S_TRACE  :
                    zeroline? S_ZERO   :
                    grid    ? S_GRID   : S_PLOT;
        else if (in_panel)
            sel_c = S_PANEL;
        else if (is_sep)
            sel_c = S_SEP;
        else if (in_top || in_bot)
            sel_c = S_CHROME;
        else
            sel_c = S_BG;
    end

    reg [4:0] sel;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n)
            sel <= S_BG;
        else
            sel <= sel_c;
    end

    //==================================================================
    // 第 6 级: 选择码 -> 24bit 颜色
    //==================================================================
    reg [23:0] rgb_c;

    always @(*) begin
        case (sel)
            S_TXT0 : rgb_c = C_TXT0;
            S_TXT1 : rgb_c = C_TXT1;
            S_TXT2 : rgb_c = C_TXT2;
            S_TXT3 : rgb_c = C_H1;
            S_TXT4 : rgb_c = C_H2;
            S_TXT5 : rgb_c = C_H3;
            S_TXT6 : rgb_c = C_H4;
            S_TXT7 : rgb_c = C_H5;
            S_TRACE: rgb_c = C_ORIG;
            S_H1   : rgb_c = C_H1;
            S_H2   : rgb_c = C_H2;
            S_H3   : rgb_c = C_H3;
            S_H4   : rgb_c = C_H4;
            S_H5   : rgb_c = C_H5;
            S_ZERO : rgb_c = C_ZERO;
            S_GRID : rgb_c = C_GRID;
            S_PLOT : rgb_c = C_PLOT;
            S_PANEL: rgb_c = C_PANEL;
            S_SEP  : rgb_c = C_SEP;
            S_CHROME:rgb_c = C_CHROME;
            default: rgb_c = C_BG;
        endcase
    end

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            O_r <= 8'd0;  O_g <= 8'd0;  O_b <= 8'd0;
        end else begin
            O_r <= rgb_c[23:16];
            O_g <= rgb_c[15:8];
            O_b <= rgb_c[7:0];
        end
    end

endmodule

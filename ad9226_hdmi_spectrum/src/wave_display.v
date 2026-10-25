// ============================================================================
// wave_display.v  --  时域波形 (示波器) 显示子系统
//
//   与 spec_display 同构的 6 级像素流水线, 版面/网格位置一致,
//   在 video_top 里按显示模式二选一输出 RGB (两级流水线延迟相同, 可直接切换)。
//
//   数据: wave_cap 采集的 1024 点波形 (Q4 有符号, ±32768 = ±1V)
//         经 spec_data_if + spec_ram 乒乓双时钟缓存后按列读出绘制。
//
//   时基 (4 倍内插放大): 屏幕只显示记录的前 256 点, 每点占 4 列,
//   相邻样点间线性内插 -> 100kHz 信号在 Span 1MHz 档约 13 个周期, 80px/周期。
//     Span 0 (fs 2M)  : 窗口 128us     Span 1 (fs 500k): 窗口 512us
//     Span 2 (fs 100k): 窗口 2.56ms    Span 3 (fs 20k) : 窗口 12.8ms
//
//   纵轴: 512 行 = 满量程 ±1V (AD9226 2Vpp, 2048 码 = 1V), 中线 = 0V
//   迹线: 当前列行值 + 与前列行值之间的竖直填充 (连接线), 亮绿色
//
//   波形 RAM 读时序 (spec_ram 打一拍):
//     每拍固定发地址 widx+1; 列 X 第 2 级拿到 smp[w(X)+1] (下一样点),
//     其打一拍就是 smp[w(X)] (当前样点, 因为 sub=0 列的前一列 widx 恰为 w-1)。
//     于是在 sub=0 的列锁存 {cur, nxt} 样点对, 其余 3 列复用。
// ============================================================================
module wave_display (
    input             I_pix_clk    ,
    input             I_pix_rst_n  ,
    input      [11:0] I_x          ,   // 像素列
    input      [11:0] I_y          ,   // 像素行
    input      [2:0]  I_span       ,   // 跨度档 (决定时基文字与采样率)
    // ---- 数据写入接口 (与像素时钟可异步, 来自 wave_cap) ----
    input             I_wr_clk     ,
    input             I_wr_rst_n   ,
    input             I_frame_start,   // 单拍: 本帧第一次写 (触发时刻)
    input             I_wr_en      ,
    input      [9:0]  I_wr_addr    ,
    input      [15:0] I_wr_mag     ,   // 样点 (Q4 有符号)
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

    // 配色 (chrome/网格与频谱页一致, 迹线换成示波器绿)
    localparam [23:0] C_BG     = 24'h00_00_00;
    localparam [23:0] C_CHROME = 24'h0C_12_1A;
    localparam [23:0] C_PANEL  = 24'h0E_16_22;
    localparam [23:0] C_SEP    = 24'h28_38_50;
    localparam [23:0] C_GRID   = 24'h22_30_40;
    localparam [23:0] C_PLOT   = 24'h00_00_00;
    localparam [23:0] C_ZERO   = 24'h1E_5E_46;   // 0V 基准线 (暗绿)
    localparam [23:0] C_TRACE  = 24'h00_E8_64;   // 迹线亮绿
    localparam [23:0] C_TXT0   = 24'hC8_D8_E8;
    localparam [23:0] C_TXT1   = 24'h3C_D8_78;
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

    // 地址规则: 每拍发 widx+1 (widx = (x-64)>>2)
    wire [9:0] widx = I_x[11:2] - 10'd16;

    always @(posedge I_pix_clk) rd_addr <= widx + 10'd1;

    //==================================================================
    // 文字标签: 80x45 个 16px 单元, 组合逻辑判定 (行,列) 落在哪个标签里
    //   put(r0, c0, len, 字符串, 颜色): 命中则输出该列字符
    //==================================================================
    wire [5:0]  cell_row = (I_y[11:4] > 6'd44) ? 6'd44 : I_y[11:4];
    wire [6:0]  cell_col = (I_x[11:4] > 7'd79) ? 7'd79 : I_x[11:4];

    reg  [7:0]  t_ch;
    reg  [1:0]  t_co;
    reg         t_vld;

    task put;
        input integer  r0;
        input integer  c0;
        input integer  len;
        input [287:0]  s;
        input [1:0]    colr;
        integer k;
        begin
            if ((cell_row == r0[5:0]) && (cell_col >= c0) && (cell_col < c0 + len)) begin
                k    = (len - 1) - (cell_col - c0);
                t_ch = s[k*8 +: 8];
                t_co = colr;
                t_vld = 1'b1;
            end
        end
    endtask

    // 敏感列表必须显式列出 (任务内部读取的信号, always @(*) 对老工具不可靠)
    always @(cell_row or cell_col or I_span) begin
        t_ch  = 8'd0;
        t_co  = 2'd0;
        t_vld = 1'b0;

        put(1, 2, 21, "WAVEFORM  TIME DOMAIN", 2'd0);

        // 纵轴电压刻度 (0V 在正中, 满量程 ±1V)
        put( 6, 0, 3, "+1V",  2'd2);
        put(14, 0, 4, "+.5V", 2'd2);
        put(22, 0, 2, "0V",   2'd2);
        put(30, 0, 4, "-.5V", 2'd2);
        put(38, 0, 3, "-1V",  2'd2);

        // 第 2 行: 窗口/采样率 (随跨度)
        case (I_span)
        2'd0: put(2, 2, 31, "Window: 128us   Rate: 2.00MS/s", 2'd1);
        2'd1: put(2, 2, 31, "Window: 512us   Rate:  500KS/s", 2'd1);
        2'd2: put(2, 2, 31, "Window: 2.56ms  Rate:  100KS/s", 2'd1);
        2'd3: put(2, 2, 31, "Window: 12.8ms  Rate:   20KS/s", 2'd1);
        3'd4: put(2, 2, 31, "Window: 4.74us  Rate: 54.0MS/s", 2'd1);
        endcase

        // 第 39 行 (底栏): 时间刻度, 5 个位置对应 0/1/4/1/2/3/4 窗口
        case (I_span)
        2'd0: begin
            put(39,  4, 1, "0",      2'd2);
            put(39, 20, 4, "32us",   2'd2);
            put(39, 36, 4, "64us",   2'd2);
            put(39, 52, 4, "96us",   2'd2);
            put(39, 67, 5, "128us",  2'd2);
        end
        2'd1: begin
            put(39,  4, 1, "0",      2'd2);
            put(39, 20, 5, "128us",  2'd2);
            put(39, 36, 5, "256us",  2'd2);
            put(39, 52, 5, "384us",  2'd2);
            put(39, 67, 5, "512us",  2'd2);
        end
        2'd2: begin
            put(39,  4, 1, "0",      2'd2);
            put(39, 20, 5, "640us",  2'd2);
            put(39, 36, 6, "1.28ms", 2'd2);
            put(39, 52, 6, "1.92ms", 2'd2);
            put(39, 67, 6, "2.56ms", 2'd2);
        end
        2'd3: begin
            put(39,  4, 1, "0",      2'd2);
            put(39, 20, 5, "3.2ms",  2'd2);
            put(39, 36, 5, "6.4ms",  2'd2);
            put(39, 52, 5, "9.6ms",  2'd2);
            put(39, 67, 6, "12.8ms", 2'd2);
        end
        3'd4: begin
            put(39,  4, 1, "0",      2'd2);
            put(39, 20, 6, "1.18us", 2'd2);
            put(39, 36, 6, "2.36us", 2'd2);
            put(39, 52, 6, "3.55us", 2'd2);
            put(39, 67, 6, "4.74us", 2'd2);
        end
        endcase

        put(41, 2, 35, "Trig: Rise 0V    KEY2: Spectrum View", 2'd0);
    end

    //==================================================================
    // 第 1 级: 文字结果打一拍 + 字模 ROM 读
    //==================================================================
    reg [11:0] x1, y1;
    reg [7:0]  ch1;
    reg [1:0]  co1;
    reg        vld1;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x1 <= 12'd0;  y1 <= 12'd0;
            ch1 <= 8'd0;  co1 <= 2'd0;  vld1 <= 1'b0;
        end else begin
            x1 <= I_x;  y1 <= I_y;
            ch1 <= t_ch;  co1 <= t_co;  vld1 <= t_vld;
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
    //==================================================================
    reg [11:0] x2, y2;
    reg [1:0]  co2;
    reg        vld2;
    reg [15:0] cur2, nxt2;
    reg [15:0] wv_ram_d;

    always @(posedge I_pix_clk) wv_ram_d <= wv_ram;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x2 <= 12'd0;  y2 <= 12'd0;
            co2 <= 2'd0;  vld2 <= 1'b0;
            cur2 <= 16'd0;  nxt2 <= 16'd0;
        end else begin
            x2 <= x1;  y2 <= y1;
            co2 <= co1;  vld2 <= vld1;
            if (x2[1:0] == 2'd0) begin
                cur2 <= wv_ram_d;                  // D(X-1) = smp[w]
                nxt2 <= wv_ram;                    // D(X)   = smp[w+1]
            end
        end
    end

    //==================================================================
    // 第 3 级: 线性内插 -> 行值
    //==================================================================
    reg [11:0] x3, y3;
    reg        vld3;
    reg [7:0]  fb3;
    reg [1:0]  co3;
    reg [9:0]  row3;

    // 拼接 {bit, reg} 是无符号的, 必须先 $signed 再做加减, 否则跨符号样点对
    // 的差值被零扩展成垃圾 (曾在过零处产生满屏瞬变, 教训)
    wire signed [16:0] nxt_se = $signed({nxt2[15], nxt2});
    wire signed [16:0] cur_se = $signed({cur2[15], cur2});
    wire signed [17:0] d_nxt_c = nxt_se - cur_se;
    wire signed [17:0] d_qua  = d_nxt_c >>> 2;     // (nxt-cur)/4

    reg signed [17:0] dsub;
    always @(*) begin
        case (x3[1:0])
        2'd0:    dsub = 18'sd0;
        2'd1:    dsub = d_qua;
        2'd2:    dsub = d_qua <<< 1;
        default: dsub = d_qua + (d_qua <<< 1);
        endcase
    end

    wire signed [17:0] v_interp = cur_se + dsub;
    wire signed [18:0] v_all   = v_interp + 19'sd32768;   // 0..65535
    wire [9:0]        v_row    = v_all[16:7];             // >>>7 -> 0..511

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x3 <= 12'd0;  y3 <= 12'd0;
            vld3 <= 1'b0;  fb3 <= 8'd0;  co3 <= 2'd0;
            row3 <= 10'd256;
        end else begin
            x3 <= x2;  y3 <= y2;
            vld3 <= vld2;
            fb3  <= font_bits;
            co3  <= co2;
            row3 <= v_row;                          // 0..511, 相对绘图区顶 (与 yr 同系)
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
    reg [1:0]  co4;
    reg [9:0]  row4, prev4;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x4 <= 12'd0;  y4 <= 12'd0;
            vld4 <= 1'b0;  tbit4 <= 1'b0;  co4 <= 2'd0;
            row4 <= 10'd256;  prev4 <= 10'd256;
        end else begin
            x4 <= x3;  y4 <= y3;
            vld4 <= vld3;
            tbit4 <= vld3 & font_bit_sel;
            co4  <= co3;
            row4 <= row3;
            prev4 <= row4;
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

    wire trace_cap = in_plot && (yr >= row4) && (yr <= (row4 + 10'd1));
    wire trace_seg = in_plot && (x4 > PX0) && (yr >= seg_lo) && (yr <= (seg_hi + 10'd1));
    wire on_trace  = trace_cap || trace_seg;

    wire is_sep = ((y4 >= 12'd96)  && (y4 <= 12'd99))  ||
                  ((y4 >= 12'd618) && (y4 <= 12'd621)) ||
                  ((x4 >= 12'd1098) && (x4 <= 12'd1101));

    localparam [3:0] S_TXT0  = 4'd0, S_TXT1  = 4'd1, S_TXT2  = 4'd2;
    localparam [3:0] S_TRACE = 4'd4, S_ZERO  = 4'd5, S_GRID  = 4'd6;
    localparam [3:0] S_PLOT  = 4'd7, S_PANEL = 4'd8, S_SEP   = 4'd11;
    localparam [3:0] S_CHROME= 4'd12, S_BG   = 4'd13;

    reg [3:0] sel_c;

    always @(*) begin
        if (tbit4)
            sel_c = (co4 == 2'd1) ? S_TXT1 :
                    (co4 == 2'd2) ? S_TXT2 : S_TXT0;
        else if (in_plot)
            sel_c = on_trace ? S_TRACE :
                    zeroline ? S_ZERO  :
                    grid     ? S_GRID  : S_PLOT;
        else if (in_panel)
            sel_c = S_PANEL;
        else if (is_sep)
            sel_c = S_SEP;
        else if (in_top || in_bot)
            sel_c = S_CHROME;
        else
            sel_c = S_BG;
    end

    reg [3:0] sel;

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
            S_TRACE: rgb_c = C_TRACE;
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

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
//   文字: 屏幕按 16x16 像素划成 80x45 个单元, 单元内容存在 ui_text_rom 里
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
    input      [1:0]  I_span       ,   // 频率跨度 0:500kHz 1:1MHz 2:10MHz
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
    localparam [23:0] C_TXT1    = 24'h3C_D8_78;   // 绿
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
    // 第 1 级: 字符网格 ROM (80 x 45 单元, 3 个量程层)
    //==================================================================
    wire [5:0]  cell_row = I_y[9:4];                 // 0..44
    wire [6:0]  cell_col = I_x[10:4];                // 0..79
    wire [11:0] cell_idx = (cell_row << 6) + (cell_row << 4) + cell_col;

    wire [10:0] map_d;                               // {scale, color[1:0], ch[7:0]}

    ui_text_rom u_text_rom (
        .I_clk  (I_pix_clk          ),
        .I_addr ({I_span, cell_idx}),
        .O_data (map_d              )
    );

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
            t_vld1 <= (map_d[7:0] != 8'd0);
        end
    end

    //==================================================================
    // 第 2 级: 字模 ROM (同步读, BSRAM)
    //   scale=1 时字高 32, 行/列取 5bit 里的高 3 位; scale=0 时字高 16
    //==================================================================
    wire [2:0] glyph_row = map_d[10] ? py1[4:2] : py1[3:1];

    wire [7:0] font_bits;

    ui_font_rom u_font_rom (
        .I_clk  (I_pix_clk   ),
        .I_ch   (map_d[7:0]  ),
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
            color2 <= map_d[9:8];
            scale2 <= map_d[10];
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

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x4 <= 12'd0;  y4 <= 12'd0;
            bar4 <= 10'd511;  pk4 <= 10'd511;  prev4 <= 10'd511;
            tbit4 <= 1'b0;  tvld4 <= 1'b0;  pkvld4 <= 1'b0;  color4 <= 2'd0;
        end else begin
            x4 <= x3;  y4 <= y3;
            bar4  <= r3;
            pk4   <= rp3;
            prev4 <= bar4;
            tbit4 <= t_vld3 & t_bit;
            tvld4 <= t_vld3;
            color4 <= color3;
            pkvld4 <= pk_vld3;
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
    wire btn_hi = (row4 >= 7) && (row4 <= 10);          // 第一个按钮高亮

    wire is_sep = ((y4 >= 12'd96)  && (y4 <= 12'd99))  ||
                  ((y4 >= 12'd618) && (y4 <= 12'd621)) ||
                  ((x4 >= 12'd1098) && (x4 <= 12'd1101));

    // 元素选择码
    localparam [3:0] S_TXT0  = 4'd0;
    localparam [3:0] S_TXT1  = 4'd1;
    localparam [3:0] S_TXT2  = 4'd2;
    localparam [3:0] S_TXT3  = 4'd3;
    localparam [3:0] S_TRACE = 4'd4;
    localparam [3:0] S_PEAK  = 4'd5;
    localparam [3:0] S_GRID  = 4'd6;
    localparam [3:0] S_PLOT  = 4'd7;
    localparam [3:0] S_BTN_H = 4'd8;
    localparam [3:0] S_BTN   = 4'd9;
    localparam [3:0] S_PANEL = 4'd10;
    localparam [3:0] S_SEP   = 4'd11;
    localparam [3:0] S_CHROME= 4'd12;
    localparam [3:0] S_BG    = 4'd13;

    reg [3:0] sel_c;

    always @(*) begin
        if (tbit4)
            sel_c = (color4 == 2'd1) ? S_TXT1 :
                    (color4 == 2'd2) ? S_TXT2 :
                    (color4 == 2'd3) ? S_TXT3 : S_TXT0;
        else if (in_plot)
            sel_c = on_trace ? S_TRACE :
                    on_peak  ? S_PEAK  :
                    grid     ? S_GRID  : S_PLOT;
        else if (in_panel)
            sel_c = in_btn ? (btn_hi ? S_BTN_H : S_BTN) : S_PANEL;
        else if (is_sep)
            sel_c = S_SEP;
        else if (in_top || in_bot)
            sel_c = S_CHROME;
        else
            sel_c = S_BG;
    end

    reg [3:0] sel;
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

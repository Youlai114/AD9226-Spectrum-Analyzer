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
    input      [3:0]  I_span       ,   // 0:1M 1:250k 2:50k 3:10k 4:1k 5:250Hz 6:27M 7:500k 8:100k 9:2.7M 10:5.4M 11:13.5M
    input      [1:0]  I_win        ,
    input      [1:0]  I_det        ,
    input      [1:0]  I_trc        ,
    input             I_trc_sub    ,
    input      [1:0]  I_ref_mode   ,
    input             I_ref_save_tog,
    input      [2:0]  I_avg        ,
    input      [1:0]  I_view       ,
    input      [9:0]  I_mkr_col    ,
    input             I_mkr_fine   ,
    input             I_mkr_delta  ,
    input             I_mkr_track  ,
    input      [9:0]  I_mkr_ref_col,
    input      [2:0]  I_harm_mode  ,
    input      [1:0]  I_yscale     ,
    input      [2:0]  I_yref       ,
    input             I_yscale_ref ,
    input      [3:0]  I_lim_lvl    ,
    input             I_lim_sub    ,
    input             I_menu_open  ,
    input      [3:0]  I_menu_sel   ,
    input      [2:0]  I_trig_mode  ,
    input      [3:0]  I_trig_lvl   ,
    input             I_trig_sub   ,
    input      [3:0]  I_vscale     ,
    input      [3:0]  I_tscale     ,
    input             I_vt_sel     ,
    input      [9:0]  I_pk_col     ,
    input      [15:0] I_pk_mag     ,
    input      [15:0] I_pk_left    ,
    input      [15:0] I_pk_right   ,
    input      [15:0] I_spur_mag   ,
    input      [15:0] I_h2_mag     ,
    input      [15:0] I_h3_mag     ,
    input      [15:0] I_h4_mag     ,
    input      [15:0] I_h5_mag     ,
    input      [9:0]  I_h2_col     ,
    input      [9:0]  I_h3_col     ,
    input      [9:0]  I_h4_col     ,
    input      [9:0]  I_h5_col     ,
    input             I_pk_tog     ,
    output     [9:0]  O_wave_addr  ,
    input  signed [11:0] I_wave_data,
    input  signed [11:0] I_harm_wave,
    input         [34:0] I_harm_all ,
    input      [11:0] I_vpp        ,
    input  signed [11:0] I_wave_mid,
    input      [9:0]  I_period_smp ,
    input      [9:0]  I_period_cnt ,
    input      [9:0]  I_high_smp   ,
    input             I_meas_vld   ,
    input             I_vpp_tog    ,
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

    // 后半: log2 定点 -> 未缩放行坐标 (0..615), 由第 4 级做 Scale 乘算
    function [9:0] log_row_base;
        input [3:0] k;
        input [4:0] f;
        input [9:0] ref_lv;
        reg [5:0]  lg;
        reg [9:0]  lv, x, x_rel;
        begin
            lg = log_fraclut(f);
            lv = {k, 5'd0} + {4'd0, lg};
            x  = 10'd511 - lv;
            x_rel = (x > ref_lv) ? (x - ref_lv) : 10'd0;
            log_row_base = x_rel + (x_rel >> 3) + (x_rel >> 4) + (x_rel >> 6);
        end
    endfunction

    // 第 4 级量程换算: 5 dB/div (x1), 2 dB/div (x2.5), 1 dB/div (x5)
    function [9:0] scale_row;
        input [9:0] r_base;
        input [1:0] yscale;
        reg [12:0] r_scaled;
        begin
            case (yscale)
                2'd1: r_scaled = {2'b00, r_base, 1'b0} + {4'd0, r_base[9:1]};
                2'd2: r_scaled = {1'b0, r_base, 2'b00} + {3'd0, r_base};
                default: r_scaled = {3'd0, r_base};
            endcase
            scale_row = (r_scaled > 13'd511) ? 10'd511 : r_scaled[9:0];
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

    // 像素列 -> 频点地址 (绘图区内恰好 1024 列); 时域读地址支持线性水平缩放
    wire [9:0] bin_addr = I_x[9:0] - 10'd64;
    reg [3:0] tscale_r;
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) tscale_r <= 4'd2;
        else              tscale_r <= I_tscale;
    end
    reg [9:0] wave_addr_r;
    always @(*) begin
        case (tscale_r)
            4'd3:    wave_addr_r = bin_addr - {2'b00, bin_addr[9:2]};
            4'd4:    wave_addr_r = {1'b0, bin_addr[9:1]};
            4'd5:    wave_addr_r = {1'b0, bin_addr[9:1]} - {3'b000, bin_addr[9:3]};
            4'd6:    wave_addr_r = {2'b00, bin_addr[9:2]};
            4'd7:    wave_addr_r = {2'b00, bin_addr[9:2]} - {4'b0000, bin_addr[9:4]};
            4'd8:    wave_addr_r = {3'b000, bin_addr[9:3]};
            4'd9:    wave_addr_r = {4'b0000, bin_addr[9:4]};
            4'd10:   wave_addr_r = {5'b00000, bin_addr[9:5]};
            4'd11:   wave_addr_r = {6'b000000, bin_addr[9:6]};
            default: wave_addr_r = bin_addr;
        endcase
    end
    assign O_wave_addr = wave_addr_r;

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
    // 参考迹线存储 (1024x16, 1 BSRAM)
    //==================================================================
    reg [15:0] ref_mem [0:1023];
    reg [15:0] ref_ram;
    reg        ref_sav_s0, ref_sav_s1, ref_sav_s2, ref_arm, ref_cap;

    always @(posedge I_wr_clk or negedge I_wr_rst_n) begin
        if (!I_wr_rst_n) begin
            ref_sav_s0 <= 1'b0;
            ref_sav_s1 <= 1'b0;
            ref_sav_s2 <= 1'b0;
            ref_arm    <= 1'b0;
            ref_cap    <= 1'b0;
        end else begin
            ref_sav_s0 <= I_ref_save_tog;
            ref_sav_s1 <= ref_sav_s0;
            ref_sav_s2 <= ref_sav_s1;
            if (ref_sav_s1 ^ ref_sav_s2)
                ref_arm <= 1'b1;
            if (I_frame_start) begin
                ref_cap <= ref_arm;
                if (ref_arm)
                    ref_arm <= 1'b0;
            end
        end
    end

    always @(posedge I_wr_clk) begin
        if (ref_cap && I_wr_en)
            ref_mem[I_wr_addr] <= I_wr_mag;
    end

    always @(posedge I_pix_clk) begin
        ref_ram <= ref_mem[bin_addr];
    end

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

    reg [15:0] mkr_mag_lat, mkr_ref_mag_lat;
    reg        mkr_upd_tog;
    wire [9:0] eff_mkr_col = (I_mkr_track && (I_view != 2'd2))
                             ? ((pk_col_lat == 10'd0) ? 10'd1 : pk_col_lat)
                             : I_mkr_col;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            pk_upd_d <= 1'b0;  bin_d <= 10'd0;  pk_ready <= 1'b0;
            mkr_mag_lat <= 16'd0;  mkr_ref_mag_lat <= 16'd0;  mkr_upd_tog <= 1'b0;
        end else begin
            pk_upd_d <= pk_upd;
            bin_d    <= bin_addr;
            if (pk_upd_d && (bin_d == 10'd1023))        // 第一帧装载完成
                pk_ready <= 1'b1;
            if (pk_upd_d && (bin_d == eff_mkr_col)) begin
                mkr_mag_lat <= mag_ram;
                mkr_upd_tog <= ~mkr_upd_tog;
            end
            if (pk_upd_d && (bin_d == I_mkr_ref_col)) begin
                mkr_ref_mag_lat <= mag_ram;
            end
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
    // 峰值读数 CDC 与 BCD 格式化 (pix_clk 域, 低资源顺序移位)
    //==================================================================
    reg        pk_tog_s1, pk_tog_s2, pk_tog_s3;
    reg        vpp_tog_s1, vpp_tog_s2, vpp_tog_s3;
    reg [9:0]  pk_col_lat;
    reg [15:0] pk_mag_lat, pk_left_lat, pk_right_lat;
    reg [12:0] pk_col_q3;
    reg [11:0] vpp_lat;
    reg signed [11:0] mid_lat;
    reg        wdiv_busy;
    reg [4:0]  wdiv_cnt;
    reg [16:0] wdiv_num;
    reg [12:0] wdiv_rem;
    reg [11:0] wdiv_den, wdiv_q, wave_gain_q8;
    reg [47:0] pk_f_str  = 48'h20_20_20_30_2E_30; // "   0.0"
    reg [23:0] pk_f_unit = 24'h6B_48_7A;          // "kHz"
    reg [47:0] pk_db_str = 48'h2D_39_36_2E_30_20; // "-96.0 "
    reg [31:0] vpp_str   = 32'h20_20_20_30;       // "   0"
    reg [47:0] wf_str    = 48'h20_20_2D_2D_2D_20; // "  --- "
    reg [23:0] wf_unit   = 24'h20_20_20;          // "   "
    reg [23:0] duty_str  = 24'h20_2D_2D;          // " --"
    reg [47:0] t1_str    = 48'h20_20_20_30_2E_30; // "   0.0"
    reg [47:0] dt_str    = 48'h20_20_20_30_2E_30;
    reg [47:0] idt_str   = 48'h20_20_2D_2D_2D_20;
    reg [23:0] t_unit    = 24'h75_73_20;          // "us "
    reg [31:0] tx1_str   = 32'h20_2E_32_35;
    reg [31:0] tx2_str   = 32'h20_2E_35_30;
    reg [31:0] tx3_str   = 32'h20_2E_37_35;
    reg [31:0] tx4_str   = 32'h54_49_4D_45;
    reg [39:0] h2_str    = 40'h20_20_2D_2D_2D;    // "  ---"
    reg [39:0] h3_str    = 40'h20_20_2D_2D_2D;
    reg [39:0] h4_str    = 40'h20_20_2D_2D_2D;
    reg [39:0] h5_str    = 40'h20_20_2D_2D_2D;
    reg [31:0] thd_str   = 32'h20_30_2E_30;       // " 0.0"
    reg [31:0] sfdr_str  = 32'h20_2D_2D_2D;       // " ---"
    reg [47:0] mkr_f_str = 48'h20_20_20_30_2E_30;
    reg [47:0] mkr_db_str= 48'h2D_39_36_2E_30_20;
    reg [47:0] dmkr_f_str = 48'h2B_20_20_30_2E_30;
    reg [47:0] dmkr_db_str= 48'h2B_20_30_2E_30_20;
    reg [47:0] h1_f_str  = 48'h20_20_2D_2D_2D_20;
    reg [47:0] h2_f_str  = 48'h20_20_2D_2D_2D_20;
    reg [47:0] h3_f_str  = 48'h20_20_2D_2D_2D_20;
    reg [47:0] h4_f_str  = 48'h20_20_2D_2D_2D_20;
    reg [47:0] h5_f_str  = 48'h20_20_2D_2D_2D_20;

    reg        fmt_busy;
    reg [4:0]  fmt_cnt;
    reg [8:0]  pk_lg2_r;
    reg [19:0] db_calc_r;
    reg [13:0] f_bin, db_bin, v_bin;
    reg [15:0] f_bcd, db_bcd, v_bcd;
    reg        f_two_dec;
    reg [23:0] f_unit_lat;

    wire [23:0] vpp_calc = vpp_lat * 12'd2500;

    function [15:0] bcd_add3;
        input [15:0] b;
        begin
            bcd_add3[3:0]   = (b[3:0]   >= 4'd5) ? (b[3:0]   + 4'd3) : b[3:0];
            bcd_add3[7:4]   = (b[7:4]   >= 4'd5) ? (b[7:4]   + 4'd3) : b[7:4];
            bcd_add3[11:8]  = (b[11:8]  >= 4'd5) ? (b[11:8]  + 4'd3) : b[11:8];
            bcd_add3[15:12] = (b[15:12] >= 4'd5) ? (b[15:12] + 4'd3) : b[15:12];
        end
    endfunction

    wire [15:0] f_bcd_adj  = bcd_add3(f_bcd);
    wire [15:0] db_bcd_adj = bcd_add3(db_bcd);
    wire [15:0] v_bcd_adj  = bcd_add3(v_bcd);

    wire span_mhz    = (I_span == 4'd6) || (I_span == 4'd9) || (I_span == 4'd10) || (I_span == 4'd11);
    wire span_twodec = span_mhz || (I_span == 4'd13) || (I_span == 4'd14);

    reg [13:0] f_scale_k;
    always @(*) begin
        case (I_span)
            4'd0:    f_scale_k = 14'd10000; // 1.000 MHz (kHz, 1dec)
            4'd1:    f_scale_k = 14'd2000;  // 200.0 kHz (kHz, 1dec)
            4'd2:    f_scale_k = 14'd500;   // 50.00 kHz (kHz, 1dec)
            4'd3:    f_scale_k = 14'd100;   // 10.00 kHz (kHz, 1dec)
            4'd4:    f_scale_k = 14'd10000; // 1.000 kHz (Hz,  1dec)
            4'd5:    f_scale_k = 14'd2000;  // 200.0 Hz  (Hz,  1dec)
            4'd6:    f_scale_k = 14'd2700;  // 27.00 MHz (MHz, 2dec)
            4'd7:    f_scale_k = 14'd5000;  // 500.0 kHz (kHz, 1dec)
            4'd8:    f_scale_k = 14'd1000;  // 100.0 kHz (kHz, 1dec)
            4'd9:    f_scale_k = 14'd270;   // 2.700 MHz (MHz, 2dec)
            4'd10:   f_scale_k = 14'd540;   // 5.400 MHz (MHz, 2dec)
            4'd11:   f_scale_k = 14'd1350;  // 13.50 MHz (MHz, 2dec)
            4'd12:   f_scale_k = 14'd200;   // 20.00 kHz (kHz, 1dec)
            4'd13:   f_scale_k = 14'd500;   // 5.000 kHz (kHz, 2dec)
            4'd14:   f_scale_k = 14'd200;   // 2.000 kHz (kHz, 2dec)
            4'd15:   f_scale_k = 14'd5000;  // 500.0 Hz  (Hz,  1dec)
            default: f_scale_k = 14'd0;
        endcase
    end

    wire [26:0] f_mul_val = pk_col_q3 * f_scale_k;

    reg [15:0] pk_abs_rl_r;
    reg [18:0] pk_den_r;
    reg        pk_r_ge_r;
    wire [18:0] pk_num8   = {pk_abs_rl_r, 3'b000};
    wire [19:0] pk_den1   = {1'b0, pk_den_r};
    wire [19:0] pk_den3   = {1'b0, pk_den_r} + {pk_den_r, 1'b0};
    wire [19:0] pk_den5   = {pk_den_r[17:0], 2'b00} + {1'b0, pk_den_r};
    wire [19:0] pk_den7   = {pk_den_r[17:0], 2'b00} + {pk_den_r, 1'b0} + {1'b0, pk_den_r};
    wire [2:0]  pk_sub_q3 = ((pk_col_lat <= 10'd3) || (pk_col_lat >= 10'd1022) || (pk_den_r == 19'd0)) ? 3'd0 :
                            ({1'b0, pk_num8} < pk_den1) ? 3'd0 :
                            ({1'b0, pk_num8} < pk_den3) ? 3'd1 :
                            ({1'b0, pk_num8} < pk_den5) ? 3'd2 :
                            ({1'b0, pk_num8} < pk_den7) ? 3'd3 : 3'd4;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            pk_tog_s1 <= 1'b0;  pk_tog_s2 <= 1'b0;  pk_tog_s3 <= 1'b0;
            vpp_tog_s1 <= 1'b0; vpp_tog_s2 <= 1'b0; vpp_tog_s3 <= 1'b0;
            pk_col_lat <= 10'd0;  pk_mag_lat <= 16'd0;  pk_left_lat <= 16'd0;  pk_right_lat <= 16'd0;
            pk_col_q3  <= 13'd0;  vpp_lat <= 12'd0;  mid_lat <= 12'sd0;
            wdiv_busy <= 1'b0;  wdiv_cnt <= 5'd0;
            wdiv_num <= 17'd0;  wdiv_rem <= 13'd0;  wdiv_den <= 12'd48;
            wdiv_q <= 12'd0;  wave_gain_q8 <= 12'd28;
            fmt_busy <= 1'b0;  fmt_cnt <= 5'd0;
            pk_lg2_r <= 9'd0;  db_calc_r <= 20'd0;
            f_bin <= 14'd0;  db_bin <= 14'd0;  v_bin <= 14'd0;
            f_bcd <= 16'd0;  db_bcd <= 16'd0;  v_bcd <= 16'd0;
            f_two_dec <= 1'b0;
            f_unit_lat <= 24'h6B_48_7A;
            pk_f_str  <= 48'h20_20_20_30_2E_30;
            pk_f_unit <= 24'h6B_48_7A;
            pk_db_str <= 48'h2D_39_36_2E_30_20;
            vpp_str   <= 32'h20_20_20_30;
        end else begin
            pk_tog_s1  <= I_pk_tog;
            pk_tog_s2  <= pk_tog_s1;
            pk_tog_s3  <= pk_tog_s2;
            vpp_tog_s1 <= I_vpp_tog;
            vpp_tog_s2 <= vpp_tog_s1;
            vpp_tog_s3 <= vpp_tog_s2;

            if (vpp_tog_s2 ^ vpp_tog_s3) begin
                mid_lat   <= I_wave_mid;
                wdiv_busy <= 1'b1;
                wdiv_cnt  <= 5'd0;
                wdiv_num  <= 17'd117760; // 460 px * 256
                wdiv_rem  <= 13'd0;
                wdiv_den  <= (I_vpp < 12'd48) ? 12'd48 : I_vpp;
                wdiv_q    <= 12'd0;
            end else if (wdiv_busy) begin
                if ({wdiv_rem[11:0], wdiv_num[16]} >= {1'b0, wdiv_den}) begin
                    wdiv_rem <= {wdiv_rem[11:0], wdiv_num[16]} - {1'b0, wdiv_den};
                    wdiv_q   <= {wdiv_q[10:0], 1'b1};
                end else begin
                    wdiv_rem <= {wdiv_rem[11:0], wdiv_num[16]};
                    wdiv_q   <= {wdiv_q[10:0], 1'b0};
                end
                wdiv_num <= {wdiv_num[15:0], 1'b0};
                if (wdiv_cnt == 5'd16) begin
                    wave_gain_q8 <= ({wdiv_rem[11:0], wdiv_num[16]} >= {1'b0, wdiv_den})
                                    ? {wdiv_q[10:0], 1'b1} : {wdiv_q[10:0], 1'b0};
                    wdiv_busy    <= 1'b0;
                end else begin
                    wdiv_cnt <= wdiv_cnt + 5'd1;
                end
            end

            if (((pk_tog_s2 ^ pk_tog_s3) || (vpp_tog_s2 ^ vpp_tog_s3)) && !fmt_busy) begin
                pk_col_lat   <= I_pk_col;
                pk_mag_lat   <= I_pk_mag;
                pk_left_lat  <= I_pk_left;
                pk_right_lat <= I_pk_right;
                vpp_lat      <= I_vpp;
                fmt_busy     <= 1'b1;
                fmt_cnt      <= 5'd0;
            end else if (fmt_busy) begin
                if (fmt_cnt == 5'd0) begin
                    pk_lg2_r    <= log_split(pk_mag_lat);
                    pk_r_ge_r   <= (pk_right_lat >= pk_left_lat);
                    pk_abs_rl_r <= (pk_right_lat >= pk_left_lat) ? (pk_right_lat - pk_left_lat)
                                                                 : (pk_left_lat - pk_right_lat);
                    pk_den_r    <= {2'b00, pk_mag_lat, 1'b0} - {3'b000, pk_left_lat} - {3'b000, pk_right_lat};
                    fmt_cnt     <= 5'd1;
                end else if (fmt_cnt == 5'd1) begin
                    db_calc_r <= (10'd512 - {1'b0, pk_lg2_r}) * 12'd1926;
                    pk_col_q3 <= pk_r_ge_r
                                 ? ({pk_col_lat, 3'b000} + {10'd0, pk_sub_q3})
                                 : ({pk_col_lat, 3'b000} - {10'd0, pk_sub_q3});
                    fmt_cnt   <= 5'd2;
                end else if (fmt_cnt == 5'd2) begin
                    f_bin  <= f_mul_val[26:13];
                    db_bin <= (pk_mag_lat == 16'd0) ? 14'd960 : {4'd0, db_calc_r[19:10]};
                    v_bin  <= vpp_calc[23:10];
                    f_bcd  <= 16'd0;
                    db_bcd <= 16'd0;
                    v_bcd  <= 16'd0;
                    f_two_dec <= span_twodec;
                    case (I_span)
                        4'd4, 4'd5, 4'd15:        f_unit_lat <= 24'h48_7A_20; // "Hz "
                        4'd6, 4'd9, 4'd10, 4'd11: f_unit_lat <= 24'h4D_48_7A; // "MHz"
                        default:                  f_unit_lat <= 24'h6B_48_7A; // "kHz"
                    endcase
                    fmt_cnt <= 5'd3;
                end else if (fmt_cnt <= 5'd16) begin
                    f_bcd   <= {f_bcd_adj[14:0], f_bin[13]};
                    f_bin   <= {f_bin[12:0], 1'b0};
                    db_bcd  <= {db_bcd_adj[14:0], db_bin[13]};
                    db_bin  <= {db_bin[12:0], 1'b0};
                    v_bcd   <= {v_bcd_adj[14:0], v_bin[13]};
                    v_bin   <= {v_bin[12:0], 1'b0};
                    fmt_cnt <= fmt_cnt + 5'd1;
                end else begin
                    fmt_busy  <= 1'b0;
                    pk_f_unit <= f_unit_lat;
                    if (f_two_dec) begin
                        pk_f_str <= {
                            8'h20,
                            (f_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, f_bcd[15:12]}) : 8'h20,
                            8'h30 + {4'd0, f_bcd[11:8]},
                            8'h2E,
                            8'h30 + {4'd0, f_bcd[7:4]},
                            8'h30 + {4'd0, f_bcd[3:0]}
                        };
                    end else begin
                        pk_f_str <= {
                            8'h20,
                            (f_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, f_bcd[15:12]}) : 8'h20,
                            ((f_bcd[15:12] != 4'd0) || (f_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, f_bcd[11:8]}) : 8'h20,
                            8'h30 + {4'd0, f_bcd[7:4]},
                            8'h2E,
                            8'h30 + {4'd0, f_bcd[3:0]}
                        };
                    end
                    pk_db_str <= {
                        8'h2D,
                        (db_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, db_bcd[11:8]}) : 8'h20,
                        8'h30 + {4'd0, db_bcd[7:4]},
                        8'h2E,
                        8'h30 + {4'd0, db_bcd[3:0]},
                        8'h20
                    };
                    vpp_str <= {
                        (v_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, v_bcd[15:12]}) : 8'h20,
                        ((v_bcd[15:12] != 4'd0) || (v_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, v_bcd[11:8]}) : 8'h20,
                        ((v_bcd[15:12] != 4'd0) || (v_bcd[11:8] != 4'd0) || (v_bcd[7:4] != 4'd0)) ? (8'h30 + {4'd0, v_bcd[7:4]}) : 8'h20,
                        8'h30 + {4'd0, v_bcd[3:0]}
                    };
                end
            end
        end
    end

    //==================================================================
    // 时域测频 (WF) & 占空比 (DT%) 顺序除法与 BCD 格式化 (0 BSRAM)
    //==================================================================
    reg [1:0]  td_st;
    reg [4:0]  td_cnt;
    reg [24:0] td_num, td_q;
    reg [12:0] td_rem;
    reg [11:0] td_den;
    reg [9:0]  td_high_lat, td_psmp_lat;
    reg [13:0] td_wf_bin, td_dt_bin;
    reg [15:0] td_wf_bcd, td_dt_bcd;
    reg        td_two_dec;
    reg [23:0] td_unit_lat;

    wire [1:0]  td_tdec = (I_tscale == 4'd0) ? 2'd2 : (I_tscale == 4'd1) ? 2'd1 : 2'd0;
    wire [14:0] td_span_2x = (I_span == 4'd0)  ? 15'd20000 :
                             (I_span == 4'd1)  ? 15'd4000  :
                             (I_span == 4'd2)  ? 15'd1000  :
                             (I_span == 4'd3)  ? 15'd200   :
                             (I_span == 4'd4)  ? 15'd20000 :
                             (I_span == 4'd5)  ? 15'd4000  :
                             (I_span == 4'd7)  ? 15'd10000 :
                             (I_span == 4'd8)  ? 15'd2000  :
                             (I_span == 4'd9)  ? 15'd540   :
                             (I_span == 4'd10) ? 15'd1080  :
                             (I_span == 4'd11) ? 15'd2700  :
                             (I_span == 4'd12) ? 15'd400   :
                             (I_span == 4'd13) ? 15'd1000  :
                             (I_span == 4'd14) ? 15'd400   :
                             (I_span == 4'd15) ? 15'd10000 : 15'd5400;
    wire [12:0] td_rem_nxt   = {td_rem[11:0], td_num[24]};
    wire        td_ge        = (td_rem_nxt >= {1'b0, td_den});
    wire [15:0] td_wf_adj    = bcd_add3(td_wf_bcd);
    wire [15:0] td_dt_adj    = bcd_add3(td_dt_bcd);
    wire [16:0] td_high_100  = td_high_lat * 7'd100;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            td_st       <= 2'd0;
            td_cnt      <= 5'd0;
            td_num      <= 25'd0;
            td_q        <= 25'd0;
            td_rem      <= 13'd0;
            td_den      <= 12'd1;
            td_high_lat <= 10'd0;
            td_psmp_lat <= 10'd1;
            td_wf_bin   <= 14'd0;
            td_dt_bin   <= 14'd0;
            td_wf_bcd   <= 16'd0;
            td_dt_bcd   <= 16'd0;
            td_two_dec  <= 1'b0;
            td_unit_lat <= 24'h20_20_20;
            wf_str      <= 48'h20_20_2D_2D_2D_20;
            wf_unit     <= 24'h20_20_20;
            duty_str    <= 24'h20_2D_2D;
        end else if (vpp_tog_s2 ^ vpp_tog_s3) begin
            if (!I_meas_vld || (I_period_smp == 10'd0)) begin
                td_st    <= 2'd0;
                wf_str   <= 48'h20_20_2D_2D_2D_20;
                wf_unit  <= 24'h20_20_20;
                duty_str <= 24'h20_2D_2D;
            end else begin
                td_st       <= 2'd1;
                td_cnt      <= 5'd0;
                td_num      <= td_span_2x * I_period_cnt;
                td_den      <= {2'b00, I_period_smp} << td_tdec;
                td_rem      <= 13'd0;
                td_q        <= 25'd0;
                td_high_lat <= I_high_smp;
                td_psmp_lat <= I_period_smp;
                td_two_dec  <= span_twodec;
                case (I_span)
                    4'd4, 4'd5, 4'd15:        td_unit_lat <= 24'h48_7A_20;
                    4'd6, 4'd9, 4'd10, 4'd11: td_unit_lat <= 24'h4D_48_7A;
                    default:                  td_unit_lat <= 24'h6B_48_7A;
                endcase
            end
        end else begin
            case (td_st)
                2'd1: begin
                    if (td_cnt < 5'd25) begin
                        td_rem <= td_ge ? (td_rem_nxt - {1'b0, td_den}) : td_rem_nxt;
                        td_q   <= {td_q[23:0], td_ge};
                        td_num <= {td_num[23:0], 1'b0};
                        td_cnt <= td_cnt + 5'd1;
                    end else begin
                        td_wf_bin <= (|td_q[24:14]) ? 14'd9999 : td_q[13:0];
                        td_num    <= {td_high_100, 8'd0};
                        td_den    <= {2'b00, td_psmp_lat};
                        td_rem    <= 13'd0;
                        td_q      <= 25'd0;
                        td_cnt    <= 5'd0;
                        td_st     <= 2'd2;
                    end
                end
                2'd2: begin
                    if (td_cnt < 5'd17) begin
                        td_rem <= td_ge ? (td_rem_nxt - {1'b0, td_den}) : td_rem_nxt;
                        td_q   <= {td_q[23:0], td_ge};
                        td_num <= {td_num[23:0], 1'b0};
                        td_cnt <= td_cnt + 5'd1;
                    end else begin
                        td_dt_bin <= {7'd0, (td_q[6:0] > 7'd100) ? 7'd100 : td_q[6:0]};
                        td_wf_bcd <= 16'd0;
                        td_dt_bcd <= 16'd0;
                        td_cnt    <= 5'd0;
                        td_st     <= 2'd3;
                    end
                end
                2'd3: begin
                    if (td_cnt < 5'd14) begin
                        td_wf_bcd <= {td_wf_adj[14:0], td_wf_bin[13]};
                        td_wf_bin <= {td_wf_bin[12:0], 1'b0};
                        td_dt_bcd <= {td_dt_adj[14:0], td_dt_bin[13]};
                        td_dt_bin <= {td_dt_bin[12:0], 1'b0};
                        td_cnt    <= td_cnt + 5'd1;
                    end else begin
                        td_st   <= 2'd0;
                        wf_unit <= td_unit_lat;
                        if (td_two_dec) begin
                            wf_str <= {
                                8'h20,
                                (td_wf_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, td_wf_bcd[15:12]}) : 8'h20,
                                8'h30 + {4'd0, td_wf_bcd[11:8]},
                                8'h2E,
                                8'h30 + {4'd0, td_wf_bcd[7:4]},
                                8'h30 + {4'd0, td_wf_bcd[3:0]}
                            };
                        end else begin
                            wf_str <= {
                                8'h20,
                                (td_wf_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, td_wf_bcd[15:12]}) : 8'h20,
                                ((td_wf_bcd[15:12] != 4'd0) || (td_wf_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, td_wf_bcd[11:8]}) : 8'h20,
                                8'h30 + {4'd0, td_wf_bcd[7:4]},
                                8'h2E,
                                8'h30 + {4'd0, td_wf_bcd[3:0]}
                            };
                        end
                        duty_str <= {
                            (td_dt_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, td_dt_bcd[11:8]}) : 8'h20,
                            ((td_dt_bcd[11:8] != 4'd0) || (td_dt_bcd[7:4] != 4'd0)) ? (8'h30 + {4'd0, td_dt_bcd[7:4]}) : 8'h20,
                            8'h30 + {4'd0, td_dt_bcd[3:0]}
                        };
                    end
                end
                default: td_st <= 2'd0;
            endcase
        end
    end

    //==================================================================
    // 时域双光标 (T1 / dT / 1/dT) 计算与格式化 (0 BSRAM)
    //==================================================================
    function [13:0] px_to_q2;
        input [9:0] dx;
        input [3:0] tz;
        reg [11:0] dx3;
        begin
            dx3 = {2'b00, dx} + {1'b0, dx, 1'b0}; // 3 * dx
            case (tz)
                4'd0:    px_to_q2 = {dx, 4'b0000};       // x0.25 -> 16*dx
                4'd1:    px_to_q2 = {1'b0, dx, 3'b000};  // x0.5  -> 8*dx
                4'd2:    px_to_q2 = {2'b00, dx, 2'b00};  // x1.0  -> 4*dx
                4'd3:    px_to_q2 = {2'b00, dx3};        // x1.3  -> 3*dx
                4'd4:    px_to_q2 = {3'b000, dx, 1'b0};  // x2.0  -> 2*dx
                4'd5:    px_to_q2 = {3'b000, dx3[11:1]}; // x2.7  -> 1.5*dx
                4'd6:    px_to_q2 = {4'b0000, dx};       // x4.0  -> 1*dx
                4'd7:    px_to_q2 = {4'b0000, dx3[11:2]};// x5.3  -> 0.75*dx
                4'd8:    px_to_q2 = {5'b00000, dx[9:1]}; // x8.0  -> dx/2
                4'd9:    px_to_q2 = {6'b000000, dx[9:2]};// x16   -> dx/4
                4'd10:   px_to_q2 = {7'd0, dx[9:3]};     // x32   -> dx/8
                default: px_to_q2 = {8'd0, dx[9:4]};     // x64   -> dx/16
            endcase
        end
    endfunction

    function [24:0] tc_scale_mul;
        input [13:0] q2;
        input [3:0]  sp;
        reg [24:0] q, q474;
        begin
            q    = {11'd0, q2};
            q474 = (q << 9) - (q << 5) - (q << 2) - (q << 1); // *474
            case (sp)
                4'd0, 4'd3, 4'd4: tc_scale_mul = (q << 10) + (q << 8);              // *1280
                4'd1, 4'd5:       tc_scale_mul = (q << 6);                          // *64 (200k, 200Hz)
                4'd2, 4'd13, 4'd15: tc_scale_mul = (q << 8);                        // *256 (50k, 5k, 500Hz)
                4'd7:             tc_scale_mul = (q << 11) + (q << 9);              // *2560
                4'd8:             tc_scale_mul = (q << 7);                          // *128
                4'd10:            tc_scale_mul = (q474 << 2) + q474;                // *2370
                4'd11:            tc_scale_mul = (q474 << 1);                       // *948
                4'd12, 4'd14:     tc_scale_mul = (q << 9) + (q << 7);               // *640 (20k, 2k)
                default:          tc_scale_mul = q474;                              // *474 (6, 9)
            endcase
        end
    endfunction

    reg [30:0] tc_key_prev;
    wire [30:0] tc_key_cur = {I_view, I_span, I_tscale, I_mkr_col, I_mkr_ref_col, I_mkr_delta};
    reg [2:0]  tc_st;
    reg [4:0]  tc_cnt;
    reg [13:0] tc_q2_1, tc_q2_2;
    reg [14:0] tc_t1_v_r, tc_dt_v_r;
    reg [16:0] tc_num, tc_q;
    reg [14:0] tc_rem;
    reg [13:0] tc_den, tc_t1_bin, tc_dt_bin, tc_idt_bin;
    reg [15:0] tc_t1_bcd, tc_dt_bcd, tc_idt_bcd;
    reg        tc_t_twodec, tc_f_twodec, tc_idt_vld;
    reg [23:0] tc_tunit_lat;

    wire [9:0]  tc_dx2     = (I_mkr_col >= I_mkr_ref_col) ? (I_mkr_col - I_mkr_ref_col)
                                                          : (I_mkr_ref_col - I_mkr_col);
    wire [24:0] tc_t1_mul  = tc_scale_mul(tc_q2_1, I_span);
    wire [24:0] tc_dt_mul  = tc_scale_mul(tc_q2_2, I_span);
    wire [14:0] tc_rem_nxt = {tc_rem[13:0], tc_num[16]};
    wire        tc_ge      = (tc_rem_nxt >= {1'b0, tc_den});
    wire [15:0] tc_t1_adj  = bcd_add3(tc_t1_bcd);
    wire [15:0] tc_dt_adj  = bcd_add3(tc_dt_bcd);
    wire [15:0] tc_idt_adj = bcd_add3(tc_idt_bcd);

    reg [7:0]  tx_key_prev;
    wire [7:0] tx_key_cur = {I_span, I_tscale};
    reg [2:0]  tx_st;
    reg [1:0]  tx_idx;
    reg [4:0]  tx_cnt;
    reg [13:0] tx_q2, tx_bin;
    reg [14:0] tx_v_r;
    reg [15:0] tx_bcd;
    reg        tx_over, tx_twodec;
    wire [9:0]  tx_dx = (tx_idx == 2'd0) ? 10'd256 :
                        (tx_idx == 2'd1) ? 10'd512 :
                        (tx_idx == 2'd2) ? 10'd768 : 10'd1023;
    wire [24:0] tx_mul = tc_scale_mul(tx_q2, I_span);
    wire [13:0] tx_div10 = (tx_v_r >> 4) + (tx_v_r >> 5) + (tx_v_r >> 8) + (tx_v_r >> 9) + (tx_v_r >> 12);
    wire [15:0] tx_bcd_adj = bcd_add3(tx_bcd);
    wire [31:0] tx_fmt_str = tx_over ? (
                                 tx_twodec ? {
                                     (tx_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tx_bcd[15:12]}) : 8'h20,
                                     8'h30 + {4'd0, tx_bcd[11:8]}, 8'h30 + {4'd0, tx_bcd[7:4]}, 8'h20
                                 } : {
                                     (tx_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tx_bcd[15:12]}) : 8'h20,
                                     8'h30 + {4'd0, tx_bcd[11:8]}, 8'h30 + {4'd0, tx_bcd[7:4]}, 8'h30 + {4'd0, tx_bcd[3:0]}
                                 }
                             ) : tx_twodec ? {
                                 (tx_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tx_bcd[15:12]}) : 8'h20,
                                 8'h30 + {4'd0, tx_bcd[11:8]}, 8'h2E, 8'h30 + {4'd0, tx_bcd[7:4]}
                             } : (tx_bcd[15:12] != 4'd0) ? {
                                 8'h30 + {4'd0, tx_bcd[15:12]}, 8'h30 + {4'd0, tx_bcd[11:8]},
                                 8'h30 + {4'd0, tx_bcd[7:4]}, 8'h20
                             } : {
                                 (tx_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, tx_bcd[11:8]}) : 8'h20,
                                 8'h30 + {4'd0, tx_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, tx_bcd[3:0]}
                             };

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            tx_key_prev <= 8'hFF;
            tx_st       <= 3'd0;
            tx_idx      <= 2'd0;
            tx_cnt      <= 5'd0;
            tx_q2       <= 14'd0;
            tx_v_r      <= 15'd0;
            tx_bin      <= 14'd0;
            tx_bcd      <= 16'd0;
            tx_over     <= 1'b0;
            tx_twodec   <= 1'b0;
            tx1_str     <= 32'h20_2E_32_35;
            tx2_str     <= 32'h20_2E_35_30;
            tx3_str     <= 32'h20_2E_37_35;
            tx4_str     <= 32'h54_49_4D_45;
        end else if (tx_key_cur != tx_key_prev) begin
            tx_key_prev <= tx_key_cur;
            tx_twodec   <= (I_span == 4'd1) || (I_span == 4'd2) || (I_span == 4'd3) || (I_span == 4'd5) ||
                           (I_span == 4'd6) || (I_span == 4'd8) || (I_span == 4'd10) || (I_span == 4'd11) || (I_span == 4'd12);
            tx_idx      <= 2'd0;
            tx_st       <= 3'd1;
        end else begin
            case (tx_st)
                3'd1: begin
                    tx_q2 <= px_to_q2(tx_dx, I_tscale);
                    tx_st <= 3'd2;
                end
                3'd2: begin
                    tx_v_r <= tx_mul[24:10];
                    tx_st  <= 3'd3;
                end
                3'd3: begin
                    tx_over <= (tx_v_r > 15'd9999);
                    tx_bin  <= (tx_v_r > 15'd9999) ? tx_div10 : tx_v_r[13:0];
                    tx_bcd  <= 16'd0;
                    tx_cnt  <= 5'd0;
                    tx_st   <= 3'd4;
                end
                3'd4: begin
                    if (tx_cnt < 5'd14) begin
                        tx_bcd <= {tx_bcd_adj[14:0], tx_bin[13]};
                        tx_bin <= {tx_bin[12:0], 1'b0};
                        tx_cnt <= tx_cnt + 5'd1;
                    end else begin
                        case (tx_idx)
                            2'd0: tx1_str <= tx_fmt_str;
                            2'd1: tx2_str <= tx_fmt_str;
                            2'd2: tx3_str <= tx_fmt_str;
                            2'd3: tx4_str <= tx_fmt_str;
                        endcase
                        if (tx_idx == 2'd3) begin
                            tx_st <= 3'd0;
                        end else begin
                            tx_idx <= tx_idx + 2'd1;
                            tx_st  <= 3'd1;
                        end
                    end
                end
                default: tx_st <= 3'd0;
            endcase
        end
    end

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            tc_key_prev  <= 31'd0;
            tc_st        <= 3'd0;
            tc_cnt       <= 5'd0;
            tc_q2_1      <= 14'd0;
            tc_q2_2      <= 14'd0;
            tc_t1_v_r    <= 15'd0;
            tc_dt_v_r    <= 15'd0;
            tc_num       <= 17'd0;
            tc_q         <= 17'd0;
            tc_rem       <= 15'd0;
            tc_den       <= 14'd1;
            tc_t1_bin    <= 14'd0;
            tc_dt_bin    <= 14'd0;
            tc_idt_bin   <= 14'd0;
            tc_t1_bcd    <= 16'd0;
            tc_dt_bcd    <= 16'd0;
            tc_idt_bcd   <= 16'd0;
            tc_t_twodec  <= 1'b0;
            tc_f_twodec  <= 1'b0;
            tc_idt_vld   <= 1'b0;
            tc_tunit_lat <= 24'h75_73_20;
            t1_str       <= 48'h20_20_20_30_2E_30;
            dt_str       <= 48'h20_20_20_30_2E_30;
            idt_str      <= 48'h20_20_2D_2D_2D_20;
            t_unit       <= 24'h75_73_20;
        end else if (tc_key_cur != tc_key_prev) begin
            tc_key_prev  <= tc_key_cur;
            tc_q2_1      <= px_to_q2(I_mkr_col, I_tscale);
            tc_q2_2      <= px_to_q2(tc_dx2, I_tscale);
            tc_t_twodec  <= (I_span == 4'd1) || (I_span == 4'd2) || (I_span == 4'd3) || (I_span == 4'd5) ||
                            (I_span == 4'd6) || (I_span == 4'd8) || (I_span == 4'd10) || (I_span == 4'd11) || (I_span == 4'd12);
            tc_f_twodec  <= span_twodec;
            case (I_span)
                4'd0, 4'd6, 4'd7, 4'd9, 4'd10, 4'd11: tc_tunit_lat <= 24'h75_73_20; // "us "
                4'd5:                                 tc_tunit_lat <= 24'h73_20_20; // "s  "
                default:                              tc_tunit_lat <= 24'h6D_73_20; // "ms "
            endcase
            tc_st <= 3'd1;
        end else begin
            case (tc_st)
                3'd1: begin
                    tc_t1_v_r <= tc_t1_mul[24:10];
                    tc_dt_v_r <= tc_dt_mul[24:10];
                    tc_st     <= 3'd2;
                end
                3'd2: begin
                    tc_t1_bin <= (tc_t1_v_r > 15'd9999) ? 14'd9999 : tc_t1_v_r[13:0];
                    tc_dt_bin <= (tc_dt_v_r > 15'd9999) ? 14'd9999 : tc_dt_v_r[13:0];
                    if (I_mkr_delta && (tc_q2_2 != 14'd0)) begin
                        tc_num     <= {td_span_2x, 2'b00};
                        tc_den     <= tc_q2_2;
                        tc_rem     <= 15'd0;
                        tc_q       <= 17'd0;
                        tc_cnt     <= 5'd0;
                        tc_idt_vld <= 1'b1;
                        tc_st      <= 3'd3;
                    end else begin
                        tc_idt_bin <= 14'd0;
                        tc_idt_vld <= 1'b0;
                        tc_t1_bcd  <= 16'd0;
                        tc_dt_bcd  <= 16'd0;
                        tc_idt_bcd <= 16'd0;
                        tc_cnt     <= 5'd0;
                        tc_st      <= 3'd4;
                    end
                end
                3'd3: begin
                    if (tc_cnt < 5'd17) begin
                        tc_rem <= tc_ge ? (tc_rem_nxt - {1'b0, tc_den}) : tc_rem_nxt;
                        tc_q   <= {tc_q[15:0], tc_ge};
                        tc_num <= {tc_num[15:0], 1'b0};
                        tc_cnt <= tc_cnt + 5'd1;
                    end else begin
                        tc_idt_bin <= (|tc_q[16:14] || (tc_q[13:0] > 14'd9999)) ? 14'd9999 : tc_q[13:0];
                        tc_t1_bcd  <= 16'd0;
                        tc_dt_bcd  <= 16'd0;
                        tc_idt_bcd <= 16'd0;
                        tc_cnt     <= 5'd0;
                        tc_st      <= 3'd4;
                    end
                end
                3'd4: begin
                    if (tc_cnt < 5'd14) begin
                        tc_t1_bcd  <= {tc_t1_adj[14:0], tc_t1_bin[13]};
                        tc_t1_bin  <= {tc_t1_bin[12:0], 1'b0};
                        tc_dt_bcd  <= {tc_dt_adj[14:0], tc_dt_bin[13]};
                        tc_dt_bin  <= {tc_dt_bin[12:0], 1'b0};
                        tc_idt_bcd <= {tc_idt_adj[14:0], tc_idt_bin[13]};
                        tc_idt_bin <= {tc_idt_bin[12:0], 1'b0};
                        tc_cnt     <= tc_cnt + 5'd1;
                    end else begin
                        tc_st  <= 3'd0;
                        t_unit <= tc_tunit_lat;
                        if (tc_t_twodec) begin
                            t1_str <= {
                                8'h20,
                                (tc_t1_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tc_t1_bcd[15:12]}) : 8'h20,
                                8'h30 + {4'd0, tc_t1_bcd[11:8]}, 8'h2E,
                                8'h30 + {4'd0, tc_t1_bcd[7:4]}, 8'h30 + {4'd0, tc_t1_bcd[3:0]}
                            };
                            dt_str <= {
                                8'h20,
                                (tc_dt_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tc_dt_bcd[15:12]}) : 8'h20,
                                8'h30 + {4'd0, tc_dt_bcd[11:8]}, 8'h2E,
                                8'h30 + {4'd0, tc_dt_bcd[7:4]}, 8'h30 + {4'd0, tc_dt_bcd[3:0]}
                            };
                        end else begin
                            t1_str <= {
                                8'h20,
                                (tc_t1_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tc_t1_bcd[15:12]}) : 8'h20,
                                ((tc_t1_bcd[15:12] != 4'd0) || (tc_t1_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, tc_t1_bcd[11:8]}) : 8'h20,
                                8'h30 + {4'd0, tc_t1_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, tc_t1_bcd[3:0]}
                            };
                            dt_str <= {
                                8'h20,
                                (tc_dt_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tc_dt_bcd[15:12]}) : 8'h20,
                                ((tc_dt_bcd[15:12] != 4'd0) || (tc_dt_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, tc_dt_bcd[11:8]}) : 8'h20,
                                8'h30 + {4'd0, tc_dt_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, tc_dt_bcd[3:0]}
                            };
                        end
                        if (!tc_idt_vld) begin
                            idt_str <= 48'h20_20_2D_2D_2D_20;
                        end else if (tc_f_twodec) begin
                            idt_str <= {
                                8'h20,
                                (tc_idt_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tc_idt_bcd[15:12]}) : 8'h20,
                                8'h30 + {4'd0, tc_idt_bcd[11:8]}, 8'h2E,
                                8'h30 + {4'd0, tc_idt_bcd[7:4]}, 8'h30 + {4'd0, tc_idt_bcd[3:0]}
                            };
                        end else begin
                            idt_str <= {
                                8'h20,
                                (tc_idt_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, tc_idt_bcd[15:12]}) : 8'h20,
                                ((tc_idt_bcd[15:12] != 4'd0) || (tc_idt_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, tc_idt_bcd[11:8]}) : 8'h20,
                                8'h30 + {4'd0, tc_idt_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, tc_idt_bcd[3:0]}
                            };
                        end
                    end
                end
                default: tc_st <= 2'd0;
            endcase
        end
    end

    //==================================================================
    // 谐波 dBc / THD% / Marker 顺序计算状态机 (0 BSRAM, 共享乘法/BCD)
    //==================================================================
    reg [15:0] h2_lat, h3_lat, h4_lat, h5_lat, spur_mag_lat;
    reg [9:0]  h2_col_lat, h3_col_lat, h4_col_lat, h5_col_lat;
    reg        mkr_tog_s1, mkr_tog_s2;
    reg [9:0]  prev_mkr_col, prev_mkr_ref_col;
    reg        prev_mkr_delta;
    reg [13:0] mkr_f_val_r;
    reg [9:0]  mkr_db_val_r;
    reg        df_neg, ddb_neg;
    reg [3:0]  aux_phase;      // 0:idle 1:mkr 2..5:H2..H5 6:sqrt 7:div/thd 8..12:H1..H5 freq 13:dMkr
    reg [5:0]  aux_cnt;
    reg        aux_req;
    reg [13:0] a_bin, b_bin;
    reg [15:0] a_bcd, b_bcd;
    reg [15:0] aux_mag_r;
    reg [9:0]  aux_f_col_r;
    reg [23:0] aux_f_mul_r;
    reg [8:0]  aux_lg2_r;
    reg [9:0]  aux_lg2_dif_r;
    reg [19:0] aux_db_mul_r;
    reg [31:0] aux_sq_r;
    reg [33:0] h_sq_sum, sqrt_rad;
    reg [18:0] sqrt_rem;
    reg [16:0] sqrt_q;
    reg [26:0] div_num;
    reg [16:0] div_rem;
    reg [13:0] div_q;

    wire [15:0] a_bcd_adj = bcd_add3(a_bcd);
    wire [15:0] b_bcd_adj = bcd_add3(b_bcd);

    wire [9:0] harm_f_col = (aux_phase == 4'd8)  ? pk_col_lat :
                            (aux_phase == 4'd9)  ? h2_col_lat :
                            (aux_phase == 4'd10) ? h3_col_lat :
                            (aux_phase == 4'd11) ? h4_col_lat : h5_col_lat;

    wire [23:0] aux_f_mul = aux_f_col_r * f_scale_k;

    wire [15:0] h_cur_mag = (aux_phase == 4'd2) ? h2_lat :
                            (aux_phase == 4'd3) ? h3_lat :
                            (aux_phase == 4'd4) ? h4_lat : h5_lat;

    wire harm_f_vld = (aux_phase == 4'd8) ? (pk_col_lat >= 10'd3) : (aux_f_col_r != 10'd0);
    wire [47:0] h_f_fmt_str = !harm_f_vld ? 48'h20_20_2D_2D_2D_20 :
                              span_twodec ? {
                                  8'h20,
                                  (a_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, a_bcd[15:12]}) : 8'h20,
                                  8'h30 + {4'd0, a_bcd[11:8]}, 8'h2E,
                                  8'h30 + {4'd0, a_bcd[7:4]}, 8'h30 + {4'd0, a_bcd[3:0]}
                              } : {
                                  8'h20,
                                  (a_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, a_bcd[15:12]}) : 8'h20,
                                  ((a_bcd[15:12] != 4'd0) || (a_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, a_bcd[11:8]}) : 8'h20,
                                  8'h30 + {4'd0, a_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, a_bcd[3:0]}
                              };

    wire [18:0] sqrt_rem_nxt = {sqrt_rem[16:0], sqrt_rad[33:32]};
    wire [18:0] sqrt_cand    = {sqrt_q, 2'b01};
    wire        sqrt_ge      = (sqrt_rem_nxt >= sqrt_cand);

    wire [16:0] div_rem_nxt  = {div_rem[15:0], div_num[26]};
    wire        div_ge       = (div_rem_nxt >= {1'b0, pk_mag_lat});

    wire [39:0] h_fmt_str = (aux_mag_r == 16'd0 || pk_mag_lat == 16'd0) ? 40'h20_20_2D_2D_2D : {
        8'h2D,
        (a_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, a_bcd[11:8]}) : 8'h20,
        8'h30 + {4'd0, a_bcd[7:4]},
        8'h2E,
        8'h30 + {4'd0, a_bcd[3:0]}
    };

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            h2_lat <= 16'd0;  h3_lat <= 16'd0;  h4_lat <= 16'd0;  h5_lat <= 16'd0;
            spur_mag_lat <= 16'd0;
            h2_col_lat <= 10'd0;  h3_col_lat <= 10'd0;  h4_col_lat <= 10'd0;  h5_col_lat <= 10'd0;
            mkr_tog_s1 <= 1'b0;  mkr_tog_s2 <= 1'b0;
            prev_mkr_col <= 10'd0;  prev_mkr_ref_col <= 10'd0;  prev_mkr_delta <= 1'b0;
            mkr_f_val_r <= 14'd0;  mkr_db_val_r <= 10'd960;
            df_neg <= 1'b0;  ddb_neg <= 1'b0;
            aux_phase <= 4'd0;  aux_cnt <= 6'd0;  aux_req <= 1'b0;
            a_bin <= 14'd0;  b_bin <= 14'd0;  a_bcd <= 16'd0;  b_bcd <= 16'd0;
            aux_mag_r <= 16'd0;  aux_f_col_r <= 10'd0;  aux_f_mul_r <= 24'd0;
            aux_lg2_r <= 9'd0;  aux_lg2_dif_r <= 10'd0;
            aux_db_mul_r <= 20'd0;  aux_sq_r <= 32'd0;
            h_sq_sum <= 34'd0;  sqrt_rad <= 34'd0;  sqrt_rem <= 19'd0;  sqrt_q <= 17'd0;
            div_num <= 27'd0;  div_rem <= 17'd0;  div_q <= 14'd0;
            h2_str <= 40'h20_20_2D_2D_2D;  h3_str <= 40'h20_20_2D_2D_2D;
            h4_str <= 40'h20_20_2D_2D_2D;  h5_str <= 40'h20_20_2D_2D_2D;
            thd_str <= 32'h20_30_2E_30;
            sfdr_str <= 32'h20_2D_2D_2D;
            mkr_f_str <= 48'h20_20_20_30_2E_30;
            mkr_db_str <= 48'h2D_39_36_2E_30_20;
            dmkr_f_str <= 48'h2B_20_20_30_2E_30;
            dmkr_db_str <= 48'h2B_20_30_2E_30_20;
            h1_f_str <= 48'h20_20_2D_2D_2D_20;  h2_f_str <= 48'h20_20_2D_2D_2D_20;
            h3_f_str <= 48'h20_20_2D_2D_2D_20;  h4_f_str <= 48'h20_20_2D_2D_2D_20;
            h5_f_str <= 48'h20_20_2D_2D_2D_20;
        end else begin
            mkr_tog_s1       <= mkr_upd_tog;
            mkr_tog_s2       <= mkr_tog_s1;
            prev_mkr_col     <= eff_mkr_col;
            prev_mkr_ref_col <= I_mkr_ref_col;
            prev_mkr_delta   <= I_mkr_delta;

            if (pk_tog_s2 ^ pk_tog_s3) begin
                h2_lat     <= I_h2_mag;
                h3_lat     <= I_h3_mag;
                h4_lat     <= I_h4_mag;
                h5_lat     <= I_h5_mag;
                spur_mag_lat <= I_spur_mag;
                h2_col_lat <= I_h2_col;
                h3_col_lat <= I_h3_col;
                h4_col_lat <= I_h4_col;
                h5_col_lat <= I_h5_col;
                aux_req    <= 1'b1;
            end else if ((mkr_tog_s1 ^ mkr_tog_s2) || (eff_mkr_col != prev_mkr_col) ||
                         (I_mkr_delta != prev_mkr_delta) || (I_mkr_ref_col != prev_mkr_ref_col)) begin
                aux_req <= 1'b1;
            end

            if (aux_phase == 4'd0) begin
                if (aux_req && !fmt_busy) begin
                    aux_req   <= 1'b0;
                    aux_phase <= 4'd1;
                    aux_cnt   <= 6'd0;
                    h_sq_sum  <= 34'd0;
                end
            end else if (aux_phase == 4'd1) begin
                // Marker 频率与 dBFS (流水线分拍避免长组合路径)
                if (aux_cnt == 6'd0) begin
                    aux_mag_r   <= mkr_mag_lat;
                    aux_f_col_r <= eff_mkr_col;
                    aux_cnt     <= 6'd1;
                end else if (aux_cnt == 6'd1) begin
                    aux_lg2_r   <= log_split(aux_mag_r);
                    aux_f_mul_r <= aux_f_mul;
                    aux_cnt     <= 6'd2;
                end else if (aux_cnt == 6'd2) begin
                    aux_lg2_dif_r <= 10'd512 - {1'b0, aux_lg2_r};
                    aux_cnt       <= 6'd3;
                end else if (aux_cnt == 6'd3) begin
                    aux_db_mul_r <= aux_lg2_dif_r * 12'd1926;
                    aux_cnt      <= 6'd4;
                end else if (aux_cnt == 6'd4) begin
                    mkr_f_val_r  <= aux_f_mul_r[23:10];
                    mkr_db_val_r <= (aux_mag_r == 16'd0) ? 10'd960 : aux_db_mul_r[19:10];
                    a_bin   <= aux_f_mul_r[23:10];
                    b_bin   <= (aux_mag_r == 16'd0) ? 14'd960 : {4'd0, aux_db_mul_r[19:10]};
                    a_bcd   <= 16'd0;  b_bcd <= 16'd0;
                    aux_cnt <= 6'd5;
                end else if (aux_cnt <= 6'd18) begin
                    a_bcd <= {a_bcd_adj[14:0], a_bin[13]};  a_bin <= {a_bin[12:0], 1'b0};
                    b_bcd <= {b_bcd_adj[14:0], b_bin[13]};  b_bin <= {b_bin[12:0], 1'b0};
                    aux_cnt <= aux_cnt + 6'd1;
                end else begin
                    if (span_twodec) begin
                        mkr_f_str <= {
                            8'h20,
                            (a_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, a_bcd[15:12]}) : 8'h20,
                            8'h30 + {4'd0, a_bcd[11:8]}, 8'h2E,
                            8'h30 + {4'd0, a_bcd[7:4]}, 8'h30 + {4'd0, a_bcd[3:0]}
                        };
                    end else begin
                        mkr_f_str <= {
                            8'h20,
                            (a_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, a_bcd[15:12]}) : 8'h20,
                            ((a_bcd[15:12] != 4'd0) || (a_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, a_bcd[11:8]}) : 8'h20,
                            8'h30 + {4'd0, a_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, a_bcd[3:0]}
                        };
                    end
                    mkr_db_str <= {
                        8'h2D,
                        (b_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, b_bcd[11:8]}) : 8'h20,
                        8'h30 + {4'd0, b_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, b_bcd[3:0]}, 8'h20
                    };
                    aux_phase <= 3'd2;
                    aux_cnt   <= 6'd0;
                end
            end else if (aux_phase >= 3'd2 && aux_phase <= 3'd5) begin
                // H2..H5 dBc 与平方累加 (流水线分拍避免长组合路径)
                if (aux_cnt == 6'd0) begin
                    aux_mag_r <= h_cur_mag;
                    aux_cnt   <= 6'd1;
                end else if (aux_cnt == 6'd1) begin
                    aux_lg2_r <= log_split(aux_mag_r);
                    aux_sq_r  <= aux_mag_r * aux_mag_r;
                    aux_cnt   <= 6'd2;
                end else if (aux_cnt == 6'd2) begin
                    aux_lg2_dif_r <= (pk_lg2_r > aux_lg2_r) ? {1'b0, (pk_lg2_r - aux_lg2_r)} : 10'd0;
                    h_sq_sum      <= h_sq_sum + {2'b00, aux_sq_r};
                    aux_cnt       <= 6'd3;
                end else if (aux_cnt == 6'd3) begin
                    aux_db_mul_r <= aux_lg2_dif_r * 12'd1926;
                    aux_cnt      <= 6'd4;
                end else if (aux_cnt == 6'd4) begin
                    a_bin   <= (aux_db_mul_r[19:10] > 10'd999) ? 14'd999 : {4'd0, aux_db_mul_r[19:10]};
                    a_bcd   <= 16'd0;
                    aux_cnt <= 6'd5;
                end else if (aux_cnt <= 6'd18) begin
                    a_bcd   <= {a_bcd_adj[14:0], a_bin[13]};
                    a_bin   <= {a_bin[12:0], 1'b0};
                    aux_cnt <= aux_cnt + 6'd1;
                end else begin
                    case (aux_phase)
                        3'd2: h2_str <= h_fmt_str;
                        3'd3: h3_str <= h_fmt_str;
                        3'd4: h4_str <= h_fmt_str;
                        3'd5: h5_str <= h_fmt_str;
                        default: ;
                    endcase
                    if (aux_phase == 3'd5) begin
                        aux_phase <= 3'd6;
                        aux_cnt   <= 5'd0;
                    end else begin
                        aux_phase <= aux_phase + 3'd1;
                        aux_cnt   <= 5'd0;
                    end
                end
            end else if (aux_phase == 3'd6) begin
                // 34bit 整数开方 (17 拍)
                if (aux_cnt == 5'd0) begin
                    sqrt_rad <= h_sq_sum;
                    sqrt_rem <= 19'd0;
                    sqrt_q   <= 17'd0;
                    aux_cnt  <= 5'd1;
                end else if (aux_cnt <= 5'd17) begin
                    sqrt_rad <= {sqrt_rad[31:0], 2'b00};
                    sqrt_rem <= sqrt_ge ? (sqrt_rem_nxt - sqrt_cand) : sqrt_rem_nxt;
                    sqrt_q   <= {sqrt_q[15:0], sqrt_ge};
                    aux_cnt  <= aux_cnt + 5'd1;
                end else begin
                    aux_phase <= 3'd7;
                    aux_cnt   <= 5'd0;
                end
            end else if (aux_phase == 3'd7) begin
                // 除法 (sqrt_q * 1000 / pk_mag_lat) + BCD 格式化 THD%
                if (aux_cnt == 6'd0) begin
                    div_num <= sqrt_q * 10'd1000;
                    div_rem <= 17'd0;
                    div_q   <= 14'd0;
                    aux_cnt <= 6'd1;
                end else if (aux_cnt <= 6'd27) begin
                    div_num <= {div_num[25:0], 1'b0};
                    div_rem <= div_ge ? (div_rem_nxt - {1'b0, pk_mag_lat}) : div_rem_nxt;
                    div_q   <= {div_q[12:0], div_ge};
                    aux_cnt <= aux_cnt + 6'd1;
                end else if (aux_cnt == 6'd28) begin
                    a_bin   <= (pk_mag_lat == 16'd0) ? 14'd0 : ((div_q > 14'd999) ? 14'd999 : div_q);
                    a_bcd   <= 16'd0;
                    aux_cnt <= 6'd29;
                end else if (aux_cnt <= 6'd42) begin
                    a_bcd   <= {a_bcd_adj[14:0], a_bin[13]};
                    a_bin   <= {a_bin[12:0], 1'b0};
                    aux_cnt <= aux_cnt + 6'd1;
                end else begin
                    thd_str <= {
                        (a_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, a_bcd[11:8]}) : 8'h20,
                        8'h30 + {4'd0, a_bcd[7:4]},
                        8'h2E,
                        8'h30 + {4'd0, a_bcd[3:0]}
                    };
                    aux_phase <= 4'd8;
                    aux_cnt   <= 6'd0;
                end
            end else if (aux_phase >= 4'd8 && aux_phase <= 4'd12) begin
                // H1..H5 谐波频率 BCD 格式化
                if (aux_cnt == 6'd0) begin
                    aux_f_col_r <= harm_f_col;
                    aux_cnt     <= 6'd1;
                end else if (aux_cnt == 6'd1) begin
                    aux_f_mul_r <= aux_f_mul;
                    aux_cnt     <= 6'd2;
                end else if (aux_cnt == 6'd2) begin
                    a_bin   <= aux_f_mul_r[23:10];
                    a_bcd   <= 16'd0;
                    aux_cnt <= 6'd3;
                end else if (aux_cnt <= 6'd16) begin
                    a_bcd   <= {a_bcd_adj[14:0], a_bin[13]};
                    a_bin   <= {a_bin[12:0], 1'b0};
                    aux_cnt <= aux_cnt + 6'd1;
                end else begin
                    case (aux_phase)
                        4'd8:  h1_f_str <= h_f_fmt_str;
                        4'd9:  h2_f_str <= h_f_fmt_str;
                        4'd10: h3_f_str <= h_f_fmt_str;
                        4'd11: h4_f_str <= h_f_fmt_str;
                        4'd12: h5_f_str <= h_f_fmt_str;
                        default: ;
                    endcase
                    if (aux_phase == 4'd12) begin
                        aux_phase <= I_mkr_delta ? 4'd13 : 4'd14;
                        aux_cnt   <= 6'd0;
                    end else begin
                        aux_phase <= aux_phase + 4'd1;
                        aux_cnt   <= 6'd0;
                    end
                end
            end else if (aux_phase == 4'd13) begin
                // Delta Marker 差值频率 (df) 与差值幅度 (ddB)
                if (aux_cnt == 6'd0) begin
                    aux_mag_r   <= mkr_ref_mag_lat;
                    aux_f_col_r <= I_mkr_ref_col;
                    aux_cnt     <= 6'd1;
                end else if (aux_cnt == 6'd1) begin
                    aux_lg2_r   <= log_split(aux_mag_r);
                    aux_f_mul_r <= aux_f_mul;
                    aux_cnt     <= 6'd2;
                end else if (aux_cnt == 6'd2) begin
                    aux_lg2_dif_r <= 10'd512 - {1'b0, aux_lg2_r};
                    aux_cnt       <= 6'd3;
                end else if (aux_cnt == 6'd3) begin
                    aux_db_mul_r <= aux_lg2_dif_r * 12'd1926;
                    aux_cnt      <= 6'd4;
                end else if (aux_cnt == 6'd4) begin
                    df_neg  <= (mkr_f_val_r < aux_f_mul_r[23:10]);
                    a_bin   <= (mkr_f_val_r >= aux_f_mul_r[23:10])
                               ? (mkr_f_val_r - aux_f_mul_r[23:10])
                               : (aux_f_mul_r[23:10] - mkr_f_val_r);
                    if (aux_mag_r == 16'd0) begin
                        ddb_neg <= (10'd960 < mkr_db_val_r);
                        b_bin   <= (10'd960 >= mkr_db_val_r)
                                   ? {4'd0, (10'd960 - mkr_db_val_r)}
                                   : {4'd0, (mkr_db_val_r - 10'd960)};
                    end else begin
                        ddb_neg <= (aux_db_mul_r[19:10] < mkr_db_val_r);
                        b_bin   <= (aux_db_mul_r[19:10] >= mkr_db_val_r)
                                   ? {4'd0, (aux_db_mul_r[19:10] - mkr_db_val_r)}
                                   : {4'd0, (mkr_db_val_r - aux_db_mul_r[19:10])};
                    end
                    a_bcd   <= 16'd0;  b_bcd <= 16'd0;
                    aux_cnt <= 6'd5;
                end else if (aux_cnt <= 6'd18) begin
                    a_bcd <= {a_bcd_adj[14:0], a_bin[13]};  a_bin <= {a_bin[12:0], 1'b0};
                    b_bcd <= {b_bcd_adj[14:0], b_bin[13]};  b_bin <= {b_bin[12:0], 1'b0};
                    aux_cnt <= aux_cnt + 6'd1;
                end else begin
                    if (span_twodec) begin
                        dmkr_f_str <= {
                            df_neg ? 8'h2D : 8'h2B,
                            (a_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, a_bcd[15:12]}) : 8'h20,
                            8'h30 + {4'd0, a_bcd[11:8]}, 8'h2E,
                            8'h30 + {4'd0, a_bcd[7:4]}, 8'h30 + {4'd0, a_bcd[3:0]}
                        };
                    end else begin
                        dmkr_f_str <= {
                            df_neg ? 8'h2D : 8'h2B,
                            (a_bcd[15:12] != 4'd0) ? (8'h30 + {4'd0, a_bcd[15:12]}) : 8'h20,
                            ((a_bcd[15:12] != 4'd0) || (a_bcd[11:8] != 4'd0)) ? (8'h30 + {4'd0, a_bcd[11:8]}) : 8'h20,
                            8'h30 + {4'd0, a_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, a_bcd[3:0]}
                        };
                    end
                    dmkr_db_str <= {
                        ddb_neg ? 8'h2D : 8'h2B,
                        (b_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, b_bcd[11:8]}) : 8'h20,
                        8'h30 + {4'd0, b_bcd[7:4]}, 8'h2E, 8'h30 + {4'd0, b_bcd[3:0]}, 8'h20
                    };
                    aux_phase <= 4'd14;
                    aux_cnt   <= 6'd0;
                end
            end else if (aux_phase == 4'd14) begin
                // SFDR (无杂散动态范围: pk_dB - max_spur_dB)
                if (aux_cnt == 6'd0) begin
                    aux_mag_r <= spur_mag_lat;
                    aux_cnt   <= 6'd1;
                end else if (aux_cnt == 6'd1) begin
                    aux_lg2_r <= log_split(aux_mag_r);
                    aux_cnt   <= 6'd2;
                end else if (aux_cnt == 6'd2) begin
                    aux_lg2_dif_r <= (pk_lg2_r > aux_lg2_r) ? {1'b0, (pk_lg2_r - aux_lg2_r)} : 10'd0;
                    aux_cnt       <= 6'd3;
                end else if (aux_cnt == 6'd3) begin
                    aux_db_mul_r <= aux_lg2_dif_r * 12'd1926;
                    aux_cnt      <= 6'd4;
                end else if (aux_cnt == 6'd4) begin
                    a_bin   <= (aux_db_mul_r[19:10] > 10'd999) ? 14'd999 : {4'd0, aux_db_mul_r[19:10]};
                    a_bcd   <= 16'd0;
                    aux_cnt <= 6'd5;
                end else if (aux_cnt <= 6'd18) begin
                    a_bcd   <= {a_bcd_adj[14:0], a_bin[13]};
                    a_bin   <= {a_bin[12:0], 1'b0};
                    aux_cnt <= aux_cnt + 6'd1;
                end else begin
                    sfdr_str <= (spur_mag_lat == 16'd0 || pk_mag_lat == 16'd0) ? 32'h20_2D_2D_2D : {
                        (a_bcd[11:8] != 4'd0) ? (8'h30 + {4'd0, a_bcd[11:8]}) : 8'h20,
                        8'h30 + {4'd0, a_bcd[7:4]},
                        8'h2E,
                        8'h30 + {4'd0, a_bcd[3:0]}
                    };
                    aux_phase <= 4'd0;
                end
            end
        end
    end

    //==================================================================
    // 第 1 级: 字符网格 ROM (80 x 45 单元, 0-BSRAM 组合查表+寄存)
    //==================================================================
    wire [5:0] cell_row = I_y[9:4];                 // 0..44
    wire [6:0] cell_col = I_x[10:4];                // 0..79

    wire [6:0] ui_char;

    wire mkr_en = (eff_mkr_col != 10'd0);

    reg [9:0] lim_lv_r;
    reg       lim_fail;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n)
            lim_fail <= 1'b0;
        else
            lim_fail <= (I_lim_lvl != 4'd0) && (pk_mag_lat != 16'd0) &&
                        ((10'd512 - {1'b0, pk_lg2_r}) < lim_lv_r);
    end

    ui_text_rom u_text_rom (
        .I_clk       (I_pix_clk ),
        .I_col       (cell_col  ),
        .I_row       (cell_row  ),
        .I_span      (I_span    ),
        .I_win       (I_win     ),
        .I_det       (I_det     ),
        .I_trc       (I_trc     ),
        .I_trc_sub   (I_trc_sub ),
        .I_ref_mode  (I_ref_mode),
        .I_avg       (I_avg     ),
        .I_view      (I_view    ),
        .I_mkr_en     (mkr_en     ),
        .I_mkr_fine   (I_mkr_fine ),
        .I_mkr_delta  (I_mkr_delta),
        .I_mkr_track  (I_mkr_track),
        .I_harm_mode  (I_harm_mode),
        .I_yscale     (I_yscale   ),
        .I_yref       (I_yref     ),
        .I_yscale_ref (I_yscale_ref),
        .I_lim_lvl    (I_lim_lvl  ),
        .I_lim_sub    (I_lim_sub  ),
        .I_lim_fail   (lim_fail   ),
        .I_trig_mode  (I_trig_mode),
        .I_trig_lvl   (I_trig_lvl ),
        .I_trig_sub   (I_trig_sub ),
        .I_vscale     (I_vscale   ),
        .I_tscale     (I_tscale   ),
        .I_vt_sel     (I_vt_sel   ),
        .I_pk_f_str   (pk_f_str   ),
        .I_pk_f_unit  (pk_f_unit  ),
        .I_pk_db_str  (pk_db_str  ),
        .I_vpp_str    (vpp_str    ),
        .I_wf_str     (wf_str     ),
        .I_wf_unit    (wf_unit    ),
        .I_duty_str   (duty_str   ),
        .I_h2_str     (h2_str     ),
        .I_h3_str     (h3_str     ),
        .I_h4_str     (h4_str     ),
        .I_h5_str     (h5_str     ),
        .I_thd_str    (thd_str    ),
        .I_sfdr_str   (sfdr_str   ),
        .I_mkr_f_str  (mkr_f_str  ),
        .I_mkr_db_str (mkr_db_str ),
        .I_dmkr_f_str (dmkr_f_str ),
        .I_dmkr_db_str(dmkr_db_str),
        .I_h1_f_str  (h1_f_str  ),
        .I_h2_f_str  (h2_f_str  ),
        .I_h3_f_str  (h3_f_str  ),
        .I_h4_f_str  (h4_f_str  ),
        .I_h5_f_str  (h5_f_str  ),
        .I_t1_str    (t1_str    ),
        .I_dt_str    (dt_str    ),
        .I_idt_str   (idt_str   ),
        .I_t_unit    (t_unit    ),
        .I_tx1_str   (tx1_str   ),
        .I_tx2_str   (tx2_str   ),
        .I_tx3_str   (tx3_str   ),
        .I_tx4_str   (tx4_str   ),
        .O_char      (ui_char   )
    );

    reg [1:0]  txt_color_d1;
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n)
            txt_color_d1 <= 2'd0;
        else if (cell_row == 6'd1 && cell_col < 7'd26)
            txt_color_d1 <= 2'd1; // 标题高亮
        else if (cell_row == 6'd3 || cell_row == 6'd43)
            txt_color_d1 <= 2'd3; // Peak / Marker 读数醒目色
        else if (cell_row == 6'd5 || cell_row == 6'd44)
            txt_color_d1 <= 2'd1; // 谐波与 THD / 谐波频率行
        else if (cell_row == 6'd42 && cell_col >= 7'd59 && cell_col <= 7'd66)
            txt_color_d1 <= lim_fail ? 2'd3 : 2'd1; // Limit FAIL/PASS
        else if (cell_col >= 7'd70 && (cell_row == 6'd6 || cell_row == 6'd10 ||
                 cell_row == 6'd14 || cell_row == 6'd18 || cell_row == 6'd22 ||
                 cell_row == 6'd26 || cell_row == 6'd30 || cell_row == 6'd34 ||
                 cell_row == 6'd38 || cell_row == 6'd42))
            txt_color_d1 <= 2'd2; // 按钮标签次要色
        else
            txt_color_d1 <= 2'd0;
    end

    wire [10:0] map_d = {1'b0, txt_color_d1, 1'b0, ui_char};

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
            t_vld1 <= (ui_char != 7'h20);
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
    reg [8:0]  lg2m, lg2p, lg2ref;
    reg [9:0]  hw_row2;
    reg signed [25:0] w_prod2;
    reg [11:0] w_gain_eff;
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            w_gain_eff <= 12'd28;
        end else begin
            case (I_vscale)
                4'd1:    w_gain_eff <= 12'd8;
                4'd2:    w_gain_eff <= 12'd16;
                4'd3:    w_gain_eff <= 12'd32;
                4'd4:    w_gain_eff <= 12'd48;
                4'd5:    w_gain_eff <= 12'd64;
                4'd6:    w_gain_eff <= 12'd96;
                4'd7:    w_gain_eff <= 12'd128;
                4'd8:    w_gain_eff <= 12'd192;
                4'd9:    w_gain_eff <= 12'd256;
                4'd10:   w_gain_eff <= 12'd384;
                4'd11:   w_gain_eff <= 12'd512;
                4'd12:   w_gain_eff <= 12'd1024;
                4'd13:   w_gain_eff <= 12'd2048;
                default: w_gain_eff <= wave_gain_q8;
            endcase
        end
    end

    wire signed [12:0] w_diff1  = $signed({I_wave_data[11], I_wave_data}) - $signed({mid_lat[11], mid_lat});
    wire signed [17:0] w_scaled = $signed(w_prod2[25:8]);
    wire signed [17:0] w_full_s  = 18'sd256 - w_scaled;
    wire signed [17:0] w_split_s = 18'sd384 - (w_scaled >>> 1);
    wire [9:0] w_full_c  = (w_full_s < 18'sd0) ? 10'd0 : (w_full_s > 18'sd511) ? 10'd511 : w_full_s[9:0];
    wire [9:0] w_split_c = (w_split_s < 18'sd257) ? 10'd257 : (w_split_s > 18'sd511) ? 10'd511 : w_split_s[9:0];

    // 触发电平参考线坐标计算 (寄存器流水, 零时序压力)
    wire [11:0] vpp8_disp = {3'b000, vpp_lat[11:3]};
    reg signed [12:0] tlvl_diff_r;
    reg signed [25:0] tlvl_prod_r;
    reg [9:0]         tlvl_row_r;
    reg               tlvl_en_r;
    wire signed [17:0] tlvl_scaled = $signed(tlvl_prod_r[25:8]);
    wire signed [17:0] tlvl_y_calc = (I_view == 2'd1) ? (18'sd384 - (tlvl_scaled >>> 1))
                                                      : (18'sd256 - tlvl_scaled);
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            tlvl_diff_r <= 13'sd0;
            tlvl_prod_r <= 26'sd0;
            tlvl_row_r  <= 10'd256;
            tlvl_en_r   <= 1'b0;
        end else begin
            case (I_trig_lvl)
                4'd0:    tlvl_diff_r <= -$signed({vpp8_disp[10:0], 2'b00});
                4'd1:    tlvl_diff_r <= -$signed({vpp8_disp[10:0], 1'b0}) - $signed({1'b0, vpp8_disp});
                4'd2:    tlvl_diff_r <= -$signed({vpp8_disp[10:0], 1'b0});
                4'd3:    tlvl_diff_r <= -$signed({1'b0, vpp8_disp});
                4'd5:    tlvl_diff_r <=  $signed({1'b0, vpp8_disp});
                4'd6:    tlvl_diff_r <=  $signed({vpp8_disp[10:0], 1'b0});
                4'd7:    tlvl_diff_r <=  $signed({vpp8_disp[10:0], 1'b0}) + $signed({1'b0, vpp8_disp});
                4'd8:    tlvl_diff_r <=  $signed({vpp8_disp[10:0], 2'b00});
                default: tlvl_diff_r <=  13'sd0;
            endcase
            tlvl_prod_r <= tlvl_diff_r * $signed({1'b0, w_gain_eff});
            tlvl_en_r   <= (I_view == 2'd1) ? (tlvl_y_calc >= 18'sd257 && tlvl_y_calc <= 18'sd511)
                                            : (tlvl_y_calc >= 18'sd0   && tlvl_y_calc <= 18'sd511);
            tlvl_row_r  <= tlvl_y_calc[9:0];
        end
    end

    wire signed [10:0] hw_full_s  = 11'sd256 - $signed({{2{I_harm_wave[11]}}, I_harm_wave[11:3]});
    wire signed [10:0] hw_split_s = 11'sd384 - $signed({{3{I_harm_wave[11]}}, I_harm_wave[11:4]});
    wire [9:0] hw_full_c  = (hw_full_s < 11'sd0) ? 10'd0 : (hw_full_s > 11'sd511) ? 10'd511 : hw_full_s[9:0];
    wire [9:0] hw_split_c = (hw_split_s < 11'sd257) ? 10'd257 : (hw_split_s > 11'sd511) ? 10'd511 : hw_split_s[9:0];

    // ALL5 模式: 5 个谐波分道显示 (TIME: +-47px, 56/156/256/356/456; SPLIT: +-23px, 282/333/384/435/486)
    wire signed [6:0] ha1_s = $signed(I_harm_all[6:0]);
    wire signed [6:0] ha2_s = $signed(I_harm_all[13:7]);
    wire signed [6:0] ha3_s = $signed(I_harm_all[20:14]);
    wire signed [6:0] ha4_s = $signed(I_harm_all[27:21]);
    wire signed [6:0] ha5_s = $signed(I_harm_all[34:28]);

    wire signed [9:0] ha1_off = (I_view == 2'd1) ? ($signed({{4{ha1_s[6]}}, ha1_s[6:1]}) - $signed({{6{ha1_s[6]}}, ha1_s[6:3]}))
                                                 : ($signed({{3{ha1_s[6]}}, ha1_s})      - $signed({{5{ha1_s[6]}}, ha1_s[6:2]}));
    wire signed [9:0] ha2_off = (I_view == 2'd1) ? ($signed({{4{ha2_s[6]}}, ha2_s[6:1]}) - $signed({{6{ha2_s[6]}}, ha2_s[6:3]}))
                                                 : ($signed({{3{ha2_s[6]}}, ha2_s})      - $signed({{5{ha2_s[6]}}, ha2_s[6:2]}));
    wire signed [9:0] ha3_off = (I_view == 2'd1) ? ($signed({{4{ha3_s[6]}}, ha3_s[6:1]}) - $signed({{6{ha3_s[6]}}, ha3_s[6:3]}))
                                                 : ($signed({{3{ha3_s[6]}}, ha3_s})      - $signed({{5{ha3_s[6]}}, ha3_s[6:2]}));
    wire signed [9:0] ha4_off = (I_view == 2'd1) ? ($signed({{4{ha4_s[6]}}, ha4_s[6:1]}) - $signed({{6{ha4_s[6]}}, ha4_s[6:3]}))
                                                 : ($signed({{3{ha4_s[6]}}, ha4_s})      - $signed({{5{ha4_s[6]}}, ha4_s[6:2]}));
    wire signed [9:0] ha5_off = (I_view == 2'd1) ? ($signed({{4{ha5_s[6]}}, ha5_s[6:1]}) - $signed({{6{ha5_s[6]}}, ha5_s[6:3]}))
                                                 : ($signed({{3{ha5_s[6]}}, ha5_s})      - $signed({{5{ha5_s[6]}}, ha5_s[6:2]}));

    wire [9:0] ha1_c = ((I_view == 2'd1) ? 10'd282 : 10'd56)  - ha1_off;
    wire [9:0] ha2_c = ((I_view == 2'd1) ? 10'd333 : 10'd156) - ha2_off;
    wire [9:0] ha3_c = ((I_view == 2'd1) ? 10'd384 : 10'd256) - ha3_off;
    wire [9:0] ha4_c = ((I_view == 2'd1) ? 10'd435 : 10'd356) - ha4_off;
    wire [9:0] ha5_c = ((I_view == 2'd1) ? 10'd486 : 10'd456) - ha5_off;

    reg [9:0] ha1_r2, ha2_r2, ha3_r2, ha4_r2, ha5_r2;
    reg [9:0] ha1_r3, ha2_r3, ha3_r3, ha4_r3, ha5_r3;
    reg [9:0] ha1_lo4, ha2_lo4, ha3_lo4, ha4_lo4, ha5_lo4;
    reg [9:0] ha1_hi4, ha2_hi4, ha3_hi4, ha4_hi4, ha5_hi4;
    reg [9:0] xr4, yr4;
    reg       in_plot4, in_panel4, in_top4, in_bot4, gt_px0_4;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x2 <= 12'd0;  y2 <= 12'd0;  bin2 <= 10'd0;  px2 <= 5'd0;
            color2 <= 2'd0;  scale2 <= 1'b0;  t_vld2 <= 1'b0;
            mag2 <= 16'd0;  peak2 <= 16'd0;  lg2m <= 9'd0;  lg2p <= 9'd0;  lg2ref <= 9'd0;
            w_prod2 <= 26'sd0;  hw_row2 <= 10'd256;
            ha1_r2 <= 10'd56; ha2_r2 <= 10'd156; ha3_r2 <= 10'd256; ha4_r2 <= 10'd356; ha5_r2 <= 10'd456;
        end else begin
            x2 <= x1;  y2 <= y1;  bin2 <= bin1;  px2 <= px1;
            color2 <= map_d[9:8];
            scale2 <= map_d[10];
            t_vld2 <= t_vld1;
            mag2  <= mag_ram;
            peak2 <= peak_ram;
            lg2m   <= log_split(mag_ram);
            lg2p   <= log_split(peak_ram);
            lg2ref <= log_split(ref_ram);
            w_prod2 <= w_diff1 * $signed({1'b0, w_gain_eff});
            hw_row2 <= (I_view == 2'd1) ? hw_split_c : hw_full_c;
            ha1_r2 <= ha1_c; ha2_r2 <= ha2_c; ha3_r2 <= ha3_c; ha4_r2 <= ha4_c; ha5_r2 <= ha5_c;
        end
    end

    //==================================================================
    // 第 3 级: 对数换算后半 + 字模输出寄存
    //==================================================================
    reg [9:0] ref_lv_r;
    reg [1:0] yscale_r;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            ref_lv_r <= 10'd0;
            lim_lv_r <= 10'd0;
            yscale_r <= 2'd0;
        end else begin
            case (I_yref)
                3'd1: ref_lv_r <= 10'd53;
                3'd2: ref_lv_r <= 10'd106;
                3'd3: ref_lv_r <= 10'd159;
                3'd4: ref_lv_r <= 10'd213;
                default: ref_lv_r <= 10'd0;
            endcase
            case (I_lim_lvl)
                4'd1: lim_lv_r <= 10'd53;
                4'd2: lim_lv_r <= 10'd106;
                4'd3: lim_lv_r <= 10'd159;
                4'd4: lim_lv_r <= 10'd213;
                4'd5: lim_lv_r <= 10'd266;
                4'd6: lim_lv_r <= 10'd319;
                4'd7: lim_lv_r <= 10'd372;
                4'd8: lim_lv_r <= 10'd426;
                default: lim_lv_r <= 10'd0;
            endcase
            yscale_r <= I_yscale;
        end
    end

    wire [9:0] lim_x_rel = (lim_lv_r > ref_lv_r) ? (lim_lv_r - ref_lv_r) : 10'd0;

    reg [11:0] x3, y3;
    reg [9:0]  r3, rp3, r_ref3, lim_r3, w_row3, hw_row3;
    reg [7:0]  fb3;
    reg [4:0]  px3;
    reg [1:0]  color3;
    reg        scale3, t_vld3, pk_vld3;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x3 <= 12'd0;  y3 <= 12'd0;
            r3 <= 10'd511;  rp3 <= 10'd511;  r_ref3 <= 10'd511;  w_row3 <= 10'd256;  hw_row3 <= 10'd256;
            fb3 <= 8'd0;  px3 <= 5'd0;  color3 <= 2'd0;
            scale3 <= 1'b0;  t_vld3 <= 1'b0;  pk_vld3 <= 1'b0;
        end else begin
            x3 <= x2;  y3 <= y2;
            r3     <= log_row_base(lg2m[8:5], lg2m[4:0], ref_lv_r);
            rp3    <= log_row_base(lg2p[8:5], lg2p[4:0], ref_lv_r);
            r_ref3 <= log_row_base(lg2ref[8:5], lg2ref[4:0], ref_lv_r);
            lim_r3 <= lim_x_rel + (lim_x_rel >> 3) + (lim_x_rel >> 4) + (lim_x_rel >> 6);
            w_row3  <= (I_view == 2'd1) ? w_split_c : w_full_c;
            hw_row3 <= hw_row2;
            ha1_r3 <= ha1_r2; ha2_r3 <= ha2_r2; ha3_r3 <= ha3_r2; ha4_r3 <= ha4_r2; ha5_r3 <= ha5_r2;
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
    reg [9:0]  bar4, pk4, prev4, ref4, ref_prev4, lim_y4, w_row4, w_prev4, hw_row4, hw_prev4;
    reg [9:0]  ha1_r4, ha2_r4, ha3_r4, ha4_r4, ha5_r4;
    reg        tbit4, tvld4, pkvld4;
    reg [1:0]  color4;

    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) begin
            x4 <= 12'd0;  y4 <= 12'd0;
            xr4 <= 10'd0; yr4 <= 10'd0;
            in_plot4 <= 1'b0; in_panel4 <= 1'b0; in_top4 <= 1'b0; in_bot4 <= 1'b0; gt_px0_4 <= 1'b0;
            bar4 <= 10'd511;  pk4 <= 10'd511;  prev4 <= 10'd511;  ref4 <= 10'd511;  ref_prev4 <= 10'd511;  lim_y4 <= 10'd511;
            w_row4 <= 10'd256;  w_prev4 <= 10'd256;
            hw_row4 <= 10'd256; hw_prev4 <= 10'd256;
            ha1_r4 <= 10'd256; ha2_r4 <= 10'd256; ha3_r4 <= 10'd256; ha4_r4 <= 10'd256; ha5_r4 <= 10'd256;
            ha1_lo4 <= 10'd256; ha2_lo4 <= 10'd256; ha3_lo4 <= 10'd256; ha4_lo4 <= 10'd256; ha5_lo4 <= 10'd256;
            ha1_hi4 <= 10'd257; ha2_hi4 <= 10'd257; ha3_hi4 <= 10'd257; ha4_hi4 <= 10'd257; ha5_hi4 <= 10'd257;
            tbit4 <= 1'b0;  tvld4 <= 1'b0;  pkvld4 <= 1'b0;  color4 <= 2'd0;
        end else begin
            x4 <= x3;  y4 <= y3;
            xr4 <= x3[9:0] - 10'd64;
            yr4 <= y3[9:0] - 10'd104;
            in_plot4  <= (x3 >= PX0) && (x3 <= PX1) && (y3 >= PY0) && (y3 <= PY1);
            in_panel4 <= (x3 >= PANEL_X);
            in_top4   <= (y3 < TOP_H);
            in_bot4   <= (y3 >= BOT_Y);
            gt_px0_4  <= (x3 > PX0);
            bar4      <= scale_row(r3, yscale_r);
            pk4       <= scale_row(rp3, yscale_r);
            prev4     <= bar4;
            ref4      <= scale_row(r_ref3, yscale_r);
            ref_prev4 <= ref4;
            lim_y4    <= scale_row(lim_r3, yscale_r);
            w_row4  <= w_row3;
            w_prev4 <= w_row4;
            hw_row4 <= hw_row3;
            hw_prev4<= hw_row4;
            ha1_r4  <= ha1_r3;
            ha1_lo4 <= ((x3 > PX0) && (ha1_r4 < ha1_r3)) ? ha1_r4 : ha1_r3;
            ha1_hi4 <= (((x3 > PX0) && (ha1_r4 > ha1_r3)) ? ha1_r4 : ha1_r3) + 10'd1;
            ha2_r4  <= ha2_r3;
            ha2_lo4 <= ((x3 > PX0) && (ha2_r4 < ha2_r3)) ? ha2_r4 : ha2_r3;
            ha2_hi4 <= (((x3 > PX0) && (ha2_r4 > ha2_r3)) ? ha2_r4 : ha2_r3) + 10'd1;
            ha3_r4  <= ha3_r3;
            ha3_lo4 <= ((x3 > PX0) && (ha3_r4 < ha3_r3)) ? ha3_r4 : ha3_r3;
            ha3_hi4 <= (((x3 > PX0) && (ha3_r4 > ha3_r3)) ? ha3_r4 : ha3_r3) + 10'd1;
            ha4_r4  <= ha4_r3;
            ha4_lo4 <= ((x3 > PX0) && (ha4_r4 < ha4_r3)) ? ha4_r4 : ha4_r3;
            ha4_hi4 <= (((x3 > PX0) && (ha4_r4 > ha4_r3)) ? ha4_r4 : ha4_r3) + 10'd1;
            ha5_r4  <= ha5_r3;
            ha5_lo4 <= ((x3 > PX0) && (ha5_r4 < ha5_r3)) ? ha5_r4 : ha5_r3;
            ha5_hi4 <= (((x3 > PX0) && (ha5_r4 > ha5_r3)) ? ha5_r4 : ha5_r3) + 10'd1;
            tbit4 <= t_vld3 & t_bit;
            tvld4 <= t_vld3;
            color4 <= color3;
            pkvld4 <= pk_vld3;
        end
    end

    //==================================================================
    // 第 5 级: 判定像素属于哪个元素, 输出 4bit 选择码
    //==================================================================
    wire in_plot  = in_plot4;
    wire in_panel = in_panel4;
    wire in_top   = in_top4;
    wire in_bot   = in_bot4;

    wire [9:0] xr = xr4;       // 0..1023
    wire [9:0] yr = yr4;      // 0..511

    wire grid_bdr  = (xr == 10'd0) || (xr == 10'd1023) || (yr == 10'd0) || (yr == 10'd511);
    wire grid_ctr  = (xr == 10'd512) || (yr == 10'd256) ||
                     ((xr[3:0] == 4'd0) && ((yr >= 10'd254) && (yr <= 10'd258) || (yr <= 10'd2) || (yr >= 10'd509))) ||
                     ((yr[3:0] == 4'd0) && ((xr >= 10'd510) && (xr <= 10'd514) || (xr <= 10'd2) || (xr >= 10'd1021)));
    wire grid_maj  = grid_ctr ||
                     ((xr[6:0] == 7'd0) && yr[0]) ||
                     ((yr[5:0] == 6'd0) && xr[0]);       // 8x8 主格虚点线 + 中心十字刻度
    wire grid_min  = ((xr[5:0] == 6'd0) && (yr[2:0] == 3'd0)) ||
                     ((yr[4:0] == 5'd0) && (xr[2:0] == 3'd0)); // 16x16 次格疏点线

    reg [1:0] view_s5;
    always @(posedge I_pix_clk or negedge I_pix_rst_n) begin
        if (!I_pix_rst_n) view_s5 <= 2'd0;
        else              view_s5 <= I_view;
    end

    wire spec_en   = (view_s5 == 2'd0) || ((view_s5 == 2'd1) && (yr < 10'd255));
    wire wave_en   = (view_s5 == 2'd2) || ((view_s5 == 2'd1) && (yr >= 10'd257));
    wire split_div = (view_s5 == 2'd1) && ((yr == 10'd255) || (yr == 10'd256));
    wire on_trig_line = wave_en && tlvl_en_r && (yr == tlvl_row_r) && (xr[3:2] != 2'b00);

    wire [9:0] bar_s      = (view_s5 == 2'd1) ? {1'b0, bar4[9:1]}      : bar4;
    wire [9:0] prev_s     = (view_s5 == 2'd1) ? {1'b0, prev4[9:1]}     : prev4;
    wire [9:0] ref_s      = (view_s5 == 2'd1) ? {1'b0, ref4[9:1]}      : ref4;
    wire [9:0] ref_prev_s = (view_s5 == 2'd1) ? {1'b0, ref_prev4[9:1]} : ref_prev4;
    wire [9:0] pk_s       = (view_s5 == 2'd1) ? {1'b0, pk4[9:1]}       : pk4;

    wire [9:0] seg_lo = (bar_s < prev_s) ? bar_s : prev_s;
    wire [9:0] seg_hi = (bar_s < prev_s) ? prev_s : bar_s;
    wire [9:0] ref_lo = (ref_s < ref_prev_s) ? ref_s : ref_prev_s;
    wire [9:0] ref_hi = (ref_s < ref_prev_s) ? ref_prev_s : ref_s;

    wire trace_cap = spec_en && in_plot && (yr >= bar_s) && (yr <= (bar_s + 10'd1));
    wire trace_seg = spec_en && in_plot && gt_px0_4 && (yr >= seg_lo) && (yr <= (seg_hi + 10'd1));
    wire on_trace  = trace_cap || trace_seg;
    wire ref_en    = (I_ref_mode != 2'd0) && spec_en && in_plot;
    wire on_ref    = ref_en && (((yr >= ref_s) && (yr <= (ref_s + 10'd1))) ||
                                (gt_px0_4 && (yr >= ref_lo) && (yr <= (ref_hi + 10'd1))));
    wire on_peak   = spec_en && in_plot && pkvld4 && ((yr == pk_s) || (yr == (pk_s + 10'd1)));

    wire [9:0] w_seg_lo = (w_row4 < w_prev4) ? w_row4 : w_prev4;
    wire [9:0] w_seg_hi = (w_row4 < w_prev4) ? w_prev4 : w_row4;
    wire on_wave   = wave_en && in_plot && (
                         ((yr >= w_row4) && (yr <= (w_row4 + 10'd1))) ||
                         (gt_px0_4 && (yr >= w_seg_lo) && (yr <= (w_seg_hi + 10'd1)))
                     );

    wire [9:0] hw_seg_lo = (hw_row4 < hw_prev4) ? hw_row4 : hw_prev4;
    wire [9:0] hw_seg_hi = (hw_row4 < hw_prev4) ? hw_prev4 : hw_row4;
    wire on_harm_wave = (I_harm_mode != 3'd0) && (I_harm_mode != 3'd7) && wave_en && in_plot && (
                            ((yr >= hw_row4) && (yr <= (hw_row4 + 10'd1))) ||
                            (gt_px0_4 && (yr >= hw_seg_lo) && (yr <= (hw_seg_hi + 10'd1)))
                        );

    wire ha_en = (I_harm_mode == 3'd7) && wave_en && in_plot;
    wire on_ha1 = ha_en && (yr >= ha1_lo4) && (yr <= ha1_hi4);
    wire on_ha2 = ha_en && (yr >= ha2_lo4) && (yr <= ha2_hi4);
    wire on_ha3 = ha_en && (yr >= ha3_lo4) && (yr <= ha3_hi4);
    wire on_ha4 = ha_en && (yr >= ha4_lo4) && (yr <= ha4_hi4);
    wire on_ha5 = ha_en && (yr >= ha5_lo4) && (yr <= ha5_hi4);

    wire mkr_vis    = spec_en || (view_s5 == 2'd2);
    wire on_mkr     = mkr_en && mkr_vis && in_plot && (xr == eff_mkr_col) && yr[2];
    wire on_mkr_ref = mkr_en && I_mkr_delta && mkr_vis && in_plot && (xr == I_mkr_ref_col) && (yr[2] ^ yr[1]);
    wire [9:0] lim_yr = (view_s5 == 2'd1) ? {1'b0, lim_y4[9:1]} : lim_y4;
    wire on_lim_line = spec_en && in_plot && (I_lim_lvl != 4'd0) && (lim_lv_r >= ref_lv_r) && (yr == lim_yr) && xr[2];

    // 1~5 次谐波位置标记: 顶部倒三角 (yr=2..4) + 稀疏点线 (yr[3:2]==0)
    wire h1_vld = (pk_col_lat >= 10'd3);
    wire h2_vld = (h2_col_lat != 10'd0);
    wire h3_vld = (h3_col_lat != 10'd0);
    wire h4_vld = (h4_col_lat != 10'd0);
    wire h5_vld = (h5_col_lat != 10'd0);

    wire harm_col_exact = (h1_vld && (xr == pk_col_lat)) ||
                          (h2_vld && (xr == h2_col_lat)) ||
                          (h3_vld && (xr == h3_col_lat)) ||
                          (h4_vld && (xr == h4_col_lat)) ||
                          (h5_vld && (xr == h5_col_lat));
    wire harm_col_near1 = (h1_vld && (xr + 10'd1 >= pk_col_lat) && (xr <= pk_col_lat + 10'd1)) ||
                          (h2_vld && (xr + 10'd1 >= h2_col_lat) && (xr <= h2_col_lat + 10'd1)) ||
                          (h3_vld && (xr + 10'd1 >= h3_col_lat) && (xr <= h3_col_lat + 10'd1)) ||
                          (h4_vld && (xr + 10'd1 >= h4_col_lat) && (xr <= h4_col_lat + 10'd1)) ||
                          (h5_vld && (xr + 10'd1 >= h5_col_lat) && (xr <= h5_col_lat + 10'd1));
    wire harm_col_near2 = (h1_vld && (xr + 10'd2 >= pk_col_lat) && (xr <= pk_col_lat + 10'd2)) ||
                          (h2_vld && (xr + 10'd2 >= h2_col_lat) && (xr <= h2_col_lat + 10'd2)) ||
                          (h3_vld && (xr + 10'd2 >= h3_col_lat) && (xr <= h3_col_lat + 10'd2)) ||
                          (h4_vld && (xr + 10'd2 >= h4_col_lat) && (xr <= h4_col_lat + 10'd2)) ||
                          (h5_vld && (xr + 10'd2 >= h5_col_lat) && (xr <= h5_col_lat + 10'd2));

    wire on_harm_tri  = spec_en && in_plot && (
                            ((yr == 10'd2) && harm_col_near2) ||
                            ((yr == 10'd3) && harm_col_near1) ||
                            ((yr == 10'd4) && harm_col_exact)
                        );
    wire on_harm_line = spec_en && in_plot && harm_col_exact && (yr[3:2] == 2'b00);

    // 右侧按钮: 每 5 行一个按钮 (4 行按钮 + 1 行间隔), 6 个参数按钮 (12..40 行)
    wire [5:0] row4 = y4[9:4];
    wire in_btn = (y4 >= 12'd100) && (
                  ((row4 >= 6'd6)  && (row4 <= 6'd8))  ||
                  ((row4 >= 6'd10) && (row4 <= 6'd12)) ||
                  ((row4 >= 6'd14) && (row4 <= 6'd16)) ||
                  ((row4 >= 6'd18) && (row4 <= 6'd20)) ||
                  ((row4 >= 6'd22) && (row4 <= 6'd24)) ||
                  ((row4 >= 6'd26) && (row4 <= 6'd28)) ||
                  ((row4 >= 6'd30) && (row4 <= 6'd32)) ||
                  ((row4 >= 6'd34) && (row4 <= 6'd36)) ||
                  ((row4 >= 6'd38) && (row4 <= 6'd40)) ||
                  ((row4 >= 6'd42) && (row4 <= 6'd44)));
    wire btn_hi = I_menu_open && (y4 >= 12'd100) && (
        ((I_menu_sel == 4'd0) && (row4 >= 6'd6)  && (row4 <= 6'd8))  ||
        ((I_menu_sel == 4'd1) && (row4 >= 6'd10) && (row4 <= 6'd12)) ||
        ((I_menu_sel == 4'd2) && (row4 >= 6'd14) && (row4 <= 6'd16)) ||
        ((I_menu_sel == 4'd3) && (row4 >= 6'd18) && (row4 <= 6'd20)) ||
        ((I_menu_sel == 4'd4) && (row4 >= 6'd22) && (row4 <= 6'd24)) ||
        ((I_menu_sel == 4'd5) && (row4 >= 6'd26) && (row4 <= 6'd28)) ||
        ((I_menu_sel == 4'd6) && (row4 >= 6'd30) && (row4 <= 6'd32)) ||
        ((I_menu_sel == 4'd7) && (row4 >= 6'd34) && (row4 <= 6'd36)) ||
        ((I_menu_sel == 4'd8) && (row4 >= 6'd38) && (row4 <= 6'd40)) ||
        ((I_menu_sel == 4'd9) && (row4 >= 6'd42) && (row4 <= 6'd44))
    );

    wire is_sep = ((y4 >= 12'd96)  && (y4 <= 12'd99))  ||
                  ((y4 >= 12'd618) && (y4 <= 12'd621)) ||
                  ((x4 >= 12'd1098) && (x4 <= 12'd1101));

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
    localparam [4:0] S_WAVE  = 5'd14;
    localparam [4:0] S_MKR      = 5'd15;
    localparam [4:0] S_HARM     = 5'd16;
    localparam [4:0] S_GRID_MAJ = 5'd17;
    localparam [4:0] S_GRID_BDR = 5'd18;
    localparam [4:0] S_TRIG     = 5'd19;
    localparam [4:0] S_REF      = 5'd20;
    localparam [4:0] S_LIM      = 5'd21;

    reg [4:0] sel_c;

    always @(*) begin
        if (tbit4)
            sel_c = (color4 == 2'd1) ? S_TXT1 :
                    (color4 == 2'd2) ? S_TXT2 :
                    (color4 == 2'd3) ? S_TXT3 : S_TXT0;
        else if (in_plot)
            sel_c = split_div    ? S_SEP   :
                    on_mkr       ? S_MKR   :
                    on_mkr_ref   ? S_TXT2  :
                    on_harm_tri  ? S_HARM  :
                    on_ha1       ? S_HARM  :
                    on_ha2       ? S_WAVE  :
                    on_ha3       ? S_MKR   :
                    on_ha4       ? S_TRACE :
                    on_ha5       ? S_PEAK  :
                    on_harm_wave ? S_HARM  :
                    (on_wave && (I_harm_mode != 3'd7)) ? S_WAVE  :
                    on_trace     ? S_TRACE :
                    on_peak      ? S_PEAK  :
                    on_ref       ? S_REF   :
                    on_harm_line ? S_HARM     :
                    on_lim_line  ? S_LIM      :
                    on_trig_line ? S_TRIG     :
                    grid_bdr     ? S_GRID_BDR :
                    grid_maj     ? S_GRID_MAJ :
                    grid_min     ? S_GRID     : S_PLOT;
        else if (in_panel)
            sel_c = in_btn ? (btn_hi ? S_BTN_H : S_BTN) : S_PANEL;
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
    reg [23:0] rgb_c;

    always @(*) begin
        case (sel)
            S_TXT0  : rgb_c = C_TXT0;
            S_TXT1  : rgb_c = C_TXT1;
            S_TXT2  : rgb_c = C_TXT2;
            S_TXT3  : rgb_c = C_TXT3;
            S_TRACE : rgb_c = C_TRACE;
            S_WAVE  : rgb_c = 24'h38_E8_FF;
            S_MKR   : rgb_c = 24'hFF_50_FF;
            S_HARM  : rgb_c = 24'h30_FF_90;
            S_PEAK     : rgb_c = C_PEAK;
            S_GRID     : rgb_c = 24'h2C_3C_4E;
            S_GRID_MAJ : rgb_c = 24'h3E_52_68;
            S_GRID_BDR : rgb_c = 24'h50_68_80;
            S_TRIG     : rgb_c = 24'hFF_88_20;
            S_REF      : rgb_c = 24'h80_C0_FF;
            S_LIM      : rgb_c = 24'hFF_30_30;
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

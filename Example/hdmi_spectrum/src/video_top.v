// ============================================================================
// video_top.v  --  频谱分析仪 HDMI 显示顶层
//
//   基于高云 GW2AR-18 (Tang Nano 20K) 官方 HDMI 例程改造:
//     - 保留 27MHz -> 74.25MHz 像素时钟、DVI_TX IP、按键/LED
//     - 原来的测试图案 (彩条/网格/灰阶) 换成频谱分析仪界面
//     - 增加一路"频谱数据写入接口", 后续接 AD9226 / FFT 结果
//
//   数据源:
//     spec_tone_gen  —— 默认, 200kHz 单音正弦的 FFT 幅度谱 (测试用)
//     spec_demo_gen  —— 多峰扫频演示 (想看动态效果时换这一个)
//   接真实数据的位置见下面 "数据源" 一节。
// ============================================================================
module video_top
(
    input             I_clk           ,   // 27MHz 晶振
    input             I_rst           ,
    input             I_key           ,
    output     [4:0]  O_led           ,
    output            running         ,
    output            O_tmds_clk_p    ,
    output            O_tmds_clk_n    ,
    output     [2:0]  O_tmds_data_p   ,   // {r,g,b}
    output     [2:0]  O_tmds_data_n
`ifdef EXT_DATA_IO
    ,                                     // ---- 外部频谱数据接口 (可选) ----
    input             I_ext_clk        ,  // 数据源时钟
    input             I_ext_rst_n      ,  // 数据源复位, 低有效
    input             I_ext_frame_start,  // 帧起始单拍脉冲
    input             I_ext_wr_en      ,  // 单点写使能
    input      [9:0]  I_ext_wr_addr    ,  // 频点 0..1023
    input      [15:0] I_ext_wr_mag        // 幅度 0..65535
`endif
);

    wire I_rst_n = ~I_rst;

    //======================================================================
    // 时钟: 27MHz -> 371.25MHz (串行) / 74.25MHz (像素)
    //======================================================================
    wire serial_clk;
    wire pll_lock;
    wire pix_clk;

    TMDS_rPLL u_tmds_rpll
    (
        .clkin  (I_clk     ),
        .clkout (serial_clk),
        .lock   (pll_lock  )
    );

    wire hdmi4_rst_n = I_rst_n & pll_lock;

    CLKDIV u_clkdiv
    (
        .RESETN (hdmi4_rst_n),
        .HCLKIN (serial_clk ),
        .CLKOUT (pix_clk    ),
        .CALIB  (1'b1       )
    );
    defparam u_clkdiv.DIV_MODE = "5";
    defparam u_clkdiv.GSREN    = "false";

    //======================================================================
    // 心跳灯
    //======================================================================
    reg [31:0] run_cnt;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            run_cnt <= 32'd0;
        else if (run_cnt >= 32'd27_000_000)
            run_cnt <= 32'd0;
        else
            run_cnt <= run_cnt + 32'd1;
    end

    assign running = (run_cnt < 32'd13_500_000);

    //======================================================================
    // 视频时序 1280x720@60
    //======================================================================
    wire        de_in;
    wire        hs_in;
    wire        vs_in;
    wire [11:0] px;
    wire [11:0] py;

    video_timing #(
        .H_TOTAL  (1650), .H_SYNC (40), .H_BPORCH (220), .H_RES (1280),
        .V_TOTAL  (750 ), .V_SYNC (5 ), .V_BPORCH (20 ), .V_RES (720 )
    ) u_timing (
        .I_clk   (pix_clk    ),
        .I_rst_n (hdmi4_rst_n),
        .O_de    (de_in      ),
        .O_hs    (hs_in      ),
        .O_vs    (vs_in      ),
        .O_x     (px         ),
        .O_y     (py         )
    );

    // 场同步上升沿 = 一帧开始
    reg vs_d;
    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n) vs_d <= 1'b0;
        else              vs_d <= vs_in;
    end
    wire frame_tick = vs_in & ~vs_d;

    //======================================================================
    // 按键 / 频率跨度 / LED
    //======================================================================
    wire [1:0] span;

    key_ctrl #(.SPAN_NUM(3)) u_key (
        .I_clk       (pix_clk    ),
        .I_rst_n     (hdmi4_rst_n),
        .I_key       (I_key      ),
        .I_heartbeat (running    ),
        .O_span      (span       ),
        .O_led       (O_led      )
    );

    //======================================================================
    // 数据源
    //
    //   接真实数据时, 把下面 6 根 spec_* 线换成自己的模块输出即可:
    //     spec_wr_clk / spec_wr_rst_n 与数据源同域,
    //     spec_frame_start 帧起始单拍, spec_wr_en/addr/mag 逐点写入。
    //
    //   注意: 两个测试源必须都例化。Verilog 里"没有被任何模块例化"的模块
    //   会被 Gowin 当成顶层候选, 出现两个候选时 IDE 会放弃指定顶层,
    //   综合器就随便挑一个当顶层 -> .cst 全部报 "Can't find object".
    //======================================================================
    wire        spec_wr_clk;
    wire        spec_wr_rst_n;
    wire        spec_frame_start;
    wire        spec_wr_en;
    wire [9:0]  spec_wr_addr;
    wire [15:0] spec_wr_mag;

    // 0: 200kHz 单音正弦 (默认)   1: 多峰扫频演示
    localparam USE_SWEEP = 0;

    wire        tone_fs, tone_en, swp_fs, swp_en;
    wire [9:0]  tone_addr, swp_addr;
    wire [15:0] tone_mag,  swp_mag;

    spec_tone_gen u_tone (
        .I_clk         (pix_clk    ),
        .I_rst_n       (hdmi4_rst_n),
        .I_frame_tick  (frame_tick ),
        .O_frame_start (tone_fs    ),
        .O_wr_en       (tone_en    ),
        .O_wr_addr     (tone_addr  ),
        .O_wr_mag      (tone_mag   )
    );

    spec_demo_gen u_sweep (
        .I_clk         (pix_clk    ),
        .I_rst_n       (hdmi4_rst_n),
        .I_frame_tick  (frame_tick ),
        .O_frame_start (swp_fs     ),
        .O_wr_en       (swp_en     ),
        .O_wr_addr     (swp_addr   ),
        .O_wr_mag      (swp_mag    )
    );

`ifdef EXT_DATA_IO
    //----------------------------------------------------------------------
    // 【外部数据源】定义 EXT_DATA_IO 后启用, 需自行在 .cst 里分配引脚
    //----------------------------------------------------------------------
    assign spec_wr_clk       = I_ext_clk;
    assign spec_wr_rst_n     = I_ext_rst_n;
    assign spec_frame_start  = I_ext_frame_start;
    assign spec_wr_en        = I_ext_wr_en;
    assign spec_wr_addr      = I_ext_wr_addr;
    assign spec_wr_mag       = I_ext_wr_mag;
`else
    assign spec_wr_clk      = pix_clk;
    assign spec_wr_rst_n    = hdmi4_rst_n;
    assign spec_frame_start = USE_SWEEP ? swp_fs   : tone_fs;
    assign spec_wr_en       = USE_SWEEP ? swp_en   : tone_en;
    assign spec_wr_addr     = USE_SWEEP ? swp_addr : tone_addr;
    assign spec_wr_mag      = USE_SWEEP ? swp_mag  : tone_mag;
`endif

    //======================================================================
    // 频谱显示
    //======================================================================
    wire [7:0] disp_r;
    wire [7:0] disp_g;
    wire [7:0] disp_b;

    spec_display u_display (
        .I_pix_clk     (pix_clk         ),
        .I_pix_rst_n   (hdmi4_rst_n     ),
        .I_x           (px              ),
        .I_y           (py              ),
        .I_span        (span            ),
        .I_wr_clk      (spec_wr_clk     ),
        .I_wr_rst_n    (spec_wr_rst_n   ),
        .I_frame_start (spec_frame_start),
        .I_wr_en       (spec_wr_en      ),
        .I_wr_addr     (spec_wr_addr    ),
        .I_wr_mag      (spec_wr_mag     ),
        .O_r           (disp_r          ),
        .O_g           (disp_g          ),
        .O_b           (disp_b          )
    );

    //======================================================================
    // 显示输出与同步信号对齐 (显示流水线延迟 5 拍)
    //======================================================================
    reg [5:0] de_d;
    reg [5:0] hs_d;
    reg [5:0] vs_dly;

    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n) begin
            de_d   <= 6'b000000;
            hs_d   <= 6'b000000;
            vs_dly <= 6'b000000;
        end else begin
            de_d   <= {de_d[4:0],   de_in};
            hs_d   <= {hs_d[4:0],   hs_in};
            vs_dly <= {vs_dly[4:0], vs_in};
        end
    end

    //======================================================================
    // TMDS 发送
    //======================================================================
    DVI_TX_Top DVI_TX_Top_inst
    (
        .I_rst_n       (hdmi4_rst_n   ),
        .I_serial_clk  (serial_clk    ),
        .I_rgb_clk     (pix_clk       ),
        .I_rgb_vs      (vs_dly[5]     ),
        .I_rgb_hs      (hs_d[5]       ),
        .I_rgb_de      (de_d[5]       ),
        .I_rgb_r       (disp_r        ),
        .I_rgb_g       (disp_g        ),
        .I_rgb_b       (disp_b        ),
        .O_tmds_clk_p  (O_tmds_clk_p  ),
        .O_tmds_clk_n  (O_tmds_clk_n  ),
        .O_tmds_data_p (O_tmds_data_p ),
        .O_tmds_data_n (O_tmds_data_n )
    );

endmodule

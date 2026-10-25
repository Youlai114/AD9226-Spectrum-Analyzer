// ============================================================================
// video_top.v  --  AD9226 + HDMI 频谱分析仪 顶层 (Tang Nano 20K / GW2AR-18)
//
//   结构:
//     27MHz ─┬─ TMDS_rPLL -> 371.25MHz ─ CLKDIV/5 -> 74.25MHz 像素时钟 (HDMI)
//            └─ ad9226_pll -> 54MHz ────────────────> AD9226 CLK + 采样/FFT 时钟
//
//     AD9226 12bit ─> ad9226_capture (抽取 27/108/540/2700 -> fs 2M/500k/100k/20k)
//                     ─> fft4096 (Hann + 4096 点 FFT + 开方求模 + 2 点 1 列)
//                     ─> spec_data_if ─> spec_ram(乒乓) ─> spec_display
//                     ─> DVI_TX ─> HDMI
//
//   人机界面 (打板版本):
//     5 个按键 + EC11 旋转编码器 (A/B/SW), 均由 key_enc_ctrl 处理
//     编码器旋转 = 切跨度 (到头停), 按压 = Preset, KEY1 = 循环切跨度
//     KEY2 = 显示模式循环 (频谱+瀑布/纯净频谱/时域波形);
//     KEY3 = AUTO 自动跨度; KEY4 = 光标三态 (关/普通/增量 Δ);
//     KEY5 = 窗函数循环 (Hann/Rect/Blackman/FlatTop, 默认 Hann)
//
//   显示模式 (KEY2 循环 0/1/2, 两路显示流水线延迟相同, 可无缝切换):
//     0 频谱+瀑布: FFT 幅度谱 + 谐波标记 + 背景瀑布图 (128 行历史) + 右侧菜单
//     1 纯净频谱: 菜单折叠成黑、无瀑布, 画面最干净
//     2 时域波形: wave_cap 边沿触发采 1024 点, 前 256 点 4 倍内插放大绘制
//
//   数据源 (localparam USE_ADC):
//     1 = AD9226 实测数据 (默认)
//     0 = 内部 200kHz 单音测试数据 (不接 ADC 板也能看到完整界面)
//
//   注意: 三个数据源模块必须全部例化。Verilog 里没有被例化的模块会被
//   高云综合器当成"顶层候选", 出现多个候选时顶层会被乱挑, .cst 全报错。
// ============================================================================
module video_top
(
    input             I_clk           ,   // 27MHz 晶振 (引脚 4)
    input             I_rst           ,   // 复位按键 (引脚 88, 按下为高)
    input      [4:0]  I_key           ,   // 5 个按键 (低有效, 板上 10k 上拉)
    input             I_enc_a         ,   // EC11 A 相
    input             I_enc_b         ,   // EC11 B 相
    input             I_enc_sw        ,   // EC11 按压 (低有效)
    output     [1:0]  O_led           ,   // LED_STAT / LED_OVR (低电平点亮)

    // ---- HDMI ----
    output            O_tmds_clk_p    ,
    output            O_tmds_clk_n    ,
    output     [2:0]  O_tmds_data_p   ,   // {r,g,b}
    output     [2:0]  O_tmds_data_n   ,

    // ---- AD9226 并行接口 ----
    output            O_clk_adc       ,   // 54MHz -> AD9226 CLK
    input      [11:0] I_adc_d         ,   // AD9226 D0..D11
    input             I_adc_otr           // AD9226 OTR (过压, 高有效)
);

    localparam USE_ADC = 1;               // 1: 用 AD9226 实测数据

    wire I_rst_n = ~I_rst;

    //======================================================================
    // 时钟 1: 27MHz -> 371.25MHz (串行) / 74.25MHz (像素)
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
    // 时钟 2: 27MHz -> 54MHz (AD9226 采样 + 采样/FFT 时钟)
    //======================================================================
    wire adc_clk;
    wire adc_pll_lock;

    ad9226_pll u_adc_pll
    (
        .clk_out (adc_clk     ),
        .locked  (adc_pll_lock),
        .clkin   (I_clk       )
    );

    // AD9226 采样时钟直接由 PLL 输出到管脚 (不经 fabric 分频, 抖动最小)
    assign O_clk_adc = adc_clk;

    // 复位: 异步置位, 同步释放 (54MHz 域)
    wire adc_rst_n_async = I_rst_n & adc_pll_lock;
    reg  [2:0] adc_rst_sync;

    always @(posedge adc_clk or negedge adc_rst_n_async) begin
        if (!adc_rst_n_async) adc_rst_sync <= 3'b000;
        else                  adc_rst_sync <= {adc_rst_sync[1:0], 1'b1};
    end
    wire adc_rst_n = adc_rst_sync[2];

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

    wire heartbeat = (run_cnt < 32'd13_500_000);

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

    // 帧同步翻转标志 (给 54MHz 域用; 单拍脉冲跨时钟会丢, 用翻转量更稳)
    reg frame_tog;
    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n)    frame_tog <= 1'b0;
        else if (frame_tick) frame_tog <= ~frame_tog;
    end

    //======================================================================
    // 按键 / 频率跨度 / LED / 显示模式
    //======================================================================
    wire [2:0] span;            // 0..4: 1M / 250k / 50k / 10k / 27M(宽频)

    wire [4:0] key_press;          // bit0=KEY1 切跨度, bit1=KEY2 切显示模式,
                                   // bit4=KEY5=Preset; bit2~3 预留
    // 显示模式 (KEY2 循环): 0=频谱+菜单+瀑布 1=纯净频谱(菜单折叠) 2=时域波形
    reg [1:0] mode;

    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n)      mode <= 2'd0;
        else if (key_press[1]) mode <= (mode == 2'd2) ? 2'd0 : (mode + 2'd1);
    end

    wire mode_wave  = (USE_ADC != 0) && (mode == 2'd2);
    wire spec_wf_en = (mode == 2'd0);          // 频谱视图 + 瀑布背景
    wire spec_hide  = (mode == 2'd1);          // 菜单折叠的纯净频谱

    // 窗函数 (KEY5 循环, 默认 Hann): 0=Hann 1=Rect 2=Blackman 3=FlatTop
    reg [1:0] win;
    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n)      win <= 2'd0;
        else if (key_press[4]) win <= (win == 2'd3) ? 2'd0 : (win + 2'd1);
    end

    //------------------------------------------------------------------
    // 光标 (KEY4 开关): 开启时编码器移光标, 关闭时调跨度
    //   波形视图下光标无频率意义, 自动隐藏并让编码器回到调跨度
    //------------------------------------------------------------------
    reg  [1:0] csr_mode;                  // 0=关 1=普通 2=增量 (KEY4 循环)
    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n)      csr_mode <= 2'd0;
        else if (key_press[3]) csr_mode <= (csr_mode == 2'd2) ? 2'd0 : (csr_mode + 2'd1);
    end
    wire csr_en  = (csr_mode != 2'd0);
    wire mode_csr = csr_en & ~mode_wave;

    wire csr_up, csr_dn, sw_press;

    reg  [9:0] csr_col;                    // 光标列 0..1023 (更新逻辑在 CDC 块之后)

    // AUTO (KEY3): 自动跨度, 结果写回 key_enc_ctrl 保持单一跨度源
    wire [1:0] span_auto;
    wire       span_load;

    key_enc_ctrl #(.SPAN_NUM(4)) u_key (
        .I_clk           (pix_clk    ),
        .I_rst_n         (hdmi4_rst_n),
        .I_key           (I_key      ),
        .I_enc_a         (I_enc_a    ),
        .I_enc_b         (I_enc_b    ),
        .I_enc_sw        (I_enc_sw   ),
        .I_span_load     (span_load  ),
        .I_span_load_val (span_auto  ),
        .I_enc_mode      (mode_csr   ),
        .O_csr_up        (csr_up     ),
        .O_csr_dn        (csr_dn     ),
        .O_sw_press      (sw_press   ),
        .O_span          (span       ),
        .O_key_press     (key_press  )
    );

    //======================================================================
    // AD9226 采集 -> FFT
    //======================================================================
    // 跨度 (像素域) 同步到 54MHz 域: 3bit 慢变信号, 2 级同步足够
    reg [2:0] span_s0, span_s1;
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            span_s0 <= 2'd0;
            span_s1 <= 2'd0;
        end else begin
            span_s0 <= span;
            span_s1 <= span_s0;
        end
    end
    wire cap_start;                        // 来自 fft4096: 开始采一帧

    // 跨度只在每帧采集开始时生效, 避免切换瞬间把一帧采成两种速率的混合
    reg [2:0] dec_sel;                     // 0:/27(2M) 1:/108(500k) 2:/540(100k) 3:/2700(20k) 4:/1(54M)
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n)      dec_sel <= 3'd0;
        else if (cap_start)  dec_sel <= span_s1;
    end
    wire dec_wide = (dec_sel == 3'd4);     // 宽频直采: FFT 补偿切平
    // 窗选择跨时钟域 (准静态, 2 级同步足够)
    reg [1:0] win_s0, win_s1;
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            win_s0 <= 2'd0;
            win_s1 <= 2'd0;
        end else begin
            win_s0 <= win;
            win_s1 <= win_s0;
        end
    end

    // 帧同步: toggle 同步 + 边沿检测 -> 一屏算一帧
    reg [1:0] ftog_sync;
    reg       ftog_d;
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            ftog_sync <= 2'b00;
            ftog_d    <= 1'b0;
        end else begin
            ftog_sync <= {ftog_sync[0], frame_tog};
            ftog_d    <= ftog_sync[1];
        end
    end
    wire adc_frame_req = ftog_sync[1] ^ ftog_d;

    wire [15:0] adc_smp;
    wire        adc_smp_en;
    wire        adc_otr;

    ad9226_capture #(.NLOG(11)) u_cap (
        .I_clk     (adc_clk   ),
        .I_rst_n   (adc_rst_n ),
        .I_adc_d   (I_adc_d   ),
        .I_adc_otr (I_adc_otr ),
        .I_dec_sel (dec_sel   ),
        .I_start   (cap_start ),
        .O_smp     (adc_smp   ),
        .O_smp_en  (adc_smp_en),
        .O_otr     (adc_otr   )
    );

    wire        spec_frame_start_adc;
    wire        spec_wr_en_adc;
    wire [9:0]  spec_wr_addr_adc;
    wire [15:0] spec_wr_mag_adc;

    wire [9:0] fft_hrm_col;
    wire       fft_hrm_valid;
    wire       fft_hrm_tog;
    wire [15:0] fft_h2, fft_h3, fft_h4, fft_h5;

    fft4096 #(.N(4096), .NLOG(12)) u_fft (
        .I_clk         (adc_clk             ),
        .I_rst_n       (adc_rst_n           ),
        .I_frame_req   (adc_frame_req       ),
        .O_cap_start   (cap_start           ),
        .O_busy        (                    ),
        .I_smp         (adc_smp             ),
        .I_smp_en      (adc_smp_en          ),
        .O_frame_start (spec_frame_start_adc),
        .O_mag_en      (spec_wr_en_adc      ),
        .O_mag_addr    (spec_wr_addr_adc    ),
        .O_mag         (spec_wr_mag_adc     ),
        .O_hrm_col     (fft_hrm_col         ),
        .O_hrm_valid   (fft_hrm_valid       ),
        .O_hrm_tog     (fft_hrm_tog         ),
        .O_h2          (fft_h2              ),
        .O_h3          (fft_h3              ),
        .O_h4          (fft_h4              ),
        .O_h5          (fft_h5              ),
        .I_mag_flat    (dec_wide            ),
        .I_win         (win_s1              ),
        .I_avg_fast    (dec_sel == 3'd3     ),  // 慢档 (5fps) 用 1/4 平均深度
        .I_cfg_id      ({span_s1, win_s1}   )   // 参数指纹: 变化时平均重新预装
    );

    //------------------------------------------------------------------
    // 时域波形采集: 每显示帧 arm 一次 (上一帧没采完则等它采完)
    //   wave_cap 与 FFT 共用同一样点流, 跨度切换与 FFT 在同一拍生效
    //------------------------------------------------------------------
    reg  wave_armed;
    wire wave_frame_ok;
    wire wave_arm = adc_frame_req & ~wave_armed;

    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n)            wave_armed <= 1'b0;
        else if (wave_arm)         wave_armed <= 1'b1;
        else if (wave_frame_ok)    wave_armed <= 1'b0;
    end

    wire        wcap_wr_start;
    wire        wcap_we;
    wire [9:0]  wcap_addr;
    wire [15:0] wcap_data;

    wave_cap u_wcap (
        .I_clk       (adc_clk       ),
        .I_rst_n     (adc_rst_n     ),
        .I_smp       (adc_smp       ),
        .I_smp_en    (adc_smp_en    ),
        .I_arm       (wave_arm      ),
        .I_level     (16'sd0        ),   // 触发电平 = 0V (中点)
        .I_edge      (1'b0          ),   // 上升沿触发
        .O_addr      (wcap_addr     ),
        .O_data      (wcap_data     ),
        .O_we        (wcap_we       ),
        .O_wr_start  (wcap_wr_start ),
        .O_frame_ok  (wave_frame_ok ),
        .O_cnt       (              )
    );

    //------------------------------------------------------------------
    // 谐波检测跨时钟域: toggle + 2 级同步 + 边沿 -> 锁存稳定的数据总线
    //   (O_hrm_col/valid 只在 O_hrm_tog 翻转那一拍变化, 边沿到达时总线已稳定)
    //------------------------------------------------------------------
    reg [1:0] hrm_tog_s0;
    reg       hrm_tog_d;
    reg       hrm_valid_p;
    reg [9:0] hrm_col_p;
    reg [2:0] hrm_span_p;              // 测量该峰时的跨度档 (AUTO 换算 f0 用)
    reg [15:0] h2_p, h3_p, h4_p, h5_p; // 谐波电平 (顶栏 H2..H5 读数)

    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n) begin
            hrm_tog_s0 <= 2'b00;
            hrm_tog_d  <= 1'b0;
            hrm_valid_p <= 1'b0;
            hrm_col_p  <= 10'd0;
            hrm_span_p <= 2'd0;
            h2_p <= 16'd0;  h3_p <= 16'd0;  h4_p <= 16'd0;  h5_p <= 16'd0;
        end else begin
            hrm_tog_s0 <= {hrm_tog_s0[0], fft_hrm_tog};
            hrm_tog_d  <= hrm_tog_s0[1];
            if (hrm_tog_s0[1] ^ hrm_tog_d) begin
                hrm_valid_p <= fft_hrm_valid;
                hrm_col_p   <= fft_hrm_col;
                hrm_span_p  <= span;   // 像素域 span 在帧期间不变, 与测量档一致
                h2_p <= fft_h2;  h3_p <= fft_h3;
                h4_p <= fft_h4;  h5_p <= fft_h5;
            end
        end
    end

    // AUTO: 用检测到的基波列 + 测量跨度算目标档, KEY3 按下时加载
    auto_span u_auto (
        .I_clk       (pix_clk    ),
        .I_rst_n     (hdmi4_rst_n),
        .I_req       (key_press[2]),
        .I_hrm_valid (hrm_valid_p),
        .I_hrm_col   (hrm_col_p  ),
        .I_hrm_span  (hrm_span_p ),
        .I_span_cur  (span       ),
        .O_span      (span_auto  ),
        .O_load      (span_load  )
    );

    // 光标列更新: 旋转步进; 光标模式下按压 = 跳到基波峰值列
    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n)                       csr_col <= 10'd512;
        else if (mode_csr && sw_press && hrm_valid_p)
                                                csr_col <= hrm_col_p;
        else if (csr_up && csr_col <= 10'd1019) csr_col <= csr_col + 10'd4;
        else if (csr_dn && csr_col >= 10'd4)    csr_col <= csr_col - 10'd4;
    end

    // LED (低电平点亮): LED_STAT 心跳, LED_OVR 过载常亮
    assign O_led[0] = ~heartbeat;
    assign O_led[1] = ~adc_otr;

    //======================================================================
    // 数据源选择
    //======================================================================
    wire        spec_wr_clk;
    wire        spec_wr_rst_n;
    wire        spec_frame_start;
    wire        spec_wr_en;
    wire [9:0]  spec_wr_addr;
    wire [15:0] spec_wr_mag;

    wire        tone_fs, tone_en, swp_fs, swp_en;
    wire [9:0]  tone_addr, swp_addr;
    wire [15:0] tone_mag,  swp_mag;

    spec_tone_gen u_tone (
        .I_clk         (pix_clk    ),
        .I_rst_n       (hdmi4_rst_n),
        .I_span        (span       ),
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

    assign spec_wr_clk      = USE_ADC ? adc_clk            : pix_clk;
    assign spec_wr_rst_n    = USE_ADC ? adc_rst_n          : hdmi4_rst_n;
    assign spec_frame_start = USE_ADC ? spec_frame_start_adc : tone_fs;
    assign spec_wr_en       = USE_ADC ? spec_wr_en_adc       : tone_en;
    assign spec_wr_addr     = USE_ADC ? spec_wr_addr_adc     : tone_addr;
    assign spec_wr_mag      = USE_ADC ? spec_wr_mag_adc      : tone_mag;

    //======================================================================
    // 频谱 / 波形显示 (两个模块 6 级流水线延迟相同, 输出可无缝切换)
    //======================================================================
    wire [7:0] spec_r, spec_g, spec_b;
    wire [7:0] wave_r, wave_g, wave_b;

    spec_display u_display (
        .I_pix_clk     (pix_clk         ),
        .I_pix_rst_n   (hdmi4_rst_n     ),
        .I_x           (px              ),
        .I_y           (py              ),
        .I_span        (span            ),
        .I_hrm_valid   (hrm_valid_p     ),
        .I_hrm_col     (hrm_col_p       ),
        .I_hrm_span    (hrm_span_p      ),
        .I_csr_en      (csr_en & ~mode_wave),
        .I_csr_mode    (mode_csr        ),
        .I_h2          (h2_p            ),
        .I_h3          (h3_p            ),
        .I_h4          (h4_p            ),
        .I_h5          (h5_p            ),
        .I_csr_col     (csr_col         ),
        .I_wf_en       (spec_wf_en      ),
        .I_menu_hide   (spec_hide       ),
        .I_win         (win             ),
        .I_wr_clk      (spec_wr_clk     ),
        .I_wr_rst_n    (spec_wr_rst_n   ),
        .I_frame_start (spec_frame_start),
        .I_wr_en       (spec_wr_en      ),
        .I_wr_addr     (spec_wr_addr    ),
        .I_wr_mag      (spec_wr_mag     ),
        .O_r           (spec_r          ),
        .O_g           (spec_g          ),
        .O_b           (spec_b          )
    );

    wave_display u_wdisp (
        .I_pix_clk     (pix_clk         ),
        .I_pix_rst_n   (hdmi4_rst_n     ),
        .I_x           (px              ),
        .I_y           (py              ),
        .I_span        (span            ),
        .I_wr_clk      (adc_clk         ),
        .I_wr_rst_n    (adc_rst_n       ),
        .I_frame_start (wcap_wr_start   ),
        .I_wr_en       (wcap_we         ),
        .I_wr_addr     (wcap_addr       ),
        .I_wr_mag      (wcap_data       ),
        .O_r           (wave_r          ),
        .O_g           (wave_g          ),
        .O_b           (wave_b          )
    );

    wire [7:0] disp_r = mode_wave ? wave_r : spec_r;
    wire [7:0] disp_g = mode_wave ? wave_g : spec_g;
    wire [7:0] disp_b = mode_wave ? wave_b : spec_b;

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

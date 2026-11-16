// ============================================================================
// video_top.v  --  简易频谱分析仪顶层 (AD9226 + Gowin FFT IP + HDMI 1280x720)
//
//   硬件: Tang Nano 20K (GW2AR-LV18QN88C8/I7) + AD9226 模块
//   时钟:
//     I_clk      27.00 MHz  板载晶振
//     adc_clk    54.00 MHz  ad9226_pll 输出 -> AD9226 采样 + 抽取 + FFT IP
//     serial_clk 371.25 MHz TMDS_rPLL 输出 -> DVI_TX 串行化
//     pix_clk    74.25 MHz  CLKDIV /5 -> HDMI 显示时序与绘图
// ============================================================================
module video_top (
    input             I_clk           ,   // 27MHz 晶振
    input             I_rst           ,   // S2 复位按键 (按下为高)
    input      [4:0]  I_key           ,   // 底板 KEY5..KEY1 (低有效)
    input             I_enc_a         ,   // EC11 A 相
    input             I_enc_b         ,   // EC11 B 相
    input             I_enc_sw        ,   // EC11 按键 (低有效)
    output     [1:0]  O_led           ,   // 底板 LED[1:0] (低电平点亮)
    output            O_tmds_clk_p    ,
    output            O_tmds_clk_n    ,
    output     [2:0]  O_tmds_data_p   ,
    output     [2:0]  O_tmds_data_n   ,
    // ---- AD9226 并行接口 ----
    output            O_clk_adc       ,   // 54MHz 采样时钟送出给 AD9226
    input      [11:0] I_adc_d         ,   // AD9226 D0..D11
    input             I_adc_otr           // AD9226 OTR 过压标志
);

    wire I_rst_n = ~I_rst;

    //======================================================================
    // 时钟 1: HDMI 27MHz -> 371.25MHz (串行) / 74.25MHz (像素)
    //======================================================================
    wire serial_clk;
    wire pll_lock;
    wire pix_clk;

    TMDS_rPLL u_tmds_rpll (
        .clkin  (I_clk     ),
        .clkout (serial_clk),
        .lock   (pll_lock  )
    );

    wire hdmi4_rst_n = I_rst_n & pll_lock;

    CLKDIV u_clkdiv (
        .RESETN (hdmi4_rst_n),
        .HCLKIN (serial_clk ),
        .CLKOUT (pix_clk    ),
        .CALIB  (1'b1       )
    );
    defparam u_clkdiv.DIV_MODE = "5";
    defparam u_clkdiv.GSREN    = "false";

    //======================================================================
    // 时钟 2: AD9226 / FFT 27MHz -> 54MHz
    //======================================================================
    wire adc_clk;
    wire adc_pll_lock;

    ad9226_pll u_adc_pll (
        .clkin   (I_clk       ),
        .clk_out (adc_clk     ),
        .locked  (adc_pll_lock)
    );

    assign O_clk_adc = adc_clk;

    // adc_clk 域复位同步释放
    reg [1:0] adc_rst_sync;
    wire      adc_rst_raw_n = I_rst_n & adc_pll_lock;
    always @(posedge adc_clk or negedge adc_rst_raw_n) begin
        if (!adc_rst_raw_n) adc_rst_sync <= 2'b00;
        else                adc_rst_sync <= {adc_rst_sync[0], 1'b1};
    end
    wire adc_rst_n = adc_rst_sync[1];

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

    wire running = (run_cnt < 32'd13_500_000);

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

    //======================================================================
    // 底板按键 / 编码器 / LED 控制
    //======================================================================
    wire [3:0] span;
    wire [1:0] win, det, trc, ref_mode;
    wire       trc_sub, ref_save_tog;
    wire [2:0] avg;
    wire [1:0] view;
    wire       menu_open;
    wire [3:0] menu_sel;
    wire [9:0] mkr_col;
    wire       mkr_fine;
    wire       mkr_delta;
    wire       mkr_track;
    wire [9:0] mkr_ref_col;
    wire [2:0] harm_mode;
    wire [1:0] yscale;
    wire [2:0] yref;
    wire       yscale_ref;
    wire [3:0] lim_lvl;
    wire       lim_sub;
    wire [2:0] trig_mode;
    wire [3:0] trig_lvl;
    wire       trig_sub;
    wire [3:0] vscale;
    wire [3:0] tscale;
    wire       vt_sel;
    wire [1:0] wave_tdec = (tscale == 4'd0) ? 2'd2 :
                           (tscale == 4'd1) ? 2'd1 : 2'd0;
    wire [9:0] pk_col;
    wire       pk_tog;
    wire       adc_otr_lat;
    reg  [1:0] otr_sync;

    always @(posedge pix_clk or negedge hdmi4_rst_n) begin
        if (!hdmi4_rst_n) otr_sync <= 2'b00;
        else              otr_sync <= {otr_sync[0], adc_otr_lat};
    end

    input_ctrl #(.CLK_HZ(74_250_000)) u_input (
        .I_clk       (pix_clk    ),
        .I_rst_n     (hdmi4_rst_n),
        .I_key       (I_key      ),
        .I_enc_a     (I_enc_a    ),
        .I_enc_b     (I_enc_b    ),
        .I_enc_sw    (I_enc_sw   ),
        .I_heartbeat (running    ),
        .I_ovr       (otr_sync[1]),
        .I_pk_col    (pk_col     ),
        .I_pk_tog    (pk_tog     ),
        .O_span      (span       ),
        .O_win       (win        ),
        .O_det       (det        ),
        .O_trc       (trc        ),
        .O_trc_sub   (trc_sub    ),
        .O_ref_mode  (ref_mode   ),
        .O_ref_save_tog(ref_save_tog),
        .O_avg       (avg        ),
        .O_view      (view       ),
        .O_menu_open (menu_open  ),
        .O_menu_sel  (menu_sel   ),
        .O_mkr_col     (mkr_col    ),
        .O_mkr_fine    (mkr_fine   ),
        .O_mkr_delta   (mkr_delta  ),
        .O_mkr_track   (mkr_track  ),
        .O_mkr_ref_col (mkr_ref_col),
        .O_harm_mode   (harm_mode  ),
        .O_yscale      (yscale     ),
        .O_yref        (yref       ),
        .O_yscale_ref  (yscale_ref ),
        .O_lim_lvl     (lim_lvl    ),
        .O_lim_sub     (lim_sub    ),
        .O_trig_mode   (trig_mode  ),
        .O_trig_lvl    (trig_lvl   ),
        .O_trig_sub    (trig_sub   ),
        .O_vscale      (vscale     ),
        .O_tscale      (tscale     ),
        .O_vt_sel      (vt_sel     ),
        .O_led         (O_led      )
    );

    // 控制参数同步到 adc_clk 域
    reg [3:0] span_s0, span_s1;
    reg [1:0] win_s0,  win_s1;
    reg [1:0] det_s0,  det_s1;
    reg [1:0] trc_s0,  trc_s1;
    reg [2:0] avg_s0,  avg_s1;

    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            span_s0 <= 4'd0; span_s1 <= 4'd0;
            win_s0  <= 2'd0; win_s1  <= 2'd0;
            det_s0  <= 2'd0; det_s1  <= 2'd0;
            trc_s0  <= 2'd0; trc_s1  <= 2'd0;
            avg_s0  <= 3'd0; avg_s1  <= 3'd0;
        end else begin
            span_s0 <= span; span_s1 <= span_s0;
            win_s0  <= win;  win_s1  <= win_s0;
            det_s0  <= det;  det_s1  <= det_s0;
            trc_s0  <= trc;  trc_s1  <= trc_s0;
            avg_s0  <= avg;  avg_s1  <= avg_s0;
        end
    end

    // 低频档采用 4096 点环形滑窗重叠刷新 (保持 4096 点 RBW 与谐波精度, 提速 2~16 倍)
    wire [12:0] hop_n = (span_s1 == 4'd5)  ? 13'd256  :   // 200Hz 档: 0.64s 刷新
                        (span_s1 == 4'd15) ? 13'd512  :   // 500Hz 档: 0.51s 刷新
                        (span_s1 == 4'd4)  ? 13'd1024 :   // 1kHz  档: 0.51s 刷新
                        (span_s1 == 4'd14) ? 13'd2048 :   // 2kHz  档: 0.51s 刷新
                                             13'd4096 ;

    // 0..15 与 ad9226_capture 抽取比完全对应 (6 为 27MHz 宽频直采, 关闭逆 sinc)
    wire [3:0] dec_sel  = span_s1;
    wire       mag_flat = (span_s1 == 4'd6);

    reg [1:0] avg_k;
    always @(*) begin
        if (avg_s1 == 3'd0) begin
            // Auto: 低 Span 慢扫描直通, 中 Span x4, 高 Span x16
            case (span_s1)
                4'd4, 4'd5, 4'd14, 4'd15: avg_k = 2'd0;
                4'd3, 4'd12, 4'd13:       avg_k = 2'd1;
                default:                  avg_k = 2'd2;
            endcase
        end else begin
            avg_k = avg_s1[1:0] - 2'd1;
        end
    end

    //======================================================================
    // AD9226 采集 + Gowin 官方可变点 FFT IP 核 (当前 4096 点, 留有 BW 匹配接口)
    //======================================================================
    wire        cap_start;
    wire [15:0] adc_smp;
    wire        adc_smp_en;

    ad9226_capture u_cap (
        .I_clk     (adc_clk    ),
        .I_rst_n   (adc_rst_n  ),
        .I_adc_d   (I_adc_d    ),
        .I_adc_otr (I_adc_otr  ),
        .I_dec_sel (dec_sel    ),
        .I_start   (cap_start  ),
        .O_smp     (adc_smp    ),
        .O_smp_en  (adc_smp_en ),
        .O_otr     (adc_otr_lat)
    );

    wire        spec_frame_start;
    wire        spec_wr_en;
    wire [9:0]  spec_wr_addr;
    wire [15:0] spec_wr_mag;
    wire [15:0] pk_mag, pk_left, pk_right, spur_mag;
    wire [15:0] h2_mag, h3_mag, h4_mag, h5_mag;
    wire [9:0]  h2_col, h3_col, h4_col, h5_col;
    wire signed [15:0] h1_re, h1_im, h2_re, h2_im, h3_re, h3_im, h4_re, h4_im, h5_re, h5_im;

    fft_ip_wrap u_fft_wrap (
        .I_clk         (adc_clk                ),
        .I_rst_n       (adc_rst_n              ),
        .I_fft_log2    (4'd12                  ),
        .I_hop_n       (hop_n                  ),
        .I_win         (win_s1                 ),
        .I_det         (det_s1                 ),
        .I_trc         (trc_s1                 ),
        .I_avg_k       (avg_k                  ),
        .I_mag_flat    (mag_flat               ),
        .I_cfg_id      ({span_s1, win_s1, det_s1}),
        .O_cap_start   (cap_start              ),
        .I_smp         (adc_smp                ),
        .I_smp_en      (adc_smp_en             ),
        .O_frame_start (spec_frame_start       ),
        .O_mag_en      (spec_wr_en             ),
        .O_mag_addr    (spec_wr_addr           ),
        .O_mag         (spec_wr_mag            ),
        .O_pk_col      (pk_col                 ),
        .O_pk_mag      (pk_mag                 ),
        .O_pk_left     (pk_left                ),
        .O_pk_right    (pk_right               ),
        .O_spur_mag    (spur_mag               ),
        .O_pk_tog      (pk_tog                 ),
        .O_h2_mag      (h2_mag                 ),
        .O_h3_mag      (h3_mag                 ),
        .O_h4_mag      (h4_mag                 ),
        .O_h5_mag      (h5_mag                 ),
        .O_h2_col      (h2_col                 ),
        .O_h3_col      (h3_col                 ),
        .O_h4_col      (h4_col                 ),
        .O_h5_col      (h5_col                 ),
        .O_h1_re       (h1_re                  ),
        .O_h1_im       (h1_im                  ),
        .O_h2_re       (h2_re                  ),
        .O_h2_im       (h2_im                  ),
        .O_h3_re       (h3_re                  ),
        .O_h3_im       (h3_im                  ),
        .O_h4_re       (h4_re                  ),
        .O_h4_im       (h4_im                  ),
        .O_h5_re       (h5_re                  ),
        .O_h5_im       (h5_im                  )
    );

    //======================================================================
    // 时域波形触发采集 + Vpp 测量 (1 BSRAM)
    //======================================================================
    wire        [9:0]  wave_addr;
    wire signed [11:0] wave_data;
    wire        [11:0] vpp;
    wire signed [11:0] wave_mid;
    wire        [9:0]  period_smp, period_cnt, high_smp;
    wire               meas_vld;
    wire               vpp_tog;

    wave_capture u_wave (
        .I_clk       (adc_clk   ),
        .I_rst_n     (adc_rst_n ),
        .I_smp       (adc_smp   ),
        .I_smp_en    (adc_smp_en),
        .I_rearm     (cap_start ),
        .I_trig_mode (trig_mode ),
        .I_trig_lvl  (trig_lvl  ),
        .I_tdec      (wave_tdec ),
        .I_rd_clk    (pix_clk   ),
        .I_rd_addr   (wave_addr ),
        .O_rd_data   (wave_data ),
        .O_vpp       (vpp       ),
        .O_mid       (wave_mid  ),
        .O_period_smp(period_smp),
        .O_period_cnt(period_cnt),
        .O_high_smp  (high_smp  ),
        .O_meas_vld  (meas_vld  ),
        .O_vpp_tog   (vpp_tog   )
    );

    //======================================================================
    // 1~5 次时域谐波分离与合成重建 (2 BSRAM)
    //======================================================================
    wire signed [11:0] harm_wave;
    wire        [34:0] harm_all;

    harm_wave_synth u_harm_synth (
        .I_clk       (pix_clk   ),
        .I_rst_n     (hdmi4_rst_n),
        .I_harm_mode (harm_mode ),
        .I_tdec      (wave_tdec ),
        .I_pk_col    (pk_col    ),
        .I_h2_col    (h2_col    ),
        .I_h3_col    (h3_col    ),
        .I_h4_col    (h4_col    ),
        .I_h5_col    (h5_col    ),
        .I_h1_re     (h1_re     ),
        .I_h1_im     (h1_im     ),
        .I_h2_re     (h2_re     ),
        .I_h2_im     (h2_im     ),
        .I_h3_re     (h3_re     ),
        .I_h3_im     (h3_im     ),
        .I_h4_re     (h4_re     ),
        .I_h4_im     (h4_im     ),
        .I_h5_re     (h5_re     ),
        .I_h5_im     (h5_im     ),
        .I_pk_tog    (pk_tog    ),
        .I_rd_addr   (wave_addr ),
        .O_rd_data   (harm_wave ),
        .O_rd_all    (harm_all  )
    );

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
        .I_win         (win             ),
        .I_det         (det             ),
        .I_trc         (trc             ),
        .I_trc_sub     (trc_sub         ),
        .I_ref_mode    (ref_mode        ),
        .I_ref_save_tog(ref_save_tog    ),
        .I_avg         (avg             ),
        .I_view        (view            ),
        .I_menu_open   (menu_open       ),
        .I_menu_sel    (menu_sel        ),
        .I_mkr_col     (mkr_col         ),
        .I_mkr_fine    (mkr_fine        ),
        .I_mkr_delta   (mkr_delta       ),
        .I_mkr_track   (mkr_track       ),
        .I_mkr_ref_col (mkr_ref_col     ),
        .I_harm_mode   (harm_mode       ),
        .I_yscale      (yscale          ),
        .I_yref        (yref            ),
        .I_yscale_ref  (yscale_ref      ),
        .I_lim_lvl     (lim_lvl         ),
        .I_lim_sub     (lim_sub         ),
        .I_trig_mode   (trig_mode       ),
        .I_trig_lvl    (trig_lvl        ),
        .I_trig_sub    (trig_sub        ),
        .I_vscale      (vscale          ),
        .I_tscale      (tscale          ),
        .I_vt_sel      (vt_sel          ),
        .I_pk_col      (pk_col          ),
        .I_pk_mag      (pk_mag          ),
        .I_pk_left     (pk_left         ),
        .I_pk_right    (pk_right        ),
        .I_spur_mag    (spur_mag        ),
        .I_pk_tog      (pk_tog          ),
        .I_h2_mag      (h2_mag          ),
        .I_h3_mag      (h3_mag          ),
        .I_h4_mag      (h4_mag          ),
        .I_h5_mag      (h5_mag          ),
        .I_h2_col      (h2_col          ),
        .I_h3_col      (h3_col          ),
        .I_h4_col      (h4_col          ),
        .I_h5_col      (h5_col          ),
        .O_wave_addr   (wave_addr       ),
        .I_wave_data   (wave_data       ),
        .I_harm_wave   (harm_wave       ),
        .I_harm_all    (harm_all        ),
        .I_vpp         (vpp             ),
        .I_wave_mid    (wave_mid        ),
        .I_period_smp  (period_smp      ),
        .I_period_cnt  (period_cnt      ),
        .I_high_smp    (high_smp        ),
        .I_meas_vld    (meas_vld        ),
        .I_vpp_tog     (vpp_tog         ),
        .I_wr_clk      (adc_clk         ),
        .I_wr_rst_n    (adc_rst_n       ),
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
    DVI_TX_Top DVI_TX_Top_inst (
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

// ============================================================================
// fft_ip_wrap.v  --  Gowin 官方可变点数 FFT IP 包装器 (256..4096 点)
//
//   数据流 (adc_clk 54MHz 域):
//     1. 样点缓冲 cap_mem (4096x16, 3 BSRAM): 采集 N = 1<<I_fft_log2 点
//     2. 加窗 win_rom (4 窗镜像, 5 BSRAM): Hann / Rect / Blackman / FlatTop
//     3. Gowin_FFT_Top (VARIABLE 模式, pset/points 动态点数接口)
//     4. 复数取模 + 窗相干增益 + 0-BSRAM 逆 sinc 补偿 -> 0 dBFS = 65535
//     5. 检波 (PosPeak/Avg/NegPeak/Sample) -> 1024 列
//     6. 视频平均 (avg_mem 1024x18, 1 BSRAM) + 迹线保持 (trc_mem 1024x16, 1 BSRAM)
//     7. 基波峰值跟踪 (O_pk_col / O_pk_mag / O_pk_tog)
// ============================================================================
module fft_ip_wrap (
    input             I_clk         ,   // 54 MHz (adc_clk)
    input             I_rst_n       ,

    // ---- 可变点数与配置 (帧边界锁存) ----
    input      [3:0]  I_fft_log2    ,   // 8..12 (256..4096 点, 默认 12)
    input      [12:0] I_hop_n       ,   // 滑窗步进点数 (4096=非重叠; 512/1024=低频滑窗重叠)
    input      [1:0]  I_win         ,   // 0:Hann 1:Rect 2:Black 3:FlatTop
    input      [1:0]  I_det         ,   // 0:PosPeak 1:Avg 2:NegPeak 3:Sample
    input      [1:0]  I_trc         ,   // 0:ClearWrite 1:MaxHold 2:MinHold 3:View
    input      [1:0]  I_avg_k       ,   // 0:直通(1) 1:/4 2:/16 3:/64
    input             I_mag_flat    ,   // 1: 宽频档关闭逆 sinc 补偿
    input      [7:0]  I_cfg_id      ,   // {span,win,det} 变化时自动预装平均/迹线

    // ---- 来自 ad9226_capture ----
    output reg        O_cap_start   ,
    input      [15:0] I_smp         ,
    input             I_smp_en      ,

    // ---- 输出到 spec_data_if ----
    output reg        O_frame_start ,
    output reg        O_mag_en      ,
    output reg [9:0]  O_mag_addr    ,
    output reg [15:0] O_mag         ,

    // ---- 基波峰值与 2~5 次谐波输出 (adc_clk 域, O_pk_tog 握手) ----
    output reg [9:0]  O_pk_col      ,
    output reg [15:0] O_pk_mag      ,
    output reg [15:0] O_pk_left     ,
    output reg [15:0] O_pk_right    ,
    output reg [15:0] O_spur_mag    ,
    output reg [15:0] O_h2_mag      ,
    output reg [15:0] O_h3_mag      ,
    output reg [15:0] O_h4_mag      ,
    output reg [15:0] O_h5_mag      ,
    output reg [9:0]  O_h2_col      ,
    output reg [9:0]  O_h3_col      ,
    output reg [9:0]  O_h4_col      ,
    output reg [9:0]  O_h5_col      ,
    output reg signed [15:0] O_h1_re,
    output reg signed [15:0] O_h1_im,
    output reg signed [15:0] O_h2_re,
    output reg signed [15:0] O_h2_im,
    output reg signed [15:0] O_h3_re,
    output reg signed [15:0] O_h3_im,
    output reg signed [15:0] O_h4_re,
    output reg signed [15:0] O_h4_im,
    output reg signed [15:0] O_h5_re,
    output reg signed [15:0] O_h5_im,
    output reg        O_pk_tog
);

    //------------------------------------------------------------------
    // 4096 x 16bit 环形样点缓冲 (3 BSRAM)
    //------------------------------------------------------------------
    reg signed [15:0] cap_mem [0:4095];
    reg [11:0] ring_wr_ptr;
    reg [11:0] ring_base;
    reg [12:0] hop_cnt;
    reg        clr_active;
    reg [11:0] clr_addr;
    reg        vld4;
    reg [10:0] idx4;
    reg [15:0] mag4;
    reg [3:0]  fft_log2_lat, prev_fft_log2;

    reg signed [27:0] dc_acc;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            dc_acc <= 28'sd0;
        else if (I_smp_en)
            dc_acc <= dc_acc + ({{12{I_smp[15]}}, $signed(I_smp)} - {{12{dc_acc[27]}}, dc_acc[27:12]});
    end
    wire signed [16:0] smp_ac_ext = {I_smp[15], I_smp} - {dc_acc[27], dc_acc[27:12]};
    wire signed [15:0] smp_ac = (smp_ac_ext > 17'sd32767)  ? 16'sd32767 :
                                (smp_ac_ext < -17'sd32768) ? -16'sd32768 : smp_ac_ext[15:0];

    wire        bg_smp_wr     = !clr_active && I_smp_en;
    wire        cap_wr_en_m   = clr_active || bg_smp_wr || (vld4 && (fft_log2_lat < 4'd12));
    wire [11:0] cap_wr_addr_m = clr_active ? clr_addr :
                                bg_smp_wr  ? ring_wr_ptr : {2'b00, idx4[9:0]};
    wire signed [15:0] cap_wr_dat_m = clr_active ? 16'sd0 :
                                      bg_smp_wr  ? smp_ac : $signed(mag4);

    always @(posedge I_clk) begin
        if (cap_wr_en_m)
            cap_mem[cap_wr_addr_m] <= cap_wr_dat_m;
    end

    reg  [11:0]        rd_addr;
    wire [11:0]        cap_rd_addr_m = (fft_log2_lat == 4'd12) ? (ring_base + rd_addr) : rd_addr;
    reg  signed [15:0] cap_dout;

    always @(posedge I_clk) begin
        cap_dout <= cap_mem[cap_rd_addr_m];
    end

    //------------------------------------------------------------------
    // 帧边界锁存配置
    //------------------------------------------------------------------
    reg [1:0] win_lat, det_lat, trc_lat, avg_lat;
    reg       flat_lat;
    reg [7:0] cfg_lat, prev_cfg_id;
    reg [1:0] prev_trc;
    reg       avg_preload, trc_preload;

    wire [11:0] n_pts_m1 = (12'd1 << fft_log2_lat) - 12'd1;
    wire [3:0]  win_sh   = 4'd12 - fft_log2_lat;
    wire [11:0] win_addr = rd_addr << win_sh;

    //------------------------------------------------------------------
    // 4 窗对称镜像 ROM (与 cap_dout 同拍输出, 1 拍延迟)
    //------------------------------------------------------------------
    wire [11:0] win_w;
    win_rom u_win (
        .I_clk  (I_clk   ),
        .I_win  (win_lat ),
        .I_addr (win_addr),
        .O_w    (win_w   )
    );

    wire signed [27:0] win_prod = cap_dout * $signed({1'b0, win_w});
    wire signed [15:0] win_smp  = win_prod[27:12];

    //------------------------------------------------------------------
    // Gowin 官方可变点数 FFT IP 核
    //------------------------------------------------------------------
    wire [11:0]        fft_idx;
    wire signed [15:0] fft_xk_re;
    wire signed [15:0] fft_xk_im;
    wire               fft_sod, fft_ipd, fft_eod, fft_busy;
    wire               fft_soud, fft_opd, fft_eoud;
    reg                fft_start;
    reg                fft_pset;
    reg  [3:0]         fft_points;

    Gowin_FFT_Top u_fft_ip (
        .idx    (fft_idx   ),
        .xk_re  (fft_xk_re ),
        .xk_im  (fft_xk_im ),
        .sod    (fft_sod   ),
        .ipd    (fft_ipd   ),
        .eod    (fft_eod   ),
        .busy   (fft_busy  ),
        .soud   (fft_soud  ),
        .opd    (fft_opd   ),
        .eoud   (fft_eoud  ),
        .xn_re  (win_smp   ),
        .xn_im  (16'sd0    ),
        .start  (fft_start ),
        .clk    (I_clk     ),
        .rst    (~I_rst_n  ),
        .pset   (fft_pset  ),
        .points (fft_points)
    );

    //------------------------------------------------------------------
    // 采集与 FFT 调度状态机
    //------------------------------------------------------------------
    localparam [2:0] ST_IDLE       = 3'd0,
                     ST_CLR_MEM    = 3'd1,
                     ST_CAP        = 3'd2,
                     ST_FFT_PSET   = 3'd3,
                     ST_FFT_START  = 3'd4,
                     ST_FFT_RUN    = 3'd5,
                     ST_WAIT_DRAIN = 3'd6,
                     ST_EMIT       = 3'd7;

    reg [2:0]  state;
    reg [3:0]  drain_cnt;
    reg        first_run;
    reg [9:0]  emit_col, emit_col_d;
    reg        emit_vld_d, emit_done;
    reg [12:0] hop_n_lat;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state         <= ST_IDLE;
            O_cap_start   <= 1'b0;
            ring_wr_ptr   <= 12'd0;
            ring_base     <= 12'd0;
            hop_cnt       <= 13'd0;
            hop_n_lat     <= 13'd4096;
            clr_active    <= 1'b0;
            clr_addr      <= 12'd0;
            fft_start     <= 1'b0;
            fft_pset      <= 1'b0;
            fft_points    <= 4'd12;
            rd_addr       <= 12'd0;
            drain_cnt     <= 4'd0;
            first_run     <= 1'b1;
            emit_col      <= 10'd0;
            emit_col_d    <= 10'd0;
            emit_vld_d    <= 1'b0;
            emit_done     <= 1'b0;
            fft_log2_lat  <= 4'd12;
            prev_fft_log2 <= 4'd12;
            win_lat       <= 2'd0;
            det_lat       <= 2'd0;
            trc_lat       <= 2'd0;
            avg_lat       <= 2'd0;
            flat_lat      <= 1'b0;
            cfg_lat       <= 8'd0;
            prev_cfg_id   <= 8'hFF;
            prev_trc      <= 2'd0;
            avg_preload   <= 1'b1;
            trc_preload   <= 1'b1;
        end else begin
            O_cap_start <= 1'b0;
            fft_start   <= 1'b0;
            fft_pset    <= 1'b0;

            // 后台持续写入环形缓冲并累计 hop_cnt
            if (!clr_active && I_smp_en) begin
                ring_wr_ptr <= ring_wr_ptr + 12'd1;
                if (hop_cnt < hop_n_lat)
                    hop_cnt <= hop_cnt + 13'd1;
            end

            case (state)
                ST_IDLE: begin
                    fft_log2_lat <= (I_fft_log2 < 4'd8) ? 4'd8 :
                                    (I_fft_log2 > 4'd12) ? 4'd12 : I_fft_log2;
                    hop_n_lat    <= (I_hop_n == 13'd0) ? 13'd4096 : I_hop_n;
                    win_lat      <= I_win;
                    det_lat      <= I_det;
                    trc_lat      <= I_trc;
                    avg_lat      <= I_avg_k;
                    flat_lat     <= I_mag_flat;
                    cfg_lat      <= I_cfg_id;
                    avg_preload  <= first_run || (I_cfg_id != prev_cfg_id);
                    trc_preload  <= first_run || (I_cfg_id != prev_cfg_id) ||
                                    ((I_trc == 2'd1 || I_trc == 2'd2) && (I_trc != prev_trc));
                    if (first_run || (I_cfg_id != prev_cfg_id)) begin
                        clr_active  <= 1'b1;
                        clr_addr    <= 12'd0;
                        ring_wr_ptr <= 12'd0;
                        hop_cnt     <= 13'd0;
                        state       <= ST_CLR_MEM;
                    end else begin
                        state <= ST_CAP;
                    end
                end

                ST_CLR_MEM: begin
                    if (clr_addr == 12'd4095) begin
                        clr_active  <= 1'b0;
                        O_cap_start <= 1'b1;
                        state       <= ST_CAP;
                    end else begin
                        clr_addr <= clr_addr + 12'd1;
                    end
                end

                ST_CAP: begin
                    if (hop_cnt >= hop_n_lat) begin
                        hop_cnt   <= 13'd0;
                        ring_base <= (fft_log2_lat == 4'd12) ? ring_wr_ptr : 12'd0;
                        drain_cnt <= 4'd0;
                        state     <= (first_run || (fft_log2_lat != prev_fft_log2)) ? ST_FFT_PSET : ST_FFT_START;
                    end
                end

                ST_FFT_PSET: begin
                    fft_points <= fft_log2_lat;
                    if (drain_cnt == 4'd0) begin
                        if (!fft_busy) begin
                            fft_pset  <= 1'b1;
                            drain_cnt <= 4'd1;
                        end
                    end else if (drain_cnt < 4'd8) begin
                        drain_cnt <= drain_cnt + 4'd1;
                    end else if (!fft_busy) begin
                        prev_fft_log2 <= fft_log2_lat;
                        drain_cnt     <= 4'd0;
                        state         <= ST_FFT_START;
                    end
                end

                ST_FFT_START: begin
                    rd_addr <= 12'd0;
                    if (!fft_busy) begin
                        fft_start   <= 1'b1;
                        first_run   <= 1'b0;
                        prev_cfg_id <= cfg_lat;
                        prev_trc    <= trc_lat;
                        state       <= ST_FFT_RUN;
                    end
                end

                ST_FFT_RUN: begin
                    if (fft_ipd)
                        rd_addr <= rd_addr + 12'd1;
                    if (fft_eoud) begin
                        drain_cnt <= 4'd0;
                        state     <= ST_WAIT_DRAIN;
                    end
                end

                ST_WAIT_DRAIN: begin
                    if (drain_cnt == 4'd12) begin
                        if (fft_log2_lat == 4'd12) begin
                            state <= ST_IDLE;
                        end else begin
                            emit_col   <= 10'd0;
                            emit_col_d <= 10'd0;
                            emit_vld_d <= 1'b0;
                            emit_done  <= 1'b0;
                            state      <= ST_EMIT;
                        end
                    end else begin
                        drain_cnt <= drain_cnt + 4'd1;
                    end
                end

                ST_EMIT: begin
                    if (!emit_done) begin
                        rd_addr    <= {2'b00, emit_col >> (4'd11 - fft_log2_lat)};
                        emit_col_d <= emit_col;
                        emit_vld_d <= 1'b1;
                        if (emit_col == 10'd1023)
                            emit_done <= 1'b1;
                        else
                            emit_col  <= emit_col + 10'd1;
                    end else begin
                        emit_vld_d <= 1'b0;
                        if (!emit_vld_d)
                            state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    //------------------------------------------------------------------
    // 幅度计算 + 窗相干增益 + 0-BSRAM 逆 sinc 补偿
    //------------------------------------------------------------------
    wire [11:0] pos_lim = 12'd1 << (fft_log2_lat - 4'd1); // N/2 (128..2048)
    wire        in_pos  = fft_opd && (fft_idx < pos_lim);

    // Stage 1: |re|, |im| 寄存与 (-1)^k 符号修正预处理
    reg        vld1;
    reg [10:0] idx1;
    reg [15:0] abs_re, abs_im;
    reg signed [15:0] xk_re_d1, xk_im_d1;
    reg [9:0]  xk_col_d1;
    reg signed [15:0] h1_re_run, h1_im_run, h2_re_run, h2_im_run, h3_re_run, h3_im_run;
    reg signed [15:0] h4_re_run, h4_im_run, h5_re_run, h5_im_run;
    reg [15:0] h1_est_run, h2_est_run, h3_est_run, h4_est_run, h5_est_run;

    wire [15:0] xk_abs_re = fft_xk_re[15] ? (~fft_xk_re + 16'd1) : fft_xk_re;
    wire [15:0] xk_abs_im = fft_xk_im[15] ? (~fft_xk_im + 16'd1) : fft_xk_im;
    wire [9:0]  xk_col    = (fft_log2_lat == 4'd12) ? fft_idx[10:1] : (fft_idx[9:0] << (4'd11 - fft_log2_lat));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vld1     <= 1'b0;
            idx1     <= 11'd0;
            abs_re   <= 16'd0;
            abs_im   <= 16'd0;
            xk_re_d1 <= 16'sd0;
            xk_im_d1 <= 16'sd0;
            xk_col_d1<= 10'd0;
        end else begin
            vld1     <= in_pos;
            idx1     <= fft_idx[10:0];
            abs_re   <= xk_abs_re;
            abs_im   <= xk_abs_im;
            xk_re_d1 <= fft_xk_re;
            xk_im_d1 <= fft_xk_im;
            xk_col_d1<= xk_col;
        end
    end

    // Stage 2: 近似欧氏模值 + 窗增益乘法 + 1~5 次谐波复数谱捕获
    reg        vld2;
    reg [10:0] idx2;
    reg [15:0] mag2;

    wire [15:0] max_v = (abs_re > abs_im) ? abs_re : abs_im;
    wire signed [15:0] xk_re_c = idx1[0] ? -xk_re_d1 : xk_re_d1;
    wire signed [15:0] xk_im_c = idx1[0] ? -xk_im_d1 : xk_im_d1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            h1_re_run <= 16'sd0; h1_im_run <= 16'sd0; h1_est_run <= 16'd0;
            h2_re_run <= 16'sd0; h2_im_run <= 16'sd0; h2_est_run <= 16'd0;
            h3_re_run <= 16'sd0; h3_im_run <= 16'sd0; h3_est_run <= 16'd0;
            h4_re_run <= 16'sd0; h4_im_run <= 16'sd0; h4_est_run <= 16'd0;
            h5_re_run <= 16'sd0; h5_im_run <= 16'sd0; h5_est_run <= 16'd0;
        end else if (state == ST_FFT_START) begin
            h1_re_run <= 16'sd0; h1_im_run <= 16'sd0; h1_est_run <= 16'd0;
            h2_re_run <= 16'sd0; h2_im_run <= 16'sd0; h2_est_run <= 16'd0;
            h3_re_run <= 16'sd0; h3_im_run <= 16'sd0; h3_est_run <= 16'd0;
            h4_re_run <= 16'sd0; h4_im_run <= 16'sd0; h4_est_run <= 16'd0;
            h5_re_run <= 16'sd0; h5_im_run <= 16'sd0; h5_est_run <= 16'd0;
        end else if (vld1) begin
            if ((O_pk_col >= 10'd3) && (xk_col_d1 == O_pk_col) && (max_v >= h1_est_run)) begin
                h1_re_run <= xk_re_c; h1_im_run <= xk_im_c; h1_est_run <= max_v;
            end
            if ((O_h2_col != 10'd0) && (xk_col_d1 == O_h2_col) && (max_v >= h2_est_run)) begin
                h2_re_run <= xk_re_c; h2_im_run <= xk_im_c; h2_est_run <= max_v;
            end
            if ((O_h3_col != 10'd0) && (xk_col_d1 == O_h3_col) && (max_v >= h3_est_run)) begin
                h3_re_run <= xk_re_c; h3_im_run <= xk_im_c; h3_est_run <= max_v;
            end
            if ((O_h4_col != 10'd0) && (xk_col_d1 == O_h4_col) && (max_v >= h4_est_run)) begin
                h4_re_run <= xk_re_c; h4_im_run <= xk_im_c; h4_est_run <= max_v;
            end
            if ((O_h5_col != 10'd0) && (xk_col_d1 == O_h5_col) && (max_v >= h5_est_run)) begin
                h5_re_run <= xk_re_c; h5_im_run <= xk_im_c; h5_est_run <= max_v;
            end
        end
    end
    wire [15:0] min_v = (abs_re > abs_im) ? abs_im : abs_re;
    wire [16:0] mag_approx = {1'b0, max_v} + {3'b0, min_v[15:2]} + {4'b0, min_v[15:3]};
    wire [8:0]  win_gain   = (win_lat == 2'd0) ? 9'd128 :   // Hann:    1.00
                             (win_lat == 2'd1) ? 9'd64  :   // Rect:    0.50
                             (win_lat == 2'd2) ? 9'd152 :   // Black:   1.19
                                                 9'd274 ;   // FlatTop: 2.14
    wire [25:0] mag_wg     = mag_approx * win_gain;         // 17b x 9b
    wire [21:0] mag_wg_s   = mag_wg[25:4];                  // >> 4 (等效 <<3 / 128)
    wire [15:0] mag_wg_sat = (|mag_wg_s[21:16]) ? 16'hFFFF : mag_wg_s[15:0];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vld2 <= 1'b0;
            idx2 <= 11'd0;
            mag2 <= 16'd0;
        end else begin
            vld2 <= vld1;
            idx2 <= idx1;
            mag2 <= mag_wg_sat;
        end
    end

    // Stage 3: 0-BSRAM 逆 sinc 补偿 (1024 + (584 * col^2 >> 20))
    reg        vld3;
    reg [10:0] idx3;
    reg [15:0] mag3;
    reg [10:0] sinc_gain3;

    wire [9:0]  col2       = (fft_log2_lat == 4'd12) ? idx2[10:1] : (idx2[9:0] << (4'd11 - fft_log2_lat));
    wire [19:0] col2_sq    = col2 * col2;
    wire [29:0] sinc_term  = col2_sq * 10'd584;
    wire [10:0] sinc_k     = flat_lat ? 11'd1024 : (11'd1024 + {1'b0, sinc_term[29:20]});

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vld3       <= 1'b0;
            idx3       <= 11'd0;
            mag3       <= 16'd0;
            sinc_gain3 <= 11'd1024;
        end else begin
            vld3       <= vld2;
            idx3       <= idx2;
            mag3       <= mag2;
            sinc_gain3 <= sinc_k;
        end
    end

    wire [26:0] mag_sc     = mag3 * sinc_gain3;
    wire [16:0] mag_sc_s   = mag_sc[26:10];
    wire [15:0] mag_sc_sat = mag_sc_s[16] ? 16'hFFFF : mag_sc_s[15:0];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            vld4 <= 1'b0;
            idx4 <= 11'd0;
            mag4 <= 16'd0;
        end else begin
            vld4 <= vld3;
            idx4 <= idx3;
            mag4 <= mag_sc_sat;
        end
    end

    //------------------------------------------------------------------
    // Stage 5: 2-bin 检波 -> 1024 列 (PosPeak / Avg / NegPeak / Sample)
    //------------------------------------------------------------------
    reg        det_vld;
    reg [9:0]  det_col;
    reg [15:0] det_mag;
    reg [15:0] bin_even;

    wire [16:0] sum_2 = {1'b0, bin_even} + {1'b0, mag4};
    wire [15:0] det_res = (det_lat == 2'd0) ? ((mag4 > bin_even) ? mag4 : bin_even) :
                          (det_lat == 2'd1) ? sum_2[16:1] :
                          (det_lat == 2'd2) ? ((mag4 < bin_even) ? mag4 : bin_even) :
                                              bin_even;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            bin_even <= 16'd0;
            det_vld  <= 1'b0;
            det_col  <= 10'd0;
            det_mag  <= 16'd0;
        end else begin
            det_vld <= 1'b0;
            if (fft_log2_lat == 4'd12) begin
                if (vld4) begin
                    if (!idx4[0]) begin
                        bin_even <= mag4;
                    end else begin
                        det_vld <= 1'b1;
                        det_col <= idx4[10:1];
                        det_mag <= det_res;
                    end
                end
            end else if (emit_vld_d) begin
                det_vld <= 1'b1;
                det_col <= emit_col_d;
                det_mag <= cap_dout;
            end
        end
    end

    //------------------------------------------------------------------
    // Stage 6~7: 视频平均 (avg_mem 1024x18, 1 BSRAM) + 迹线保持 (trc_mem 1024x16, 1 BSRAM)
    //------------------------------------------------------------------
    reg [17:0] avg_mem [0:1023];
    reg [15:0] trc_mem [0:1023];

    reg [17:0] avg_rd;
    reg [15:0] trc_rd;
    reg        avg_wr_en, trc_wr_en;
    reg [9:0]  avg_wr_addr, trc_wr_addr;
    reg [17:0] avg_wr_dat;
    reg [15:0] trc_wr_dat;

    always @(posedge I_clk) begin
        avg_rd <= avg_mem[det_col];
        if (avg_wr_en) avg_mem[avg_wr_addr] <= avg_wr_dat;
    end

    always @(posedge I_clk) begin
        trc_rd <= trc_mem[det_col];
        if (trc_wr_en) trc_mem[trc_wr_addr] <= trc_wr_dat;
    end

    // 对齐 RAM 读延迟 1 拍
    reg        s6_vld;
    reg [9:0]  s6_col;
    reg [15:0] s6_mag;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            s6_vld <= 1'b0;
            s6_col <= 10'd0;
            s6_mag <= 16'd0;
        end else begin
            s6_vld <= det_vld;
            s6_col <= det_col;
            s6_mag <= det_mag;
        end
    end

    // 计算一阶 IIR 视频平均
    wire [17:0]        s6_ext  = {s6_mag, 2'b00};
    wire signed [18:0] avg_err = $signed({1'b0, s6_ext}) - $signed({1'b0, avg_rd});
    wire signed [18:0] avg_stp = (avg_lat == 2'd1) ? (avg_err >>> 2) :
                                 (avg_lat == 2'd2) ? (avg_err >>> 4) :
                                 (avg_lat == 2'd3) ? (avg_err >>> 6) : 19'sd0;
    wire signed [18:0] avg_nxt_s = $signed({1'b0, avg_rd}) + avg_stp;
    wire [17:0]        avg_nxt   = (avg_lat == 2'd0 || avg_preload) ? s6_ext :
                                   (avg_nxt_s[18] ? 18'd0 : avg_nxt_s[17:0]);
    wire [15:0]        mag_avg   = avg_nxt[17:2];

    reg        s7_vld;
    reg [9:0]  s7_col;
    reg [15:0] s7_mag_avg;
    reg [15:0] s7_trc_old;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            s7_vld      <= 1'b0;
            s7_col      <= 10'd0;
            s7_mag_avg  <= 16'd0;
            s7_trc_old  <= 16'd0;
            avg_wr_en   <= 1'b0;
            avg_wr_addr <= 10'd0;
            avg_wr_dat  <= 18'd0;
        end else begin
            s7_vld    <= s6_vld;
            s7_col    <= s6_col;
            s7_mag_avg<= mag_avg;
            s7_trc_old<= trc_rd;
            avg_wr_en <= s6_vld;
            avg_wr_addr <= s6_col;
            avg_wr_dat  <= avg_nxt;
        end
    end

    // 迹线保持与最终输出 (在 s7_col==0 提前一拍给 O_frame_start)
    wire [15:0] trc_out = (trc_lat == 2'd0 || trc_preload) ? s7_mag_avg :
                          (trc_lat == 2'd1) ? ((s7_mag_avg > s7_trc_old) ? s7_mag_avg : s7_trc_old) :
                          (trc_lat == 2'd2) ? ((s7_mag_avg < s7_trc_old) ? s7_mag_avg : s7_trc_old) :
                                              s7_trc_old;

    reg [15:0] pk_max_run, pk_left_run, pk_right_run, pk_prev_trc, spur_max_run;
    reg        pk_need_right;
    reg [9:0]  pk_col_run;
    reg [15:0] h2_run, h3_run, h4_run, h5_run;
    reg [9:0]  h2_col_run, h3_col_run, h4_col_run, h5_col_run;

    wire spur_out_band = (s7_col >= 10'd3) &&
                         (({1'b0, s7_col} + 11'd4 < {1'b0, O_pk_col}) ||
                          ({1'b0, s7_col} > {1'b0, O_pk_col} + 11'd4));

    // 上一帧基波列号的 2~5 倍谐波目标列 (13bit 防溢出)
    wire [12:0] h2_c = {2'b00, O_pk_col, 1'b0};
    wire [12:0] h3_c = {2'b00, O_pk_col, 1'b0} + {3'b000, O_pk_col};
    wire [12:0] h4_c = {1'b0, O_pk_col, 2'b00};
    wire [12:0] h5_c = {1'b0, O_pk_col, 2'b00} + {3'b000, O_pk_col};

    wire [12:0] s7_ext = {3'b000, s7_col};
    wire h2_hit = (O_pk_col >= 10'd3) && (h2_c <= 13'd1021) && (s7_ext + 13'd2 >= h2_c) && (s7_ext <= h2_c + 13'd2);
    wire h3_hit = (O_pk_col >= 10'd3) && (h3_c <= 13'd1021) && (s7_ext + 13'd2 >= h3_c) && (s7_ext <= h3_c + 13'd2);
    wire h4_hit = (O_pk_col >= 10'd3) && (h4_c <= 13'd1021) && (s7_ext + 13'd2 >= h4_c) && (s7_ext <= h4_c + 13'd2);
    wire h5_hit = (O_pk_col >= 10'd3) && (h5_c <= 13'd1021) && (s7_ext + 13'd2 >= h5_c) && (s7_ext <= h5_c + 13'd2);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_frame_start <= 1'b0;
            O_mag_en      <= 1'b0;
            O_mag_addr    <= 10'd0;
            O_mag         <= 16'd0;
            trc_wr_en     <= 1'b0;
            trc_wr_addr   <= 10'd0;
            trc_wr_dat    <= 16'd0;
            pk_max_run    <= 16'd0;
            pk_left_run   <= 16'd0;
            pk_right_run  <= 16'd0;
            pk_prev_trc   <= 16'd0;
            spur_max_run  <= 16'd0;
            pk_need_right <= 1'b0;
            pk_col_run    <= 10'd0;
            h2_run        <= 16'd0;
            h3_run        <= 16'd0;
            h4_run        <= 16'd0;
            h5_run        <= 16'd0;
            h2_col_run    <= 10'd0;
            h3_col_run    <= 10'd0;
            h4_col_run    <= 10'd0;
            h5_col_run    <= 10'd0;
            O_pk_col      <= 10'd0;
            O_pk_mag      <= 16'd0;
            O_pk_left     <= 16'd0;
            O_pk_right    <= 16'd0;
            O_spur_mag    <= 16'd0;
            O_h2_mag      <= 16'd0;
            O_h3_mag      <= 16'd0;
            O_h4_mag      <= 16'd0;
            O_h5_mag      <= 16'd0;
            O_h2_col      <= 10'd0;
            O_h3_col      <= 10'd0;
            O_h4_col      <= 10'd0;
            O_h5_col      <= 10'd0;
            O_h1_re       <= 16'sd0; O_h1_im <= 16'sd0;
            O_h2_re       <= 16'sd0; O_h2_im <= 16'sd0;
            O_h3_re       <= 16'sd0; O_h3_im <= 16'sd0;
            O_h4_re       <= 16'sd0; O_h4_im <= 16'sd0;
            O_h5_re       <= 16'sd0; O_h5_im <= 16'sd0;
            O_pk_tog      <= 1'b0;
        end else begin
            O_frame_start <= s6_vld && (s6_col == 10'd0);
            O_mag_en      <= s7_vld;
            O_mag_addr    <= s7_col;
            O_mag         <= trc_out;

            trc_wr_en     <= s7_vld && (trc_lat != 2'd3);
            trc_wr_addr   <= s7_col;
            trc_wr_dat    <= trc_out;

            if (s7_vld) begin
                pk_prev_trc <= trc_out;
                if (pk_need_right) begin
                    pk_right_run  <= trc_out;
                    pk_need_right <= 1'b0;
                end

                if (s7_col == 10'd0) begin
                    pk_need_right <= 1'b0;
                    spur_max_run  <= 16'd0;
                    h2_run     <= 16'd0;
                    h3_run     <= 16'd0;
                    h4_run     <= 16'd0;
                    h5_run     <= 16'd0;
                    h2_col_run <= 10'd0;
                    h3_col_run <= 10'd0;
                    h4_col_run <= 10'd0;
                    h5_col_run <= 10'd0;
                end else begin
                    if (spur_out_band && (trc_out > spur_max_run)) spur_max_run <= trc_out;
                    if (h2_hit && (trc_out > h2_run)) begin h2_run <= trc_out; h2_col_run <= s7_col; end
                    if (h3_hit && (trc_out > h3_run)) begin h3_run <= trc_out; h3_col_run <= s7_col; end
                    if (h4_hit && (trc_out > h4_run)) begin h4_run <= trc_out; h4_col_run <= s7_col; end
                    if (h5_hit && (trc_out > h5_run)) begin h5_run <= trc_out; h5_col_run <= s7_col; end
                end

                // 跳过 col 0..2 (DC 及窗函数直流主瓣泄漏), 从 col 3 开始搜峰
                if (s7_col == 10'd3) begin
                    pk_max_run    <= trc_out;
                    pk_left_run   <= pk_prev_trc;
                    pk_right_run  <= 16'd0;
                    pk_need_right <= 1'b1;
                    pk_col_run    <= 10'd3;
                end else if ((s7_col > 10'd3) && (trc_out > pk_max_run)) begin
                    pk_max_run    <= trc_out;
                    pk_left_run   <= pk_prev_trc;
                    pk_right_run  <= 16'd0;
                    pk_need_right <= 1'b1;
                    pk_col_run    <= s7_col;
                end

                if (s7_col == 10'd1023) begin
                    O_pk_col   <= (trc_out > pk_max_run) ? 10'd1023 : pk_col_run;
                    O_pk_mag   <= (trc_out > pk_max_run) ? trc_out  : pk_max_run;
                    O_pk_left  <= (trc_out > pk_max_run) ? pk_prev_trc : pk_left_run;
                    O_pk_right <= (trc_out > pk_max_run) ? 16'd0    : (pk_need_right ? trc_out : pk_right_run);
                    O_spur_mag <= (spur_out_band && (trc_out > spur_max_run)) ? trc_out : spur_max_run;
                    O_h2_mag <= (h2_hit && (trc_out > h2_run)) ? trc_out : h2_run;
                    O_h3_mag <= (h3_hit && (trc_out > h3_run)) ? trc_out : h3_run;
                    O_h4_mag <= (h4_hit && (trc_out > h4_run)) ? trc_out : h4_run;
                    O_h5_mag <= (h5_hit && (trc_out > h5_run)) ? trc_out : h5_run;
                    O_h2_col <= (h2_hit && (trc_out > h2_run)) ? 10'd1023 : h2_col_run;
                    O_h3_col <= (h3_hit && (trc_out > h3_run)) ? 10'd1023 : h3_col_run;
                    O_h4_col <= (h4_hit && (trc_out > h4_run)) ? 10'd1023 : h4_col_run;
                    O_h5_col <= (h5_hit && (trc_out > h5_run)) ? 10'd1023 : h5_col_run;
                    O_h1_re  <= h1_re_run; O_h1_im <= h1_im_run;
                    O_h2_re  <= h2_re_run; O_h2_im <= h2_im_run;
                    O_h3_re  <= h3_re_run; O_h3_im <= h3_im_run;
                    O_h4_re  <= h4_re_run; O_h4_im <= h4_im_run;
                    O_h5_re  <= h5_re_run; O_h5_im <= h5_im_run;
                    O_pk_tog <= ~O_pk_tog;
                end
            end
        end
    end

endmodule

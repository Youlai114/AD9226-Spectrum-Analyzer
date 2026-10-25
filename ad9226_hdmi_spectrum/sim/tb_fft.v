// ============================================================================
// tb_fft.v  --  AD9226 采集 + 2048 点 FFT 的 RTL 仿真
//
//   模拟 AD9226: 每个采样时钟输出一个 12bit 正弦码 (中间刻度 2048)
//   同时把
//     sim/out/smp.txt  -- 采集模块实际输出的 4096 个样点 (十进制有符号)
//     sim/out/mag.txt  -- FFT 算出的 1024 列幅度 ("addr mag")
//   落到文件, 由 tools/cmp_fft.py 用比特精确模型比对
//
//   用法:  vsim -c -do "run -all; quit -f" tb_fft +F0=250000 +AMP=2040 +DEC=0
// ============================================================================
`timescale 1ns/1ps

module tb_fft;

    localparam real T_CLK = 18.518;          // 54MHz (ADC 时钟)

    reg clk = 1'b0;
    always #(T_CLK/2.0) clk = ~clk;

    reg         rst_n   = 1'b0;
    reg  [11:0] adc_d   = 12'd2048;
    reg         adc_otr = 1'b0;
    reg  [2:0]  dec_sel = 3'd0;
    reg  [1:0]  win_sel = 2'd0;
    reg         frame_req = 1'b0;
    reg [15:0]  peak_mag = 16'd0;

    wire        cap_start;
    wire [15:0] smp;
    wire        smp_en;
    wire        otr;
    wire        fs, mag_en;
    wire [9:0]  mag_addr;
    wire [15:0] mag;
    wire        busy;
    wire [9:0]  hrm_col;
    wire        hrm_valid, hrm_tog;

    ad9226_capture #(.NLOG(11)) u_cap (
        .I_clk     (clk      ),
        .I_rst_n   (rst_n    ),
        .I_adc_d   (adc_d    ),
        .I_adc_otr (adc_otr  ),
        .I_dec_sel (dec_sel  ),
        .I_start   (cap_start),
        .O_smp     (smp      ),
        .O_smp_en  (smp_en   ),
        .O_otr     (otr      )
    );

    fft4096 #(.N(4096), .NLOG(12)) u_fft (
        .I_clk         (clk      ),
        .I_rst_n       (rst_n    ),
        .I_frame_req   (frame_req),
        .O_cap_start   (cap_start),
        .O_busy        (busy     ),
        .I_smp         (smp      ),
        .I_smp_en      (smp_en   ),
        .O_frame_start (fs       ),
        .O_mag_en      (mag_en   ),
        .O_mag_addr    (mag_addr ),
        .O_mag         (mag      ),
        .O_hrm_col     (hrm_col  ),
        .O_hrm_valid   (hrm_valid),
        .O_hrm_tog     (hrm_tog  ),
        .I_mag_flat    (dec_sel == 3'd4),
        .I_win         (win_sel),
        .I_avg_fast    (dec_sel == 3'd3),
        .I_cfg_id      (5'd0)
    );

    //------------------------------------------------------------------
    // AD9226 行为模型: 12bit 正弦, 数据在时钟沿后 1ns 更新 (模拟 tPD)
    //------------------------------------------------------------------
    // 正弦查表 (4096 点) + 32bit 相位累加器: 比每拍调用 $sin 快一个数量级
    real     sinlut [0:4095];
    real     f0, amp;
    reg [31:0] phase_acc, phase_inc;
    integer  dec_arg, k, inc_i, win_arg;

    initial begin
        for (k = 0; k < 4096; k = k + 1)
            sinlut[k] = $sin(2.0 * 3.14159265358979 * k / 4096.0);

        if (!$value$plusargs("F0=%f",  f0 )) f0  = 250e3;
        if (!$value$plusargs("AMP=%f", amp)) amp = 2040.0;
        if (!$value$plusargs("DEC=%d", dec_arg)) dec_arg = 0;
        if (!$value$plusargs("WIN=%d", win_arg)) win_arg = 0;
        win_sel = win_arg[1:0];
        dec_sel   = dec_arg[2:0];
        phase_acc = 32'd0;
        inc_i     = $rtoi(f0 / 54.0e6 * 4294967296.0);
        phase_inc = inc_i[31:0];
    end

    integer noise_amp;
    initial if (!$value$plusargs("NOISE=%d", noise_amp)) noise_amp = 0;

    // +HARM=1: 复合波 (基波 1300 + 2~5 次谐波 320/160/80/50), 验证谐波表
    integer harm_en;
    initial if (!$value$plusargs("HARM=%d", harm_en)) harm_en = 0;
    real harm5;

    always @(posedge clk) begin
        phase_acc = phase_acc + phase_inc;
        harm5 = harm_en ? (1300.0*sinlut[phase_acc[31:20]]
                         +  320.0*sinlut[(phase_acc[31:20]*2) & 12'hFFF]
                         +  160.0*sinlut[(phase_acc[31:20]*3) & 12'hFFF]
                         +   80.0*sinlut[(phase_acc[31:20]*4) & 12'hFFF]
                         +   50.0*sinlut[(phase_acc[31:20]*5) & 12'hFFF])
                        : amp * sinlut[phase_acc[31:20]];
        #1 adc_d = $rtoi(2048.0 + harm5)
                 + (({$random} % (2*noise_amp + 1)) - noise_amp);
    end

    //------------------------------------------------------------------
    // 落盘
    //------------------------------------------------------------------
    integer f_smp, f_mag, nmag;
    reg     dumping = 1'b0;
    integer nsmp;

    always @(posedge clk) if (cap_start) dumping <= 1'b1;

    always @(posedge clk) begin
        if (rst_n && dumping && smp_en && (nsmp < 4096)) begin
            $fdisplay(f_smp, "%0d", $signed(smp));
            nsmp = nsmp + 1;
        end
    end

    // +FRAMES>1 时只落盘最后一帧 (视频平均收敛后的结果)
    integer nframes_arg, fi;
    integer ndump = 0;
    integer w2hits = 0;
    reg dump_on = 1'b0;      // 单帧模式常开; 多帧模式仅最后一轮

    always @(posedge clk) if (u_fft.in_w2) w2hits = w2hits + 1;

    always @(posedge clk) begin
        if (rst_n && mag_en) begin
            nmag = nmag + 1;                       // 计数永远跑 (帧同步用)
            if (dump_on) begin
                ndump = ndump + 1;
                $fdisplay(f_mag, "%0d %0d", mag_addr, mag);
            end
            if (mag > peak_mag) peak_mag = mag;
        end
    end

    // ---- 调试探针 (+DBG=1 开启) ----
    integer dbg = 0;
    integer dbg_en = 0;
    initial dbg_en = $test$plusargs("DBG") ? 1 : 0;

    // ---- 调试: 峰值列的根/增益 ----
    always @(posedge clk) begin
        if (dbg_en && rst_n && mag_en && mag_addr == 10'd256)
            #1 $display("col256: root=%0d gain=%0d mag=%0d win=%0d",
                        u_fft.root, u_fft.gain_r, mag, u_fft.I_win);
    end
    always @(posedge clk) begin
        if (dbg_en && rst_n && u_fft.mph == 5'd5 && u_fft.m_cnt == 10'd256)
            #1 $display("mph5: base=%0d wg=%0d gain_r=%0d g_w=%0d flat=%0d",
                        u_fft.base_gain, u_fft.win_gain, u_fft.gain_r,
                        u_fft.g_w, u_fft.I_mag_flat);
    end

    // ---- 调试: 窗乘法采样 ----
    always @(posedge clk) begin
        if (dbg_en && rst_n && u_fft.cap_en && dbg < 4) begin
            dbg = dbg + 1;
            #1 $display("cap dbg: addr=%0d hann_w=%0d x=%0d xw=%0d win=%0d",
                        u_fft.hann_addr, u_fft.hann_w, u_fft.s1,
                        u_fft.prod[27:12], u_fft.I_win);
        end
    end

    // ---- 调试: 状态变化与周期状态 ----
    integer st_prev = -1;
    always @(posedge clk) begin
        if (u_fft.st !== st_prev) begin
            $display("[%0t] st=%0d", $time, u_fft.st);
            st_prev = u_fft.st;
        end
    end
    always #20000 $display("[%0t] st=%0d stg=%0d ph=%0d capn=%0d bf=%0d nmag=%0d",
                           $time, u_fft.st, u_fft.stg, u_fft.ph, u_fft.cap_n, u_fft.bf_cnt, nmag);

    initial begin
        nmag = 0;
        nsmp = 0;
        f_smp = $fopen("out/smp.txt", "w");
        f_mag = $fopen("out/mag.txt", "w");

        if (!$value$plusargs("FRAMES=%d", nframes_arg)) nframes_arg = 1;
        dump_on = (nframes_arg == 1);

        #200 rst_n = 1'b1;
        repeat (20) @(posedge clk);

        for (fi = 0; fi < nframes_arg; fi = fi + 1) begin
            // 循环不变式: 进入时 st 必为 IDLE。发脉冲 -> 等真正忙 -> 等回闲。
            // (nmag 在 mag_done 前完成, st 回闲时本帧 1024 列已全部输出)
            @(posedge clk); #1 frame_req = 1'b1;
            @(posedge clk); #1 frame_req = 1'b0;
            $display("[it %0d] req @%0t st=%0d", fi, $time, u_fft.st);
            dump_on = (fi == nframes_arg - 1);          // 最后一帧才落盘
            while (u_fft.st === 3'd0) @(posedge clk);   // 等忙: 帧已开始
            $display("[it %0d] busy @%0t st=%0d", fi, $time, u_fft.st);
            while (u_fft.st !== 3'd0) @(posedge clk);   // 等闲: 帧已完成
            $display("[it %0d] idle @%0t nmag=%0d", fi, $time, nmag);
        end
        repeat (10) @(posedge clk);
        if (nmag != nframes_arg * 1024)
            $display("ERROR: 只算出了 %0d 个频点, 状态=%0d", nmag, u_fft.st);

        $fclose(f_smp);
        $fclose(f_mag);

        // ---- 基波峰值检测自检: 期望列 = f0 / (fs/2) * 1024 ----
        begin : hrm_check
            real fs_eff, exp_col;
            fs_eff  = (dec_sel == 3'd0) ? 2.0e6 :
                      (dec_sel == 3'd1) ? 500.0e3 :
                      (dec_sel == 3'd2) ? 100.0e3 :
                      (dec_sel == 3'd3) ? 20.0e3  : 54.0e6;
            exp_col = f0 / fs_eff * 2.0 * 1024.0;
            if (!hrm_valid)
                $display("FAIL: hrm_valid=0 (幅度 %0f 应高于门限)", amp);
            else if ((hrm_col > exp_col + 2.0) || (hrm_col < exp_col - 2.0))
                $display("FAIL: hrm_col=%0d 期望 %.1f", hrm_col, exp_col);
            else
                $display("pass: hrm_col=%0d 期望 %.1f", hrm_col, exp_col);
        end

        if (win_sel != 2'd0) begin
            if ((peak_mag > 64830) && (peak_mag < 65600))   // +-1%% = 0.09dB
                $display("pass: win=%0d 校准 peak=%0d (expect ~65480)", win_sel, peak_mag);
            else
                $display("FAIL: win=%0d 校准 peak=%0d (expect ~65480)", win_sel, peak_mag);
        end
        if (harm_en) begin : hchk
            // 理论: Hk_dB = 20lg(Ak/1300) + 基波(-0.04)  [相干增益已归一]
            real l2, l3, l4, l5;
            l2 = 20.0*$ln(320.0/1300.0)/2.302585093 - 0.04;
            l3 = 20.0*$ln(160.0/1300.0)/2.302585093 - 0.04;
            l4 = 20.0*$ln( 80.0/1300.0)/2.302585093 - 0.04;
            l5 = 20.0*$ln( 50.0/1300.0)/2.302585093 - 0.04;
            $display("H table: H2=%0d (%.1f) H3=%0d (%.1f) H4=%0d (%.1f) H5=%0d (%.1f)",
                     u_fft.O_h2, l2, u_fft.O_h3, l3, u_fft.O_h4, l4, u_fft.O_h5, l5);
            $display("H dbg: hcol_lat=%0d vld=%b h2max=%0d w2hits=%0d nmag=%0d",
                     u_fft.hcol_lat, u_fft.hcol_vld, u_fft.h2_max, w2hits, nmag);
        end
        $display("tb_fft done: %0d bins, dumped %0d (nframes_arg=%0d)", nmag, ndump, nframes_arg);
        $finish;
    end

endmodule

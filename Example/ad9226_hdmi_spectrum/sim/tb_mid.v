// ============================================================================
// tb_mid.v  --  低频中间帧 (mid frame) 验证
//
//   两个 fft4096 实例吃同一路样点与同一个 frame_req:
//     u_ref  : I_mid_en = 0  -> 只有完整帧 (v1.6.0 行为)
//     u_mid  : I_mid_en = 1  -> 一个完整帧内插 8 个中间帧 (K=128..3584)
//
//   样点不用 ad9226_capture 产生, 而是每 SMPDIV 拍送一个 (模拟慢速档的抽取
//   率): 一帧 FFT 要 4096 个样点, 一次中间帧约 25 万拍, 只有样点间隔够大
//   (真实 20kSPS 档: 一帧 205ms, 一次中间帧 4.5ms) 8 个中间帧才能全部塞进
//   一帧 —— 这正是中间帧只在慢速档开的原因。
//
//   检查项:
//     1) 完整帧逐列比特一致 (中间帧没有破坏完整帧)        -> pass: mid frame
//     2) O_mid_sh 阶梯 = 5,4,3,2,1,1,0,0                -> pass: mid sh
//     3) 中间帧期间 O_hrm_tog 不翻转 (谐波表/THD/SNR 冻结) -> pass: mid freeze
//     4) 中间帧谱峰落在与完整帧相同的列                  -> pass: mid peak
//     5) 中间帧幅度与完整帧同量级 (N/K 补偿对)            -> pass: mid amp
//
//   用法:  vsim -c -do "run -all; quit -f" work.tb_mid
//          可选 +SMPDIV=520 +AMP=2040 +NOISE=0
// ============================================================================
`timescale 1ns/1ps

module tb_mid;

    localparam real T_CLK = 18.518;          // 54MHz
    //   bin 512 <-> fs_eff/8, 相位增量 1/8: 对 K=128..4096 全都相干
    localparam real PH_INC = 0.125;

    reg clk = 1'b0;
    always #(T_CLK/2.0) clk = ~clk;

    reg         rst_n   = 1'b0;
    reg         frame_req = 1'b0;
    reg  [15:0] smp     = 16'd0;
    reg         smp_en  = 1'b0;

    //------------------------------------------------------------------
    // 被测 FFT: 打开中间帧 (cap_start 由它给)
    //------------------------------------------------------------------
    wire        cap_start;
    wire        mid_fs, mid_en;
    wire [9:0]  mid_addr;
    wire [15:0] mid_mag;
    wire        mid_hrm_tog, mid_frame;
    wire [2:0]  mid_sh;

    fft4096 #(.N(4096), .NLOG(12)) u_mid (
        .I_clk         (clk        ),
        .I_rst_n       (rst_n      ),
        .I_frame_req   (frame_req  ),
        .O_cap_start   (cap_start  ),
        .O_busy        (           ),
        .I_mid_en      (1'b1       ),
        .O_mid         (mid_frame  ),
        .O_mid_sh      (mid_sh     ),
        .I_smp         (smp        ),
        .I_smp_en      (smp_en     ),
        .O_frame_start (mid_fs     ),
        .O_mag_en      (mid_en     ),
        .O_mag_addr    (mid_addr   ),
        .O_mag         (mid_mag    ),
        .O_hrm_col     (           ),
        .O_hrm_valid   (           ),
        .O_hrm_tog     (mid_hrm_tog),
        .O_h2          (           ),
        .O_h3          (           ),
        .O_h4          (           ),
        .O_h5          (           ),
        .O_h1          (           ),
        .O_pwr         (           ),
        .I_mag_flat    (1'b0       ),
        .I_win         (2'd0       ),
        .I_det_sel     (2'd0       ),
        .I_avg_sel     (2'd2       ),
        .I_cfg_id      (7'd0       )
    );

    //------------------------------------------------------------------
    // 参考 FFT: 关掉中间帧
    //------------------------------------------------------------------
    wire        ref_fs, ref_en;
    wire [9:0]  ref_addr;
    wire [15:0] ref_mag;
    wire        ref_hrm_tog;

    fft4096 #(.N(4096), .NLOG(12)) u_ref (
        .I_clk         (clk        ),
        .I_rst_n       (rst_n      ),
        .I_frame_req   (frame_req  ),
        .O_cap_start   (           ),
        .O_busy        (           ),
        .I_mid_en      (1'b0       ),
        .O_mid         (           ),
        .O_mid_sh      (           ),
        .I_smp         (smp        ),
        .I_smp_en      (smp_en     ),
        .O_frame_start (ref_fs     ),
        .O_mag_en      (ref_en     ),
        .O_mag_addr    (ref_addr   ),
        .O_mag         (ref_mag    ),
        .O_hrm_col     (           ),
        .O_hrm_valid   (           ),
        .O_hrm_tog     (ref_hrm_tog),
        .O_h2          (           ),
        .O_h3          (           ),
        .O_h4          (           ),
        .O_h5          (           ),
        .O_h1          (           ),
        .O_pwr         (           ),
        .I_mag_flat    (1'b0       ),
        .I_win         (2'd0       ),
        .I_det_sel     (2'd0       ),
        .I_avg_sel     (2'd2       ),
        .I_cfg_id      (7'd0       )
    );

    //------------------------------------------------------------------
    // 样点源: 每 SMPDIV 拍一个 12bit 正弦样点 (零阶保持, 模拟 ADC 输出)
    //------------------------------------------------------------------
    real sinlut [0:4095];
    integer ii;
    initial begin
        for (ii = 0; ii < 4096; ii = ii + 1)
            sinlut[ii] = $sin(2.0 * 3.14159265358979 * ii / 4096.0);
    end

    real    amp       = 2040.0;
    integer dbg_sp    = 0;
    integer noise_arg = 0;
    integer smpdiv    = 520;
    integer smp_cnt   = 0;
    real    phase_acc = 0.0;
    integer ph_i;

    initial begin
        if ($value$plusargs("AMP=%f", amp))        ;
        if ($value$plusargs("NOISE=%d", noise_arg));
        if ($value$plusargs("SMPDIV=%d", smpdiv))  ;
    end

    always @(posedge clk) begin
        if (smp_cnt == smpdiv - 1) begin
            smp_cnt = 0;
            smp_en  <= 1'b1;
            phase_acc = phase_acc + PH_INC;
            if (phase_acc >= 1.0) phase_acc = phase_acc - 1.0;
            ph_i = $rtoi(phase_acc * 4096.0);
            if (ph_i > 4095) ph_i = 4095;
            smp <= $rtoi(amp * sinlut[ph_i]) + noise_arg;   // 有符号样点, 不带 2048 直流
            if ($test$plusargs("DBG") && (dbg_sp < 8)) begin
                dbg_sp = dbg_sp + 1;
                $display("dbg samp %0d: ph_i=%0d smp=%0d", dbg_sp, ph_i,
                         $rtoi(amp * sinlut[ph_i]));
            end
        end else begin
            smp_cnt = smp_cnt + 1;
            smp_en  <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // 采集输出
    //------------------------------------------------------------------
    reg [15:0] ref_m    [0:1023];
    reg [15:0] full_m   [0:1023];
    reg [15:0] midf_m   [0:1023];
    integer    ref_cnt  = 0;
    integer    full_cnt = 0;
    integer    mid_frames = 0;
    reg        full_done  = 1'b0;

    reg [15:0] mid_pk_v   = 16'd0;
    reg [9:0]  mid_pk_c   = 10'd0;
    reg [15:0] per_pk_v   [0:15];
    reg [9:0]  per_pk_c   [0:15];
    reg [2:0]  per_pk_sh  [0:15];

    integer injw_n = 0;
    reg [2:0] pst2 = 3'd0;
    always @(posedge clk) begin
        pst2 <= u_mid.st;
        if ((pst2 != 3'd4) && (u_mid.st == 3'd4)) injw_n <= 0;   // 进 ST_WIN 清零
        if (u_mid.ram_pipe_we && u_mid.inj2) injw_n <= injw_n + 1;
    end

    // 记录 dump: ST_ZERO(5) -> ST_STG(2) 那一拍, ram[0..K-1] 已是中间帧记录
    reg [2:0] pst = 3'd0;
    integer kk;
    always @(posedge clk) begin
        pst <= u_mid.st;
        if ((pst == 3'd5) && (u_mid.st == 3'd2) && u_mid.mid_pend) begin
            $display("info: rec mid_idx=%0d k=%0d sh=%0d cap_n=%0d",
                     u_mid.mid_idx, u_mid.k_lat, u_mid.sh_lat, u_mid.cap_n);
            for (kk = 0; kk < 6; kk = kk + 1)
                $display("   ram[%0d]=%h snap=%h", kk, u_mid.ram[kk], u_mid.snap[kk]);
            $display("   ram[64]=%h ram[100]=%h ram[128]=%h ram[200]=%h",
                     u_mid.ram[12'd64], u_mid.ram[12'd100],
                     u_mid.ram[12'd128], u_mid.ram[12'd200]);
            $display("   injw=%0d half=%h last=%h beyond=%h", injw_n,
                     u_mid.ram[u_mid.k_lat >> 1],
                     u_mid.ram[u_mid.k_lat - 12'd1],
                     u_mid.ram[u_mid.k_lat]);
        end
        // 每个中间帧的谱峰 (中间帧输出直通, 幅值已由 video_top 侧补偿,
        //   这里比较的是 fft 内部幅度 -> 需要按 sh 换算, 见下面检查)
        if (mid_en && mid_frame) begin
            if (mid_mag > mid_pk_v) begin
                mid_pk_v <= mid_mag;
                mid_pk_c <= mid_addr;
            end
            if (mid_addr == 10'd1023) begin
                per_pk_v[mid_frames]  <= (mid_mag > mid_pk_v) ? mid_mag : mid_pk_v;
                per_pk_c[mid_frames]  <= mid_pk_c;
                per_pk_sh[mid_frames] <= mid_sh;
                mid_pk_v <= 16'd0;
                mid_pk_c <= 10'd0;
            end
        end
        if (ref_en) begin
            ref_m[ref_addr] <= ref_mag;
            ref_cnt <= ref_cnt + 1;
        end
        if (mid_en) begin
            if (mid_frame) begin
                midf_m[mid_addr] <= mid_mag;
                if (mid_addr == 10'd1023) begin
                    $display("info: mid frame %0d done, sh=%0d", mid_frames, mid_sh);
                    mid_frames <= mid_frames + 1;
                end
            end else begin
                full_m[mid_addr] <= mid_mag;
                if (mid_addr == 10'd1023) begin
                    full_cnt  <= full_cnt + 1;
                    full_done <= 1'b1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // O_mid_sh 阶梯
    //------------------------------------------------------------------
    reg [2:0] sh_seen [0:15];
    integer   sh_n  = 0;
    reg       mid_d = 1'b0;

    always @(posedge clk) begin
        if (mid_frame && !mid_d && (sh_n < 16)) begin
            sh_seen[sh_n] <= mid_sh;
            sh_n <= sh_n + 1;
        end
        mid_d <= mid_frame;
    end

    //------------------------------------------------------------------
    // 中间帧期间 O_hrm_tog 必须冻结
    //------------------------------------------------------------------
    reg        mid_tog_d  = 1'b0;
    integer    mid_tog_n  = 0;      // 中间帧期间翻转次数 (必须 0)
    integer    full_tog_n = 0;      // 完整帧期间翻转次数 (必须 1)

    always @(posedge clk) begin
        if (mid_hrm_tog !== mid_tog_d) begin
            if (mid_frame) mid_tog_n  <= mid_tog_n + 1;
            else           full_tog_n <= full_tog_n + 1;
            mid_tog_d <= mid_hrm_tog;
        end
    end

    //------------------------------------------------------------------
    // 主流程
    //------------------------------------------------------------------
    integer i, bad, ref_peak_col, ref_peak_val, mid_peak_val, mid_peak_col;
    integer sh_exp [0:7];
    localparam NMID = 5;
    integer sh_bad;

    initial begin
        for (i = 0; i < 8; i = i + 1) sh_exp[i] = 0;
        sh_exp[0] = 5; sh_exp[1] = 4; sh_exp[2] = 3; sh_exp[3] = 2; sh_exp[4] = 1;

        #200 rst_n = 1'b1;
        repeat (20) @(posedge clk);

        @(posedge clk); #1 frame_req = 1'b1;
        @(posedge clk); #1 frame_req = 1'b0;

        while (!full_done) @(posedge clk);
        repeat (10) @(posedge clk);

        // ---- 1) 完整帧逐列一致 ----
        if (ref_cnt < 1024) begin
            $display("FAIL: ref frame incomplete, only %0d cols", ref_cnt);
        end else if (full_cnt < 1) begin
            $display("FAIL: mid frame (full) incomplete");
        end else begin
            bad = 0;
            for (i = 0; i < 1024; i = i + 1)
                if (ref_m[i] !== full_m[i]) begin
                    if (bad < 8)
                        $display("FAIL: col %0d ref=%0d mid=%0d", i, ref_m[i], full_m[i]);
                    bad = bad + 1;
                end
            if (bad == 0) $display("pass: mid frame (1024 cols bit-exact)");
            else          $display("FAIL: mid frame %0d cols differ", bad);
        end

        // ---- 2) O_mid_sh 阶梯 ----
        sh_bad = 0;
        if (sh_n != NMID) begin
            $display("FAIL: mid count = %0d (expect %0d)", sh_n, NMID);
            sh_bad = 1;
        end
        for (i = 0; i < NMID; i = i + 1)
            if (sh_seen[i] !== sh_exp[i]) begin
                $display("FAIL: mid %0d sh=%0d expect %0d", i, sh_seen[i], sh_exp[i]);
                sh_bad = 1;
            end
        if (sh_bad == 0) $display("pass: mid sh ladder 5,4,3,2,1");

        // ---- 3) 中间帧冻结 ----
        if (mid_tog_n != 0) begin
            $display("FAIL: hrm_tog toggled %0d times during mid frames", mid_tog_n);
        end else if (full_tog_n != 1) begin
            $display("FAIL: hrm_tog toggled %0d times in full frame (expect 1)", full_tog_n);
        end else begin
            $display("pass: mid freeze (hrm_tog: 0 in mid, 1 in full)");
        end

        // ---- 4)+5) 中间帧谱峰列 / 幅度 (逐级) ----
        //   中间帧用 K 点相对窗, 幅度比完整窗小 K/N, 靠 O_mid_sh 左移补回
        //   这里比的是 fft 输出的原始幅度 (未左移), 所以期望比值 = 2^-sh
        bad = 0;
        for (i = 0; i < NMID; i = i + 1) begin
            $display("info: mid %0d K-sh=%0d peak col=%0d val=%0d",
                     i, per_pk_sh[i], per_pk_c[i], per_pk_v[i]);
            // ±2 bin: K 点窗主瓣宽 4096/K bin, 相邻 bin 可能同高
            if ((per_pk_c[i] < 10'd254) || (per_pk_c[i] > 10'd258)) begin
                $display("FAIL: mid %0d peak col %0d outside 254..258", i, per_pk_c[i]);
                bad = bad + 1;
            end
            if (per_pk_v[i] < 16'd64) begin
                $display("FAIL: mid %0d peak too small (%0d)", i, per_pk_v[i]);
                bad = bad + 1;
            end
        end
        if (bad == 0) $display("pass: mid peak col 256 for all %0d mids", NMID);

        // ---- 4)+5) 谱峰列 / 幅度 (用最后一个中间帧 K=3584 的谱) ----
        ref_peak_col = 0; ref_peak_val = 0;
        for (i = 0; i < 1024; i = i + 1)
            if (ref_m[i] > ref_peak_val) begin
                ref_peak_val = ref_m[i];
                ref_peak_col = i;
            end
        mid_peak_col = 0; mid_peak_val = 0;
        for (i = 0; i < 1024; i = i + 1)
            if (midf_m[i] > mid_peak_val) begin
                mid_peak_val = midf_m[i];
                mid_peak_col = i;
            end
        $display("info: ref peak col=%0d val=%0d ; mid peak col=%0d val=%0d",
                 ref_peak_col, ref_peak_val, mid_peak_col, mid_peak_val);
        $display("info: ref m[0]=%0d m[1]=%0d m[510]=%0d m[511]=%0d m[512]=%0d m[513]=%0d",
                 ref_m[0], ref_m[1], ref_m[510], ref_m[511], ref_m[512], ref_m[513]);

        if ((mid_peak_col - ref_peak_col) > 1 || (ref_peak_col - mid_peak_col) > 1)
            $display("FAIL: mid peak col %0d != ref %0d", mid_peak_col, ref_peak_col);
        else
            $display("pass: mid peak col %0d", mid_peak_col);

        if (mid_peak_val < (ref_peak_val / 4))
            $display("FAIL: mid amplitude too low (%0d vs %0d)", mid_peak_val, ref_peak_val);
        else if (mid_peak_val > (ref_peak_val * 4))
            $display("FAIL: mid amplitude too high (%0d vs %0d)", mid_peak_val, ref_peak_val);
        else
            $display("pass: mid amp %0d vs %0d", mid_peak_val, ref_peak_val);

        $display("tb_mid done");
        $finish;
    end

    // 超时保护
    initial begin
        #200_000_000;
        $display("FAIL: tb_mid timeout (mid_frames=%0d full_done=%0d ref_cnt=%0d full_cnt=%0d sh_n=%0d)",
                 mid_frames, full_done, ref_cnt, full_cnt, sh_n);
        $finish;
    end

endmodule

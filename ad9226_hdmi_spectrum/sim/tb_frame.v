// ============================================================================
// tb_frame.v  --  把 FFT 算出来的幅度谱灌进 spec_display, 渲染一整帧成 PPM
//
//   数据来自 tb_fft 落盘的 sim/out/mag.txt ("addr mag" 十进制)
//   输出 sim/frames/frame_000.ppm, 再用 tools/ppm2png.py 转 PNG
//
//   用法:  vsim -c -do "run -all; quit -f" tb_frame +SPAN=0 +FRAMES=2
// ============================================================================
`timescale 1ns/1ps

module tb_frame;

    localparam H_RES = 1280;
    localparam V_RES = 720;
    localparam NPIX  = H_RES * V_RES;

    reg clk = 1'b0;
    always #6.734 clk = ~clk;          // 74.25MHz 像素时钟

    reg         rst_n = 1'b0;
    reg  [11:0] x = 12'd0;
    reg  [11:0] y = 12'd0;
    reg  [2:0]  span = 3'd0;

    reg         w_fs = 1'b0;
    reg         w_en = 1'b0;
    reg  [9:0]  w_addr = 10'd0;
    reg  [15:0] w_mag  = 16'd0;

    // 谐波标记: +HRM=列号 (基波列), 缺省 102 (相当于 100kHz @ Span 1MHz)
    reg         hrm_vld = 1'b0;
    reg  [9:0]  hrm_col = 10'd0;
    integer     hrm_arg;

    // 光标: +CSR=列号 (>=0 开启), 负值关闭; +CMODE=1/2 光标模式
    //   增量模式参考列 = 渲染前先模拟 1->2 的模式跳变 (+REFCOL=快照列)
    reg         csr_en = 1'b0;
    reg  [1:0]  csr_mode = 2'd0;
    reg  [9:0]  csr_col = 10'd512;
    integer     csr_arg;
    integer     cmode_arg;

    // 显示模式: +MODE=0(频谱+菜单+瀑布) 1(纯净频谱); 窗: +WIN=0..3
    reg         wf_en = 1'b1;
    reg         menu_hide = 1'b0;
    integer     mode_arg;
    reg  [1:0]  win_v = 2'd0;
    integer     winv_arg;
    integer     wfill_arg;

    wire [7:0]  r, g, b;

    spec_display u_dut (
        .I_pix_clk     (clk     ),
        .I_pix_rst_n   (rst_n   ),
        .I_x           (x       ),
        .I_y           (y       ),
        .I_span        (span    ),
        .I_hrm_valid   (hrm_vld ),
        .I_hrm_col     (hrm_col ),
        .I_hrm_span    (span    ),
        .I_csr_en      (csr_en  ),
        .I_csr_mode    (csr_mode),
        .I_csr_col     (csr_col ),
        .I_wf_en       (wf_en   ),
        .I_menu_hide   (menu_hide),
        .I_win         (win_v   ),
        .I_wr_clk      (clk     ),
        .I_wr_rst_n    (rst_n   ),
        .I_frame_start (w_fs    ),
        .I_wr_en       (w_en    ),
        .I_wr_addr     (w_addr  ),
        .I_wr_mag      (w_mag   ),
        .O_r           (r       ),
        .O_g           (g       ),
        .O_b           (b       )
    );

    //------------------------------------------------------------------
    // 读入 FFT 结果
    //------------------------------------------------------------------
    reg [15:0] magmem [0:1023];
    integer fd, i, a, m, code, nframes, f, p;

    initial begin
        for (i = 0; i < 1024; i = i + 1) magmem[i] = 16'd0;
        fd = $fopen("out/mag.txt", "r");
        if (fd == 0) begin
            $display("ERROR: 找不到 out/mag.txt, 先跑 tb_fft");
            $finish;
        end
        for (i = 0; i < 1024; i = i + 1) begin
            code = $fscanf(fd, "%d %d\n", a, m);
            if (code == 2) magmem[a[9:0]] = m[15:0];
        end
        $fclose(fd);
    end

    // 灌一帧
    task push_frame;
        integer k;
        begin
            @(posedge clk); #1 w_fs = 1'b1;
            @(posedge clk); #1 w_fs = 1'b0;
            for (k = 0; k < 1024; k = k + 1) begin
                @(posedge clk); #1 w_en = 1'b1; w_addr = k[9:0]; w_mag = magmem[k];
            end
            @(posedge clk); #1 w_en = 1'b0;
            repeat (200) @(posedge clk);
        end
    endtask

    integer csr_cols [0:0];
    integer csr_x3, csr_x4;

    // 扫一帧存 PPM
    task scan_frame;
        input integer idx;
        integer fp, q;
        begin
            fp = $fopen($sformatf("frames/frame_%03d.ppm", idx), "wb");
            $fwrite(fp, "P6\n%0d %0d\n255\n", H_RES, V_RES);
            x = 12'd0;
            y = 12'd0;
            for (q = 0; q < NPIX + 8; q = q + 1) begin
                @(posedge clk);
                if (x == H_RES - 1) begin
                    x = 12'd0;
                    y = y + 12'd1;
                end else begin
                    x = x + 12'd1;
                end
                @(negedge clk);
                // PPM[p] = 输入列 p (O_r 滞后 6 拍, 首样本在第 5 次迭代)
                if (q >= 5 && q < NPIX + 5) begin
                    $fwrite(fp, "%c%c%c", r, g, b);
                    if ({r,g,b} == 24'hE8_E8_E8) begin
                        csr_cols[0] = x;                   // 记录光标线所在的 PPM 列
                        csr_x3 = u_dut.x3;  csr_x4 = u_dut.x4;
                    end
                end
            end
            $fclose(fp);
        end
    endtask


    initial begin
        if (!$value$plusargs("SPAN=%d",   span)) span = 3'd0;
        if (!$value$plusargs("FRAMES=%d", nframes)) nframes = 1;
        if (!$value$plusargs("HRM=%d",    hrm_arg)) hrm_arg = 102;
        hrm_col = hrm_arg[9:0];
        hrm_vld = (hrm_arg >= 0);          // +HRM=-1 关闭标记
        if (!$value$plusargs("CSR=%d",    csr_arg)) csr_arg = -1;
        csr_en  = (csr_arg >= 0);
        csr_col = (csr_arg >= 0) ? csr_arg[9:0] : 10'd512;
        if (!$value$plusargs("CMODE=%d", cmode_arg)) cmode_arg = 1;
        csr_mode = cmode_arg[1:0];
        if (!$value$plusargs("MODE=%d",   mode_arg)) mode_arg = 0;
        wf_en     = (mode_arg == 0);
        menu_hide = (mode_arg == 1);
        if (!$value$plusargs("WIN=%d",    winv_arg)) winv_arg = 0;
        win_v = winv_arg[1:0];

        #200 rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // +WFILL=N: 预灌 N 帧瀑布 (不扫描, 只写数据, 约每帧 15us 仿真时间)
        if (!$value$plusargs("WFILL=%d", wfill_arg)) wfill_arg = 0;
        for (f = 0; f < wfill_arg; f = f + 1) push_frame;

        if (csr_mode == 2'd2) begin
            csr_mode = 2'd1;                  // 先普通模式跑两帧 (参考列幅度已知)
        end
        push_frame;               // 第一帧进 bank
        push_frame;               // 第二帧, 显示第一帧
        if (csr_arg >= 0 && cmode_arg == 2) begin
            // 1->2 跳变时参考快照取当前 csr_col; 随后模拟编码器把光标移走
            csr_col = 10'd256;
            #1000 csr_mode = 2'd2;            // 快照参考 = 256
            #1000 csr_col = 10'd358;          // 再移到 358 (ΔF = 102 列)
            #20000;                           // 等 BCD FSM (~40 拍) 完成一次增量转换
        end
        for (f = 0; f < nframes; f = f + 1) scan_frame(f);

        $display("wf probe: wrow=%0d full=%0d mem[peak]=%0d mem[noise]=%0d maxr=%0d cidx=%0d",
                 u_dut.wf_wrow, u_dut.wf_full,
                 u_dut.wf_mem[{3'd3, 8'd64}], u_dut.wf_mem[{3'd3, 8'd0}],
                 u_dut.wf_max_r, u_dut.wf_cidx);
        if (csr_en) begin
            $display("csr probe: csr_mag=%0d freq_val=%0d db_abs=%0d freq_bcd=%h db_bcd=%h",
                     u_dut.csr_mag, u_dut.freq_val, u_dut.db_abs,
                     u_dut.freq_bcd, u_dut.db_bcd);
            $display("csr line: ppm_col=%0d (csr_col=%0d) dut.x3=%0d dut.x4=%0d",
                     csr_cols[0], csr_col, csr_x3, csr_x4);
        $display("delta probe: mode=%0d ref_col=%0d ref_db=%0d cref_v=%b",
                     u_dut.I_csr_mode, u_dut.csr_ref_col, u_dut.csr_ref_db, u_dut.cref_v);
        $display("delta2: csr_col=%0d freq_val=%0d db_abs=%0d signs=%b%b",
                     u_dut.I_csr_col, u_dut.freq_val, u_dut.db_abs,
                     u_dut.dfr_sign, u_dut.ddb_sign);
        end
        $display("tb_frame done");
        $finish;
    end

endmodule

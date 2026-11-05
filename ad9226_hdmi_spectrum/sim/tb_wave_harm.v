// ============================================================================
// tb_wave_harm.v  --  时域谐波视图端到端出图
//
//   ADC 模型 -> ad9226_capture -> wave_cap -> (wave_display 原始波形 RAM)
//                                          -> harm_est -> (harm_ram, 5 lane)
//   渲染一整帧 1280x720 到 frames/wave_harm.ppm, 用于目视核对:
//     - 灰色原始波形
//     - H1..H5 五条彩色分量正弦叠加在同一坐标系
//     - 图例 / V/Div / Zoom / Orig 标签
//
//   用法: vsim -c -do "run -all; quit -f" work.tb_wave_harm
// ============================================================================
`timescale 1ns / 1ps

module tb_wave_harm;

    localparam real T_ADC = 18.518;             // 54MHz
    localparam real T_PIX = 6.734;              // 74.25MHz
    localparam H_RES = 1280, V_RES = 720;
    localparam NPIX = H_RES * V_RES;

    // ---------------- 54MHz 采集域 ----------------
    reg aclk = 1'b0;
    always #(T_ADC/2.0) aclk = ~aclk;

    reg         arst_n = 1'b0;
    reg  [11:0] adc_d  = 12'd2048;
    reg  [2:0]  dec_sel = 3'd0;                 // /27 -> fs = 2 MS/s
    reg         arm = 1'b0;

    wire [15:0] smp;
    wire        smp_en;

    ad9226_capture #(.NLOG(11)) u_cap (
        .I_clk     (aclk    ),
        .I_rst_n   (arst_n  ),
        .I_adc_d   (adc_d   ),
        .I_adc_otr (1'b0    ),
        .I_dec_sel (dec_sel ),
        .I_start   (1'b0    ),
        .O_smp     (smp     ),
        .O_smp_en  (smp_en  ),
        .O_otr     (        )
    );

    wire        wr_start, we, frame_ok;
    wire [9:0]  waddr;
    wire [15:0] wdata;

    wave_cap u_wcap (
        .I_clk       (aclk     ),
        .I_rst_n     (arst_n   ),
        .I_smp       (smp      ),
        .I_smp_en    (smp_en   ),
        .I_arm       (arm      ),
        .I_level     (16'sd0   ),
        .I_edge      (1'b0     ),
        .O_addr      (waddr    ),
        .O_data      (wdata    ),
        .O_we        (we       ),
        .O_wr_start  (wr_start ),
        .O_frame_ok  (frame_ok )
    );

    // ---------------- 谐波估计 (adc 域) ----------------
    // 100kHz @ fs=2MS/s -> bin 204.8 -> 显示列 102
    localparam [9:0] HCOL = 10'd102;

    wire        h_we;
    wire [7:0]  h_addr;
    wire [49:0] h_rows;

    harm_est u_harm (
        .I_clk      (aclk     ),
        .I_rst_n    (arst_n   ),
        .I_wr_en    (we       ),
        .I_wr_addr  (waddr    ),
        .I_wr_data  (wdata    ),
        .I_frame_ok (frame_ok ),
        .I_hcol     (HCOL     ),
        .I_amp      (2'd1     ),
        .O_we       (h_we     ),
        .O_addr     (h_addr   ),
        .O_rows     (h_rows   )
    );

    // ---------------- 像素域 ----------------
    reg pclk = 1'b0;
    always #(T_PIX/2.0) pclk = ~pclk;

    reg  prst_n = 1'b0;
    reg  [11:0] x = 12'd0, y = 12'd0;
    reg  [2:0]  span = 3'd0;

    wire [7:0] r, g, b;

    wave_display u_wdisp (
        .I_pix_clk     (pclk     ),
        .I_pix_rst_n   (prst_n   ),
        .I_x           (x        ),
        .I_y           (y        ),
        .I_span        (span     ),
        .I_amp         (2'd1     ),
        .I_zoom        (2'd0     ),
        .I_orig        (1'b1     ),
        .I_hvalid      (1'b1     ),
        .I_hwe         (h_we     ),
        .I_haddr       (h_addr   ),
        .I_hrows       (h_rows   ),
        .I_wr_clk      (aclk     ),
        .I_wr_rst_n    (arst_n   ),
        .I_frame_start (wr_start ),
        .I_wr_en       (we       ),
        .I_wr_addr     (waddr    ),
        .I_wr_mag      (wdata    ),
        .O_r           (r        ),
        .O_g           (g        ),
        .O_b           (b        )
    );

    // ---------------- ADC 模型 ----------------
    real    wlut [0:4095];
    real    sum;
    integer k;
    reg [31:0] phase_acc, phase_inc;

    initial begin
        for (k = 0; k < 4096; k = k + 1) begin
            sum =  900.0 * $sin(2.0*3.14159265358979*k/4096.0)
                +  360.0 * $sin(2.0*3.14159265358979*k/4096.0*2.0)
                +  300.0 * $sin(2.0*3.14159265358979*k/4096.0*3.0)
                +  140.0 * $sin(2.0*3.14159265358979*k/4096.0*4.0)
                +  180.0 * $sin(2.0*3.14159265358979*k/4096.0*5.0);
            wlut[k] = sum;
        end
        phase_acc = 32'd0;
        phase_inc = $rtoi(100.0e3 / 54.0e6 * 4294967296.0);
    end

    always @(posedge aclk) begin
        phase_acc = phase_acc + phase_inc;
        #1 adc_d = $rtoi(2048.0 + wlut[phase_acc[31:20]]);
    end

    // ---------------- 扫一帧存 PPM ----------------
    task scan_frame;
        input integer idx;
        integer fp, q;
        begin
            fp = $fopen($sformatf("frames/wave_harm_%03d.ppm", idx), "wb");
            $fwrite(fp, "P6\n%0d %0d\n255\n", H_RES, V_RES);
            x = 12'd0;
            y = 12'd0;
            for (q = 0; q < NPIX + 8; q = q + 1) begin
                @(posedge pclk);
                if (x == H_RES - 1) begin
                    x = 12'd0;
                    y = y + 12'd1;
                end else begin
                    x = x + 12'd1;
                end
                @(negedge pclk);
                if (q >= 6 && q < NPIX + 6)
                    $fwrite(fp, "%c%c%c", r, g, b);
                if (y == 12'd300 && x == 12'd300) begin
                    $display("dbg bank wr=%b rd=%b m0[59]=%h m1[59]=%h",
                             u_wdisp.wr_bank, u_wdisp.rd_bank,
                             u_wdisp.u_harm_ram.mem0[59], u_wdisp.u_harm_ram.mem1[59]);
                    $display("dbg m0[0]=%h m1[0]=%h m0[255]=%h m1[255]=%h",
                             u_wdisp.u_harm_ram.mem0[0],   u_wdisp.u_harm_ram.mem1[0],
                             u_wdisp.u_harm_ram.mem0[255], u_wdisp.u_harm_ram.mem1[255]);
                end
                if (y == 12'd150 && x >= 12'd64 && x <= 12'd84)
                    $display("px x=%0d h1=%0d/%0d h5=%0d/%0d hv4=%b hcur1=%0d hnxt1=%0d",
                             x, u_wdisp.hrow4_1, u_wdisp.hprev4_1,
                             u_wdisp.hrow4_5, u_wdisp.hprev4_5, u_wdisp.hv4,
                             u_wdisp.h_cur2[9:0], u_wdisp.h_nxt2[9:0]);
                if (y == 12'd300 && x >= 12'd300 && x <= 12'd303)
                    $display("dbg x=%0d yr=%0d hv4=%b row4=%0d h4_1=%0d h4_2=%0d h4_3=%0d h_cur2=%h h_addr=%0d",
                             x, u_wdisp.yr, u_wdisp.hv4, u_wdisp.row4,
                             u_wdisp.hrow4_1, u_wdisp.hrow4_2, u_wdisp.hrow4_3,
                             u_wdisp.h_cur2, u_wdisp.h_addr);
            end
            $fclose(fp);
        end
    endtask

    // ---------------- 主流程 ----------------
    integer captures;
    integer hcols;

    // 统计 harm_est 写出的列数
    integer fw;
    always @(posedge aclk) begin
        if (arst_n && h_we) begin
            hcols = hcols + 1;
            if (hcols > 256 && h_addr < 20)
                $display("col %0d l1=%0d l2=%0d l3=%0d l5=%0d", h_addr,
                         h_rows[9:0], h_rows[19:10], h_rows[29:20], h_rows[49:40]);
        end
        if (arst_n && we && waddr < 16)
            $display("smp[%0d]=%0d", waddr, $signed(wdata));
    end

    initial begin
        hcols = 0;
        #200 arst_n = 1'b1;
        #200 prst_n = 1'b1;
        repeat (50) @(posedge aclk);

        for (captures = 0; captures < 2; captures = captures + 1) begin
            @(posedge aclk); #1 arm = 1'b1;
            @(posedge aclk); #1 arm = 1'b0;
            while (!frame_ok) @(posedge aclk);
            repeat (10) @(posedge aclk);
            // 等本轮谐波算完 (harm_est 约 2.3 万拍), 否则下一帧的写 bank 会被提前翻转
            while (hcols < 256 * (captures + 1)) @(posedge aclk);
            repeat (10) @(posedge aclk);
        end

        repeat (200) @(posedge aclk);

        if (hcols != 512)
            $display("FAIL: harm 列数 %0d != 512 (2 帧)", hcols);
        else
            $display("pass: harm 列数 512 (2 帧 x 256 列)");

        repeat (20) @(posedge pclk);
        scan_frame(0);
        $display("tb_wave_harm done -> frames/wave_harm_000.ppm");
        $finish;
    end

endmodule

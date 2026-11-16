// ============================================================================
// tb_spec_span.v  --  spec_display 单独渲染, 用于核对新跨度档 (1 kHz / 250 Hz) 的文字
//
//   不接 FFT: 频谱数据全填 "无信号" 电平, 只为看顶栏/横轴/底栏/右侧菜单的字有没有错位。
//   spec_display 是 6 级流水, 所以按光栅连续送像素, 输出再延迟 6 拍落盘。
//   用法: vsim -c -do "run -all; quit -f" tb_spec_span +SPAN=4
//         产出 frames/spec_span_<n>.ppm (再由 tools/ppm2png.py 转 png)
// ============================================================================
`timescale 1ns/1ps

module tb_spec_span;

    localparam integer W = 1280;
    localparam integer H = 720;

    reg pix_clk = 1'b0;
    always #6.7 pix_clk = ~pix_clk;          // ~74.6 MHz

    reg         rst_n = 1'b0;
    reg  [11:0] x = 12'd0, y = 12'd0;
    reg  [2:0]  span = 3'd0;

    // 频谱数据注入 (可选 +PEAK=n: 在 n 列及其 2/3/4/5 次谐波处写峰, 其余写噪底)
    reg         frame_start = 1'b0;
    reg         wr_en = 1'b0;
    reg  [9:0]  wr_addr = 10'd0;
    reg  [15:0] wr_mag = 16'd0;
    integer     peak_col, i_col;
    // 菜单态 (可选 +MENU=n 高亮第 n 项 / +DET= +TRC= +AVG= 设定各项值)
    reg         menu_on = 1'b0;
    reg  [2:0]  menu_sel = 3'd0;
    reg  [1:0]  det_sel = 2'd0, trc_sel = 2'd0;
    reg  [2:0]  avg_sel = 3'd0;
    integer     menu_arg, det_arg, trc_arg, avg_arg;

    wire [7:0] r, g, b;

    spec_display u_dut (
        .I_pix_clk    (pix_clk),
        .I_pix_rst_n  (rst_n  ),
        .I_x          (x      ),
        .I_y          (y      ),
        .I_span       (span   ),
        .I_hrm_valid  (1'b0   ),
        .I_hrm_col    (10'd0  ),
        .I_hrm_span   (span   ),
        .I_csr_en     (1'b0   ),
        .I_csr_mode   (2'd0   ),
        .I_csr_col    (10'd0  ),
        .I_h2         (16'd0  ),
        .I_h3         (16'd0  ),
        .I_h4         (16'd0  ),
        .I_h5         (16'd0  ),
        .I_mid        (1'b0   ),      // 中间帧标记 (本用例只核对跨度文字)
        .I_menu_hide  (1'b0   ),
        .I_win        (2'd0   ),
        .I_fine       (1'b0   ),
        .I_menu_on    (menu_on ),
        .I_menu_sel   (menu_sel),
        .I_det_sel    (det_sel ),
        .I_trc_sel    (trc_sel ),
        .I_avg_sel    (avg_sel ),
        .I_wr_clk     (pix_clk),
        .I_wr_rst_n   (rst_n  ),
        .I_frame_start(frame_start),
        .I_wr_en      (wr_en  ),
        .I_wr_addr    (wr_addr),
        .I_wr_mag     (wr_mag ),
        .O_r          (r      ),
        .O_g          (g      ),
        .O_b          (b      )
    );

    integer fd;
    integer n, total;
    integer sp_arg;
    reg [1023:0] fname;

    // 6 级流水补偿: 把输出打 6 拍再按光栅顺序写文件
    reg [7:0] q_r [0:5];
    reg [7:0] q_g [0:5];
    reg [7:0] q_b [0:5];
    integer   k;

    // 写一整帧: 峰列 peak_col 及 k 次谐波, 其余噪底
    task write_frame;
        begin
            frame_start = 1'b1; #13.4; frame_start = 1'b0; #13.4;
            for (i_col = 0; i_col < 1024; i_col = i_col + 1) begin
                wr_en   = 1'b1;
                wr_addr = i_col[9:0];
                wr_mag  = 16'd200;                        // 噪底约 -50 dBFS
                if (i_col == peak_col)                 wr_mag = 16'd12000;  // -8 dBFS
                if (i_col == peak_col*2 && peak_col*2 < 1024) wr_mag = 16'd5000;
                if (i_col == peak_col*3 && peak_col*3 < 1024) wr_mag = 16'd2400;
                if (i_col == peak_col*4 && peak_col*4 < 1024) wr_mag = 16'd1100;
                if (i_col == peak_col*5 && peak_col*5 < 1024) wr_mag = 16'd700;
                #13.4;
            end
            wr_en = 1'b0;
            #200;
        end
    endtask

    initial begin
        for (k = 0; k < 6; k = k + 1) begin
            q_r[k] = 8'd0; q_g[k] = 8'd0; q_b[k] = 8'd0;
        end
        if (!$value$plusargs("SPAN=%d", sp_arg)) sp_arg = 4;
        span  = sp_arg[2:0];
        if (!$value$plusargs("PEAK=%d", peak_col)) peak_col = -1;
        if ($value$plusargs("MENU=%d", menu_arg)) begin
            menu_on  = 1'b1;
            menu_sel = menu_arg[2:0];
        end
        if (!$value$plusargs("DET=%d", det_arg)) det_arg = 0;
        if (!$value$plusargs("TRC=%d", trc_arg)) trc_arg = 0;
        if (!$value$plusargs("AVG=%d", avg_arg)) avg_arg = 0;
        det_sel = det_arg[1:0];
        trc_sel = trc_arg[1:0];
        avg_sel = avg_arg[2:0];
        total = W * H;

        $sformat(fname, "frames/spec_span_%0d.ppm", sp_arg);
        fd = $fopen(fname, "wb");
        $fwrite(fd, "P6\n%0d %0d\n255\n", W, H);

        #100 rst_n = 1'b1;
        #100;

        if (peak_col >= 0) begin
            write_frame;      // 第一轮: 切 bank 并写入
            write_frame;      // 第二轮: 显示侧读的是上一帧的 bank
        end

        for (n = 0; n < total + 6; n = n + 1) begin
            // +4: 抵消流水/拍照错位 (实测渲染整体右移 4 像素)
            x = ((n + 4) % W);
            y = ((n + 4) / W);
            #13.4;                            // 一个像素时钟
            for (k = 5; k > 0; k = k - 1) begin
                q_r[k] = q_r[k-1]; q_g[k] = q_g[k-1]; q_b[k] = q_b[k-1];
            end
            q_r[0] = r; q_g[0] = g; q_b[0] = b;
            if (n >= 6) $fwrite(fd, "%c%c%c", q_r[5], q_g[5], q_b[5]);
        end

        $fclose(fd);
        $display("tb_spec_span done span=%0d -> %0s", span, fname);
        $finish;
    end

endmodule

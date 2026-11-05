// ============================================================================
// tb_wave_syn.v  --  时域谐波视图: 合成激励出图 (只测 wave_display 渲染)
//
//   直接按列写入 5 条谐波的行值 (跳过 harm_est 的估计/合成, 那部分由 tb_harm
//   做数值验证), 用来单独核对:
//     - 5 条彩色迹线是否画在正确行
//     - 1/2/4 px 粗线 + 列间竖直连线
//     - 图例 / V/Div / Zoom / Orig 标签
//   输出 frames/wave_syn_000.ppm
// ============================================================================
`timescale 1ns / 1ps

module tb_wave_syn;

    localparam real T_ADC = 18.518;
    localparam real T_PIX = 6.734;
    localparam H_RES = 1280, V_RES = 720;
    localparam NPIX = H_RES * V_RES;

    reg aclk = 1'b0;
    always #(T_ADC/2.0) aclk = ~aclk;

    reg aclk_rst_n = 1'b0;

    reg pclk = 1'b0;
    always #(T_PIX/2.0) pclk = ~pclk;

    reg  prst_n = 1'b0;
    reg  [11:0] x = 12'd0, y = 12'd0;

    wire [7:0] r, g, b;

    // 谐波行值激励 (adc 域写)
    reg         h_we = 1'b0;
    reg  [7:0]  h_addr = 8'd0;
    reg  [49:0] h_rows = 50'd0;

    // 原始波形记录
    reg         we = 1'b0;
    reg  [9:0]  waddr = 10'd0;
    reg  [15:0] wdata = 16'd0;
    reg         wr_start = 1'b0;

    wave_display u_wdisp (
        .I_pix_clk     (pclk     ),
        .I_pix_rst_n   (prst_n   ),
        .I_x           (x        ),
        .I_y           (y        ),
        .I_span        (3'd0     ),
        .I_amp         (2'd1     ),
        .I_zoom        (2'd0     ),
        .I_orig        (1'b1     ),
        .I_hvalid      (1'b1     ),
        .I_hwe         (h_we     ),
        .I_haddr       (h_addr   ),
        .I_hrows       (h_rows   ),
        .I_wr_clk      (aclk     ),
        .I_wr_rst_n    (aclk_rst_n),
        .I_frame_start (wr_start ),
        .I_wr_en       (we       ),
        .I_wr_addr     (waddr    ),
        .I_wr_mag      (wdata    ),
        .O_r           (r        ),
        .O_g           (g        ),
        .O_b           (b        )
    );

    //------------------------------------------------------------------
    // 生成 5 条谐波 (1..5 次, 幅度递减) 的列行值
    //------------------------------------------------------------------
    integer n;
    real    th, s;
    integer row1, row2, row3, row4, row5;
    reg [9:0] r1, r2, r3, r4, r5;

    task gen_col;
        input integer c;
        begin
            th = 2.0 * 3.14159265358979 * c / 20.0;   // 20 列一个基波周期
            s = $sin(th);
            row1 = 256 + $rtoi( 90.0 * $sin(th));
            row2 = 256 + $rtoi( 55.0 * $sin(2.0*th));
            row3 = 256 + $rtoi( 35.0 * $sin(3.0*th));
            row4 = 256 + $rtoi( 22.0 * $sin(4.0*th));
            row5 = 256 + $rtoi( 14.0 * $sin(5.0*th));
            r1 = row1[9:0]; r2 = row2[9:0]; r3 = row3[9:0];
            r4 = row4[9:0]; r5 = row5[9:0];
        end
    endtask

    //------------------------------------------------------------------
    // 扫一帧存 PPM
    //------------------------------------------------------------------
    task scan_frame;
        integer fp, q;
        begin
            fp = $fopen("frames/wave_syn_000.ppm", "wb");
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
                if (y == 12'd150 && x >= 12'd64 && x <= 12'd76)
                    $display("px x=%0d addr=%0d ram1=%0d cur1=%0d nxt1=%0d rows=%0d/%0d/%0d/%0d/%0d prev=%0d/%0d/%0d/%0d/%0d",
                             x, u_wdisp.h_addr, u_wdisp.h_ram[9:0],
                             u_wdisp.h_cur2[9:0], u_wdisp.h_nxt2[9:0],
                             u_wdisp.hrow4_1, u_wdisp.hrow4_2, u_wdisp.hrow4_3,
                             u_wdisp.hrow4_4, u_wdisp.hrow4_5,
                             u_wdisp.hprev4_1, u_wdisp.hprev4_2, u_wdisp.hprev4_3,
                             u_wdisp.hprev4_4, u_wdisp.hprev4_5);
            end
            $fclose(fp);
        end
    endtask

    integer round;
    initial begin
        #200 aclk_rst_n = 1'b1;
        #200 prst_n = 1'b1;
        repeat (20) @(posedge aclk);

        // 乒乓: 显示侧读"上一帧"的 bank, 所以要写两轮同样的内容
        for (round = 0; round < 2; round = round + 1) begin
            @(posedge aclk); #1 wr_start = 1'b1;
            @(posedge aclk); #1 wr_start = 1'b0;

            // 原始波形: 1024 点
            for (n = 0; n < 1024; n = n + 1) begin
                @(posedge aclk);
                #1 we = 1'b1;
                waddr = n[9:0];
                th = 2.0 * 3.14159265358979 * n / 20.0;
                s  = 90.0*$sin(th) + 55.0*$sin(2.0*th) + 35.0*$sin(3.0*th)
                   + 22.0*$sin(4.0*th) + 14.0*$sin(5.0*th);
                wdata = $rtoi(s * 128.0);            // 行值 -> Q4 幅度单位
            end
            @(posedge aclk); #1 we = 1'b0;

            // 5 条谐波行值 (256 列)
            for (n = 0; n < 256; n = n + 1) begin
                @(posedge aclk);
                #1 h_we = 1'b1;
                h_addr = n[7:0];
                gen_col(n);
                h_rows = {r5, r4, r3, r2, r1};
            end
            @(posedge aclk); #1 h_we = 1'b0;
            repeat (10) @(posedge aclk);
        end

        repeat (200) @(posedge aclk);
        repeat (20)  @(posedge pclk);
        scan_frame;
        $display("tb_wave_syn done -> frames/wave_syn_000.ppm");
        $finish;
    end

endmodule

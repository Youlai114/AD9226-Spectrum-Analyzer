// ============================================================================
// tb_spec_display.v  --  频谱界面离线渲染测试台
//
//   不依赖 HDMI / PLL, 直接把一帧像素扫一遍, 输出 frame.ppm (P6) 便于查看界面。
//   用法 (ModelSim):
//       vlib work
//       vlog ../src/*.v tb_spec_display.v
//       vsim -c -do "run -all; quit" tb_spec_display
//   然后把 frame.ppm 转成 png 查看。
// ============================================================================
`timescale 1ns/1ps

module tb_spec_display;

    localparam H_RES = 1280;
    localparam V_RES = 720;
    localparam NPIX  = H_RES * V_RES;

    reg clk = 1'b0;
    always #6.734 clk = ~clk;          // 74.25MHz

    reg         rst_n = 1'b0;
    reg  [11:0] x = 12'd0;
    reg  [11:0] y = 12'd0;
    reg  [1:0]  mode = 2'd0;

    reg         frame_start = 1'b0;
    reg         wr_en       = 1'b0;
    reg  [9:0]  wr_addr     = 10'd0;
    reg  [15:0] wr_mag      = 16'd0;

    wire [7:0]  r, g, b;

    spec_display u_dut (
        .I_pix_clk     (clk         ),
        .I_pix_rst_n   (rst_n       ),
        .I_x           (x           ),
        .I_y           (y           ),
        .I_span       (mode        ),
        .I_wr_clk      (clk         ),
        .I_wr_rst_n    (rst_n       ),
        .I_frame_start (frame_start ),
        .I_wr_en       (wr_en       ),
        .I_wr_addr     (wr_addr     ),
        .I_wr_mag      (wr_mag      ),
        .O_r           (r           ),
        .O_g           (g           ),
        .O_b           (b           )
    );

    // 合成频谱: 噪声底 + 3 个峰
    // 12bit 幅度模型, 输出时左移 4 位映射到 16bit 满量程
    function [15:0] magf;
        input integer i;
        integer d;
        reg [11:0] m;
        begin
            m = 12'd40 + ((i * 37) % 50);
            d = i - 300; if (d < 0) d = -d;
            if (d < 94) m = m + (12'd3000 - d * 32);
            d = i - 620; if (d < 0) d = -d;
            if (d < 68) m = m + (12'd2200 - d * 32);
            d = i - 820; if (d < 0) d = -d;
            if (d < 81) m = m + (12'd2600 - d * 32);
            if (m > 12'd4095) m = 12'd4095;
            magf = {m, 4'd0};
        end
    endfunction

    integer fd;
    integer i, p, f;
    integer pass;

    initial begin
        if (!$value$plusargs("SPAN=%d", mode)) mode = 2'd0;

        fd = $fopen("frame.ppm", "wb");
        if (fd == 0) begin
            $display("ERROR: cannot open frame.ppm");
            $finish;
        end
        $fwrite(fd, "P6\n%0d %0d\n255\n", H_RES, V_RES);

        #200 rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ---- 写 2 帧数据 (乒乓需要 2 帧) ----
        for (f = 0; f < 2; f = f + 1) begin
            @(posedge clk);
            frame_start = 1'b1;
            @(posedge clk);
            frame_start = 1'b0;
            for (i = 0; i < 1024; i = i + 1) begin
                @(posedge clk);
                wr_en   = 1'b1;
                wr_addr = i[9:0];
                wr_mag  = magf(i);
            end
            @(posedge clk);
            wr_en = 1'b0;
            repeat (8) @(posedge clk);
        end

        repeat (10) @(posedge clk);

        // ---- 扫描 2 帧: 第 1 帧填满峰值保持存储, 第 2 帧写入文件 ----
        for (pass = 0; pass < 2; pass = pass + 1) begin
            for (p = 0; p < NPIX + 8; p = p + 1) begin
                @(posedge clk);
                x = (p < NPIX) ? (p % H_RES) : 12'd0;
                y = (p < NPIX) ? (p / H_RES) : 12'd0;
                @(negedge clk);
                if (pass == 1 && p >= 6 && p < NPIX + 6)
                    $fwrite(fd, "%c%c%c", r, g, b);
            end
        end

        $fclose(fd);
        $display("done: frame.ppm written, span=%0d", mode);
        $finish;
    end

endmodule

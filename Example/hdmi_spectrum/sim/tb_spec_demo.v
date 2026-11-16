// ============================================================================
// tb_spec_demo.v  --  频谱动画测试台 (演示数据源 + 显示 全链路)
//
//   把 spec_demo_gen 的实时输出直接接到 spec_display, 连续渲染 N 帧并存成
//   frames/frame_XXX.ppm, 用来观察频谱随时间的动态效果。
//
//   用法 (ModelSim):
//       vsim -c -do "run -all; quit -f" tb_spec_demo +FRAMES=16 +TICKS=8 +SPAN=0
//       +FRAMES 渲染帧数, +TICKS 每渲染帧之间推进多少个数据帧, +MODE 显示模式
// ============================================================================
`timescale 1ns/1ps

module tb_spec_demo;

    localparam H_RES = 1280;
    localparam V_RES = 720;
    localparam NPIX  = H_RES * V_RES;

    reg clk = 1'b0;
    always #6.734 clk = ~clk;          // 74.25MHz

    reg         rst_n = 1'b0;
    reg  [11:0] x = 12'd0;
    reg  [11:0] y = 12'd0;
    reg  [1:0]  mode = 2'd0;
    reg         frame_tick = 1'b0;

    wire        demo_fs, demo_we;
    wire [9:0]  demo_wa;
    wire [15:0] demo_wm;

    wire [7:0]  r, g, b;

    // ---- 数据源 (与上板时一致): 默认单音正弦, +define+DEMO_SWEEP 换成多峰扫频 ----
`ifdef DEMO_SWEEP
    spec_demo_gen u_demo (
        .I_clk         (clk       ),
        .I_rst_n       (rst_n     ),
        .I_frame_tick  (frame_tick),
        .O_frame_start (demo_fs   ),
        .O_wr_en       (demo_we   ),
        .O_wr_addr     (demo_wa   ),
        .O_wr_mag      (demo_wm   )
    );
`else
    spec_tone_gen u_tone (
        .I_clk         (clk       ),
        .I_rst_n       (rst_n     ),
        .I_span        (mode      ),
        .I_frame_tick  (frame_tick),
        .O_frame_start (demo_fs   ),
        .O_wr_en       (demo_we   ),
        .O_wr_addr     (demo_wa   ),
        .O_wr_mag      (demo_wm   )
    );
`endif

    // ---- 频谱显示 ----
    spec_display u_dut (
        .I_pix_clk     (clk       ),
        .I_pix_rst_n   (rst_n     ),
        .I_x           (x         ),
        .I_y           (y         ),
        .I_span        (mode      ),
        .I_wr_clk      (clk       ),
        .I_wr_rst_n    (rst_n     ),
        .I_frame_start (demo_fs   ),
        .I_wr_en       (demo_we   ),
        .I_wr_addr     (demo_wa   ),
        .I_wr_mag      (demo_wm   ),
        .O_r           (r         ),
        .O_g           (g         ),
        .O_b           (b         )
    );

    integer fd;
    integer p, f, k;
    integer nframes, nticks;

    // 推进一帧数据 (给演示源一个 frame_tick, 等它写完 1024 点)
    task tick_demo;
        begin
            @(posedge clk);
            frame_tick = 1'b1;
            @(posedge clk);
            frame_tick = 1'b0;
            repeat (1080) @(posedge clk);
        end
    endtask

    // 扫描一帧并写 PPM
    task scan_frame;
        input integer idx;
        begin
            fd = $fopen($sformatf("frames/m%0d/frame_%03d.ppm", mode, idx), "wb");
            $fwrite(fd, "P6\n%0d %0d\n255\n", H_RES, V_RES);
            x = 12'd0;
            y = 12'd0;
            for (p = 0; p < NPIX + 8; p = p + 1) begin
                @(posedge clk);
                if (x == H_RES - 1) begin
                    x = 12'd0;
                    y = y + 12'd1;
                end else begin
                    x = x + 12'd1;
                end
                @(negedge clk);
                if (p >= 6 && p < NPIX + 6)
                    $fwrite(fd, "%c%c%c", r, g, b);
            end
            $fclose(fd);
        end
    endtask

    initial begin
        if (!$value$plusargs("FRAMES=%d", nframes)) nframes = 12;
        if (!$value$plusargs("TICKS=%d",  nticks )) nticks  = 8;
        if (!$value$plusargs("SPAN=%d",  mode   )) mode    = 2'd0;

        #200 rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // 先灌 2 帧, 让乒乓缓存里有数据
        tick_demo;
        tick_demo;

        for (f = 0; f < nframes; f = f + 1) begin
            scan_frame(f);
            for (k = 0; k < nticks; k = k + 1)
                tick_demo;
        end

        $display("done: %0d frames, span=%0d", nframes, mode);
        $finish;
    end

endmodule

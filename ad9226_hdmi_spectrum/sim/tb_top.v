// ============================================================================
// tb_top.v  --  顶层联调仿真: video_top 全链路 (真实三时钟域)
//
//   27MHz 晶振 -> rPLL 桩 -> 54MHz (ADC+FFT 域) / 371.25+CLKDIV -> 74.25MHz 像素域
//   ADC 模型: f0 基波 + 2~5 次谐波 (+F0=Hz 可调, 缺省 100kHz)
//
//   流程 (+AUTO 时):
//     帧 0..3   : 预热 (FFT 出谱, 基波检测稳定)
//     ~60ms     : 按 KEY3 = AUTO, 期望按 5*f0<=0.92*Span 选最窄跨度
//     帧 5      : 落盘 AUTO 后的频谱视图              -> frames/top_005.ppm
//     帧 8      : 落盘 KEY2 切换后的时域波形视图       -> frames/top_008.ppm
//     结束      : 断言 span == AUTO 期望值
//   不加 +AUTO: 85ms 落盘帧 4 (频谱) / 150ms 落盘帧 8 (波形), 同旧版
//
//   用法: vsim -c -do "run -all; quit -f" tb_top +DUMP1=5 +DUMP2=8 +F0=20000 +AUTO
// ============================================================================
`timescale 1ns/1ps

module tb_top;

    localparam real T27 = 18.519;

    // ---------------- 27MHz 晶振 ----------------
    reg clk27 = 1'b0;
    always #(T27/2.0) clk27 = ~clk27;

    reg        rst     = 1'b1;      // 高有效 (引脚 88)
    reg  [4:0] key     = 5'h1F;     // 低有效
    reg        enc_a   = 1'b1;
    reg        enc_b   = 1'b1;
    reg        enc_sw  = 1'b1;
    wire [1:0] led;

    wire       tmds_clk_p, tmds_clk_n;
    wire [2:0] tmds_data_p, tmds_data_n;

    wire       clk_adc;             // 54MHz -> AD9226
    reg [11:0] adc_d  = 12'd2048;
    reg        adc_otr = 1'b0;

    video_top u_top (
        .I_clk         (clk27       ),
        .I_rst         (rst         ),
        .I_key         (key         ),
        .I_enc_a       (enc_a       ),
        .I_enc_b       (enc_b       ),
        .I_enc_sw      (enc_sw      ),
        .O_led         (led         ),
        .O_tmds_clk_p  (tmds_clk_p  ),
        .O_tmds_clk_n  (tmds_clk_n  ),
        .O_tmds_data_p (tmds_data_p ),
        .O_tmds_data_n (tmds_data_n ),
        .O_clk_adc     (clk_adc     ),
        .I_adc_d       (adc_d       ),
        .I_adc_otr     (adc_otr     )
    );

    //------------------------------------------------------------------
    // AD9226 行为模型: clk_adc 上升沿后 1ns 更新 (模拟 tPD, 避免抢沿)
    //   f0 基波 (+F0 可调) + 2~5 次谐波
    //------------------------------------------------------------------
    real    wlut [0:4095];
    real    sum;
    integer k;
    integer f0_hz;
    reg [31:0] phase_acc, phase_inc;

    initial begin
        for (k = 0; k < 4096; k = k + 1) begin
            sum = 1300.0 * $sin(2.0*3.14159265358979*k/4096.0)
                +  320.0 * $sin(2.0*3.14159265358979*k/4096.0*2.0)
                +  160.0 * $sin(2.0*3.14159265358979*k/4096.0*3.0)
                +   80.0 * $sin(2.0*3.14159265358979*k/4096.0*4.0)
                +   50.0 * $sin(2.0*3.14159265358979*k/4096.0*5.0);
            wlut[k] = sum;
        end
        if (!$value$plusargs("F0=%d", f0_hz)) f0_hz = 100000;
        phase_acc = 32'd0;
        phase_inc = $rtoi(f0_hz / 54.0e6 * 4294967296.0);
    end

    always @(posedge clk_adc) begin
        phase_acc = phase_acc + phase_inc;
        #1 adc_d = $rtoi(2048.0 + wlut[phase_acc[31:20]]);
    end

    // span 变化监视
    always @(u_top.span)
        $display("[t=%0t us] span -> %0d", $time/1000, u_top.span);

    //------------------------------------------------------------------
    // 主流程
    //------------------------------------------------------------------
    task press_key;
        input integer idx;
        begin
            key[idx] = 1'b0;
            #20_000_000;              // 按住 20ms (> 8ms 消抖)
            key[idx] = 1'b1;
            #15_000_000;              // 松开等恢复
        end
    endtask

    reg do_auto;
    reg do_wkey;
    reg do_long;
    integer exp_span;

    initial begin
        do_auto  = $test$plusargs("AUTO");
        do_wkey  = $test$plusargs("WKEY");
        do_long  = $test$plusargs("LONG");

        #2000 rst = 1'b0;             // 2us 后释放复位 (PLL 已锁)

        if (do_long) begin
            // 视频平均收敛验证: 跑 ~45 帧, 帧 4 (初始) 与帧 45 (~94% 收敛) 落盘
            #330_000_000;
        end else if (do_wkey) begin
            // 帧 0..3 预热; 60ms 按 KEY5 两下: Hann->Rect->Black; 断言 win=2
            #60_000_000;
            press_key(4);             // -> Rect
            press_key(4);             // -> Black
            #5_000_000;               // 等新窗频谱稳定 1-2 帧
            if (u_top.win !== 2'd2)
                $display("FAIL: win=%0d, 期望 2 (Blackman)", u_top.win);
            else
                $display("pass: win=2 (Blackman), span=%0d (KEY5 不动跨度)", u_top.span);
            if (u_top.span !== 3'd0)
                $display("FAIL: KEY5 误改跨度 span=%0d", u_top.span);
            #55_000_000;              // 帧 8 落盘 Blackman 频谱
        end else if (do_auto) begin
            // 帧 0..3 预热; 60ms 按 KEY3=AUTO (基波检测已稳定)
            #60_000_000;
            press_key(2);             // t=95ms 时 span 已切换
            #5_000_000;               // t=100ms, 等 AUTO 后的频谱稳定 1-2 帧
            press_key(1);             // 再按 KEY2 切时域视图 (新档 fs 下重新触发)
            #30_000_000;              // 帧 6 (AUTO 后频谱) / 帧 8 (波形) 已落盘
        end else begin
            #83_000_000;              // 帧 4 (83.5ms 结束) 落盘频谱视图
            press_key(1);             // KEY2 切时域视图
            #40_000_000;              // 帧 8 (150ms 结束) 落盘波形视图
        end

        // ---- AUTO 断言: 与 auto_span.v 同一套阈值 ----
        if (do_auto) begin
            if (f0_hz <= 1841)             exp_span = 3;
            else if (f0_hz <= 9200)        exp_span = 2;
            else if (f0_hz <= 46000)       exp_span = 1;
            else                           exp_span = 0;
            if (u_top.span !== exp_span[1:0])
                $display("FAIL: AUTO span=%0d, 期望 %0d (f0=%0d Hz)",
                         u_top.span, exp_span, f0_hz);
            else
                $display("pass: AUTO span=%0d (f0=%0d Hz)", u_top.span, f0_hz);
        end

        $display("tb_top done");
        $finish;
    end

endmodule

// ============================================================================
// ad9226_capture.v  --  AD9226 并行采样前端 (Tang Nano 20K)
//
//   原例程 (AD9226_FPGA_V1.1_65M/rtl/AD9220_ReadModule.V, Altera EP4CE15):
//     用 260MHz 时钟四分频得到 65MHz 送 AD9226 的 CLK, 在 clk_driver 上升沿
//     把 13 位数据 (12bit + OTR) 锁进 FPGA。本质是"用高频时钟凑低频时钟",
//     依赖 260/4 这个特定关系, 输出时钟还是 fabric 打拍出来的。
//
//   本文件的改法 (适配 GW2AR-18, 测 0 ~ 1 MHz 低频信号):
//     1) 采样时钟直接来自 PLL 的 CLKOUT (54MHz), assign 到管脚, 不经过 fabric 分频;
//     2) 数据在同一个 54MHz 沿锁存, AD9226 在 CLK 上升沿后 tco+tPD (约 8~10ns)
//        才更新数据, FPGA 在"下一个"上升沿采样 -> setup 余量约 10ns, 可被 STA 证实;
//     3) 频段切换 = 改数字抽取比, ADC 时钟永远 54MHz:
//          抽取 27 / 108 / 540 / 2700 / 27000 / 108000
//            ->  fs = 2.000 M / 500 k / 100 k / 20 k / 2 k / 500 Hz
//          宽频档 = 1(直采 54 MSPS)
//          显示跨度 fs/2       ->  1.000 / 0.500 / 0.250 MHz
//        这样不会出现"分频时钟上时钟树""切档瞬间产生短脉冲"的问题。
//
//   为什么不用 2 的幂抽取: 54/32 = 1.6875 MHz, 跨度 843.75 kHz,
//   屏幕上频率刻度会变成一串小数; 27 抽 1 正好 2.000 MHz。
//
//   除以 27/54/108 用"乘 Q16 倒数 + 右移 16", 增益误差 < 0.03% (0.003 dB):
//     1/27 -> 2427/65536      1/54 -> 1214/65536      1/108 -> 607/65536
//
//   数据格式: 12bit 无符号 (0..4095, 中间刻度 2048)
//             -> 16bit 有符号并左对齐 4 位 (Q4), 即 (adc-2048)*16 = +-32768
//
//   ★ 抽取是滑动平均 (boxcar), 有真实的幅度倾斜: 带边 (Nyquist) 处约 -3.9 dB
//     (抽 27)。这是物理后果不是 bug, 详见 doc 第 6 节。
// ============================================================================
module ad9226_capture #(
    parameter NLOG = 12                       // 2^12 = 4096 点
)(
    input             I_clk,        // 54MHz, 同时是 AD9226 的 CLK
    input             I_rst_n,

    input      [11:0] I_adc_d,      // AD9226 D0..D11
    input             I_adc_otr,    // AD9226 OTR (过压标志, 高有效)

    input      [3:0]  I_dec_sel,    // 0:/27(2M) 1:/108(500k) 2:/540(100k) 3:/2700(20k)
                                    // 4:/27000(2k) 5:/108000(500) 6:/1(54M) 7:/54(1M)
                                    // 8:/270(200k) 9:/10(5.4M) 10:/5(10.8M) 11:/2(27M)
    input             I_start,      // 单拍: 开始采集一帧

    output reg [15:0] O_smp,        // 有符号, Q4
    output reg        O_smp_en,     // 样点有效 (fs = 54MHz / 抽取比)
    output reg        O_otr         // 本帧内是否发生过 OTR (粘滞)
);

    //------------------------------------------------------------------
    // 输入打拍 (FF 直接放在 IO 上, 由 .sdc 的 set_input_delay 约束)
    //------------------------------------------------------------------
    reg [12:0] adc_r;                       // {OTR, D11..D0}

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) adc_r <= 13'd0;
        else          adc_r <= {I_adc_otr, I_adc_d};
    end

    // 12bit 无符号 -> 13bit 有符号 (减中间刻度)
    wire signed [12:0] x_s = $signed({1'b0, adc_r[11:0]}) - 13'sd2048;

    //------------------------------------------------------------------
    // 抽取比与 Q16 倒数 (Q16 里放的是 16/dec, 直接给出 Q4 输出)
    //   dec=4 (直采): 不经乘法, sum_l(=本拍样点) 直接 <<4
    //------------------------------------------------------------------
    //   ★ 深抽取 (27e3 / 108e3) 用 2^20 刻度, 结果右移 24 位; 其余用 2^16 刻度右移 20 位
    //     否则 16/108000 只有 10 这个整数可用, 增益误差 3%(0.26 dB)
    wire [17:0] dec_n = (I_dec_sel == 4'd0)  ? 18'd27     :
                        (I_dec_sel == 4'd1)  ? 18'd135    :
                        (I_dec_sel == 4'd2)  ? 18'd540    :
                        (I_dec_sel == 4'd3)  ? 18'd2700   :
                        (I_dec_sel == 4'd4)  ? 18'd27000  :
                        (I_dec_sel == 4'd5)  ? 18'd135000 :
                        (I_dec_sel == 4'd7)  ? 18'd54     :
                        (I_dec_sel == 4'd8)  ? 18'd270    :
                        (I_dec_sel == 4'd9)  ? 18'd10     :
                        (I_dec_sel == 4'd10) ? 18'd5      :
                        (I_dec_sel == 4'd11) ? 18'd2      :
                        (I_dec_sel == 4'd12) ? 18'd1350   :
                        (I_dec_sel == 4'd13) ? 18'd5400   :
                        (I_dec_sel == 4'd14) ? 18'd13500  :
                        (I_dec_sel == 4'd15) ? 18'd54000  : 18'd1;
    wire [15:0] inv_n = (I_dec_sel == 4'd0)  ? 16'd38836 :
                        (I_dec_sel == 4'd1)  ? 16'd7767  :   // 2^16*16/135
                        (I_dec_sel == 4'd2)  ? 16'd1942  :
                        (I_dec_sel == 4'd3)  ? 16'd388   :
                        (I_dec_sel == 4'd4)  ? 16'd621   :   // 2^20*16/27000
                        (I_dec_sel == 4'd5)  ? 16'd124   :   // 2^20*16/135000
                        (I_dec_sel == 4'd7)  ? 16'd19418 :   // 2^16*16/54
                        (I_dec_sel == 4'd8)  ? 16'd3884  :   // 2^16*16/270
                        (I_dec_sel == 4'd9)  ? 16'd26214 :   // 2^14*16/10
                        (I_dec_sel == 4'd10) ? 16'd52429 :   // 2^14*16/5
                        (I_dec_sel == 4'd12) ? 16'd777   :   // 2^16*16/1350
                        (I_dec_sel == 4'd13) ? 16'd3107  :   // 2^20*16/5400
                        (I_dec_sel == 4'd14) ? 16'd1243  :   // 2^20*16/13500
                        (I_dec_sel == 4'd15) ? 16'd311   :   // 2^20*16/54000
                                               16'd65535;
    wire        dec_hi  = (I_dec_sel == 4'd4) || (I_dec_sel == 4'd5) ||
                          (I_dec_sel == 4'd13) || (I_dec_sel == 4'd14) || (I_dec_sel == 4'd15); // 右移 24
    wire        dec_lo  = (I_dec_sel == 4'd9) || (I_dec_sel == 4'd10); // 浅抽取: 右移 14
    wire        dec_div2= (I_dec_sel == 4'd11);                        // /2: 直接左移 3

    reg  [17:0]        dec_cnt;
    reg  signed [29:0] acc;                 // 最多 135000 x 2048 = 2.76e8 < 2^29
    reg  signed [29:0] sum_l;               // 累加和 (打一拍)
    reg  signed [29:0] sum_l_d;             // sum_l 再打一拍 (直采路径对齐乘法路径延迟)
    reg  signed [45:0] mul;                 // 乘倒数 (30bit x 16bit)
    reg                en1, en2;

    wire signed [30:0] sum_now  = acc + x_s;
    wire               take_now = (dec_cnt == dec_n - 18'd1);
    wire               dec_raw  = (I_dec_sel == 4'd6);      // 宽频档 54 MSPS 直采
    // 第 3 级取增益: 深抽取走 mul[39:24], 浅抽取走 mul[33:18], 其余走 mul[35:20]
    wire        [15:0] gain_q4  = dec_hi ? mul[39:24] :
                                  dec_lo ? mul[33:18] : mul[35:20];

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            dec_cnt  <= 18'd0;
            acc      <= 30'sd0;
            sum_l    <= 30'sd0;
            sum_l_d  <= 30'sd0;
            mul      <= 46'sd0;
            en1      <= 1'b0;
            en2      <= 1'b0;
            O_smp    <= 16'sd0;
            O_smp_en <= 1'b0;
        end else if (I_start) begin
            dec_cnt  <= 18'd0;
            acc      <= 30'sd0;
            en1      <= 1'b0;
            en2      <= 1'b0;
            O_smp_en <= 1'b0;
        end else begin
            // 第 1 级: 累加 / 出和
            if (take_now) begin
                dec_cnt <= 18'd0;
                acc     <= 30'sd0;
                sum_l   <= sum_now[29:0];
                en1     <= 1'b1;
            end else begin
                dec_cnt <= dec_cnt + 18'd1;
                acc     <= sum_now[29:0];
                en1     <= 1'b0;
            end

            // 第 2 级: 乘倒数 (等价于除以抽取比); 直采路径同步延迟一拍
            mul     <= sum_l * $signed({1'b0, inv_n});
            sum_l_d <= sum_l;
            en2     <= en1;

            // 第 3 级: 还原幅度并对齐到 Q4; 直采与 /2 直接移位对齐
            O_smp    <= dec_raw  ? ($signed(sum_l_d[12:0]) <<< 4) :
                        dec_div2 ? ($signed(sum_l_d[13:0]) <<< 3) :
                                   ($signed(gain_q4) <<< 4);
            O_smp_en <= en2;
        end
    end

    //------------------------------------------------------------------
    // OTR 粘滞 (每帧清零, 用于板上 LED 提示过载)
    //------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)       O_otr <= 1'b0;
        else if (I_start)   O_otr <= 1'b0;
        else if (adc_r[12]) O_otr <= 1'b1;
    end

endmodule

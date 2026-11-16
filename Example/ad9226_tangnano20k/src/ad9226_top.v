// ============================================================================
// ad9226_top.v  --  AD9226 采集测试顶层 (Tang Nano 20K / GW2AR-18C)
//
//   板载 50MHz 晶振 -> PLL 130MHz -> 2 分频 65MHz 驱动 AD9226
//   采样数据经峰值保持显示到板载 LED (低电平点亮):
//     LED 全灭       : 无信号 (输入接地或直流 0 附近)
//     点亮个数越多   : 信号峰值幅度越大 (每颗 LED 约 3dB / 128 码值)
//     LED5 常亮      : OTR 过压 (输入超出 AD9226 量程)
//
//   采样率 65 MSPS, 与原例程 (AD9226_FPGA_V1.1_65M) 一致
// ============================================================================
module ad9226_top (
    input         I_clk,      // 50 MHz 板载晶振, 引脚 4
    input         I_rst_n,    // 复位按键, 引脚 88 (按下=复位)
    output        O_clk_adc,  // 65 MHz, 接 AD9226 的 CLK 引脚
    input  [11:0] I_adc_d,    // AD9226 数据 D0..D11
    input         I_adc_otr,  // AD9226 OTR 过压标志
    output [5:0]  O_led       // 板载 LED (低电平点亮)
);

    //------------------------------------------------------------------
    // PLL: 50MHz -> 260MHz
    //------------------------------------------------------------------
    wire clk_260m;
    wire pll_locked;

    ad9226_pll u_pll (
        .clkin    (I_clk),
        .clk_260m (clk_260m),
        .locked   (pll_locked)
    );

    // 复位同步释放 (PLL 锁定后延迟释放), 再和按键复位相与
    reg [3:0] rst_sync;
    always @(posedge clk_260m or negedge pll_locked) begin
        if (!pll_locked) rst_sync <= 4'b0;
        else             rst_sync <= {rst_sync[2:0], 1'b1};
    end
    wire rstn = rst_sync[3] & I_rst_n;

    //------------------------------------------------------------------
    // AD9226 读入 (原例程模块)
    //------------------------------------------------------------------
    wire        clk_driver;
    wire [12:0] adc13;                   // {OTR, D11..D0}

    ad9226_read u_read (
        .clk       (clk_260m),
        .rstn      (rstn),
        .clk_driver(clk_driver),
        .IO_data   ({I_adc_otr, I_adc_d}),
        .ADC_Data  (adc13)
    );

    assign O_clk_adc = clk_driver;

    //------------------------------------------------------------------
    // LED 峰值指示: 8ms 窗口取最大码值, 每 8ms 衰减 1 颗 LED
    //------------------------------------------------------------------
    reg [21:0] led_cnt;
    reg [11:0] win_max;                  // 本窗口内的最大码值
    reg [11:0] led_peak;                 // 峰值保持 (缓慢衰减)
    wire       win_end = (led_cnt[20:0] == 21'd0);   // 约 8.1ms 一个窗口

    always @(posedge clk_260m or negedge rstn) begin
        if (!rstn) begin
            led_cnt  <= 22'd0;
            win_max  <= 12'd0;
            led_peak <= 12'd0;
        end else begin
            led_cnt <= led_cnt + 22'd1;
            if (win_end) begin
                // 窗口结束: 用窗口最大值更新峰值, 然后衰减 1 颗 LED (128 码值)
                led_peak <= (win_max > led_peak) ? win_max :
                            ((led_peak >= 12'd128) ? (led_peak - 12'd128) : 12'd0);
                win_max <= adc13[11:0];
            end else if (adc13[11:0] > win_max) begin
                win_max <= adc13[11:0];
            end
        end
    end

    // LED 低电平点亮: LED5 = OTR 过压, LED4..0 = 峰值高 5 位
    assign O_led[5]   = ~adc13[12];
    assign O_led[4:0] = ~led_peak[11:7];

endmodule

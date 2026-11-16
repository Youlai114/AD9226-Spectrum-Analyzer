// ============================================================================
// ad9226_read.v  --  AD9226 采样读入模块 (从原例程移植, 逻辑不变)
//
//   原例程: AD9226_FPGA_V1.1_65M/rtl/AD9220_ReadModule.V (Altera EP4CE15)
//   该模块为纯逻辑, 移植到高云无需修改:
//     clk        = 130 MHz (PLL 输出)
//     clk_driver = clk / 2 = 65 MHz, 输出到 AD9226 的 CLK 引脚
//     AD9226 在 CLK 下降沿更新输出数据, 本模块在 clk_driver 上升沿
//     (即驱动时钟高电平中点) 锁存 IO_data, 数据稳定
//
//   输入 IO_data[12:0] = {OTR, D11..D0}
//   输出 ADC_Data[12:0] = {OTR, D11..D0}
// ============================================================================
module ad9226_read(
    input            clk,        // 260 MHz
    input            rstn,       // 低有效复位

    output reg       clk_driver, // 65 MHz, 接 AD9226 CLK 引脚
    input  [12:0]    IO_data,    // AD9226 并行数据 (含 OTR)

    output reg [12:0]ADC_Data
);

`define clkOutPeriod  2		// 模块时钟分频: clk_driver = 130M/2 = 65M
reg [31:0]clkCnt;
always @(posedge clk or negedge rstn)
	if(!rstn)
		clkCnt <= 32'd0;
	else if(clkCnt == (`clkOutPeriod-1)) begin
		clkCnt <= 32'd0;
	end
	else begin
		clkCnt <= clkCnt + 32'd1;
	end

always @(posedge clk or negedge rstn)
	if(!rstn) begin
		clk_driver <= 1'd0;
		ADC_Data <= 13'd0;
	end
	else if(clkCnt == `clkOutPeriod/2-1) begin
		clk_driver <= 1'd1;
		ADC_Data <= IO_data;
	end
	else if(clkCnt == `clkOutPeriod-1) begin
		clk_driver <= 1'd0;
		ADC_Data <= ADC_Data;
	end
	else begin
		clk_driver <= clk_driver;
		ADC_Data <= ADC_Data;
	end

endmodule

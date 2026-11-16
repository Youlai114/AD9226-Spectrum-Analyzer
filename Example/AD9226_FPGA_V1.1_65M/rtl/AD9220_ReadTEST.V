module AD9220_ReadTEST(
input clk,
input rstn,

output clk_driver,	//模块时钟管脚
input [12:0]IO_data,	//模块数据管脚

output [11:0]ADC_Data,//12位ADC数据
output ADC_OTR			//信号过压标志位
);

wire areset, pll260m_lockedPIN;
wire pll_50M, pll_260M;
assign areset = ~rstn;

/*
锁相环：
用于产生240M时钟
*/
pll260m	U0_pll260m_inst (
	.areset ( areset ),
	.inclk0 ( clk ),
	.c0 ( pll_260M ),
	.c1 ( pll_50M ),
	.locked ( pll260m_lockedPIN )
	);
/*
AD9226控制器：
将输入的260M时钟4分频(在AD9220_ReadModule.V中定义)后，用于驱动AD9226模块，并采集信号电压数据。
数据输入电压对应关系（受信号调理电路器件值公差影响，不同模块可能有微小差异）：
信号(-10V)~(+10V):数据(0~4095)
*/
AD9220_ReadModule U1_AD9220_ReadModule(
.clk(pll_260M),
.rstn(rstn),

.clk_driver(clk_driver),
.IO_data(IO_data),

.ADC_Data({ADC_OTR, ADC_Data})
);

endmodule

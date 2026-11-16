module AD9220_ReadModule(
input clk,
input rstn,

output reg clk_driver,
input [12:0]IO_data,

output reg [12:0]ADC_Data
);

`define clkOutPeriod  4		//模块驱动时钟分频，clk_driver = clk/4 = 260M/4 = 65M
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

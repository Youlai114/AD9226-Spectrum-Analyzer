`timescale 1ns/1ns

`define clock_period 20
module AD9226_TEST_tb;

	reg Clock;
	reg Rst_n;
	//reg a,b,c;
	wire clk_driver;
	//wire [1:0]out;
	reg [12:0]IO_data;
	wire [12:0]ADC_Data;
	//block_nonblock block_nonblock0(Clock,Rst_n,a,b,c,out);
AD9220_ReadModule U0_AD9220_ReadModule(
.clk(Clock),
.rstn(Rst_n),
.clk_driver(clk_driver),
.IO_data(IO_data),
.ADC_Data(ADC_Data)
);
	initial Clock = 1;
	always#(`clock_period/2) Clock = ~Clock;
	
	initial begin
		Rst_n = 1'b0;
		IO_data <= 13'd0;
		#(`clock_period*200 + 1);
		Rst_n = 1'b1;
		#(`clock_period*200);		IO_data <= 13'd0;
		#(`clock_period*200);		IO_data <= 13'd1;
		#(`clock_period*200);		IO_data <= 13'd2;
		#(`clock_period*200);		IO_data <= 13'd3;
		#(`clock_period*200);		IO_data <= 13'd4;
		#(`clock_period*200);		IO_data <= 13'd5;
		#(`clock_period*200);		IO_data <= 13'd6;
		#(`clock_period*200);		IO_data <= 13'd7;
		#(`clock_period*200);
		$stop;	
	end
	



endmodule

// ============================================================================
// spec_ram.v  --  频谱数据双时钟乒乓缓存
//   写端口在写时钟域 (可来自 ADC / FFT), 读端口在像素时钟域
//   两个 bank 交替使用, 写一帧的同时显示另一帧, 避免撕裂
//   容量: 2 x 1024 x 16bit
// ============================================================================
module spec_ram (
    // 写端口 (写时钟域)
    input             I_wr_clk  ,
    input             I_wr_en   ,
    input             I_wr_bank ,   // 0: bank0, 1: bank1
    input      [9:0]  I_wr_addr ,
    input      [15:0] I_wr_data ,
    // 读端口 (像素时钟域)
    input             I_rd_clk  ,
    input             I_rd_bank ,
    input      [9:0]  I_rd_addr ,
    output reg [15:0] O_rd_data
);

    reg [15:0] mem0 [0:1023];
    reg [15:0] mem1 [0:1023];

    always @(posedge I_wr_clk) begin
        if (I_wr_en && !I_wr_bank)
            mem0[I_wr_addr] <= I_wr_data;
    end

    always @(posedge I_wr_clk) begin
        if (I_wr_en && I_wr_bank)
            mem1[I_wr_addr] <= I_wr_data;
    end

    always @(posedge I_rd_clk) begin
        O_rd_data <= I_rd_bank ? mem1[I_rd_addr] : mem0[I_rd_addr];
    end

endmodule

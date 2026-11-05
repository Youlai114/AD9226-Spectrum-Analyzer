// ============================================================================
// harm_ram.v  --  时域谐波行值 双时钟乒乓缓存
//   写端口在 adc_clk 域 (harm_est 每帧算完 256 列), 读端口在像素时钟域
//   容量: 2 x 256 x 50bit (5 个 lane, 每 lane 10bit 行值)
//   bank 与 spec_data_if 的帧同步同相, 保证"写一帧的同时显示另一帧"
// ============================================================================
module harm_ram (
    // 写端口 (写时钟域)
    input             I_wr_clk  ,
    input             I_wr_en   ,
    input             I_wr_bank ,   // 0: bank0, 1: bank1
    input      [7:0]  I_wr_addr ,
    input      [49:0] I_wr_data ,
    // 读端口 (像素时钟域)
    input             I_rd_clk  ,
    input             I_rd_bank ,
    input      [7:0]  I_rd_addr ,
    output reg [49:0] O_rd_data
);

    reg [49:0] mem0 [0:255];
    reg [49:0] mem1 [0:255];

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

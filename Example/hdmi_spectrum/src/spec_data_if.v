// ============================================================================
// spec_data_if.v  --  频谱数据接入接口 (跨时钟域 + 帧同步)
//
//   【这是后续接真实数据的唯一入口】
//
//   写侧协议 (I_wr_clk 域):
//     1. 一帧开始时, 给一个 I_frame_start 单拍脉冲;
//     2. 随后逐点写入 I_wr_en=1, I_wr_addr=频点(0..1023), I_wr_mag=幅度(0..65535);
//     3. 一帧写完 (1024 点, 顺序或乱序都可以) 后等待下一帧的 I_frame_start。
//     一帧必须在下一帧 I_frame_start 到来之前写完。
//
//   模块内部把数据写到乒乓 bank, 并把 bank 选择信号同步到读时钟域,
//   显示侧始终读取"刚刚写完的那一帧", 因此写侧时钟与像素时钟可以完全异步。
// ============================================================================
module spec_data_if (
    // ---- 写侧 (数据源时钟域) ----
    input             I_wr_clk      ,
    input             I_wr_rst_n    ,
    input             I_frame_start ,   // 帧起始, 单拍脉冲
    input             I_wr_en       ,
    input      [9:0]  I_wr_addr     ,
    input      [15:0] I_wr_mag      ,
    // ---- 读侧 (像素时钟域) ----
    input             I_rd_clk      ,
    input             I_rd_rst_n    ,
    // ---- 输出到 spec_ram ----
    output            O_wr_en       ,
    output            O_wr_bank     ,
    output     [9:0]  O_wr_addr     ,
    output     [15:0] O_wr_mag      ,
    output            O_rd_bank     ,
    // ---- 状态 (可接到 UI 显示) ----
    output reg [15:0] O_frame_cnt   ,   // 已接收帧数
    output reg        O_frame_tog       // 每帧翻转一次 (调试用)
);

    //------------------------------------------------------------------
    // 写侧: 帧起始时切换 bank, 本帧写入新的 bank
    //------------------------------------------------------------------
    reg wr_bank;

    always @(posedge I_wr_clk or negedge I_wr_rst_n) begin
        if (!I_wr_rst_n)
            wr_bank <= 1'b0;
        else if (I_frame_start)
            wr_bank <= ~wr_bank;
    end

    always @(posedge I_wr_clk or negedge I_wr_rst_n) begin
        if (!I_wr_rst_n) begin
            O_frame_cnt <= 16'd0;
            O_frame_tog <= 1'b0;
        end else if (I_frame_start) begin
            O_frame_cnt <= O_frame_cnt + 16'd1;
            O_frame_tog <= ~O_frame_tog;
        end
    end

    //------------------------------------------------------------------
    // 跨时钟域: bank 选择信号 2 级同步到读时钟域
    //------------------------------------------------------------------
    reg [1:0] bank_sync;

    always @(posedge I_rd_clk or negedge I_rd_rst_n) begin
        if (!I_rd_rst_n)
            bank_sync <= 2'b00;
        else
            bank_sync <= {bank_sync[0], wr_bank};
    end

    // 显示侧读取"刚写完的那一帧" = 写 bank 的反相
    assign O_rd_bank = ~bank_sync[1];

    //------------------------------------------------------------------
    // 写端口直通 (复位期间屏蔽写使能)
    //------------------------------------------------------------------
    assign O_wr_en   = I_wr_en & I_wr_rst_n;
    assign O_wr_bank = wr_bank;
    assign O_wr_addr = I_wr_addr;
    assign O_wr_mag  = I_wr_mag;

endmodule

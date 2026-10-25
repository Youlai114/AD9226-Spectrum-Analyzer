// ============================================================================
// wave_cap.v  --  时域波形采集 (1024 点 + 边沿触发)
//
//   数据源: ad9226_capture 的 O_smp / O_smp_en (抽取后的样点, Q4 有符号)
//   每帧由 I_arm 单拍启动, 等到指定的边沿穿越后连续记录 1024 点, 写进波形 RAM.
//
//   触发方式: 电平穿越
//     I_edge=0 上升沿: 上一个样点 < 电平, 当前 >= 电平
//     I_edge=1 下降沿: 上一个样点 > 电平, 当前 <= 电平
//
//   触发点 = 记录的第 0 点 (不做预触发, 简单起见)
//
//   1024 点 @ fs=2MHz = 512us; 100kHz 信号约 51 个周期
// ============================================================================
module wave_cap (
    input             I_clk,
    input             I_rst_n,

    input      [15:0] I_smp,        // 抽取后的样点 (Q4, 有符号)
    input             I_smp_en,     // 样点有效 (fs = 54MHz / 抽取比)

    input             I_arm,        // 单拍: 重新开始等待触发 (每显示帧一次)
    input      [15:0] I_level,      // 触发电平 (Q4, 有符号), 0 = 中点
    input             I_edge,       // 0 = 上升沿, 1 = 下降沿

    output reg [9:0]  O_addr,       // 写入地址 0..1023
    output reg [15:0] O_data,       // 写入数据
    output reg        O_we,         // 写使能 (单拍)
    output reg        O_wr_start,   // 单拍: 本帧第一次写 (触发时刻), 给乒乓 bank 切换用
    output reg        O_frame_ok,   // 采集完成 (本帧数据有效, I_arm 时清零)
    output reg [9:0]  O_cnt         // 当前已采点数 (调试/显示用)
);

    localparam [1:0] S_IDLE = 2'd0,     // 等 arm
                     S_ARM  = 2'd1,     // 等触发
                     S_CAP  = 2'd2,     // 采集中
                     S_DONE = 2'd3;

    reg [1:0]  state;
    reg [15:0] prev;                    // 上一个样点 (Q4)
    reg        have_prev;               // 是否已有有效的前一个点

    wire signed [15:0] lvl = I_level;
    wire signed [15:0] cur = I_smp;
    wire signed [15:0] prv = prev;

    // 边沿穿越判断
    wire cross_up = (prv <  lvl) && (cur >= lvl);
    wire cross_dn = (prv >  lvl) && (cur <= lvl);
    wire cross    = I_edge ? cross_dn : cross_up;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state      <= S_IDLE;
            prev       <= 16'sd0;
            have_prev  <= 1'b0;
            O_addr     <= 10'd0;
            O_data     <= 16'd0;
            O_we       <= 1'b0;
            O_wr_start <= 1'b0;
            O_frame_ok <= 1'b0;
            O_cnt      <= 10'd0;
        end else begin
            O_we       <= 1'b0;
            O_wr_start <= 1'b0;

            if (I_arm) begin
                // 每帧重新开始; prev 复位到中点避免第一拍误触发
                state      <= S_ARM;
                prev       <= 16'sd0;
                have_prev  <= 1'b0;
                O_frame_ok <= 1'b0;
                O_cnt      <= 10'd0;
            end else if (I_smp_en) begin
                case (state)
                S_ARM: begin
                    if (have_prev && cross) begin
                        // 触发: 第一个点就是记录的第 0 点
                        state      <= S_CAP;
                        O_addr     <= 10'd0;
                        O_data     <= I_smp;
                        O_we       <= 1'b1;
                        O_wr_start <= 1'b1;
                        O_cnt      <= 10'd1;
                    end
                    prev      <= I_smp;
                    have_prev <= 1'b1;
                end

                S_CAP: begin
                    O_addr <= O_cnt;
                    O_data <= I_smp;
                    O_we   <= 1'b1;
                    if (O_cnt == 10'd1023) begin
                        state      <= S_DONE;
                        O_frame_ok <= 1'b1;
                    end else begin
                        O_cnt <= O_cnt + 10'd1;
                    end
                end

                S_DONE: begin
                    // 等下一帧 arm
                end

                default: state <= S_ARM;
                endcase
            end
        end
    end

endmodule

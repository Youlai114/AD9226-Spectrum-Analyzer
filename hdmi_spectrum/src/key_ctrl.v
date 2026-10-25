// ============================================================================
// key_ctrl.v  --  按键去抖 + 频率跨度切换 + LED 指示
//   每按一次 KEY, 跨度 +1, 共 SPAN_NUM 档循环
//     0:   500 kHz (fs =  1 MHz)
//     1:     1 MHz (fs =  2 MHz)
//     2:    10 MHz (fs = 20 MHz)
//   LED[2:0] 以"进度条"方式指示当前跨度, LED[4] 为心跳灯 (低电平点亮)
// ============================================================================
module key_ctrl #(
    parameter SPAN_NUM = 3
)(
    input             I_clk      ,
    input             I_rst_n    ,
    input             I_key      ,   // 按键, 按下为高
    input             I_heartbeat,   // 心跳信号 (0.5Hz 左右)
    output reg [1:0]  O_span     ,   // 当前频率跨度
    output     [4:0]  O_led
);

    //------------------------------------------------------------------
    // 同步 + 去抖 (约 14ms @74.25MHz)
    //------------------------------------------------------------------
    reg [1:0]  key_sync;
    reg [19:0] db_cnt;
    reg        key_level;   // 去抖后的电平
    reg        key_level_d;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) key_sync <= 2'b00;
        else          key_sync <= {key_sync[0], I_key};
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            db_cnt      <= 20'd0;
            key_level   <= 1'b0;
            key_level_d <= 1'b0;
        end else if (key_sync[1] != key_level) begin
            if (db_cnt >= 20'hF_FFFF) begin
                db_cnt      <= 20'd0;
                key_level   <= key_sync[1];
                key_level_d <= key_level;
            end else begin
                db_cnt <= db_cnt + 20'd1;
            end
        end else begin
            db_cnt      <= 20'd0;
            key_level_d <= key_level;
        end
    end

    wire key_press = key_level & ~key_level_d;   // 上升沿 = 按下

    //------------------------------------------------------------------
    // 跨度切换
    //------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            O_span <= 2'd0;
        else if (key_press) begin
            if (O_span >= (SPAN_NUM - 1))
                O_span <= 2'd0;
            else
                O_span <= O_span + 2'd1;
        end
    end

    //------------------------------------------------------------------
    // LED: 低电平点亮
    //------------------------------------------------------------------
    wire [4:0] bar = (5'b00001 << O_span) - 5'd1;

    assign O_led = ~{I_heartbeat, 1'b0, bar[2:0]};

endmodule

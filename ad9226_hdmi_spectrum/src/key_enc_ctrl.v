// ============================================================================
// key_enc_ctrl.v  --  5 键 + EC11 旋转编码器 输入处理 (给打板版本用)
//
//   按键: 低有效 (板上 10k 上拉到 3.3V, 按下接地), 15ms 消抖
//   编码器: EC11 (A/B 正交 + SW), A/B 上拉到 3.3V, C 接 GND
//           4 状态格雷码解码 + 0.5ms 采样 + 净计数, 每 ENC_STEP(默认 4) 个边沿 = 1 格
//           (机械抖动会来回产生 +1/-1, 净计数自动抵消, 不需要额外滤波)
//
//   功能:
//     KEY1        循环切跨度 (与原板载按键一致)
//     KEY2~KEY5   输出单拍脉冲, 由顶层决定用途:
//                 KEY2=视图切换 KEY3=AUTO KEY4=光标开关 KEY5=Preset
//     编码器旋转  I_enc_mode=0: 跨度 +1/-1, 到头停住 (不循环)
//                 I_enc_mode=1: 输出 O_csr_up/dn 移光标, 跨度不动
//     编码器按压  短按 = 松开时出 O_sw_press:
//                 I_enc_mode=0: 翻转 O_fine (精细模式, 光标步进 4->1 列)
//                 I_enc_mode=1: O_sw_press 给顶层做"光标跳到峰值"
//                 长按 = 按住 >= SW_LONG_MS 出一次 O_sw_long: Preset (回 Span 1 MHz)
//                 (KEY5 已让位给窗切换)
// ============================================================================
module key_enc_ctrl #(
    parameter SPAN_NUM = 5,       // 跨度档数: 1M/250k/50k/10k/27M(宽频)
    parameter ENC_STEP = 4,       // 转一格产生几个边沿: 常见 EC11(20 脉冲/20 定位)=4,
                                  // 若你的编码器转两格才动一下, 改成 2
    parameter SW_LONG_MS = 800    // 编码器长按阈值 (ms)
)(
    input             I_clk,        // 74.25 MHz 像素时钟
    input             I_rst_n,

    input      [4:0]  I_key,        // KEY1..KEY5, 低有效
    input             I_enc_a,      // EC11 A 相
    input             I_enc_b,      // EC11 B 相
    input             I_enc_sw,     // EC11 按压开关, 低有效
    input             I_span_load,      // 单拍: 外部设置跨度 (AUTO 自动跨度)
    input      [2:0]  I_span_load_val,  // AUTO 给出的目标跨度 (0..4, 含 27MHz 宽频)
    input             I_enc_mode,       // 1: 编码器移光标 (O_csr_*), 0: 调跨度
    output reg        O_csr_up,         // 单拍: 光标 +步进 (仅 I_enc_mode=1 时)
    output reg        O_csr_dn,         // 单拍: 光标 -步进
    output reg        O_sw_press,       // 单拍: 编码器短按 (松开时, 未达长按阈值)
    output reg        O_sw_long,        // 单拍: 编码器长按 (Preset 用)
    output reg        O_fine,           // 精细模式状态 (短按翻转, 光标步进 4->1)

    output reg [2:0]  O_span,       // 当前跨度 0..SPAN_NUM-1
    output reg [4:0]  O_key_press   // 各键"按下"单拍脉冲 (bit0 = KEY1)
);

    //------------------------------------------------------------------
    // 0.5ms 时基 (编码器采样), 按键消抖用它的 2 分频 (1ms)
    //------------------------------------------------------------------
    localparam integer TICK_N = 37125;      // 74.25MHz * 0.5ms

    reg [15:0] tick_cnt;
    wire       tick = (tick_cnt == TICK_N - 1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) tick_cnt <= 16'd0;
        else          tick_cnt <= tick ? 16'd0 : (tick_cnt + 16'd1);
    end

    reg tick_d;
    wire tick1ms = tick & ~tick_d;          // 1ms 一次 (给按键)

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) tick_d <= 1'b0;
        else          tick_d <= tick;
    end

    //------------------------------------------------------------------
    // 按键: 2 级同步 + 1ms 采样 8 次一致才认
    //------------------------------------------------------------------
    reg [4:0] k_s0, k_s1, k_db;
    reg [2:0] k_cnt [0:4];
    integer   i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            k_s0 <= 5'h1F;
            k_s1 <= 5'h1F;
        end else begin
            k_s0 <= I_key;
            k_s1 <= k_s0;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            k_db        <= 5'h1F;
            O_key_press <= 5'd0;
            for (i = 0; i < 5; i = i + 1) begin
                k_cnt[i] <= 3'd0;
            end
        end else begin
            O_key_press <= 5'd0;
            if (tick1ms) begin
                for (i = 0; i < 5; i = i + 1) begin
                    if (k_s1[i] != k_db[i]) begin
                        if (k_cnt[i] == 3'd7) begin
                            k_db[i]      <= k_s1[i];
                            k_cnt[i]     <= 3'd0;
                            if (k_s1[i] == 1'b0)        // 稳定为低 = 按下
                                O_key_press[i] <= 1'b1;
                        end else begin
                            k_cnt[i] <= k_cnt[i] + 3'd1;
                        end
                    end else begin
                        k_cnt[i] <= 3'd0;
                    end
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 编码器: 2 级同步 + 0.5ms 采样 + 4 状态格雷码解码
    //   正向 00->01->11->10->00, 反向 00->10->11->01->00
    //------------------------------------------------------------------
    reg [1:0] e_s0, e_s1, e_prev;
    reg [3:0] e_acc;                        // 净边沿计数, 中值 4
    reg       e_up, e_dn;

    wire [1:0] e_cur = e_s1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            e_s0   <= 2'b00;
            e_s1   <= 2'b00;
            e_prev <= 2'b00;
            e_acc  <= 4'd4;
            e_up   <= 1'b0;
            e_dn   <= 1'b0;
        end else begin
            e_s0 <= {I_enc_a, I_enc_b};
            e_s1 <= e_s0;
            e_up <= 1'b0;
            e_dn <= 1'b0;

            if (tick) begin
                e_prev <= e_cur;
                if (e_cur != e_prev) begin
                    case ({e_prev, e_cur})
                    4'b00_01, 4'b01_11, 4'b11_10, 4'b10_00:     // 正向
                        if (e_acc < 4'd12) e_acc <= e_acc + 4'd1;
                    // 反向
                    4'b00_10, 4'b10_11, 4'b11_01, 4'b01_00:
                        if (e_acc > 4'd0)  e_acc <= e_acc - 4'd1;
                    default: ;                                   // 非法跳变忽略
                    endcase
                end

                // 满 ENC_STEP 个同向边沿 = 转过一格
                if (e_acc >= 4'd4 + ENC_STEP) begin
                    e_acc <= 4'd4;
                    e_up  <= 1'b1;
                end else if (e_acc <= 4'd4 - ENC_STEP) begin
                    e_acc <= 4'd4;
                    e_dn  <= 1'b1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 编码器按压: 15ms 消抖 + 短按/长按区分
    //   短按 = 按下后 SW_LONG_MS 内松开 -> 松开瞬间出单拍
    //   长按 = 持续按住 >= SW_LONG_MS   -> 按住期间出一次单拍
    //------------------------------------------------------------------
    reg [1:0]  sw_sync;
    reg [3:0]  sw_cnt;
    reg        sw_db;
    reg [10:0] sw_hold;
    reg        sw_long_done;
    reg        sw_short, sw_long;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sw_sync      <= 2'b11;
            sw_db        <= 1'b1;
            sw_cnt       <= 4'd0;
            sw_hold      <= 11'd0;
            sw_long_done <= 1'b0;
            sw_short     <= 1'b0;
            sw_long      <= 1'b0;
        end else begin
            sw_sync  <= {sw_sync[0], I_enc_sw};
            sw_short <= 1'b0;
            sw_long  <= 1'b0;
            if (tick1ms) begin
                if (sw_sync[1] != sw_db) begin
                    if (sw_cnt == 4'd15) begin
                        sw_db  <= sw_sync[1];
                        sw_cnt <= 4'd0;
                        if (sw_sync[1] == 1'b0) begin        // 按下确认
                            sw_hold      <= 11'd0;
                            sw_long_done <= 1'b0;
                        end else if (!sw_long_done) begin    // 松开且未达长按
                            sw_short <= 1'b1;
                        end
                    end else begin
                        sw_cnt <= sw_cnt + 4'd1;
                    end
                end else begin
                    sw_cnt <= 4'd0;
                end
                // 按住计时 (消抖确认按下后仍为低)
                if ((sw_db == 1'b0) && (sw_sync[1] == 1'b0) && !sw_long_done) begin
                    if (sw_hold >= SW_LONG_MS) begin
                        sw_long      <= 1'b1;
                        sw_long_done <= 1'b1;
                    end else begin
                        sw_hold <= sw_hold + 11'd1;
                    end
                end
            end
        end
    end

    //------------------------------------------------------------------
    // 跨度更新
    //------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            O_span <= 2'd0;
        else if (sw_long) begin
            O_span <= 3'd0;                                  // Preset (编码器长按)
        end else if (I_span_load) begin
            O_span <= I_span_load_val;                       // AUTO 加载
        end else if (O_key_press[0]) begin
            O_span <= (O_span >= SPAN_NUM - 1) ? 3'd0 : (O_span + 2'd1);  // KEY1 循环
        end else if (e_up && !I_enc_mode) begin
            O_span <= (O_span >= SPAN_NUM - 1) ? (SPAN_NUM - 1) : (O_span + 2'd1);
        end else if (e_dn && !I_enc_mode) begin
            O_span <= (O_span == 2'd0) ? 2'd0 : (O_span - 2'd1);
        end
    end

    //------------------------------------------------------------------
    // 光标步进脉冲 + 短按/长按输出: 光标模式下编码器旋转走这里 (不调跨度)
    //   短按在跨度档翻 O_fine (精细), 在光标档交给顶层跳峰
    //------------------------------------------------------------------
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_csr_up   <= 1'b0;
            O_csr_dn   <= 1'b0;
            O_sw_press <= 1'b0;
            O_sw_long  <= 1'b0;
            O_fine     <= 1'b0;
        end else begin
            O_csr_up   <= e_up & I_enc_mode;
            O_csr_dn   <= e_dn & I_enc_mode;
            O_sw_press <= sw_short;
            O_sw_long  <= sw_long;
            if (sw_short && !I_enc_mode)
                O_fine <= ~O_fine;
        end
    end

endmodule

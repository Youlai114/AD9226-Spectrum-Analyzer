// ============================================================================
// input_ctrl.v  --  打板底板人机接口 (5 按键 + EC11 旋转编码器 + 2 LED)
//
//   按键 (低电平有效, 16ms 消抖):
//     KEY1 (I_key[0]) : Span 循环 (0..6)
//     KEY2 (I_key[1]) : 预留视图切换 (阶段 3)
//     KEY3 (I_key[2]) : 预留 AUTO Span (阶段 2)
//     KEY4 (I_key[3]) : 菜单调参开关 (开: EC11 调菜单项; 关: EC11 调 Span)
//     KEY5 (I_key[4]) : 窗函数循环 (0..3: Hann/Rect/Black/FlatTop)
//   EC11 编码器:
//     旋转 : 菜单开时调节当前选中菜单项的值; 菜单关时调节 Span
//     短按 : 菜单关时打开菜单; 菜单开时切换菜单项 (Win/Det/Trc/Avg/Span)
//     长按 (>=800ms) : Preset 恢复默认 (1MHz / Hann / Pos Peak / Clear Write / Auto)
// ============================================================================
module input_ctrl #(
    parameter CLK_HZ = 74_250_000
)(
    input             I_clk       ,
    input             I_rst_n     ,
    input      [4:0]  I_key       ,   // KEY5..KEY1 (低有效)
    input             I_enc_a     ,
    input             I_enc_b     ,
    input             I_enc_sw    ,   // 低有效
    input             I_heartbeat ,
    input             I_ovr       ,
    input      [9:0]  I_pk_col    ,
    input             I_pk_tog    ,
    output reg [3:0]  O_span      ,   // 0:1M 1:250k 2:50k 3:10k 4:1k 5:250Hz 6:27M 7:500k 8:100k 9:2.7M 10:5.4M 11:13.5M
    output reg [1:0]  O_win       ,   // 0:Hann 1:Rect 2:Black 3:FlatTop
    output reg [1:0]  O_det       ,   // 0:PosPeak 1:Avg 2:NegPeak 3:Sample
    output reg [1:0]  O_trc       ,   // 0:ClearWrite 1:MaxHold 2:MinHold 3:View
    output reg        O_trc_sub   ,   // 0:调TRC主迹线 1:调REF参考迹线
    output reg [1:0]  O_ref_mode  ,   // 0:OFF 1:ON 2:CAP(保存并显示)
    output reg        O_ref_save_tog, // 翻转触发保存一帧到ref_mem
    output reg [2:0]  O_avg       ,   // 0:Auto 1:1 2:4 3:16 4:64
    output reg [1:0]  O_view      ,   // 0:SPEC 1:SPLIT 2:TIME
    output reg [9:0]  O_mkr_col   ,   // 0:关闭 >0:频标列号
    output reg        O_mkr_fine  ,   // 0:粗调(+-16列) 1:细调(+-1列)
    output reg        O_mkr_delta ,   // 0:单频标 1:差值频标(Delta)
    output reg        O_mkr_track ,   // 0:手动频标 1:自动追踪峰值(Peak Track)
    output reg [9:0]  O_mkr_ref_col,  // Delta 参考频标列号
    output reg [2:0]  O_harm_mode ,   // 0:OFF 1..5:H1..H5 6:H1-5合成
    output reg [1:0]  O_yscale    ,   // 0:5dB/div 1:2dB/div 2:1dB/div
    output reg [2:0]  O_yref      ,   // 0:0dB 1:-10dB 2:-20dB 3:-30dB 4:-40dB
    output reg        O_yscale_ref,   // 0:调Scale 1:调Ref
    output reg [3:0]  O_lim_lvl   ,   // 0:OFF 1..8:-10..-80dBFS
    output reg        O_lim_sub   ,   // 1:调Limit门限
    output reg [2:0]  O_trig_mode ,   // 0:AUTO 1:RISE 2:FALL 3:SNGL 4:HOLD
    output reg [3:0]  O_trig_lvl  ,   // 0..8: -50%..MID..+50%
    output reg        O_trig_sub  ,   // 0:调TRIG模式 1:调TLVL电平
    output reg [3:0]  O_vscale    ,   // 0:AUTO 1..13:x0.25..x64
    output reg [3:0]  O_tscale    ,   // 0..11:x0.25..x64 (2:x1.0)
    output reg        O_vt_sel    ,   // 0:调V-SCL 1:调T-ZM
    output reg        O_menu_open ,
    output reg [3:0]  O_menu_sel  ,   // 0..9:Y-SCL..HARM WV
    output     [1:0]  O_led           // [0]:STAT [1]:OVR (低有效)
);

    localparam integer TICK_1MS = CLK_HZ / 1000;
    reg [16:0] ms_cnt;
    reg        tick_1ms;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            ms_cnt   <= 17'd0;
            tick_1ms <= 1'b0;
        end else if (ms_cnt == TICK_1MS - 1) begin
            ms_cnt   <= 17'd0;
            tick_1ms <= 1'b1;
        end else begin
            ms_cnt   <= ms_cnt + 17'd1;
            tick_1ms <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // 按键 + 编码器开关 2 级同步与 16ms 消抖 (低有效转高有效)
    //------------------------------------------------------------------
    wire [5:0] raw_in = ~{I_enc_sw, I_key};
    reg  [5:0] btn_s0, btn_s1, btn_lvl, btn_prev;
    reg  [3:0] btn_cnt [0:5];
    integer i;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            btn_s0   <= 6'd0;
            btn_s1   <= 6'd0;
            btn_lvl  <= 6'd0;
            btn_prev <= 6'd0;
            for (i = 0; i < 6; i = i + 1) btn_cnt[i] <= 4'd0;
        end else begin
            btn_s0   <= raw_in;
            btn_s1   <= btn_s0;
            btn_prev <= btn_lvl;
            if (tick_1ms) begin
                for (i = 0; i < 6; i = i + 1) begin
                    if (btn_s1[i] != btn_lvl[i]) begin
                        if (btn_cnt[i] == 4'd15) begin
                            btn_cnt[i] <= 4'd0;
                            btn_lvl[i] <= btn_s1[i];
                        end else begin
                            btn_cnt[i] <= btn_cnt[i] + 4'd1;
                        end
                    end else begin
                        btn_cnt[i] <= 4'd0;
                    end
                end
            end
        end
    end

    wire [4:0] key_press = btn_lvl[4:0] & ~btn_prev[4:0];
    wire       sw_down   = btn_lvl[5];
    wire       sw_rel    = ~btn_lvl[5] & btn_prev[5];

    // 编码器短按 / 长按 (>=800ms) 检测
    reg [9:0] sw_hold_ms;
    reg       sw_long_done;
    reg       sw_short_p, sw_long_p;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sw_hold_ms   <= 10'd0;
            sw_long_done <= 1'b0;
            sw_short_p   <= 1'b0;
            sw_long_p    <= 1'b0;
        end else begin
            sw_short_p <= 1'b0;
            sw_long_p  <= 1'b0;
            if (!sw_down) begin
                if (sw_rel && !sw_long_done)
                    sw_short_p <= 1'b1;
                sw_hold_ms   <= 10'd0;
                sw_long_done <= 1'b0;
            end else if (tick_1ms && !sw_long_done) begin
                if (sw_hold_ms >= 10'd800) begin
                    sw_long_done <= 1'b1;
                    sw_long_p    <= 1'b1;
                end else begin
                    sw_hold_ms <= sw_hold_ms + 10'd1;
                end
            end
        end
    end

    //------------------------------------------------------------------
    // EC11 正交解码 (1ms 采样 + 4-bit 状态转移累计每格 4 跳变)
    //------------------------------------------------------------------
    reg [1:0] enc_a_s, enc_b_s;
    reg [1:0] enc_prev;
    reg signed [2:0] enc_acc;
    reg       enc_cw, enc_ccw;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            enc_a_s  <= 2'b11;
            enc_b_s  <= 2'b11;
            enc_prev <= 2'b11;
            enc_acc  <= 3'sd0;
            enc_cw   <= 1'b0;
            enc_ccw  <= 1'b0;
        end else begin
            enc_a_s <= {enc_a_s[0], I_enc_a};
            enc_b_s <= {enc_b_s[0], I_enc_b};
            enc_cw  <= 1'b0;
            enc_ccw <= 1'b0;

            if (tick_1ms) begin
                case ({enc_prev, enc_a_s[1], enc_b_s[1]})
                    4'b00_01, 4'b01_11, 4'b11_10, 4'b10_00: begin
                        if (enc_acc == 3'sd3) begin
                            enc_acc <= 3'sd0;
                            enc_cw  <= 1'b1;
                        end else begin
                            enc_acc <= enc_acc + 3'sd1;
                        end
                    end
                    4'b00_10, 4'b10_11, 4'b11_01, 4'b01_00: begin
                        if (enc_acc == -3'sd3) begin
                            enc_acc <= 3'sd0;
                            enc_ccw <= 1'b1;
                        end else begin
                            enc_acc <= enc_acc - 3'sd1;
                        end
                    end
                    default: ;
                endcase
                enc_prev <= {enc_a_s[1], enc_b_s[1]};
            end
        end
    end

    //------------------------------------------------------------------
    // 参数控制 + KEY3 AUTO Span 状态机
    //------------------------------------------------------------------
    function [3:0] span_next;
        input [3:0] s;
        begin
            case (s)
                4'd0:  span_next = 4'd7;  // 1M -> 500k
                4'd7:  span_next = 4'd1;  // 500k -> 200k
                4'd1:  span_next = 4'd8;  // 200k -> 100k
                4'd8:  span_next = 4'd2;  // 100k -> 50k
                4'd2:  span_next = 4'd12; // 50k -> 20k
                4'd12: span_next = 4'd3;  // 20k -> 10k
                4'd3:  span_next = 4'd13; // 10k -> 5k
                4'd13: span_next = 4'd14; // 5k -> 2k
                4'd14: span_next = 4'd4;  // 2k -> 1k
                4'd4:  span_next = 4'd15; // 1k -> 500Hz
                4'd15: span_next = 4'd5;  // 500Hz -> 200Hz
                4'd5:  span_next = 4'd6;  // 200Hz -> 27M
                4'd6:  span_next = 4'd11; // 27M -> 13.5M
                4'd11: span_next = 4'd10; // 13.5M -> 5.4M
                4'd10: span_next = 4'd9;  // 5.4M -> 2.7M
                4'd9:  span_next = 4'd0;  // 2.7M -> 1M
                default: span_next = 4'd0;
            endcase
        end
    endfunction

    function [3:0] span_prev;
        input [3:0] s;
        begin
            case (s)
                4'd0:  span_prev = 4'd9;
                4'd9:  span_prev = 4'd10;
                4'd10: span_prev = 4'd11;
                4'd11: span_prev = 4'd6;
                4'd6:  span_prev = 4'd5;
                4'd5:  span_prev = 4'd15;
                4'd15: span_prev = 4'd4;
                4'd4:  span_prev = 4'd14;
                4'd14: span_prev = 4'd13;
                4'd13: span_prev = 4'd3;
                4'd3:  span_prev = 4'd12;
                4'd12: span_prev = 4'd2;
                4'd2:  span_prev = 4'd8;
                4'd8:  span_prev = 4'd1;
                4'd1:  span_prev = 4'd7;
                4'd7:  span_prev = 4'd0;
                default: span_prev = 4'd0;
            endcase
        end
    endfunction

    wire step_up = enc_cw;
    wire step_dn = enc_ccw;

    reg       pk_tog_s0, pk_tog_s1, pk_tog_s2;
    reg       auto_busy;
    reg [1:0] auto_wait;
    wire      pk_fresh = pk_tog_s1 ^ pk_tog_s2;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pk_tog_s0   <= 1'b0;
            pk_tog_s1   <= 1'b0;
            pk_tog_s2   <= 1'b0;
            auto_busy   <= 1'b0;
            auto_wait   <= 2'd0;
            O_span      <= 4'd0;    // 默认 1.000 MHz
            O_win       <= 2'd0;    // Hann
            O_det       <= 2'd0;    // Pos Peak
            O_trc       <= 2'd0;    // Clear Write
            O_trc_sub   <= 1'b0;
            O_ref_mode  <= 2'd0;    // REF OFF
            O_ref_save_tog <= 1'b0;
            O_avg       <= 3'd0;    // Auto
            O_view      <= 2'd0;    // SPEC
            O_mkr_col     <= 10'd0;   // Marker OFF
            O_mkr_fine    <= 1'b0;    // 粗调
            O_mkr_delta   <= 1'b0;    // Delta OFF
            O_mkr_track   <= 1'b0;    // Track OFF
            O_mkr_ref_col <= 10'd0;
            O_harm_mode   <= 3'd0;    // 时域谐波 OFF
            O_yscale      <= 2'd0;    // 5 dB/div (16 div = 80 dB)
            O_yref        <= 3'd0;    // 0 dBFS
            O_yscale_ref  <= 1'b0;
            O_lim_lvl     <= 4'd0;    // Limit OFF
            O_lim_sub     <= 1'b0;
            O_trig_mode   <= 3'd0;    // AUTO
            O_trig_lvl    <= 4'd4;    // MID
            O_trig_sub    <= 1'b0;
            O_vscale      <= 4'd0;    // AUTO
            O_tscale      <= 4'd2;    // x1.0
            O_vt_sel      <= 1'b0;
            O_menu_open   <= 1'b0;
            O_menu_sel    <= 4'd0;
        end else if (sw_long_p) begin
            auto_busy     <= 1'b0;
            O_span        <= 4'd0;
            O_win         <= 2'd0;
            O_det         <= 2'd0;
            O_trc         <= 2'd0;
            O_trc_sub     <= 1'b0;
            O_ref_mode    <= 2'd0;
            O_avg         <= 3'd0;
            O_view        <= 2'd0;
            O_mkr_col     <= 10'd0;
            O_mkr_fine    <= 1'b0;
            O_mkr_delta   <= 1'b0;
            O_mkr_track   <= 1'b0;
            O_mkr_ref_col <= 10'd0;
            O_harm_mode   <= 3'd0;
            O_yscale      <= 2'd0;
            O_yref        <= 3'd0;
            O_yscale_ref  <= 1'b0;
            O_lim_lvl     <= 4'd0;
            O_lim_sub     <= 1'b0;
            O_trig_mode   <= 3'd0;
            O_trig_lvl    <= 4'd4;
            O_trig_sub    <= 1'b0;
            O_vscale      <= 4'd0;
            O_tscale      <= 4'd2;
            O_vt_sel      <= 1'b0;
            O_menu_open   <= 1'b0;
            O_menu_sel    <= 4'd0;
        end else begin
            pk_tog_s0 <= I_pk_tog;
            pk_tog_s1 <= pk_tog_s0;
            pk_tog_s2 <= pk_tog_s1;

            // KEY1: Span 循环
            if (key_press[0]) begin
                auto_busy <= 1'b0;
                O_span    <= span_next(O_span);
            end

            // KEY2: 视图切换 (SPEC -> SPLIT -> TIME)
            if (key_press[1])
                O_view <= (O_view == 2'd2) ? 2'd0 : (O_view + 2'd1);

            // KEY3: AUTO Span (从 27MHz 起逐级缩进, 避免混叠误判)
            if (key_press[2]) begin
                O_span    <= 4'd6;
                auto_busy <= 1'b1;
                auto_wait <= 2'd2;
            end else if (auto_busy && pk_fresh) begin
                if (auto_wait != 2'd0) begin
                    auto_wait <= auto_wait - 2'd1;
                end else begin
                    case (O_span)
                        4'd6:  if (I_pk_col < 10'd460) begin O_span <= 4'd11; auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd11: if (I_pk_col < 10'd370) begin O_span <= 4'd10; auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd10: if (I_pk_col < 10'd460) begin O_span <= 4'd9;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd9:  if (I_pk_col < 10'd340) begin O_span <= 4'd0;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd0:  if (I_pk_col < 10'd460) begin O_span <= 4'd7;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd7:  if (I_pk_col < 10'd370) begin O_span <= 4'd1;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd1:  if (I_pk_col < 10'd460) begin O_span <= 4'd8;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd8:  if (I_pk_col < 10'd460) begin O_span <= 4'd2;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd2:  if (I_pk_col < 10'd370) begin O_span <= 4'd12; auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd12: if (I_pk_col < 10'd460) begin O_span <= 4'd3;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd3:  if (I_pk_col < 10'd460) begin O_span <= 4'd13; auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd13: if (I_pk_col < 10'd370) begin O_span <= 4'd14; auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd14: if (I_pk_col < 10'd460) begin O_span <= 4'd4;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd4:  if (I_pk_col < 10'd460) begin O_span <= 4'd15; auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        4'd15: if (I_pk_col < 10'd370) begin O_span <= 4'd5;  auto_wait <= 2'd2; end else auto_busy <= 1'b0;
                        default: auto_busy <= 1'b0;
                    endcase
                end
            end

            // KEY4: 菜单开关
            if (key_press[3])
                O_menu_open <= ~O_menu_open;

            // KEY5: 窗函数循环
            if (key_press[4])
                O_win <= O_win + 2'd1;

            // 编码器短按: 切换菜单项/子模式或打开菜单
            if (sw_short_p) begin
                if (!O_menu_open)
                    O_menu_open <= 1'b1;
                else if ((O_menu_sel == 4'd0) && !O_yscale_ref && !O_lim_sub)
                    O_yscale_ref <= 1'b1;
                else if ((O_menu_sel == 4'd0) && O_yscale_ref && !O_lim_sub) begin
                    O_yscale_ref <= 1'b0;
                    O_lim_sub    <= 1'b1;
                end else if ((O_menu_sel == 4'd3) && !O_trc_sub)
                    O_trc_sub <= 1'b1;
                else if ((O_menu_sel == 4'd6) && (O_mkr_col != 10'd0) && !O_mkr_fine && !O_mkr_delta && !O_mkr_track)
                    O_mkr_fine <= 1'b1;
                else if ((O_menu_sel == 4'd6) && (O_mkr_col != 10'd0) && !O_mkr_delta && !O_mkr_track) begin
                    O_mkr_delta   <= 1'b1;
                    O_mkr_ref_col <= O_mkr_col;
                end else if ((O_menu_sel == 4'd6) && (O_mkr_col != 10'd0) && !O_mkr_track) begin
                    O_mkr_track <= 1'b1;
                    O_mkr_delta <= 1'b0;
                    O_mkr_fine  <= 1'b0;
                end else if ((O_menu_sel == 4'd7) && !O_trig_sub) begin
                    O_trig_sub <= 1'b1;
                end else if ((O_menu_sel == 4'd8) && !O_vt_sel) begin
                    O_vt_sel <= 1'b1;
                end else begin
                    O_mkr_fine   <= 1'b0;
                    O_mkr_delta  <= 1'b0;
                    O_mkr_track  <= 1'b0;
                    O_yscale_ref <= 1'b0;
                    O_lim_sub    <= 1'b0;
                    O_trc_sub    <= 1'b0;
                    O_trig_sub   <= 1'b0;
                    O_vt_sel     <= 1'b0;
                    O_menu_sel   <= (O_menu_sel == 4'd9) ? 4'd0 : (O_menu_sel + 4'd1);
                end
            end

            // 编码器旋转
            if (step_up || step_dn) begin
                if (!O_menu_open) begin
                    O_span <= step_up ? span_next(O_span) : span_prev(O_span);
                end else begin
                    case (O_menu_sel)
                        4'd0: begin
                            if (O_lim_sub) begin
                                if (step_up) O_lim_lvl <= (O_lim_lvl == 4'd8) ? 4'd0 : (O_lim_lvl + 4'd1);
                                else         O_lim_lvl <= (O_lim_lvl == 4'd0) ? 4'd8 : (O_lim_lvl - 4'd1);
                            end else if (!O_yscale_ref) begin
                                if (step_up) O_yscale <= (O_yscale == 2'd2) ? 2'd0 : (O_yscale + 2'd1);
                                else         O_yscale <= (O_yscale == 2'd0) ? 2'd2 : (O_yscale - 2'd1);
                            end else begin
                                if (step_up) O_yref <= (O_yref == 3'd0) ? 3'd0 : (O_yref - 3'd1);
                                else         O_yref <= (O_yref == 3'd4) ? 3'd4 : (O_yref + 3'd1);
                            end
                        end
                        4'd1: O_win <= step_up ? (O_win + 2'd1) : (O_win - 2'd1);
                        4'd2: O_det <= step_up ? (O_det + 2'd1) : (O_det - 2'd1);
                        4'd3: begin
                            if (!O_trc_sub) begin
                                O_trc <= step_up ? (O_trc + 2'd1) : (O_trc - 2'd1);
                            end else begin
                                if (step_up) begin
                                    O_ref_mode <= (O_ref_mode == 2'd2) ? 2'd0 : (O_ref_mode + 2'd1);
                                    if (O_ref_mode == 2'd1)
                                        O_ref_save_tog <= ~O_ref_save_tog;
                                end else begin
                                    O_ref_mode <= (O_ref_mode == 2'd0) ? 2'd2 : (O_ref_mode - 2'd1);
                                    if (O_ref_mode == 2'd0)
                                        O_ref_save_tog <= ~O_ref_save_tog;
                                end
                            end
                        end
                        4'd4: begin
                            if (step_up) O_avg <= (O_avg == 3'd4) ? 3'd0 : (O_avg + 3'd1);
                            else         O_avg <= (O_avg == 3'd0) ? 3'd4 : (O_avg - 3'd1);
                        end
                        4'd5: begin
                            O_span <= step_up ? span_next(O_span) : span_prev(O_span);
                        end
                        4'd6: begin
                            O_mkr_track <= 1'b0;
                            if ((O_mkr_col == 10'd0) && step_dn) begin
                                // Marker OFF 时逆时针旋转: 一键吸峰 (Peak -> Mkr)
                                O_mkr_col  <= (I_pk_col == 10'd0) ? 10'd1 : I_pk_col;
                                O_mkr_fine <= 1'b1;
                            end else if (O_mkr_fine) begin
                                if (step_up) O_mkr_col <= (O_mkr_col == 10'd1023) ? 10'd1023 : (O_mkr_col + 10'd1);
                                else if (O_mkr_col <= 10'd1) begin
                                    O_mkr_col   <= 10'd0;
                                    O_mkr_fine  <= 1'b0;
                                    O_mkr_delta <= 1'b0;
                                end else begin
                                    O_mkr_col <= O_mkr_col - 10'd1;
                                end
                            end else begin
                                if (step_up) O_mkr_col <= (O_mkr_col >= 10'd1007) ? 10'd1023 : (O_mkr_col + 10'd16);
                                else if (O_mkr_col <= 10'd16) begin
                                    O_mkr_col   <= 10'd0;
                                    O_mkr_delta <= 1'b0;
                                end else begin
                                    O_mkr_col <= O_mkr_col - 10'd16;
                                end
                            end
                        end
                        4'd7: begin
                            if (!O_trig_sub) begin
                                if (step_up) O_trig_mode <= (O_trig_mode == 3'd4) ? 3'd0 : (O_trig_mode + 3'd1);
                                else         O_trig_mode <= (O_trig_mode == 3'd0) ? 3'd4 : (O_trig_mode - 3'd1);
                            end else begin
                                if (step_up) O_trig_lvl <= (O_trig_lvl == 4'd8) ? 4'd8 : (O_trig_lvl + 4'd1);
                                else         O_trig_lvl <= (O_trig_lvl == 4'd0) ? 4'd0 : (O_trig_lvl - 4'd1);
                            end
                        end
                        4'd8: begin
                            if (!O_vt_sel) begin
                                if (step_up) O_vscale <= (O_vscale == 4'd13) ? 4'd0  : (O_vscale + 4'd1);
                                else         O_vscale <= (O_vscale == 4'd0)  ? 4'd13 : (O_vscale - 4'd1);
                            end else begin
                                if (step_up) O_tscale <= (O_tscale == 4'd11) ? 4'd0  : (O_tscale + 4'd1);
                                else         O_tscale <= (O_tscale == 4'd0)  ? 4'd11 : (O_tscale - 4'd1);
                            end
                        end
                        4'd9: begin
                            O_harm_mode <= step_up ? (O_harm_mode + 3'd1) : (O_harm_mode - 3'd1);
                        end
                        default: ;
                    endcase
                end
            end
        end
    end

    assign O_led = ~{I_ovr, I_heartbeat};

endmodule

// ============================================================================
// tb_key_enc.v  --  key_enc_ctrl 的功能仿真 (按键消抖 + EC11 正交解码)
//
//   验证:
//     1. 复位后 span = 0
//     2. KEY1 按一下 -> span +1 (循环)
//     3. 编码器顺时针 1 格 -> span +1
//     4. 编码器逆时针 1 格 -> span -1
//     5. 编码器短按 -> span 不变, O_fine 翻转 (精细模式)
//     6. 编码器长按 -> span 归 0 (Preset)
//     7. 转到头再转 -> 停在边界不越界
//
//   用法: vsim -c -do "run -all; quit -f" tb_key_enc
// ============================================================================
`timescale 1ns/1ps

module tb_key_enc;

    localparam real T = 13.468;              // 74.25MHz

    reg clk = 1'b0;
    always #(T/2.0) clk = ~clk;

    reg        rst_n = 1'b0;
    reg  [4:0] key   = 5'h1F;                // 全松开 (低有效)
    reg        enc_a = 1'b1;
    reg        enc_b = 1'b1;
    reg        enc_sw = 1'b1;

    wire [2:0] span;
    wire [4:0] key_press;
    wire       fine;

    key_enc_ctrl #(.SPAN_NUM(5)) u_dut (
        .I_clk       (clk    ),
        .I_rst_n     (rst_n  ),
        .I_key       (key    ),
        .I_enc_a     (enc_a  ),
        .I_enc_b     (enc_b  ),
        .I_enc_sw    (enc_sw ),
        .I_span_load (1'b0   ),
        .I_span_load_val (3'd0),
        .I_enc_mode  (1'b0   ),
        .I_span_lock (1'b0   ),
        .I_fine_en   (1'b1   ),
        .O_span      (span   ),
        .O_key_press (key_press),
        .O_fine      (fine   ),
        .O_enc_up    (       ),
        .O_enc_dn    (       )
    );

    integer errs = 0;

    integer ci = 0;
    task chk;
        input [2:0] exp;
        input [127:0] msg;
        begin
            ci = ci + 1;
            if (span !== exp) begin
                $display("check %0d: FAIL  span=%0d exp=%0d  (%0s)", ci, span, exp, msg);
                errs = errs + 1;
            end else begin
                $display("check %0d: pass  span=%0d  (%0s)", ci, span, msg);
            end
        end
    endtask

    task chk_fine;
        input exp;
        input [127:0] msg;
        begin
            ci = ci + 1;
            if (fine !== exp) begin
                $display("check %0d: FAIL  fine=%b exp=%b  (%0s)", ci, fine, exp, msg);
                errs = errs + 1;
            end else begin
                $display("check %0d: pass  fine=%b  (%0s)", ci, fine, msg);
            end
        end
    endtask

    // 按某个键 (idx 0..4), 保持 ms 毫秒
    task press_key;
        input integer idx;
        input integer ms;
        begin
            key[idx] = 1'b0;
            repeat (ms * 74250) @(posedge clk);
            key[idx] = 1'b1;
            repeat (12 * 74250) @(posedge clk);   // 等消抖恢复
        end
    endtask

    // 编码器转一格, dir=+1 顺时针, -1 逆时针; 每格 4 个状态, 每状态 2ms
    // EC11 静止态是 A=B=高(11); 转一格 = 走完 4 个状态再回到 11
    task turn;
        input integer dir;
        begin
            if (dir > 0) begin
                {enc_a, enc_b} = 2'b10; repeat (2*74250) @(posedge clk);
                {enc_a, enc_b} = 2'b00; repeat (2*74250) @(posedge clk);
                {enc_a, enc_b} = 2'b01; repeat (2*74250) @(posedge clk);
                {enc_a, enc_b} = 2'b11; repeat (2*74250) @(posedge clk);
            end else begin
                {enc_a, enc_b} = 2'b01; repeat (2*74250) @(posedge clk);
                {enc_a, enc_b} = 2'b00; repeat (2*74250) @(posedge clk);
                {enc_a, enc_b} = 2'b10; repeat (2*74250) @(posedge clk);
                {enc_a, enc_b} = 2'b11; repeat (2*74250) @(posedge clk);
            end
            repeat (3 * 74250) @(posedge clk);
        end
    endtask

    // 编码器短按 (30ms, 未达长按阈值) -> O_sw_press, O_fine 翻转
    task press_enc_sw;
        begin
            enc_sw = 1'b0;
            repeat (30 * 74250) @(posedge clk);
            enc_sw = 1'b1;
            repeat (25 * 74250) @(posedge clk);
        end
    endtask

    // 编码器长按 (1s) -> O_sw_long (Preset), 松开后不出短按
    task press_enc_long;
        begin
            enc_sw = 1'b0;
            repeat (1000 * 74250) @(posedge clk);
            enc_sw = 1'b1;
            repeat (25 * 74250) @(posedge clk);
        end
    endtask

    initial begin
        #200 rst_n = 1'b1;
        repeat (100) @(posedge clk);

        chk(3'd0, "reset");

        press_key(0, 30);        chk(3'd1, "KEY1 1st");
        press_key(0, 30);        chk(3'd2, "KEY1 2nd");

        turn(+1);                chk(3'd3, "ENC CW 1 detent");
        turn(+1);                chk(3'd4, "ENC CW 2nd -> wide");
        turn(+1);                chk(3'd4, "ENC CW at max, hold");
        turn(-1);                chk(3'd3, "ENC CCW 1 detent");
        turn(-1);                chk(3'd2, "ENC CCW 2nd");

        press_enc_sw;            chk(3'd2, "ENC short press, span hold");
                                 chk_fine(1'b1, "ENC short press -> fine");
        press_enc_sw;            chk_fine(1'b0, "ENC short press again -> fine off");
        press_enc_long;          chk(3'd0, "ENC long press = Preset");
        turn(-1);                chk(3'd0, "ENC CCW at min, hold");

        press_key(4, 30);        chk(3'd0, "KEY5 = window (span hold)");

        if (errs == 0) $display("\nALL PASS (%0d checks)", ci);
        else           $display("\n%0d of %0d FAILED", errs, ci);
        $finish;
    end

endmodule

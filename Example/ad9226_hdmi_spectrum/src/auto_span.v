// ============================================================================
// auto_span.v  --  AUTO 自动跨度选择 (KEY3)
//
//   依据 fft4096 的基波峰值检测 (O_hrm_col/O_hrm_valid), 挑选能容纳
//   "基波 + 5 次谐波"的最窄跨度档:
//     目标: 5*f0 <= 0.92 * Span  <=>  基波在新跨度下的列号 <= 188
//   f0 = col/1024 * Span_meas (测量时刻的跨度), prod = f0*1024 与测量档无关。
//     prod <= 1.84 kHz*1024 = 1_884_160     -> Span 10 kHz
//          <= 9.2  kHz*1024 = 9_420_800     -> Span 50 kHz
//          <= 46   kHz*1024 = 47_104_000    -> Span 250 kHz
//          <= 500  kHz*1024 = 512_000_000   -> Span 1 MHz
//     否则 (f0 > 500 kHz, 只有宽频档能测到) -> Span 27 MHz
//   没检测到有效峰 (峰值低于门限) 时回退 Span 1 MHz 全带概览。
//
//   结果经 I_span_load/I_span_load_val 写回 key_enc_ctrl (单一跨度源),
//   之后 KEY1/编码器/Preset 仍然正常工作。
//
//   时序: `col * span_hz` 是 10x25 位乘法, 与它后面的 4 个 35 位比较器串起来
//   曾是一条 16.9 ns 的组合链 (像素域 TNS 负值的主因)。这里拆成 4 拍状态机,
//   AUTO 只在按 KEY3 时跑一次, 多 3 拍延迟无感。
// ============================================================================
module auto_span (
    input             I_clk,
    input             I_rst_n,
    input             I_req,          // 单拍: KEY3 按下
    input             I_hrm_valid,    // 基波检测有效
    input      [9:0]  I_hrm_col,      // 基波列 (I_hrm_span 跨度下)
    input      [2:0]  I_hrm_span,     // 测量时刻的跨度档
    input      [2:0]  I_span_cur,     // 当前跨度 (非 AUTO 时透传, 未用)
    output reg [2:0]  O_span,         // AUTO 结果
    output reg        O_load          // 单拍: O_span 为 AUTO 结果, 请求加载
);

    function [24:0] span_hz;
        input [2:0] s;
        begin
            case (s)
            3'd0:    span_hz = 25'd1000000;
            3'd1:    span_hz = 25'd250000;
            3'd2:    span_hz = 25'd50000;
            3'd3:    span_hz = 25'd10000;
            default: span_hz = 25'd27000000;   // 宽频档
            endcase
        end
    endfunction

    // ---- 4 拍流水: 锁存输入 -> 乘法 -> 比较出 tgt -> 输出 ----
    reg [1:0]  st;
    reg [9:0]  col_s1;
    reg [2:0]  span_s1, cur_s1;
    reg        vld_s1;
    reg [34:0] prod_s2;
    reg [2:0]  cur_s2;
    reg        vld_s2;
    reg [2:0]  tgt_s3;

    // prod = col*Span_meas = f0*1024, 与测量档无关; 上限 1023*27e6 ≈ 2.76e10, 35bit
    wire [34:0] prod = col_s1 * span_hz(span_s1);

    // 峰贴在 DC 列 (col 0): 要么是直流偏置, 要么是信号超出当前档 Nyquist
    // 被折叠 (如 20 kHz 信号在 10 kHz 档) —— 窄档里无法区分, 统一放大一档,
    // 再按一次 AUTO 可逐级找到信号所在档
    wire alias_dc = vld_s2 && (col_s1 < 10'd4) && (cur_s2 != 3'd6);

    reg [2:0] tgt;
    always @(*) begin
        if (alias_dc)                    tgt = cur_s2 + 3'd1;
        else if (!vld_s2)                tgt = 3'd0;
        // prod = f0 x 1024; 判据取 f0 <= 10% 跨度 (被测峰落在第 ~102 列)
        else if (prod_s2 <= 35'd25600)     tgt = 3'd5;   // f0 <= 25 Hz    -> 250 Hz
        else if (prod_s2 <= 35'd102400)    tgt = 3'd4;   // f0 <= 100 Hz   -> 1 kHz
        else if (prod_s2 <= 35'd1024000)   tgt = 3'd3;   // f0 <= 1 kHz    -> 10 kHz
        else if (prod_s2 <= 35'd5120000)   tgt = 3'd2;   // f0 <= 5 kHz    -> 50 kHz
        else if (prod_s2 <= 35'd25600000)  tgt = 3'd1;   // f0 <= 25 kHz   -> 250 kHz
        else if (prod_s2 <= 35'd102400000) tgt = 3'd0;   // f0 <= 100 kHz  -> 1 MHz
        else                               tgt = 3'd6;   // f0 > 100 kHz   -> 宽频档
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            st      <= 2'd0;
            col_s1  <= 10'd0;
            span_s1 <= 3'd0;
            cur_s1  <= 3'd0;
            vld_s1  <= 1'b0;
            prod_s2 <= 35'd0;
            cur_s2  <= 3'd0;
            vld_s2  <= 1'b0;
            tgt_s3  <= 3'd0;
            O_span  <= 3'd0;
            O_load  <= 1'b0;
        end else begin
            O_load <= 1'b0;
            case (st)
            2'd0: if (I_req) begin
                      col_s1  <= I_hrm_col;
                      span_s1 <= I_hrm_span;
                      cur_s1  <= I_span_cur;
                      vld_s1  <= I_hrm_valid;
                      st      <= 2'd1;
                  end
            2'd1: begin
                      prod_s2 <= prod;
                      cur_s2  <= cur_s1;
                      vld_s2  <= vld_s1;
                      st      <= 2'd2;
                  end
            2'd2: begin
                      tgt_s3  <= tgt;
                      st      <= 2'd3;
                  end
            default: begin
                      O_span  <= tgt_s3;
                      O_load  <= 1'b1;
                      st      <= 2'd0;
                  end
            endcase
        end
    end

endmodule

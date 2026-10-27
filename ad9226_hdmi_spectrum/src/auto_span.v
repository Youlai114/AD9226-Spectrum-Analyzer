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
//   没检测到有效峰 (峰值 < -12 dBFS) 时回退 Span 1 MHz 全带概览。
//
//   结果经 I_span_load/I_span_load_val 写回 key_enc_ctrl (单一跨度源),
//   之后 KEY1/编码器/Preset 仍然正常工作。
// ============================================================================
module auto_span (
    input             I_clk,
    input             I_rst_n,
    input             I_req,          // 单拍: KEY3 按下
    input             I_hrm_valid,    // 基波检测有效
    input      [9:0]  I_hrm_col,      // 基波列 (I_hrm_span 跨度下)
    input      [2:0]  I_hrm_span,     // 测量时刻的跨度档
    input      [2:0]  I_span_cur,     // 当前跨度 (非 AUTO 时透传, 未用)
    output reg [2:0]  O_span,         // AUTO 结果 (I_req 下一拍有效)
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

    // prod = col*Span_meas = f0*1024, 与测量档无关; 上限 1023*27e6 ≈ 2.76e10, 35bit
    wire [34:0] prod = I_hrm_col * span_hz(I_hrm_span);

    reg [2:0] tgt;

    // 峰贴在 DC 列 (col 0): 要么是直流偏置, 要么是信号超出当前档 Nyquist
    // 被折叠 (如 20 kHz 信号在 10 kHz 档) —— 窄档里无法区分, 统一放大一档,
    // 再按一次 AUTO 可逐级找到信号所在档
    wire alias_dc = I_hrm_valid && (I_hrm_col < 10'd4) && (I_span_cur != 3'd4);

    always @(*) begin
        if (alias_dc)                    tgt = I_span_cur + 3'd1;
        else if (!I_hrm_valid)           tgt = 3'd0;
        else if (prod <= 35'd1884160)    tgt = 3'd3;   // 5*f0 <= 9.2 kHz
        else if (prod <= 35'd9420800)    tgt = 3'd2;   // 5*f0 <= 46 kHz
        else if (prod <= 35'd47104000)   tgt = 3'd1;   // 5*f0 <= 230 kHz
        else if (prod <= 35'd512000000)  tgt = 3'd0;   // 5*f0 <= 460 kHz (1M 档内)
        else                             tgt = 3'd4;   // f0 > 500 kHz -> 宽频档
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_span <= 3'd0;
            O_load <= 1'b0;
        end else begin
            O_load <= 1'b0;
            if (I_req) begin
                O_span <= tgt;
                O_load <= 1'b1;
            end
        end
    end

endmodule

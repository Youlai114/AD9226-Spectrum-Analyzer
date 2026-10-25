// ============================================================================
// gw_stubs.v  --  高云原语的 ModelSim 行为级桩 (仅仿真用, 不进 .gprj)
//
//   rPLL       : 按 defparam 的 IDIV_SEL/FBDIV_SEL 算输出频率
//                  CLKOUT = 27MHz x (FBDIV_SEL+1) / (IDIV_SEL+1)
//                ad9226_pll:  27 x 2/1  = 54 MHz
//                TMDS_rPLL :  27 x 55/4 = 371.25 MHz
//   CLKDIV     : HCLKIN / 5 (DIV_MODE="5")
//   DVI_TX_Top : 不做 TMDS 编码, 直接把 RGB 按 de/vs 写进帧缓存,
//                每帧结束 (vs 上升沿 且已收满 720 行) 落盘 PPM。
//                TB 通过层次引用设置 dump_en 选择要落盘的帧。
// ============================================================================
`timescale 1ns/1ps

// ---------------------------------------------------------------- rPLL
module rPLL (
    output reg CLKOUT,
    output reg LOCK,
    output     CLKOUTP,
    output     CLKOUTD,
    output     CLKOUTD3,
    input      RESET,
    input      RESET_P,
    input      CLKIN,
    input      CLKFB,
    input  [5:0] FBDSEL,
    input  [5:0] IDSEL,
    input  [5:0] ODSEL,
    input  [3:0] PSDA,
    input  [3:0] DUTYDA,
    input  [3:0] FDLY
);
    // 全部 defparam 参数都要声明 (defparam 到不存在的参数会报 elaboration 错)
    parameter FCLKIN = "27";
    parameter IDIV_SEL = 0;
    parameter FBDIV_SEL = 1;
    parameter ODIV_SEL = 16;
    parameter DYN_IDIV_SEL = 0;
    parameter DYN_FBDIV_SEL = 0;
    parameter DYN_ODIV_SEL = 0;
    parameter DYN_SDIV_SEL = 2;
    parameter PSDA_SEL = 0;
    parameter DUTYDA_SEL = 16;
    parameter DYN_DA_EN = 0;
    parameter CLKOUT_BYPASS = 0;
    parameter CLKOUTP_BYPASS = 0;
    parameter CLKOUTD_BYPASS = 0;
    parameter CLKOUT_DLY_STEP = 0;
    parameter CLKOUTP_DLY_STEP = 0;
    parameter CLKOUT_FT_DIR = 1;
    parameter CLKOUTP_FT_DIR = 1;
    parameter CLKOUTD_SRC = "CLKOUTP";
    parameter CLKOUTD3_SRC = "CLKOUTP";
    parameter CLKFB_SEL = "internal";
    parameter DEVICE = "GW2AR-18C";

    assign CLKOUTP  = 1'b0;
    assign CLKOUTD  = 1'b0;
    assign CLKOUTD3 = 1'b0;

    // 27MHz x (FBDIV+1)/(IDIV+1), 半周期用 real 计算
    real    half;
    initial half = (IDIV_SEL + 1.0) * 1000.0 / (27.0 * (FBDIV_SEL + 1.0)) / 2.0;  // ns

    initial begin
        LOCK = 1'b0;
        CLKOUT = 1'b0;
        #1000 LOCK = 1'b1;      // 1us 后锁定
    end

    always #(half) CLKOUT = ~CLKOUT;
endmodule

// ---------------------------------------------------------------- CLKDIV
module CLKDIV (
    input  RESETN,
    input  HCLKIN,
    output CLKOUT,
    input  CALIB
);
    parameter DIV_MODE = "5";
    parameter GSREN = "false";

    // 真实 CLKDIV 用双沿; /5 且 50% 占空比 => 每 5 个沿 (2.5 个周期) 翻转一次
    reg [2:0] cnt = 3'd0;
    reg       out_r = 1'b0;

    assign CLKOUT = out_r;

    always @(posedge HCLKIN or negedge HCLKIN or negedge RESETN) begin
        if (!RESETN) begin
            cnt   <= 3'd0;
            out_r <= 1'b0;
        end else begin
            if (cnt == 3'd4) begin
                cnt   <= 3'd0;
                out_r <= ~out_r;
            end else begin
                cnt <= cnt + 3'd1;
            end
        end
    end
endmodule

// ---------------------------------------------------------------- DVI_TX_Top
module DVI_TX_Top (
    input             I_rst_n,
    input             I_serial_clk,
    input             I_rgb_clk,
    input             I_rgb_vs,
    input             I_rgb_hs,
    input             I_rgb_de,
    input      [7:0]  I_rgb_r,
    input      [7:0]  I_rgb_g,
    input      [7:0]  I_rgb_b,
    output            O_tmds_clk_p,
    output            O_tmds_clk_n,
    output     [2:0]  O_tmds_data_p,
    output     [2:0]  O_tmds_data_n
);

    assign O_tmds_clk_p  = 1'b0;
    assign O_tmds_clk_n  = 1'b1;
    assign O_tmds_data_p = 3'b000;
    assign O_tmds_data_n = 3'b111;

    // ---- 帧捕获: +DUMP1=N +DUMP2=M 指定要落盘的帧号 (避免 TB 层次引用) ----
    reg  [23:0] fb [0:921599];
    integer     x, y, wy, frame;
    reg         prev_de, prev_vs;
    integer     df1, df2;
    integer     fp, i;

    initial begin
        x = 0; y = 0; wy = 0; frame = 0;
        prev_de = 1'b0; prev_vs = 1'b0;
        df1 = -1; df2 = -1;
        if (!$value$plusargs("DUMP1=%d", df1)) df1 = -1;
        if (!$value$plusargs("DUMP2=%d", df2)) df2 = -1;
    end

    always @(posedge I_rgb_clk) begin
        if (!I_rst_n) begin
            x = 0; y = 0; wy = 0; frame = 0;
            prev_de = 1'b0; prev_vs = 1'b0;
        end else begin
            // vs 上升沿: 上一帧收满 720 行则落盘, 然后行计数清零
            if (I_rgb_vs && !prev_vs) begin
                if ((y == 720) && ((frame == df1) || (frame == df2))) begin
                    fp = $fopen($sformatf("frames/top_%03d.ppm", frame), "wb");
                    $fwrite(fp, "P6\n1280 720\n255\n");
                    for (i = 0; i < 921600; i = i + 1)
                        $fwrite(fp, "%c%c%c", fb[i][23:16], fb[i][15:8], fb[i][7:0]);
                    $fclose(fp);
                    $display("[dvi] *** frame %0d dumped ***", frame);
                end
                if (y != 720)
                    $display("[dvi] frame %0d incomplete (%0d lines)", frame, y);
                y = 0;
                frame = frame + 1;
            end

            if (I_rgb_de) begin
                if (!prev_de) begin      // 行首
                    x  = 0;
                    wy = y;
                end
                fb[wy*1280 + x] = {I_rgb_r, I_rgb_g, I_rgb_b};
                x = x + 1;
            end else if (prev_de) begin  // 行尾
                y = y + 1;
            end

            prev_de = I_rgb_de;
            prev_vs = I_rgb_vs;
        end
    end

endmodule

// ============================================================================
// wave_capture.v  --  时域波形触发采集 + Vpp 测量 (1 块 BSRAM)
//
//   时钟域: adc_clk (54 MHz), 直接复用 ad9226_capture 输出的 I_smp / I_smp_en
//   存储: 1024 x 12bit SDPB (1 BSRAM), 像素时钟域直接读取 O_rd_data
//   触发: 零点上升沿触发 (带滞回 + 超时自动触发, 保证无信号/直流也能刷新)
// ============================================================================
module wave_capture (
    input             I_clk       ,   // 54 MHz (adc_clk)
    input             I_rst_n     ,
    input      [15:0] I_smp       ,   // Q4 有符号样点 (高 12 位为 ADC 码)
    input             I_smp_en    ,
    input             I_rearm     ,   // 参数切换时重新触发
    input      [2:0]  I_trig_mode ,   // 0:AUTO 1:RISE 2:FALL 3:SNGL 4:HOLD
    input      [3:0]  I_trig_lvl  ,   // 0..8: -50%..MID..+50%
    input      [1:0]  I_tdec      ,   // 0:x1(÷1) 1:x0.5(÷2) 2:x0.25(÷4)
    // ---- 像素时钟域只读接口 ----
    input             I_rd_clk    ,
    input      [9:0]  I_rd_addr   ,
    output reg signed [11:0] O_rd_data,
    // ---- 峰峰值与直流中点输出 (adc_clk 域, O_vpp_tog 握手) ----
    output reg [11:0] O_vpp       ,   // 0..4095 (ADC 码峰峰值)
    output reg signed [11:0] O_mid,   // (max + min) / 2
    output reg [9:0]  O_period_smp,   // 整数周期总样点数
    output reg [9:0]  O_period_cnt,   // 完整周期数
    output reg [9:0]  O_high_smp  ,   // 整数周期内高电平样点数
    output reg        O_meas_vld  ,   // 时域测频/占空比有效标志
    output reg        O_vpp_tog
);

    wire signed [11:0] smp_s = I_smp[15:4];

    // 1024 x 12bit 波形 RAM (1 BSRAM)
    reg signed [11:0] wave_mem [0:1023];
    reg        wr_en;
    reg [9:0]  wr_addr;
    reg signed [11:0] wr_dat;

    always @(posedge I_clk) begin
        if (wr_en)
            wave_mem[wr_addr] <= wr_dat;
    end

    always @(posedge I_rd_clk) begin
        O_rd_data <= wave_mem[I_rd_addr];
    end

    // 触发与采集状态机
    localparam [1:0] ST_ARM  = 2'd0,
                     ST_CAP  = 2'd1,
                     ST_HOLD = 2'd2;

    // 16ms @ 54MHz = 864,000 拍
    localparam [19:0] HOLD_CYCLES = 20'd864_000;

    reg [1:0]  state;
    reg        prev_arm;
    reg [13:0] wait_cnt;
    reg [19:0] hold_cnt;
    reg signed [11:0] s_min, s_max;
    reg [2:0]  trig_s0, trig_s1, trig_prev;
    reg [3:0]  lvl_s0, lvl_s1, lvl_prev;
    reg        sngl_done;
    reg [1:0]  tdec_s0, tdec_s1, tdec_prev;
    reg [1:0]  cap_div;
    wire [1:0] cap_div_reload = (tdec_s1 == 2'd2) ? 2'd3 : (tdec_s1 == 2'd1) ? 2'd1 : 2'd0;
    reg        edge_arm;
    reg [9:0]  edge_cnt, last_edge_addr, high_run, high_last;

    wire [11:0] vpp_8 = {3'b000, O_vpp[11:3]};
    reg signed [12:0] lvl_off;
    always @(*) begin
        case (lvl_s1)
            4'd0:    lvl_off = -$signed({vpp_8[10:0], 2'b00});
            4'd1:    lvl_off = -$signed({vpp_8[10:0], 1'b0}) - $signed({1'b0, vpp_8});
            4'd2:    lvl_off = -$signed({vpp_8[10:0], 1'b0});
            4'd3:    lvl_off = -$signed({1'b0, vpp_8});
            4'd5:    lvl_off =  $signed({1'b0, vpp_8});
            4'd6:    lvl_off =  $signed({vpp_8[10:0], 1'b0});
            4'd7:    lvl_off =  $signed({vpp_8[10:0], 1'b0}) + $signed({1'b0, vpp_8});
            4'd8:    lvl_off =  $signed({vpp_8[10:0], 2'b00});
            default: lvl_off =  13'sd0;
        endcase
    end

    wire signed [12:0] mid_lvl   = $signed({O_mid[11], O_mid});
    wire signed [12:0] trig_lvl  = mid_lvl + lvl_off;
    wire signed [12:0] trig_hyst = $signed({5'd0, (O_vpp[11:4] > 8'd8) ? O_vpp[11:4] : 8'd8});
    wire signed [12:0] smp_ext   = $signed({smp_s[11], smp_s});
    wire trig_rise = (trig_s1 != 3'd2) && prev_arm && (smp_ext >= trig_lvl);
    wire trig_fall = (trig_s1 == 3'd2) && prev_arm && (smp_ext <= trig_lvl);
    wire trig_hit  = trig_rise || trig_fall;
    wire trig_tout = (trig_s1 == 3'd0) && (wait_cnt == 14'd16383);
    wire cap_edge_hit = (trig_s1 == 3'd2) ? (edge_arm && (smp_ext <= mid_lvl))
                                          : (edge_arm && (smp_ext >= mid_lvl));
    wire signed [11:0] s_max_f = (smp_s > s_max) ? smp_s : s_max;
    wire signed [11:0] s_min_f = (smp_s < s_min) ? smp_s : s_min;
    wire signed [12:0] s_sum_f = $signed({s_max_f[11], s_max_f}) + $signed({s_min_f[11], s_min_f});

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state     <= ST_ARM;
            wr_en     <= 1'b0;
            wr_addr   <= 10'd0;
            wr_dat    <= 12'sd0;
            prev_arm  <= 1'b0;
            wait_cnt  <= 14'd0;
            hold_cnt  <= 20'd0;
            s_min     <= 12'sd2047;
            s_max     <= -12'sd2048;
            O_vpp        <= 12'd0;
            O_mid        <= 12'sd0;
            O_period_smp <= 10'd0;
            O_period_cnt <= 10'd0;
            O_high_smp   <= 10'd0;
            O_meas_vld   <= 1'b0;
            O_vpp_tog    <= 1'b0;
            trig_s0      <= 3'd0;
            trig_s1      <= 3'd0;
            trig_prev    <= 3'd0;
            lvl_s0       <= 4'd4;
            lvl_s1       <= 4'd4;
            lvl_prev     <= 4'd4;
            sngl_done    <= 1'b0;
            tdec_s0      <= 2'd0;
            tdec_s1      <= 2'd0;
            tdec_prev    <= 2'd0;
            cap_div      <= 2'd0;
            edge_arm     <= 1'b0;
            edge_cnt     <= 10'd0;
            last_edge_addr <= 10'd0;
            high_run     <= 10'd0;
            high_last    <= 10'd0;
        end else begin
            wr_en     <= 1'b0;
            trig_s0   <= I_trig_mode;
            trig_s1   <= trig_s0;
            trig_prev <= trig_s1;
            lvl_s0    <= I_trig_lvl;
            lvl_s1    <= lvl_s0;
            lvl_prev  <= lvl_s1;
            tdec_s0   <= I_tdec;
            tdec_s1   <= tdec_s0;
            tdec_prev <= tdec_s1;

            if (I_rearm || (trig_s1 != trig_prev) || (lvl_s1 != lvl_prev) || (tdec_s1 != tdec_prev)) begin
                state     <= ST_ARM;
                wait_cnt  <= 14'd0;
                prev_arm  <= 1'b0;
                sngl_done <= 1'b0;
                cap_div   <= 2'd0;
            end else begin
                case (state)
                    ST_ARM: begin
                        if ((trig_s1 == 3'd4) || ((trig_s1 == 3'd3) && sngl_done)) begin
                            // HOLD 或 SNGL 已捕获: 保持当前波形不刷新
                            wait_cnt <= 14'd0;
                            prev_arm <= 1'b0;
                        end else if (I_smp_en) begin
                            if (trig_s1 == 3'd2) begin
                                if (smp_ext > (trig_lvl + trig_hyst))
                                    prev_arm <= 1'b1;
                                else if (smp_ext <= trig_lvl)
                                    prev_arm <= 1'b0;
                            end else begin
                                if (smp_ext < (trig_lvl - trig_hyst))
                                    prev_arm <= 1'b1;
                                else if (smp_ext >= trig_lvl)
                                    prev_arm <= 1'b0;
                            end

                            if (trig_hit || trig_tout) begin
                                wr_en          <= 1'b1;
                                wr_addr        <= 10'd0;
                                wr_dat         <= smp_s;
                                s_min          <= smp_s;
                                s_max          <= smp_s;
                                wait_cnt       <= 14'd0;
                                cap_div        <= cap_div_reload;
                                edge_arm       <= 1'b0;
                                edge_cnt       <= 10'd0;
                                last_edge_addr <= 10'd0;
                                high_run       <= (smp_ext >= mid_lvl) ? 10'd1 : 10'd0;
                                high_last      <= 10'd0;
                                state          <= ST_CAP;
                            end else begin
                                wait_cnt <= wait_cnt + 14'd1;
                            end
                        end
                    end

                    ST_CAP: begin
                        if (I_smp_en) begin
                            if (cap_div != 2'd0) begin
                                cap_div <= cap_div - 2'd1;
                            end else begin
                                cap_div <= cap_div_reload;
                                wr_en   <= 1'b1;
                                wr_addr <= wr_addr + 10'd1;
                                wr_dat  <= smp_s;
                                if (smp_s < s_min) s_min <= smp_s;
                                if (smp_s > s_max) s_max <= smp_s;

                                if (trig_s1 == 3'd2) begin
                                    if (smp_ext > (mid_lvl + trig_hyst))
                                        edge_arm <= 1'b1;
                                    else if (smp_ext <= mid_lvl)
                                        edge_arm <= 1'b0;
                                end else begin
                                    if (smp_ext < (mid_lvl - trig_hyst))
                                        edge_arm <= 1'b1;
                                    else if (smp_ext >= mid_lvl)
                                        edge_arm <= 1'b0;
                                end
                                if (cap_edge_hit) begin
                                    edge_cnt       <= edge_cnt + 10'd1;
                                    last_edge_addr <= wr_addr + 10'd1;
                                    high_last      <= high_run;
                                end
                                if (smp_ext >= mid_lvl)
                                    high_run <= high_run + 10'd1;

                                if (wr_addr == 10'd1023) begin
                                    O_vpp        <= s_max_f - s_min_f;
                                    O_mid        <= s_sum_f[12:1];
                                    O_period_smp <= last_edge_addr;
                                    O_period_cnt <= edge_cnt;
                                    O_high_smp   <= high_last;
                                    O_meas_vld   <= (edge_cnt != 10'd0) && ((s_max_f - s_min_f) >= 12'd32);
                                    O_vpp_tog    <= ~O_vpp_tog;
                                    if (trig_s1 == 3'd3)
                                        sngl_done <= 1'b1;
                                    hold_cnt     <= 20'd0;
                                    state        <= ST_HOLD;
                                end
                            end
                        end
                    end

                    ST_HOLD: begin
                        if ((trig_s1 == 3'd4) || ((trig_s1 == 3'd3) && sngl_done)) begin
                            hold_cnt <= 20'd0;
                        end else if (hold_cnt >= HOLD_CYCLES) begin
                            wait_cnt <= 14'd0;
                            prev_arm <= 1'b0;
                            state    <= ST_ARM;
                        end else begin
                            hold_cnt <= hold_cnt + 20'd1;
                        end
                    end

                    default: state <= ST_ARM;
                endcase
            end
        end
    end

endmodule

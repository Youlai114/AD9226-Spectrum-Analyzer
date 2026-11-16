// ============================================================================
// harm_wave_synth.v  --  1~5 次时域谐波分离与合成重建模块 (2 BSRAM)
//
//   功能:
//     - 复用 FFT 复数谱 (H1..H5 的 Re, Im) 与 1024 点正弦表 (1 BSRAM)
//     - 根据 I_harm_mode (0:OFF 1:H1 2:H2 3:H3 4:H4 5:H5 6:H1-5合成)
//       自动以 H1 上升沿过零点对齐相位、自动归一化幅度并写入 1024x12bit 波形 RAM (1 BSRAM)
// ============================================================================
module harm_wave_synth (
    input                     I_clk      , // pix_clk (74.25 MHz)
    input                     I_rst_n    ,
    input             [2:0]   I_harm_mode, // 0:OFF 1..5:H1..H5 6:H1-5 SUM
    input             [1:0]   I_tdec     , // 0:÷1 1:÷2 2:÷4
    input             [9:0]   I_pk_col   ,
    input             [9:0]   I_h2_col   ,
    input             [9:0]   I_h3_col   ,
    input             [9:0]   I_h4_col   ,
    input             [9:0]   I_h5_col   ,
    input      signed [15:0]  I_h1_re    ,
    input      signed [15:0]  I_h1_im    ,
    input      signed [15:0]  I_h2_re    ,
    input      signed [15:0]  I_h2_im    ,
    input      signed [15:0]  I_h3_re    ,
    input      signed [15:0]  I_h3_im    ,
    input      signed [15:0]  I_h4_re    ,
    input      signed [15:0]  I_h4_im    ,
    input      signed [15:0]  I_h5_re    ,
    input      signed [15:0]  I_h5_im    ,
    input                     I_pk_tog   ,
    input             [9:0]   I_rd_addr  ,
    output     signed [11:0]  O_rd_data  ,
    output reg        [34:0]  O_rd_all
);

    // ------------------------------------------------------------------
    // 1024 x 16bit 有符号正弦表 (显式 initial 赋初值, 双口同时读 sin / cos)
    // ------------------------------------------------------------------
    reg        [9:0]  lut_addr_s, lut_addr_c;
    wire signed [15:0] sin_v, cos_v;

    sin_rom_1024 u_sin_rom (
        .I_clk    (I_clk     ),
        .I_addr_a (lut_addr_s),
        .I_addr_b (lut_addr_c),
        .O_data_a (sin_v     ),
        .O_data_b (cos_v     )
    );

    // ------------------------------------------------------------------
    // 1024 x 35bit 重建波形缓冲 (2 BSRAM: 单波模式存12b, ALL5模式存5x7b)
    // ------------------------------------------------------------------
    reg        [34:0] harm_mem [0:1023];
    reg               mem_wr_en;
    reg        [9:0]  mem_wr_addr;
    reg        [34:0] mem_wr_dat;

    assign O_rd_data = $signed(O_rd_all[11:0]);

    always @(posedge I_clk) begin
        if (mem_wr_en)
            harm_mem[mem_wr_addr] <= mem_wr_dat;
        O_rd_all <= harm_mem[I_rd_addr];
    end

    // ------------------------------------------------------------------
    // CDC 同步 & 参数锁存
    // ------------------------------------------------------------------
    reg       pk_tog_s1, pk_tog_s2, pk_tog_s3;
    reg [2:0] prev_mode;
    reg [1:0] prev_tdec, tdec_lat;
    reg [9:0] pk_col_lat;
    reg       synth_req;

    wire [10:0] phase_step = (tdec_lat == 2'd2) ? {pk_col_lat[8:0], 2'b00} :
                             (tdec_lat == 2'd1) ? {pk_col_lat[9:0], 1'b0}  :
                                                  {1'b0, pk_col_lat};

    reg signed [15:0] h1_re, h1_im, h2_re, h2_im, h3_re, h3_im, h4_re, h4_im, h5_re, h5_im;

    // ------------------------------------------------------------------
    // 2-Pass 合成与归一化状态机
    // ------------------------------------------------------------------
    localparam [2:0] ST_IDLE = 3'd0,
                     ST_P1   = 3'd1,
                     ST_DIV  = 3'd2,
                     ST_P2   = 3'd3;

    reg [2:0]  st;
    reg [9:0]  smp_idx;
    reg [3:0]  sub_step;     // 0..8
    reg [10:0] base_phase, k_phase;
    reg [10:0] h1_zero_phase;
    reg        zero_found;
    reg signed [17:0] h1_prev;
    reg signed [19:0] acc;
    reg [19:0] max_abs;

    // 流水乘加
    reg signed [15:0] cur_re, cur_im;
    reg signed [31:0] p_re, p_im;
    wire signed [32:0] p_diff = $signed({p_re[31], p_re}) - $signed({p_im[31], p_im});
    wire signed [17:0] term   = p_diff[32:15];

    // 归一化除法: norm_gain = (1800 << 12) / max_abs[19:0]
    reg [23:0] div_num;
    reg [20:0] div_rem;
    reg [23:0] div_q;
    reg [4:0]  div_cnt;
    reg [15:0] norm_gain;
    wire [20:0] div_rem_nxt = {div_rem[19:0], div_num[23]};
    wire        div_ge      = (div_rem_nxt >= {1'b0, max_abs});

    reg signed [36:0] scaled_p;
    wire signed [24:0] scaled_sh = scaled_p[36:12];
    wire signed [11:0] scaled_sat = (scaled_sh > 25'sd2047)  ?  12'sd2047 :
                                    (scaled_sh < -25'sd2047) ? -12'sd2047 :
                                    scaled_sh[11:0];
    wire signed [6:0]  scaled_7b  = (scaled_sh > 25'sd63)    ?  7'sd63 :
                                    (scaled_sh < -25'sd63)   ? -7'sd63 :
                                    scaled_sh[6:0];
    reg        [34:0] all_pack;

    wire [19:0] acc_abs = acc[19] ? (~acc + 20'd1) : acc;

    function signed [15:0] pick_re;
        input [2:0] k;
        begin
            case (k)
                3'd1: pick_re = h1_re;
                3'd2: pick_re = h2_re;
                3'd3: pick_re = h3_re;
                3'd4: pick_re = h4_re;
                3'd5: pick_re = h5_re;
                default: pick_re = 16'sd0;
            endcase
        end
    endfunction

    function signed [15:0] pick_im;
        input [2:0] k;
        begin
            case (k)
                3'd1: pick_im = h1_im;
                3'd2: pick_im = h2_im;
                3'd3: pick_im = h3_im;
                3'd4: pick_im = h4_im;
                3'd5: pick_im = h5_im;
                default: pick_im = 16'sd0;
            endcase
        end
    endfunction

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pk_tog_s1 <= 1'b0; pk_tog_s2 <= 1'b0; pk_tog_s3 <= 1'b0;
            prev_mode <= 3'd0; prev_tdec <= 2'd0; tdec_lat <= 2'd0; pk_col_lat <= 10'd0;
            synth_req <= 1'b0;
            h1_re <= 16'sd0; h1_im <= 16'sd0;
            h2_re <= 16'sd0; h2_im <= 16'sd0;
            h3_re <= 16'sd0; h3_im <= 16'sd0;
            h4_re <= 16'sd0; h4_im <= 16'sd0;
            h5_re <= 16'sd0; h5_im <= 16'sd0;
            st <= ST_IDLE; smp_idx <= 10'd0; sub_step <= 4'd0;
            base_phase <= 11'd0; k_phase <= 11'd0;
            lut_addr_s <= 10'd0; lut_addr_c <= 10'd256;
            h1_zero_phase <= 11'd0; zero_found <= 1'b0; h1_prev <= 18'sd0;
            acc <= 20'sd0; max_abs <= 20'd0;
            cur_re <= 16'sd0; cur_im <= 16'sd0;
            p_re <= 32'sd0; p_im <= 32'sd0;
            div_num <= 24'd0; div_rem <= 21'd0; div_q <= 16'd0; div_cnt <= 5'd0;
            norm_gain <= 16'd0; scaled_p <= 37'sd0; all_pack <= 35'd0;
            mem_wr_en <= 1'b0; mem_wr_addr <= 10'd0; mem_wr_dat <= 35'd0;
        end else begin
            pk_tog_s1 <= I_pk_tog;
            pk_tog_s2 <= pk_tog_s1;
            pk_tog_s3 <= pk_tog_s2;
            prev_mode <= I_harm_mode;
            prev_tdec <= I_tdec;
            mem_wr_en <= 1'b0;

            if (pk_tog_s2 ^ pk_tog_s3) begin
                pk_col_lat <= I_pk_col;
                tdec_lat   <= I_tdec;
                h1_re <= (I_pk_col >= 10'd3)  ? I_h1_re : 16'sd0;
                h1_im <= (I_pk_col >= 10'd3)  ? I_h1_im : 16'sd0;
                h2_re <= (I_h2_col != 10'd0) ? I_h2_re : 16'sd0;
                h2_im <= (I_h2_col != 10'd0) ? I_h2_im : 16'sd0;
                h3_re <= (I_h3_col != 10'd0) ? I_h3_re : 16'sd0;
                h3_im <= (I_h3_col != 10'd0) ? I_h3_im : 16'sd0;
                h4_re <= (I_h4_col != 10'd0) ? I_h4_re : 16'sd0;
                h4_im <= (I_h4_col != 10'd0) ? I_h4_im : 16'sd0;
                h5_re <= (I_h5_col != 10'd0) ? I_h5_re : 16'sd0;
                h5_im <= (I_h5_col != 10'd0) ? I_h5_im : 16'sd0;
                if (I_harm_mode != 3'd0)
                    synth_req <= 1'b1;
            end else if (((I_harm_mode != prev_mode) || (I_tdec != prev_tdec)) && (I_harm_mode != 3'd0)) begin
                tdec_lat  <= I_tdec;
                synth_req <= 1'b1;
            end

            case (st)
                ST_IDLE: begin
                    if (synth_req) begin
                        synth_req     <= 1'b0;
                        smp_idx       <= 10'd0;
                        sub_step      <= 4'd0;
                        base_phase    <= 11'd0;
                        k_phase       <= 11'd0;
                        h1_zero_phase <= 11'd0;
                        zero_found    <= 1'b0;
                        h1_prev       <= 18'sd0;
                        max_abs       <= 20'd0;
                        acc           <= 20'sd0;
                        st            <= ST_P1;
                    end
                end

                ST_P1: begin
                    // sub_step 0..4: 发 k=1..5 ROM 地址; 1..5: 寄存 Re/Im; 2..6: 乘; 3..7: 累加; 8: 更新 max_abs
                    if (sub_step <= 4'd4) begin
                        lut_addr_s <= k_phase[10:1];
                        lut_addr_c <= k_phase[10:1] + 10'd256;
                        k_phase    <= k_phase + base_phase;
                    end
                    if (sub_step >= 4'd1 && sub_step <= 4'd5) begin
                        cur_re <= pick_re(sub_step[2:0]);
                        cur_im <= pick_im(sub_step[2:0]);
                    end
                    if (sub_step >= 4'd2 && sub_step <= 4'd6) begin
                        p_re <= cur_re * cos_v;
                        p_im <= cur_im * sin_v;
                    end
                    if (sub_step == 4'd3) begin
                        // k=1 过零检测 (上升沿)
                        if ((smp_idx != 10'd0) && (h1_prev <= 18'sd0) && (term > 18'sd0) && !zero_found) begin
                            h1_zero_phase <= base_phase;
                            zero_found    <= 1'b1;
                        end
                        h1_prev <= term;
                        if (I_harm_mode == 3'd1 || I_harm_mode == 3'd6 || I_harm_mode == 3'd7)
                            acc <= acc + $signed({{2{term[17]}}, term});
                    end else if (sub_step >= 4'd4 && sub_step <= 4'd7) begin
                        if ((I_harm_mode == 3'd6) || (I_harm_mode == (sub_step[2:0] - 3'd2)))
                            acc <= acc + $signed({{2{term[17]}}, term});
                    end

                    if (sub_step < 4'd8) begin
                        sub_step <= sub_step + 4'd1;
                    end else begin
                        if (acc_abs > max_abs)
                            max_abs <= acc_abs;
                        sub_step <= 4'd0;
                        acc      <= 20'sd0;
                        if (smp_idx == 10'd1023) begin
                            div_num <= (I_harm_mode == 3'd7) ? 24'd245760 : 24'd7372800; // 60<<12 vs 1800<<12
                            div_rem <= 21'd0;
                            div_q   <= 16'd0;
                            div_cnt <= 5'd0;
                            st      <= ST_DIV;
                        end else begin
                            smp_idx    <= smp_idx + 10'd1;
                            base_phase <= base_phase + phase_step;
                            k_phase    <= base_phase + phase_step;
                        end
                    end
                end

                ST_DIV: begin
                    if (max_abs == 20'd0) begin
                        norm_gain <= 16'd0;
                        smp_idx   <= 10'd0;
                        sub_step  <= 4'd0;
                        base_phase<= h1_zero_phase;
                        k_phase   <= h1_zero_phase;
                        acc       <= 20'sd0;
                        st        <= ST_P2;
                    end else if (div_cnt < 5'd24) begin
                        div_rem <= div_ge ? (div_rem_nxt - {1'b0, max_abs}) : div_rem_nxt;
                        div_q   <= {div_q[22:0], div_ge};
                        div_num <= {div_num[22:0], 1'b0};
                        div_cnt <= div_cnt + 5'd1;
                    end else begin
                        norm_gain  <= (|div_q[23:16]) ? 16'hFFFF : div_q[15:0];
                        smp_idx    <= 10'd0;
                        sub_step   <= 4'd0;
                        base_phase <= h1_zero_phase;
                        k_phase    <= h1_zero_phase;
                        acc        <= 20'sd0;
                        st         <= ST_P2;
                    end
                end

                ST_P2: begin
                    if (sub_step <= 4'd4) begin
                        lut_addr_s <= k_phase[10:1];
                        lut_addr_c <= k_phase[10:1] + 10'd256;
                        k_phase    <= k_phase + base_phase;
                    end
                    if (sub_step >= 4'd1 && sub_step <= 4'd5) begin
                        cur_re <= pick_re(sub_step[2:0]);
                        cur_im <= pick_im(sub_step[2:0]);
                    end
                    if (sub_step >= 4'd2 && sub_step <= 4'd6) begin
                        p_re <= cur_re * cos_v;
                        p_im <= cur_im * sin_v;
                    end
                    if (sub_step >= 4'd3 && sub_step <= 4'd7) begin
                        if (I_harm_mode == 3'd7)
                            scaled_p <= $signed({{2{term[17]}}, term}) * $signed({1'b0, norm_gain});
                        else if ((I_harm_mode == 3'd6) || (I_harm_mode == (sub_step[2:0] - 3'd2)))
                            acc <= acc + $signed({{2{term[17]}}, term});
                    end
                    if (I_harm_mode == 3'd7) begin
                        case (sub_step)
                            4'd4: all_pack[6:0]   <= scaled_7b;
                            4'd5: all_pack[13:7]  <= scaled_7b;
                            4'd6: all_pack[20:14] <= scaled_7b;
                            4'd7: all_pack[27:21] <= scaled_7b;
                            4'd8: all_pack[34:28] <= scaled_7b;
                            default: ;
                        endcase
                    end

                    if (sub_step == 4'd8) begin
                        if (I_harm_mode != 3'd7)
                            scaled_p <= acc * $signed({1'b0, norm_gain});
                        sub_step <= 4'd9;
                    end else if (sub_step == 4'd9) begin
                        mem_wr_en   <= 1'b1;
                        mem_wr_addr <= smp_idx;
                        mem_wr_dat  <= (I_harm_mode == 3'd7) ? all_pack : {{23{scaled_sat[11]}}, scaled_sat};
                        sub_step    <= 4'd0;
                        acc         <= 20'sd0;
                        if (smp_idx == 10'd1023) begin
                            st <= ST_IDLE;
                        end else begin
                            smp_idx    <= smp_idx + 10'd1;
                            base_phase <= base_phase + phase_step;
                            k_phase    <= base_phase + phase_step;
                        end
                    end else begin
                        sub_step <= sub_step + 4'd1;
                    end
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

endmodule

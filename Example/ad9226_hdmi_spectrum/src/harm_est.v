// ============================================================================
// harm_est.v  --  时域谐波分量估计与合成 (54MHz / adc_clk 域)
//
//   目的: 在时域视图里同时画出 1~5 次谐波的正弦迹线。一路采样里各次谐波是
//         叠加在一起的, 无法从波形本身分离, 只能先用相关(相干解调)把每一次
//         谐波的复数幅度 (re, im) 估出来, 再按同一时间基重建 5 条正弦。
//
//   数据源: 直接用 wave_cap 的写入流 (I_wr_en/I_wr_addr/I_wr_data) 存一份
//           1024 点记录, 与显示端原始波形用的是同一段记录 —— 所以重建的相位
//           参考点就是触发点, 5 条分量相加 ≈ 屏幕上那条原始波形 (可互相印证)。
//
//   算法 (每帧一次; 帧周期 16.7ms, 本模块约 0.43ms 算完):
//     估计: 对 k=1..5, 在 NE=512 点上做相关
//             re_k = sum x[n]*cos(2*pi*k*f1*n/fs),  im_k = sum x[n]*sin(...)
//           相位步进 step_k = k * 2*hcol (以 2*pi/4096 为单位; hcol 是 1024 列
//           显示列号, 对应 2048 个频点里的第 2*hcol 个 -> 每样点转 2*hcol/4096 周)
//     合成: 对 k=1..5 与 n=0..NS-1 (NS=256, 正好是屏幕画的点数)
//             y_k[n] = (re_k*cos - im_k*sin) * 2/NE   -- 还原成 ADC 码值(Q4)
//           再换成屏幕行值 row = 256 + (y >> (8-amp)), 5 个 lane 拼成一个
//           50bit 字写进显示端的乒乓 RAM (每列一次读就拿到全部 5 条)
//
//   幅度档 amp (0..3 = 满屏 ±2V/±1V/±0.5V/±0.25V) 只影响行值换算的移位,
//   行值在写入时定死, 换档下一帧生效 (60Hz 帧率看不出延迟)。
//
//   精度说明: 相位步进取整到整数 bin, 与真实频点最大差半个 bin; 512 点相关
//   窗口下的幅度误差 <5% (视觉上无差别)。
// ============================================================================
module harm_est (
    input             I_clk     ,      // adc_clk (54MHz)
    input             I_rst_n   ,
    // ---- 采样记录写入流 (与 wave_cap 同源, 同拍) ----
    input             I_wr_en   ,
    input      [9:0]  I_wr_addr ,
    input      [15:0] I_wr_data ,
    // ---- 一帧记录采满 (wave_cap 的 O_frame_ok, 电平) ----
    input             I_frame_ok,
    // ---- 基波列 (1024 列显示坐标) 与幅度档, 均为本时钟域同步后的准静态值 ----
    input      [9:0]  I_hcol    ,
    input      [2:0]  I_amp     ,
    input      [1:0]  I_zoom    ,   // 时基档: 0=1024点 1=512 2=256 3=128 (决定合成步长)
    // ---- 结果写入流 (由 wave_display 写入其内部乒乓 RAM) ----
    output reg        O_we      ,
    output reg  [7:0] O_addr    ,      // 列 0..255
    output reg [49:0] O_rows           // {lane5, lane4, lane3, lane2, lane1}, 各 10bit
);

    localparam integer NE = 512;       // 估计窗口 (样点); 窗口太短时 5 个分量互相泄漏
    localparam integer NS = 256;       // 合成点数 (= 屏幕画的点数)

    //------------------------------------------------------------------
    // 记录存储: 与 wave_cap 同拍写入; 读口同步 (推断 BSRAM)
    //------------------------------------------------------------------
    reg  [15:0] smp [0:1023];
    reg  [9:0]  rd_a;
    reg  [15:0] rd_d;

    always @(posedge I_clk) begin
        if (I_wr_en)
            smp[I_wr_addr] <= I_wr_data;
    end

    always @(posedge I_clk) begin
        rd_d <= smp[rd_a];
    end

    //------------------------------------------------------------------
    // 正余弦 ROM (1 拍读延迟, 实例在 ph_mux 声明之后)
    //------------------------------------------------------------------
    wire signed [15:0] rom_v;

    //------------------------------------------------------------------
    // 状态机: 0=空闲 1=估计 2=合成 3=等下一帧
    //   cyc 0..5 为一个样点/lane 的微时序 (ROM 1 拍延迟):
    //     0: 发 sin 读
    //     1: 收 sin, 发 cos 读
    //     2: 收 cos, 乘 sin (估计) / 乘 im (合成)
    //     3: 乘 cos, 累加 im 项
    //     4: 累加 re 项 / 算出 lane 行值
    //     5: 进下一个样点 (或收尾: 归一化 / 换谐波 / 下一列)
    //------------------------------------------------------------------
    reg [2:0]  st;
    reg [2:0]  cyc;
    reg [10:0] n;      // 估计 0..NE-1 / 合成 0..NS-1
    reg [2:0]  kh;                        // 1..5
    reg [11:0] step1;                     // 2*hcol
    // 合成步长: 一列谐波对应 4/2/1 个样点 (1024/512/256,128 点视图)
    wire [11:0] st_base = {I_hcol, 1'b0};
    wire [11:0] st_zoom = (I_zoom == 2'd0) ? (st_base <<< 2) :
                          ((I_zoom == 2'd1) ? (st_base <<< 1) : st_base);
    reg [11:0] ph;                        // 估计相位累加
    reg [11:0] phk1, phk2, phk3, phk4, phk5;   // 合成相位累加 (每 lane 一个)
    reg [11:0] sk1, sk2, sk3, sk4, sk5;        // k*step1
    reg signed [43:0] acc_re, acc_im;
    reg signed [17:0] re1, im1, re2, im2, re3, im3, re4, im4, re5, im5;
    reg [49:0] rows_s;                    // 5 lane 行值移位寄存器
    reg [2:0]  amp_r;
    reg        okd;                       // I_frame_ok 上一拍
    reg [3:0]  skip;                      // 帧采满后等几拍 (让最后一个样点落 RAM)

    reg signed [15:0] cosv, sinv;
    reg signed [17:0] re_c, im_c;
    reg signed [33:0] p1, p2;

    // 三角函数只取高 12 位参与乘法: 16x12 比 16x16 省约 1/4 面积,
    // 而 12 位 (LSB=1/4096) 的量化误差 2.4e-4 远小于 ADC 的 1/2048。
    // 由此 acc 缩小 16 倍 (归一化改 >>>19), 合成 y 乘数缩小 16 倍 (改 >>>11)。
    wire signed [11:0] sin12 = sinv[15:4];
    wire signed [11:0] cos12 = cosv[15:4];

    wire ok_rise = I_frame_ok & ~okd;

    // 估计阶段当前谐波的相位步进 = kh*step1 (12bit 自动取模)
    wire [14:0] sk_prod    = step1 * {9'd0, kh};
    wire [11:0] sk_est     = sk_prod[11:0];

    // 合成阶段: 当前 lane 的系数 / 相位
    reg signed [17:0] re_c_mux, im_c_mux;
    reg        [11:0] ph_mux;
    always @(*) begin
        case (kh)
        3'd1:    begin re_c_mux = re1; im_c_mux = im1; ph_mux = phk1; end
        3'd2:    begin re_c_mux = re2; im_c_mux = im2; ph_mux = phk2; end
        3'd3:    begin re_c_mux = re3; im_c_mux = im3; ph_mux = phk3; end
        3'd4:    begin re_c_mux = re4; im_c_mux = im4; ph_mux = phk4; end
        default: begin re_c_mux = re5; im_c_mux = im5; ph_mux = phk5; end
        endcase
    end

    //------------------------------------------------------------------
    // 正余弦 ROM (1 拍读延迟)
    //   地址组合驱动: 估计阶段用 ph, 合成阶段用当前 lane 的相位
    //   (若地址也打拍, O_val 会多晚一拍, 微时序就得再拉长一个周期)
    //------------------------------------------------------------------
    wire [11:0] rom_addr = (st == 3'd1) ? ph : ph_mux;
    // cyc=0 读 sin, cyc=1 读 cos (组合产生, 才能和 1 拍 ROM 延迟对齐)
    wire        rom_c    = (cyc == 3'd1);

    sincos_rom u_sc (
        .I_clk  (I_clk    ),
        .I_addr (rom_addr ),
        .I_cos  (rom_c    ),
        .O_val  (rom_v    )
    );

    // 行值换算: row = 256 + ((p1+p2) >>> 15 >>> (8-amp))
    //   逆变换 x[n] = (2/N)*(re*cos + im*sin): 由 forward 定义 re=sum x*cos、im=sum x*sin
    //   推得 x[n] = (2/N)*(re*cos(theta) + im*sin(theta)), 所以这里是加不是减
    wire signed [34:0] y_full = {p1[33], p1} + {p2[33], p2};
    wire        [3:0]  amp_sh = 4'd8 - {1'b0, amp_r};
    wire signed [34:0] y_amp  = y_full >>> 11;
    wire signed [34:0] y_sc   = y_amp  >>> amp_sh;
    wire signed [35:0] row_s  = 36'sd256 + {{1{y_sc[34]}}, y_sc};
    wire        [9:0]  row_v  = (row_s < 36'sd0)   ? 10'd0 :
                                (row_s > 36'sd511) ? 10'd511 : row_s[9:0];

    // 估计归一化后的系数 (饱和到 18bit 有符号)
    function signed [17:0] sat18;
        input signed [43:0] a;
        begin
            if (a > 44'sd131071)       sat18 = 18'sd131071;
            else if (a < -44'sd131072) sat18 = -18'sd131072;
            else                       sat18 = a[17:0];
        end
    endfunction

    //   acc = sum x*sin_Q15 ≈ A*N/2*32768 = A*2^23, 右移 23 位得到样点幅度
    wire signed [17:0] re_norm = sat18(acc_re >>> 19);
    wire signed [17:0] im_norm = sat18(acc_im >>> 19);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            st     <= 3'd0;
            cyc    <= 3'd0;
            n      <= 10'd0;
            kh     <= 3'd1;
            step1  <= 12'd0;
            ph     <= 12'd0;
            phk1   <= 12'd0;  phk2 <= 12'd0;  phk3 <= 12'd0;
            phk4   <= 12'd0;  phk5 <= 12'd0;
            sk1    <= 12'd0;  sk2  <= 12'd0;  sk3  <= 12'd0;
            sk4    <= 12'd0;  sk5  <= 12'd0;
            acc_re <= 44'sd0;  acc_im <= 44'sd0;
            re1 <= 18'sd0;  im1 <= 18'sd0;  re2 <= 18'sd0;  im2 <= 18'sd0;
            re3 <= 18'sd0;  im3 <= 18'sd0;  re4 <= 18'sd0;  im4 <= 18'sd0;
            re5 <= 18'sd0;  im5 <= 18'sd0;
            rows_s <= 50'd0;
            cosv   <= 16'sd0; sinv  <= 16'sd0;
            re_c   <= 18'sd0; im_c  <= 18'sd0;
            p1     <= 34'sd0; p2    <= 34'sd0;
            rd_a   <= 10'd0;
            amp_r  <= 3'd1;
            okd    <= 1'b0;
            skip   <= 4'd0;
            O_we   <= 1'b0;
            O_addr <= 8'd0;
            O_rows <= 50'd0;
        end else begin
            okd  <= I_frame_ok;
            O_we <= 1'b0;

            case (st)
            //----------------------------------------------------------
            3'd0: begin
                if (ok_rise) begin
                    skip <= 4'd8;                      // 等最后几个样点落 RAM
                    st   <= 3'd4;
                end
            end

            //----------------------------------------------------------
            3'd4: begin
                if (skip != 4'd0) begin
                    skip <= skip - 4'd1;
                end else begin
                    step1  <= st_base;   // 估计用: 每样点相位步进 (与合成步长无关)
                    sk1    <= st_zoom;
                    sk2    <= st_zoom <<< 1;
                    sk3    <= (st_zoom <<< 1) + st_zoom;
                    sk4    <= st_zoom <<< 2;
                    sk5    <= (st_zoom <<< 2) + st_zoom;
                    amp_r  <= I_amp;
                    n      <= 10'd0;
                    kh     <= 3'd1;
                    ph     <= 12'd0;
                    rd_a   <= 10'd0;
                    acc_re <= 44'sd0;
                    acc_im <= 44'sd0;
                    cyc    <= 3'd0;
                    st     <= 3'd1;
                end
            end

            //----------------------------------------------------------
            3'd1: begin                            // 估计
                case (cyc)
                3'd0: begin
                    // sin 读 (rom_c 由 cyc 组合产生)
                end
                3'd1: begin
                    sinv  <= rom_v;                     // sin(ph)
                end
                3'd2: begin
                    // 样点必须按有符号相乘 (拼接 {2'b00,...} 会把它变成大正数)
                    p2    <= $signed(rd_d) * $signed(sin12);  // x*sin
                    cosv  <= rom_v;                     // cos(ph)
                end
                3'd3: begin
                    acc_im <= acc_im + {{10{p2[33]}}, p2};
                    p1     <= $signed(rd_d) * $signed(cos12); // x*cos
                end
                3'd4: begin
                    acc_re <= acc_re + {{10{p1[33]}}, p1};
                end
                3'd5: begin
                    if (n == NE - 1) begin
                        // 本谐波收尾: 归一化 (>>23) 并落寄存器
                        case (kh)
                        3'd1: begin re1 <= re_norm; im1 <= im_norm; end
                        3'd2: begin re2 <= re_norm; im2 <= im_norm; end
                        3'd3: begin re3 <= re_norm; im3 <= im_norm; end
                        3'd4: begin re4 <= re_norm; im4 <= im_norm; end
                        default: begin re5 <= re_norm; im5 <= im_norm; end
                        endcase
                        n      <= 10'd0;
                        ph     <= 12'd0;
                        rd_a   <= 10'd0;
                        acc_re <= 44'sd0;
                        acc_im <= 44'sd0;
                        if (kh == 3'd5) begin
                            st     <= 3'd2;
                            kh     <= 3'd1;
                            phk1   <= 12'd0;  phk2 <= 12'd0;  phk3 <= 12'd0;
                            phk4   <= 12'd0;  phk5 <= 12'd0;
                            rows_s <= 50'd0;
                            cyc    <= 3'd0;
                        end else begin
                            kh  <= kh + 3'd1;
                            cyc <= 3'd0;
                        end
                    end else begin
                        n    <= n + 10'd1;
                        ph   <= ph + sk_est;
                        rd_a <= n + 10'd1;
                        cyc  <= 3'd0;
                    end
                end
                default: ;
                endcase
                if (cyc != 3'd5) cyc <= cyc + 3'd1;
            end

            //----------------------------------------------------------
            3'd2: begin                            // 合成
                case (cyc)
                3'd0: begin
                    re_c  <= re_c_mux;
                    im_c  <= im_c_mux;
                end
                3'd1: begin
                    sinv  <= rom_v;                     // sin(theta)
                end
                3'd2: begin
                    p2    <= im_c * sin12;                   // im*sin
                    cosv  <= rom_v;                     // cos(theta)
                end
                3'd3: begin
                    p1    <= re_c * cos12;                   // re*cos
                end
                3'd4: begin
                    // rows_s 每列清零重来, 5 个 lane 依次移入:
                    //   kh=5 时 rows_s = {10'd0, r1, r2, r3, r4}
                    if (kh == 3'd1) rows_s <= {40'd0, row_v};
                    else            rows_s <= {rows_s[39:0], row_v};
                    // 只有第 5 个 lane 算完才是完整的一列; 输出按 {lane5..lane1}
                    if (kh == 3'd5) begin
                        O_we   <= 1'b1;
                        O_addr <= n[7:0];
                        O_rows <= {row_v, rows_s[9:0], rows_s[19:10],
                                   rows_s[29:20], rows_s[39:30]};
                    end
                end
                3'd5: begin
                    if (kh == 3'd5) begin
                        kh <= 3'd1;
                        if (n == NS - 1) begin
                            st <= 3'd3;          // 本帧算完
                        end else begin
                            n    <= n + 10'd1;
                            phk1 <= phk1 + sk1;  phk2 <= phk2 + sk2;
                            phk3 <= phk3 + sk3;  phk4 <= phk4 + sk4;
                            phk5 <= phk5 + sk5;
                        end
                    end else begin
                        kh <= kh + 3'd1;
                    end
                end
                default: ;
                endcase
                if (cyc != 3'd5) cyc <= cyc + 3'd1;
                else             cyc <= 3'd0;
            end

            //----------------------------------------------------------
            default: begin                         // 3: 等下一帧采满
                if (!I_frame_ok) st <= 3'd0;
            end
            endcase
        end
    end

endmodule

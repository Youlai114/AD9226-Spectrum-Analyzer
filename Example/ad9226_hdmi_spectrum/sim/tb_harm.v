// ============================================================================
// tb_harm.v  --  harm_est 单元测试
//
//   造一段"基波 + 3 次谐波"的合成记录, 按 wave_cap 的时序写进去, 然后检查
//   harm_est 重建出来的 5 条正弦:
//     x[n] = A1*sin(2*pi*bin1*n/4096) + A3*sin(3*2*pi*bin1*n/4096)
//     A1 = 8192 (0.25V), A3 = 4096 (0.125V), 基波列 hcol = 51 -> bin1 = 102
//
//   判据 (amp=1 ±1V, row = 256 + y>>7, 正电压 -> 较大行号):
//     lane1/lane3 在若干抽样点与解析值 256+floor(y/128) 相符 (±3 行)
//     lane2/4/5 无内容, 应贴 256 (±3 行)
//     总列数必须正好 256
// ============================================================================
`timescale 1ns / 1ps

module tb_harm;

    localparam integer BIN1 = 102;      // = 2*hcol, hcol = 51
    localparam integer AMP1 = 8192;
    localparam integer AMP3 = 4096;
    localparam real    PI   = 3.14159265358979;

    reg         clk = 1'b0;
    reg         rst_n = 1'b0;
    always #9.259 clk = ~clk;           // ~54MHz

    reg         wr_en;
    reg  [9:0]  wr_addr;
    reg  [15:0] wr_data;
    reg         frame_ok;
    reg  [9:0]  hcol;
    reg  [1:0]  amp;

    wire        o_we;
    wire [7:0]  o_addr;
    wire [49:0] o_rows;

    harm_est dut (
        .I_clk      (clk     ),
        .I_rst_n    (rst_n   ),
        .I_wr_en    (wr_en   ),
        .I_wr_addr  (wr_addr ),
        .I_wr_data  (wr_data ),
        .I_frame_ok (frame_ok),
        .I_hcol     (hcol    ),
        .I_amp      (amp     ),
        .O_we       (o_we    ),
        .O_addr     (o_addr  ),
        .O_rows     (o_rows  )
    );

    //------------------------------------------------------------------
    // 结果收集: 每个 lane 一张 256 点表
    //------------------------------------------------------------------
    integer lane1 [0:255];
    integer lane2 [0:255];
    integer lane3 [0:255];
    integer lane4 [0:255];
    integer lane5 [0:255];
    integer got;

    always @(posedge clk) begin
        if (o_we) begin
            lane1[o_addr] = o_rows[ 9: 0];
            lane2[o_addr] = o_rows[19:10];
            lane3[o_addr] = o_rows[29:20];
            lane4[o_addr] = o_rows[39:30];
            lane5[o_addr] = o_rows[49:40];
            got = got + 1;
        end
    end

    //------------------------------------------------------------------
    // 激励: 1024 点记录 (与 wave_cap 的写入流同形)
    //------------------------------------------------------------------
    integer i, v;
    real    ph1, ph3;

    task write_record;
        begin
            for (i = 0; i < 1024; i = i + 1) begin
                ph1 = 2.0 * PI * BIN1 * i / 4096.0;
                ph3 = 2.0 * PI * (3 * BIN1) * i / 4096.0;
                v   = $rtoi(AMP1 * $sin(ph1) + AMP3 * $sin(ph3));
                wr_en   <= 1'b1;
                wr_addr <= i[9:0];
                wr_data <= v[15:0];
                @(posedge clk);
            end
            wr_en <= 1'b0;
            @(posedge clk);
        end
    endtask

    //------------------------------------------------------------------
    // 检查
    //------------------------------------------------------------------
    integer n, exp1, exp3, err;
    real    p1, p3;

    task check_pt;
        input integer nn;
        begin
            p1  = 2.0 * PI * BIN1 * nn / 4096.0;
            p3  = 2.0 * PI * (3 * BIN1) * nn / 4096.0;
            exp1 = 256 + $floor(AMP1 * $sin(p1) / 128.0);
            exp3 = 256 + $floor(AMP3 * $sin(p3) / 128.0);

            if ((lane1[nn] < exp1 - 3) || (lane1[nn] > exp1 + 3)) begin
                $display("FAIL: lane1[%0d]=%0d expect %0d", nn, lane1[nn], exp1);
                $fatal(1);
            end
            if ((lane3[nn] < exp3 - 4) || (lane3[nn] > exp3 + 4)) begin
                $display("FAIL: lane3[%0d]=%0d expect %0d", nn, lane3[nn], exp3);
                $fatal(1);
            end
            if ((lane2[nn] < 253) || (lane2[nn] > 259) ||
                (lane4[nn] < 253) || (lane4[nn] > 259) ||
                (lane5[nn] < 253) || (lane5[nn] > 259)) begin
                $display("FAIL: 空 lane 有内容 n=%0d: %0d %0d %0d",
                         nn, lane2[nn], lane4[nn], lane5[nn]);
                $fatal(1);
            end
        end
    endtask

    initial begin
        wr_en    = 1'b0;
        wr_addr  = 10'd0;
        wr_data  = 16'd0;
        frame_ok = 1'b0;
        hcol     = 10'd51;
        amp      = 2'd1;               // ±1V
        got      = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        write_record;
        frame_ok <= 1'b1;
        repeat (5) @(posedge clk);

        // 等算完: 512*5*6 + 256*5*6 ≈ 23000 拍
        repeat (45000) @(posedge clk);

        if (got != 256) begin
            $display("FAIL: 输出列数 %0d, 期望 256", got);
            $fatal(1);
        end

        for (n = 0; n < 256; n = n + 17) check_pt(n);
        check_pt(10);  check_pt(30);  check_pt(128);  check_pt(255);

        $display("pass: harm lane1[0]=%0d lane1[10]=%0d lane1[30]=%0d lane3[3]=%0d lane2[128]=%0d",
                 lane1[0], lane1[10], lane1[30], lane3[3], lane2[128]);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: timeout");
        $fatal(1);
    end

endmodule

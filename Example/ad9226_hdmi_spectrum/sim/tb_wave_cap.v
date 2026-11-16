// ============================================================================
// tb_wave_cap.v  --  时域触发采集的单元测试
//
//   造一个 100kHz 等效方波 (fs=2MHz, 每 20 个时钟一个样点, 前 10 个 -1000,
//   后 10 个 +1000), 触发电平 0, 上升沿, 检查:
//     1. arm 之后不立即开始, 要等到上穿 0
//     2. 第一个记录点为正 (刚上穿)
//     3. 正好记录 1024 点, 地址 0..1023 连续
//     4. 采完置 O_frame_ok, 且在结束前不再写
// ============================================================================
`timescale 1ns/1ps

module tb_wave_cap;

    localparam real T = 18.518;          // 54MHz

    reg clk = 1'b0;
    always #(T/2.0) clk = ~clk;

    reg        rst_n   = 1'b0;
    reg [15:0] smp     = 16'sd0;
    reg        smp_en  = 1'b0;
    reg        arm     = 1'b0;
    reg [15:0] level   = 16'sd0;
    reg        trg_edge = 1'b0;          // 上升沿

    wire [9:0]  addr;
    wire [15:0] data;
    wire        we;
    wire        frame_ok;
    wire [9:0]  cnt;

    wave_cap u_dut (
        .I_clk      (clk     ),
        .I_rst_n    (rst_n   ),
        .I_smp      (smp     ),
        .I_smp_en   (smp_en  ),
        .I_arm      (arm     ),
        .I_level    (level   ),
        .I_edge     (trg_edge),
        .O_addr     (addr    ),
        .O_data     (data    ),
        .O_we       (we      ),
        .O_frame_ok (frame_ok),
        .O_cnt      (cnt     )
    );

    //------------------------------------------------------------------
    // 造样点: 每 20 拍一个, 前 10 个 -1000, 后 10 个 +1000 (50% 方波)
    //------------------------------------------------------------------
    integer n = 0;
    integer phase = 0;
    always @(posedge clk) begin
        smp_en <= 1'b0;
        n = n + 1;
        if (n % 20 == 0) begin
            smp    <= (phase < 10) ? -16'sd1000 : 16'sd1000;
            smp_en <= 1'b1;
            phase  = phase + 1;
            if (phase == 20) phase = 0;
        end
    end

    //------------------------------------------------------------------
    // 记录写入情况
    //------------------------------------------------------------------
    integer wrote = 0;
    integer last_addr = -1;
    integer first_data = 0;
    integer min_addr = 9999, max_addr = 0;
    always @(posedge clk) begin
        if (we) begin
            if (wrote == 0) first_data = $signed(data);
            if (addr < min_addr) min_addr = addr;
            if (addr > max_addr) max_addr = addr;
            last_addr = addr;
            wrote = wrote + 1;
        end
    end

    integer errs = 0;
    task chk;
        input cond;
        input [127:0] msg;
        begin
            if (!cond) begin
                $display("FAIL: %0s", msg);
                errs = errs + 1;
            end else
                $display("pass: %0s", msg);
        end
    endtask

    initial begin
        #200 rst_n = 1'b1;
        repeat (100) @(posedge clk);

        // arm 之前不应该写
        #1000;
        chk(wrote == 0, "arm 之前不写");

        arm = 1'b1; @(posedge clk); arm = 1'b0;

        // 等足够长时间采完 1024 点 (1024*20 = 20480 拍)
        repeat (30000) @(posedge clk);

        $display("dbg: wrote=%0d min=%0d max=%0d last=%0d", wrote, min_addr, max_addr, last_addr);
        chk(wrote == 1024,       "正好写 1024 点");
        chk(min_addr == 0,       "起始地址是 0");
        chk(max_addr == 1023,    "结束地址是 1023");
        chk(first_data > 0,      "上升沿触发, 第 0 点为正");
        chk(frame_ok == 1'b1,    "采完置 frame_ok");

        if (errs == 0) $display("\nALL PASS");
        else           $display("\n%0d FAILED", errs);
        $finish;
    end

endmodule

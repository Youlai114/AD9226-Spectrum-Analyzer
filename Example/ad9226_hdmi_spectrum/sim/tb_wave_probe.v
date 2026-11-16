// ============================================================================
// tb_wave_probe.v  --  wave_display 内部信号探针 v2
//   样点: smp[i] = i*256 (每样点 2 行, 每 sub 列 0.5 行)
//   期望: row(64+4i+s) = 256 + 2i + (s>=2 ? 1 : 0)
// ============================================================================
`timescale 1ns/1ps

module tb_wave_probe;

    localparam real T_PIX = 6.734;

    reg pclk = 1'b0;
    always #(T_PIX/2.0) pclk = ~pclk;

    reg  prst_n = 1'b0;
    reg  [11:0] x = 12'd0, y = 12'd360;
    reg  [1:0]  span = 2'd0;

    reg         w_fs = 1'b0, w_en = 1'b0;
    reg  [9:0]  w_addr = 10'd0;
    reg  [15:0] w_data = 16'd0;

    reg         h_we = 1'b0, h_valid = 1'b0;
    reg  [7:0]  h_addr = 8'd0;
    reg  [49:0] h_rows = 50'd0;

    wire [7:0] r, g, b;

    wave_display u_dut (
        .I_pix_clk     (pclk ),
        .I_pix_rst_n   (prst_n),
        .I_x           (x    ),
        .I_y           (y    ),
        .I_span        (span ),
        .I_amp         (3'd1),
        .I_zoom        (2'd2),
        .I_orig        (1'b1),
        .I_hvalid      (h_valid),
        .I_hwe         (h_we ),
        .I_haddr       (h_addr),
        .I_hrows       (h_rows),
        .I_wr_clk      (pclk ),
        .I_wr_rst_n    (prst_n),
        .I_frame_start (w_fs ),
        .I_wr_en       (w_en ),
        .I_wr_addr     (w_addr),
        .I_wr_mag      (w_data),
        .O_r           (r ),
        .O_g           (g ),
        .O_b           (b )
    );

    task push_frame;
        integer k;
        begin
            @(posedge pclk); #1 w_fs = 1'b1;
            @(posedge pclk); #1 w_fs = 1'b0;
            for (k = 0; k < 1024; k = k + 1) begin
                @(posedge pclk); #1 w_en = 1'b1; w_addr = k[9:0];
                w_data = k * 256;
            end
            @(posedge pclk); #1 w_en = 1'b0;
            repeat (10) @(posedge pclk);
        end
    endtask

    integer q;
    initial begin
        #100 prst_n = 1'b1;
        repeat (10) @(posedge pclk);
        push_frame;
        push_frame;

        for (q = 0; q < 200; q = q + 1) begin
            @(posedge pclk);
            if (x >= 62 && x <= 82)
                $display("x=%0d | rd_a=%0d ram=%0d ramd=%0d | x2=%0d c2=%0d n2=%0d | x3=%0d dsub=%0d vi=%0d | r3=%0d r4=%0d",
                         x, u_dut.rd_addr, u_dut.wv_ram, u_dut.wv_ram_d,
                         u_dut.x2, u_dut.cur2, u_dut.nxt2,
                         u_dut.x3, u_dut.dsub, u_dut.v_interp,
                         u_dut.row3, u_dut.row4);
            x = x + 12'd1;
        end
        $finish;
    end

endmodule

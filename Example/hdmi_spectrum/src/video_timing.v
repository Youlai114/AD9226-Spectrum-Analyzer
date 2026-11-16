// ============================================================================
// video_timing.v  --  视频时序发生器
//   产生 DE / HS / VS 以及像素坐标 (x,y)
//   默认 1280x720@60Hz (像素时钟 74.25MHz)
//   输出已打一拍, x/y 在 DE 有效期间等于 0..H_RES-1 / 0..V_RES-1
// ============================================================================
module video_timing #(
    parameter H_TOTAL  = 1650,
    parameter H_SYNC   = 40,
    parameter H_BPORCH = 220,
    parameter H_RES    = 1280,
    parameter V_TOTAL  = 750,
    parameter V_SYNC   = 5,
    parameter V_BPORCH = 20,
    parameter V_RES    = 720
)(
    input             I_clk    ,
    input             I_rst_n  ,
    output reg        O_de     ,   // 数据有效
    output reg        O_hs     ,   // 行同步 (正极性)
    output reg        O_vs     ,   // 场同步 (正极性)
    output reg [11:0] O_x      ,   // 像素列坐标
    output reg [11:0] O_y         // 像素行坐标
);

    localparam H_ACT = H_SYNC + H_BPORCH;
    localparam V_ACT = V_SYNC + V_BPORCH;

    reg [11:0] h_cnt;
    reg [11:0] v_cnt;

    wire h_end = (h_cnt >= (H_TOTAL - 1));
    wire v_end = (v_cnt >= (V_TOTAL - 1));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            h_cnt <= 12'd0;
            v_cnt <= 12'd0;
        end else begin
            h_cnt <= h_end ? 12'd0 : (h_cnt + 12'd1);
            if (h_end)
                v_cnt <= v_end ? 12'd0 : (v_cnt + 12'd1);
        end
    end

    wire de_w = (h_cnt >= H_ACT) && (h_cnt < H_ACT + H_RES) &&
                (v_cnt >= V_ACT) && (v_cnt < V_ACT + V_RES);
    wire hs_w = (h_cnt < H_SYNC);
    wire vs_w = (v_cnt < V_SYNC);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_de <= 1'b0;
            O_hs <= 1'b0;
            O_vs <= 1'b0;
            O_x  <= 12'd0;
            O_y  <= 12'd0;
        end else begin
            O_de <= de_w;
            O_hs <= hs_w;
            O_vs <= vs_w;
            O_x  <= h_cnt - H_ACT;
            O_y  <= v_cnt - V_ACT;
        end
    end

endmodule

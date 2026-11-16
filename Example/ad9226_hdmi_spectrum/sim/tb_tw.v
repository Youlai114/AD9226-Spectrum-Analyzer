`timescale 1ns/1ps
module tb_tw;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [10:0] addr = 0;
    wire [15:0] cos_w;
    twiddle_rom u (.I_clk(clk), .I_addr(addr), .O_cos(cos_w));
    integer k;
    initial begin
        #100;
        for (k = 0; k < 6; k = k + 1) begin
            addr = k[10:0]; #20;
            $display("cos[%0d]=%0d   (expect TWC)", k, $signed(cos_w));
        end
        for (k = 0; k < 6; k = k + 1) begin
            addr = (k + 1536) & 2047; #20;
            $display("cos[%0d+1536]=%0d   (expect TWS[%0d])", k, $signed(cos_w), k);
        end
        $finish;
    end
endmodule

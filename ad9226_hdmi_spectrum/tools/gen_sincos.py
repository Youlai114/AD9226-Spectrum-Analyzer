# -*- coding: utf-8 -*-
"""
gen_sincos.py -- 生成 src/sincos_rom.v (时域谐波合成的正余弦 ROM)

表: 1/4 周期正弦, 1024 x 16, rom[t] = round(32767 * sin(2*pi*t/4096)), t=0..1023
象限折叠在硬件里做 (见 sincos_rom.v 头注释), 因此只需 1024 个字 (1 块 BSRAM)。

用法:  py -3 tools/gen_sincos.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'src', 'sincos_rom.v')

N = 1024
FULL = 4096

HEAD = """// ============================================================================
// sincos_rom.v  --  正弦/余弦查找表 (由 tools/gen_sincos.py 生成, 请勿手改)
//
//   只需要 1/4 周期: rom[t] = round(32767 * sin(2*pi*t/4096)), t = 0..1023
//   输入相位 I_addr 为 12 bit (0..4095), 输出 Q15 有符号 (-32767..+32767)
//     I_cos=1 : O_val = cos(2*pi*I_addr/4096)
//     I_cos=0 : O_val = sin(2*pi*I_addr/4096)
//   象限折叠: cos 先把相位 +1024 (即 sin(theta+90)), 再取 {象限 q[1:0], 角内地址 t[9:0]}
//             q[0] 决定镜像 (tab[1023-t]), q[1] 决定符号
//   同步读 (1 拍延迟), 推断为 1 块 1024x16 BSRAM
// ============================================================================

module sincos_rom (
    input                    I_clk ,
    input      [11:0]        I_addr,   // 相位 0..4095 (2*pi/4096 为单位)
    input                    I_cos ,   // 1: cos, 0: sin
    output reg signed [15:0] O_val
);

    reg [15:0] rom [0:1023];

    initial begin
"""

TAIL = """    end

    // cos(theta) = sin(theta + 90 度): cos 走 +1024, sin 走原位
    wire [11:0] p  = I_cos ? (I_addr + 12'd1024) : I_addr;
    wire [1:0]  q  = p[11:10];
    wire [9:0]  t  = p[9:0];
    wire [9:0]  ta = q[0] ? (10'd1023 - t) : t;

    always @(posedge I_clk) begin
        O_val <= q[1] ? -$signed({1'b0, rom[ta]}) : $signed({1'b0, rom[ta]});
    end

endmodule
"""


def main():
    lines = [HEAD]
    for t in range(N):
        v = int(round(32767.0 * math.sin(2.0 * math.pi * t / FULL)))
        lines.append("        rom[%4d] = 16'd%5d;\n" % (t, v))
    lines.append(TAIL)
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(lines))
    print("wrote", os.path.normpath(OUT), "entries", N)


if __name__ == '__main__':
    main()

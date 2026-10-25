#!/bin/bash
# ============================================================================
# run_regression.sh  --  一键回归: 编译全量 RTL + 依次跑全部测试 + 汇总
#
#   用法:  bash tools/run_regression.sh
#   注意:  所有仿真输出先落 /tmp/*.log 再检查 (避免管道 SIGPIPE 杀掉 vsim)
# ============================================================================
set -u
cd "$(dirname "$0")/../sim"

# 用户 profile 的 LM_LICENSE_FILE 可能带不可见字符 (U+202A 坑), 无条件覆盖
export LM_LICENSE_FILE=D:/modeltech_10.1a/License.txt
VLOG="D:/modeltech_10.1a/win32/vlog.exe"
VSIM="D:/modeltech_10.1a/win32/vsim.exe"
PY="D:/Anaconda/python.exe"
LOG=/tmp; mkdir -p $LOG

PASS=0; FAIL=0; RESULTS=""

report() {  # name, ok(0=pass)
    if [ "$2" -eq 0 ]; then PASS=$((PASS+1)); RESULTS="$RESULTS  PASS  $1\n"
    else                   FAIL=$((FAIL+1)); RESULTS="$RESULTS  FAIL  $1\n"; fi
}

echo "=== [1/7] 编译全量 RTL + TB ==="
"$VLOG" -work work \
    ../src/ad9226_capture.v ../src/ad9226_pll.v ../src/wave_cap.v \
    ../src/fft4096.v ../src/fft_tables.v ../src/auto_span.v \
    ../src/key_enc_ctrl.v ../src/video_timing.v \
    ../src/spec_data_if.v ../src/spec_ram.v ../src/spec_display.v \
    ../src/wave_display.v ../src/ui_font_rom.v ../src/video_top.v \
    ../src/gowin_rpll/TMDS_rPLL.v \
    tb_fft.v tb_frame.v tb_key_enc.v tb_wave_frame.v gw_stubs.v tb_top.v \
    > $LOG/vlog.log 2>&1
if [ $? -ne 0 ]; then echo "编译失败:"; grep -a Error $LOG/vlog.log; exit 1; fi
echo "  编译通过"

echo "=== [2/7] FFT 比特精确 (cmp_fft, 期望 0 LSB) ==="
"$VSIM" -c -do "run -all; quit -f" work.tb_fft +F0=250e3 +AMP=2040 +DEC=0 > $LOG/fft.log 2>&1
$PY ../tools/cmp_fft.py > $LOG/cmp.log 2>&1
grep -q "0 LSB" $LOG/cmp.log; report "cmp_fft 0 LSB" $?

echo "=== [3/7] 四窗幅度校准 (期望全 pass) ==="
OK=0
for W in 1 2 3; do
    "$VSIM" -c -do "run -all; quit -f" work.tb_fft +F0=250e3 +AMP=2040 +DEC=0 +WIN=$W > $LOG/win$W.log 2>&1
    grep -aq "pass: win=$W" $LOG/win$W.log || OK=1
done
report "四窗校准 (Rect/Black/Flat)" $OK

echo "=== [4/7] 基波检测 (hrm_col 位置) ==="
"$VSIM" -c -do "run -all; quit -f" work.tb_fft +F0=100e3 +AMP=2040 +DEC=0 > $LOG/f100.log 2>&1
grep -aq "hrm_col=102" $LOG/f100.log; report "基波列 100kHz->102" $?

echo "=== [5/7] 人机界面 (key_enc, 期望 11/11) ==="
"$VSIM" -c -do "run -all; quit -f" work.tb_key_enc > $LOG/key.log 2>&1
grep -aq "ALL PASS" $LOG/key.log; report "tb_key_enc 11 项" $?

echo "=== [6/7] 时域波形 (逐列对拍) ==="
"$VSIM" -c -do "run -all; quit -f" work.tb_wave_frame > $LOG/wave.log 2>&1
$PY ../tools/ppm2png.py frames/wave_000.ppm > /dev/null 2>&1
$PY - > $LOG/wavechk.log 2>&1 <<'EOF'
from PIL import Image
px = Image.open('frames/wave_000.png').convert('RGB').load()
cols = sum(1 for x in range(64,1088,4)
           if any(abs(px[x,y][1]-232)<40 and abs(px[x,y][2]-100)<40 for y in range(104,616)))
print("OK" if cols >= 250 else "NG cols=%d" % cols)
EOF
grep -q "^OK$" $LOG/wavechk.log; report "wave 迹线完整性" $?

echo "=== [7/7] 顶层三时钟域 (F0/谐波表/标记/迹线) ==="
"$VSIM" -c -do "run -all; quit -f" work.tb_top +DUMP1=3 +DUMP2=4 > $LOG/top.log 2>&1
$PY ../tools/ppm2png.py frames/top_004.ppm > /dev/null 2>&1
$PY - > $LOG/topchk.log 2>&1 <<'EOF'
from PIL import Image
p = Image.open('frames/top_004.png').convert('RGB').load()
def cnt(x0,x1,y0,y1,c):
    return sum(1 for x in range(x0,x1) for y in range(y0,y1) if p[x,y]==c)
f0 = cnt(912,1120,32,48,(60,216,120))
h  = cnt(16,576,64,80,(60,216,120))
tr = cnt(64,1088,104,300,(255,216,0))
mk = sum(1 for c,(r,g,b) in {166:(0,255,0),268:(0,255,255),370:(255,0,255),
                             472:(255,160,0),574:(192,96,255)}.items()
        if sum(1 for y in range(104,112) for dx in range(-6,7) if p[c+dx,y]==(r,g,b))>10)
print("OK" if (f0>200 and h>400 and tr>100 and mk==5) else "NG f0=%d h=%d tr=%d mk=%d"%(f0,h,tr,mk))
EOF
grep -q "^OK$" $LOG/topchk.log; report "tb_top F0/H表/标记/迹线" $?

echo ""
echo "==================== 回归汇总 ===================="
echo -e "$RESULTS"
echo "  通过 $PASS / $((PASS+FAIL))"
if [ $FAIL -eq 0 ]; then echo "  ALL PASS"; else echo "  失败项日志: $LOG/{fft,win*,f100,key,wave,top}.log"; fi
exit $FAIL

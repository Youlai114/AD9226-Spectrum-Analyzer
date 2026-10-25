# ============================================================================
# build.tcl  --  命令行跑完整流程 (综合 + 布局布线 + 时序 + 比特流)
#
#   用法:  gw_sh build.tcl
#   产物:  impl/pnr/ad9226_hdmi_spectrum.fs   (高云 Programmer 用 .fs 烧录)
#
#   ★ 必须用 open_project 打开 .gprj, 不能只用 add_file 逐个加文件:
#     后者不会读 .sdc, create_clock / set_input_delay 全部失效,
#     看起来"时序通过"其实是没约束。踩过一次。
# ============================================================================
open_project ad9226_hdmi_spectrum.gprj
run all

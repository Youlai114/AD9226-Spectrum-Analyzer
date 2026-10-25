// ============================================================================
// ad9226_pll.v  --  高云 rPLL: 板载 27MHz 晶振 -> 54MHz (AD9226 采样时钟)
//
//   GW2AR-18C (Tang Nano 20K), 高云 rPLL 的参数约定:
//     CLKOUT = FCLKIN x (FBDIV_SEL+1) / (IDIV_SEL+1)
//     VCO    = CLKOUT x ODIV_SEL        (必须落在 500 ~ 1250 MHz)
//     CLKOUTD= CLKOUT / DYN_SDIV_SEL    (2 ~ 128)
//
//     CLKOUT = 27 x 2 / 1 = 54.000 MHz
//     VCO    = 54 x 16    = 864 MHz      (在 500~1250 内)
//
//   为什么不是原例程的 65MHz:
//     板载晶振是 27MHz, 65MHz 无法用 rPLL 的整数分频精确得到
//     (27 * a / b / c = 65 无整数解, 最近的是 67.5MHz, 已超出 AD9226 的 65MSPS 上限)。
//     54MHz 在 AD9226 规格内 (<=65MSPS), 且 27/13.5/6.75 三个跨度都能由 54MHz 整数抽取得到。
// ============================================================================
module ad9226_pll (
    output clk_out,     // 54 MHz
    output locked,
    input  clkin        // 27 MHz
);

wire gw_gnd;
wire clkoutp_o;
wire clkoutd_o;
wire clkoutd3_o;

assign gw_gnd = 1'b0;

rPLL rpll_inst (
    .CLKOUT  (clk_out  ),
    .LOCK    (locked   ),
    .CLKOUTP (clkoutp_o),
    .CLKOUTD (clkoutd_o),
    .CLKOUTD3(clkoutd3_o),
    .RESET   (gw_gnd   ),
    .RESET_P (gw_gnd   ),
    .CLKIN   (clkin    ),
    .CLKFB   (gw_gnd   ),
    .FBDSEL  ({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
    .IDSEL   ({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
    .ODSEL   ({gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
    .PSDA    ({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
    .DUTYDA  ({gw_gnd, gw_gnd, gw_gnd, gw_gnd}),
    .FDLY    ({gw_gnd, gw_gnd, gw_gnd, gw_gnd})
);

defparam rpll_inst.FCLKIN           = "27";
defparam rpll_inst.DYN_IDIV_SEL     = "false";
defparam rpll_inst.IDIV_SEL         = 0;      // 输入 /1
defparam rpll_inst.DYN_FBDIV_SEL    = "false";
defparam rpll_inst.FBDIV_SEL        = 1;      // 反馈 x2  -> CLKOUT 54MHz
defparam rpll_inst.DYN_ODIV_SEL     = "false";
defparam rpll_inst.ODIV_SEL         = 16;     // VCO = 54 x 16 = 864MHz
defparam rpll_inst.PSDA_SEL         = "0000";
defparam rpll_inst.DYN_DA_EN        = "true";
defparam rpll_inst.DUTYDA_SEL       = "1000";
defparam rpll_inst.CLKOUT_FT_DIR    = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR   = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP  = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL        = "internal";
defparam rpll_inst.CLKOUT_BYPASS    = "false";
defparam rpll_inst.CLKOUTP_BYPASS   = "false";
defparam rpll_inst.CLKOUTD_BYPASS   = "false";
defparam rpll_inst.DYN_SDIV_SEL     = 2;
defparam rpll_inst.CLKOUTD_SRC      = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC     = "CLKOUT";
defparam rpll_inst.DEVICE           = "GW2AR-18C";

endmodule

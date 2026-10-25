library verilog;
use verilog.vl_types.all;
entity ad9226_pll is
    port(
        clk_out         : out    vl_logic;
        locked          : out    vl_logic;
        clkin           : in     vl_logic
    );
end ad9226_pll;

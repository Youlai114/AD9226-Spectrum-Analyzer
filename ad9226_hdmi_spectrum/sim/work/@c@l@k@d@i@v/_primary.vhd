library verilog;
use verilog.vl_types.all;
entity CLKDIV is
    generic(
        DIV_MODE        : string  := "5";
        GSREN           : string  := "false"
    );
    port(
        RESETN          : in     vl_logic;
        HCLKIN          : in     vl_logic;
        CLKOUT          : out    vl_logic;
        CALIB           : in     vl_logic
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of DIV_MODE : constant is 1;
    attribute mti_svvh_generic_type of GSREN : constant is 1;
end CLKDIV;

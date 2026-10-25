library verilog;
use verilog.vl_types.all;
entity DVI_TX_Top is
    port(
        I_rst_n         : in     vl_logic;
        I_serial_clk    : in     vl_logic;
        I_rgb_clk       : in     vl_logic;
        I_rgb_vs        : in     vl_logic;
        I_rgb_hs        : in     vl_logic;
        I_rgb_de        : in     vl_logic;
        I_rgb_r         : in     vl_logic_vector(7 downto 0);
        I_rgb_g         : in     vl_logic_vector(7 downto 0);
        I_rgb_b         : in     vl_logic_vector(7 downto 0);
        O_tmds_clk_p    : out    vl_logic;
        O_tmds_clk_n    : out    vl_logic;
        O_tmds_data_p   : out    vl_logic_vector(2 downto 0);
        O_tmds_data_n   : out    vl_logic_vector(2 downto 0)
    );
end DVI_TX_Top;

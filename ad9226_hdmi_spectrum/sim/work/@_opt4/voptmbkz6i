library verilog;
use verilog.vl_types.all;
entity video_top is
    port(
        I_clk           : in     vl_logic;
        I_rst           : in     vl_logic;
        I_key           : in     vl_logic_vector(4 downto 0);
        I_enc_a         : in     vl_logic;
        I_enc_b         : in     vl_logic;
        I_enc_sw        : in     vl_logic;
        O_led           : out    vl_logic_vector(1 downto 0);
        O_tmds_clk_p    : out    vl_logic;
        O_tmds_clk_n    : out    vl_logic;
        O_tmds_data_p   : out    vl_logic_vector(2 downto 0);
        O_tmds_data_n   : out    vl_logic_vector(2 downto 0);
        O_clk_adc       : out    vl_logic;
        I_adc_d         : in     vl_logic_vector(11 downto 0);
        I_adc_otr       : in     vl_logic
    );
end video_top;

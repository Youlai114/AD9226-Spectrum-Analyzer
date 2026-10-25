library verilog;
use verilog.vl_types.all;
entity key_enc_ctrl is
    generic(
        SPAN_NUM        : integer := 4;
        ENC_STEP        : integer := 4
    );
    port(
        I_clk           : in     vl_logic;
        I_rst_n         : in     vl_logic;
        I_key           : in     vl_logic_vector(4 downto 0);
        I_enc_a         : in     vl_logic;
        I_enc_b         : in     vl_logic;
        I_enc_sw        : in     vl_logic;
        I_span_load     : in     vl_logic;
        I_span_load_val : in     vl_logic_vector(1 downto 0);
        I_enc_mode      : in     vl_logic;
        O_csr_up        : out    vl_logic;
        O_csr_dn        : out    vl_logic;
        O_sw_press      : out    vl_logic;
        O_span          : out    vl_logic_vector(2 downto 0);
        O_key_press     : out    vl_logic_vector(4 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of SPAN_NUM : constant is 1;
    attribute mti_svvh_generic_type of ENC_STEP : constant is 1;
end key_enc_ctrl;

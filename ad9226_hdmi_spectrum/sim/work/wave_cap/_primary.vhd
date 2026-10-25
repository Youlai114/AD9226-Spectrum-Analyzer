library verilog;
use verilog.vl_types.all;
entity wave_cap is
    port(
        I_clk           : in     vl_logic;
        I_rst_n         : in     vl_logic;
        I_smp           : in     vl_logic_vector(15 downto 0);
        I_smp_en        : in     vl_logic;
        I_arm           : in     vl_logic;
        I_level         : in     vl_logic_vector(15 downto 0);
        I_edge          : in     vl_logic;
        O_addr          : out    vl_logic_vector(9 downto 0);
        O_data          : out    vl_logic_vector(15 downto 0);
        O_we            : out    vl_logic;
        O_wr_start      : out    vl_logic;
        O_frame_ok      : out    vl_logic;
        O_cnt           : out    vl_logic_vector(9 downto 0)
    );
end wave_cap;

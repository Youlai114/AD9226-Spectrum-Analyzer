library verilog;
use verilog.vl_types.all;
entity spec_demo_gen is
    port(
        I_clk           : in     vl_logic;
        I_rst_n         : in     vl_logic;
        I_frame_tick    : in     vl_logic;
        O_frame_start   : out    vl_logic;
        O_wr_en         : out    vl_logic;
        O_wr_addr       : out    vl_logic_vector(9 downto 0);
        O_wr_mag        : out    vl_logic_vector(15 downto 0)
    );
end spec_demo_gen;

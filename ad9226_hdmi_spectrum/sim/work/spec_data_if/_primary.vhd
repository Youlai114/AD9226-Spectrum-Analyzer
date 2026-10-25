library verilog;
use verilog.vl_types.all;
entity spec_data_if is
    port(
        I_wr_clk        : in     vl_logic;
        I_wr_rst_n      : in     vl_logic;
        I_frame_start   : in     vl_logic;
        I_wr_en         : in     vl_logic;
        I_wr_addr       : in     vl_logic_vector(9 downto 0);
        I_wr_mag        : in     vl_logic_vector(15 downto 0);
        I_rd_clk        : in     vl_logic;
        I_rd_rst_n      : in     vl_logic;
        O_wr_en         : out    vl_logic;
        O_wr_bank       : out    vl_logic;
        O_wr_addr       : out    vl_logic_vector(9 downto 0);
        O_wr_mag        : out    vl_logic_vector(15 downto 0);
        O_rd_bank       : out    vl_logic;
        O_frame_cnt     : out    vl_logic_vector(15 downto 0);
        O_frame_tog     : out    vl_logic
    );
end spec_data_if;

library verilog;
use verilog.vl_types.all;
entity spec_display is
    port(
        I_pix_clk       : in     vl_logic;
        I_pix_rst_n     : in     vl_logic;
        I_x             : in     vl_logic_vector(11 downto 0);
        I_y             : in     vl_logic_vector(11 downto 0);
        I_span          : in     vl_logic_vector(2 downto 0);
        I_hrm_valid     : in     vl_logic;
        I_hrm_col       : in     vl_logic_vector(9 downto 0);
        I_hrm_span      : in     vl_logic_vector(1 downto 0);
        I_csr_en        : in     vl_logic;
        I_csr_mode      : in     vl_logic_vector(1 downto 0);
        I_csr_col       : in     vl_logic_vector(9 downto 0);
        I_h2            : in     vl_logic_vector(15 downto 0);
        I_h3            : in     vl_logic_vector(15 downto 0);
        I_h4            : in     vl_logic_vector(15 downto 0);
        I_h5            : in     vl_logic_vector(15 downto 0);
        I_wf_en         : in     vl_logic;
        I_menu_hide     : in     vl_logic;
        I_win           : in     vl_logic_vector(1 downto 0);
        I_wr_clk        : in     vl_logic;
        I_wr_rst_n      : in     vl_logic;
        I_frame_start   : in     vl_logic;
        I_wr_en         : in     vl_logic;
        I_wr_addr       : in     vl_logic_vector(9 downto 0);
        I_wr_mag        : in     vl_logic_vector(15 downto 0);
        O_r             : out    vl_logic_vector(7 downto 0);
        O_g             : out    vl_logic_vector(7 downto 0);
        O_b             : out    vl_logic_vector(7 downto 0)
    );
end spec_display;

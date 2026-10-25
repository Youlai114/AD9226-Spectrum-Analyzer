library verilog;
use verilog.vl_types.all;
entity fft4096 is
    generic(
        N               : integer := 4096;
        NLOG            : integer := 12
    );
    port(
        I_clk           : in     vl_logic;
        I_rst_n         : in     vl_logic;
        I_frame_req     : in     vl_logic;
        O_cap_start     : out    vl_logic;
        O_busy          : out    vl_logic;
        I_smp           : in     vl_logic_vector(15 downto 0);
        I_smp_en        : in     vl_logic;
        O_frame_start   : out    vl_logic;
        O_mag_en        : out    vl_logic;
        O_mag_addr      : out    vl_logic_vector(9 downto 0);
        O_mag           : out    vl_logic_vector(15 downto 0);
        O_hrm_col       : out    vl_logic_vector(9 downto 0);
        O_hrm_valid     : out    vl_logic;
        O_hrm_tog       : out    vl_logic;
        O_h2            : out    vl_logic_vector(15 downto 0);
        O_h3            : out    vl_logic_vector(15 downto 0);
        O_h4            : out    vl_logic_vector(15 downto 0);
        O_h5            : out    vl_logic_vector(15 downto 0);
        I_mag_flat      : in     vl_logic;
        I_win           : in     vl_logic_vector(1 downto 0);
        I_avg_fast      : in     vl_logic;
        I_cfg_id        : in     vl_logic_vector(4 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of N : constant is 1;
    attribute mti_svvh_generic_type of NLOG : constant is 1;
end fft4096;

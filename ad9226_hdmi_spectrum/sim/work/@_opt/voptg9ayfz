library verilog;
use verilog.vl_types.all;
entity fft2048 is
    generic(
        N               : integer := 2048;
        NLOG            : integer := 11
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
        O_mag           : out    vl_logic_vector(15 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of N : constant is 1;
    attribute mti_svvh_generic_type of NLOG : constant is 1;
end fft2048;

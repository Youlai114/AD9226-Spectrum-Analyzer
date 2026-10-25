library verilog;
use verilog.vl_types.all;
entity video_timing is
    generic(
        H_TOTAL         : integer := 1650;
        H_SYNC          : integer := 40;
        H_BPORCH        : integer := 220;
        H_RES           : integer := 1280;
        V_TOTAL         : integer := 750;
        V_SYNC          : integer := 5;
        V_BPORCH        : integer := 20;
        V_RES           : integer := 720
    );
    port(
        I_clk           : in     vl_logic;
        I_rst_n         : in     vl_logic;
        O_de            : out    vl_logic;
        O_hs            : out    vl_logic;
        O_vs            : out    vl_logic;
        O_x             : out    vl_logic_vector(11 downto 0);
        O_y             : out    vl_logic_vector(11 downto 0)
    );
    attribute mti_svvh_generic_type : integer;
    attribute mti_svvh_generic_type of H_TOTAL : constant is 1;
    attribute mti_svvh_generic_type of H_SYNC : constant is 1;
    attribute mti_svvh_generic_type of H_BPORCH : constant is 1;
    attribute mti_svvh_generic_type of H_RES : constant is 1;
    attribute mti_svvh_generic_type of V_TOTAL : constant is 1;
    attribute mti_svvh_generic_type of V_SYNC : constant is 1;
    attribute mti_svvh_generic_type of V_BPORCH : constant is 1;
    attribute mti_svvh_generic_type of V_RES : constant is 1;
end video_timing;

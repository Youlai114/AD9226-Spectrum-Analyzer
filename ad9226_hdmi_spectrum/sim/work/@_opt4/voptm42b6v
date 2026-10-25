library verilog;
use verilog.vl_types.all;
entity auto_span is
    port(
        I_clk           : in     vl_logic;
        I_rst_n         : in     vl_logic;
        I_req           : in     vl_logic;
        I_hrm_valid     : in     vl_logic;
        I_hrm_col       : in     vl_logic_vector(9 downto 0);
        I_hrm_span      : in     vl_logic_vector(2 downto 0);
        I_span_cur      : in     vl_logic_vector(2 downto 0);
        O_span          : out    vl_logic_vector(2 downto 0);
        O_load          : out    vl_logic
    );
end auto_span;

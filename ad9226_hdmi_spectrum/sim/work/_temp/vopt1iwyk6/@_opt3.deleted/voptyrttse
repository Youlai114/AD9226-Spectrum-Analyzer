library verilog;
use verilog.vl_types.all;
entity spec_ram is
    port(
        I_wr_clk        : in     vl_logic;
        I_wr_en         : in     vl_logic;
        I_wr_bank       : in     vl_logic;
        I_wr_addr       : in     vl_logic_vector(9 downto 0);
        I_wr_data       : in     vl_logic_vector(15 downto 0);
        I_rd_clk        : in     vl_logic;
        I_rd_bank       : in     vl_logic;
        I_rd_addr       : in     vl_logic_vector(9 downto 0);
        O_rd_data       : out    vl_logic_vector(15 downto 0)
    );
end spec_ram;

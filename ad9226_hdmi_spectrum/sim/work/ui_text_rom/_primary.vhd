library verilog;
use verilog.vl_types.all;
entity ui_text_rom is
    port(
        I_clk           : in     vl_logic;
        I_addr          : in     vl_logic_vector(14 downto 0);
        O_data          : out    vl_logic_vector(10 downto 0)
    );
end ui_text_rom;

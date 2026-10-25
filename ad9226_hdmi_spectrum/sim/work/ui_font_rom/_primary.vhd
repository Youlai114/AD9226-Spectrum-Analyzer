library verilog;
use verilog.vl_types.all;
entity ui_font_rom is
    port(
        I_clk           : in     vl_logic;
        I_ch            : in     vl_logic_vector(7 downto 0);
        I_row           : in     vl_logic_vector(2 downto 0);
        O_bits          : out    vl_logic_vector(7 downto 0)
    );
end ui_font_rom;

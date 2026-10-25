library verilog;
use verilog.vl_types.all;
entity AD9220_ReadModule is
    port(
        clk_driver      : out    vl_logic;
        ADC_Data        : out    vl_logic_vector(12 downto 0);
        clk             : in     vl_logic;
        rstn            : in     vl_logic;
        IO_data         : in     vl_logic_vector(12 downto 0)
    );
end AD9220_ReadModule;

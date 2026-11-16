#------------------GLOBAL--------------------#
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED"
set_global_assignment -name ENABLE_INIT_DONE_OUTPUT OFF

#复位引脚
set_location_assignment	PIN_M1	-to rstn

#时钟引脚
set_location_assignment	PIN_R9	-to clk

#ADC_CLK
set_location_assignment	PIN_C9	-to clk_driver
#ADC_IO
set_location_assignment	PIN_E15	-to IO_data[0]
set_location_assignment	PIN_J14	-to IO_data[1]
set_location_assignment	PIN_J12	-to IO_data[2]
set_location_assignment	PIN_L10	-to IO_data[3]
set_location_assignment	PIN_K10	-to IO_data[4]
set_location_assignment	PIN_K9	-to IO_data[5]
set_location_assignment	PIN_F14	-to IO_data[6]
set_location_assignment	PIN_F13	-to IO_data[7]
set_location_assignment	PIN_D14	-to IO_data[8]
set_location_assignment	PIN_G11	-to IO_data[9]
set_location_assignment	PIN_C14	-to IO_data[10]
set_location_assignment	PIN_E11	-to IO_data[11]
set_location_assignment	PIN_D12	-to IO_data[12]

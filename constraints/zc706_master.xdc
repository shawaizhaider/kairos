# System clock
set_property PACKAGE_PIN H9 [get_ports sysclk_p]
set_property IOSTANDARD LVDS [get_ports sysclk_p]
set_property PACKAGE_PIN G9 [get_ports sysclk_n]
set_property IOSTANDARD LVDS [get_ports sysclk_n]
create_clock -name sysclk -period 5.000 [get_ports sysclk_p]

# System Reset (Mapped to Pushbutton SW4)
set_property PACKAGE_PIN AK25 [get_ports sys_reset]
set_property IOSTANDARD LVCMOS25 [get_ports sys_reset]
set_property PACKAGE_PIN R27 [get_ports btn_continue_0]
set_property IOSTANDARD LVCMOS25 [get_ports btn_continue_0]
set_property PACKAGE_PIN AB17 [get_ports vid_switch_0]
set_property IOSTANDARD LVCMOS25 [get_ports vid_switch_0]

# I2C Interface (Mapped via IOBUF components)
set_property PACKAGE_PIN AJ14 [get_ports iic_scl]
set_property IOSTANDARD LVCMOS25 [get_ports iic_scl]
set_property PULLTYPE PULLUP [get_ports iic_scl]

set_property PACKAGE_PIN AJ18 [get_ports iic_sda]
set_property IOSTANDARD LVCMOS25 [get_ports iic_sda]
set_property PULLTYPE PULLUP [get_ports iic_sda]

# ADV7511 HDMI Video Interface
set_property PACKAGE_PIN P28 [get_ports hdmi_out_clk_0]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_out_clk_0]

set_property PACKAGE_PIN U21 [get_ports hdmi_vsync_0]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_vsync_0]
set_property PACKAGE_PIN R22 [get_ports hdmi_hsync_0]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_hsync_0]
set_property PACKAGE_PIN V24 [get_ports hdmi_data_e_0]
set_property IOSTANDARD LVCMOS25 [get_ports hdmi_data_e_0]

# HDMI Data Pins
set_property PACKAGE_PIN U24 [get_ports {hdmi_data_0[0]}]
set_property PACKAGE_PIN T22 [get_ports {hdmi_data_0[1]}]
set_property PACKAGE_PIN R23 [get_ports {hdmi_data_0[2]}]
set_property PACKAGE_PIN AA25 [get_ports {hdmi_data_0[3]}]
set_property PACKAGE_PIN AE28 [get_ports {hdmi_data_0[4]}]
set_property PACKAGE_PIN T23 [get_ports {hdmi_data_0[5]}]
set_property PACKAGE_PIN AB25 [get_ports {hdmi_data_0[6]}]
set_property PACKAGE_PIN T27 [get_ports {hdmi_data_0[7]}]
set_property PACKAGE_PIN AD26 [get_ports {hdmi_data_0[8]}]
set_property PACKAGE_PIN AB26 [get_ports {hdmi_data_0[9]}]
set_property PACKAGE_PIN AA28 [get_ports {hdmi_data_0[10]}]
set_property PACKAGE_PIN AC26 [get_ports {hdmi_data_0[11]}]
set_property PACKAGE_PIN AE30 [get_ports {hdmi_data_0[12]}]
set_property PACKAGE_PIN Y25 [get_ports {hdmi_data_0[13]}]
set_property PACKAGE_PIN AA29 [get_ports {hdmi_data_0[14]}]
set_property PACKAGE_PIN AD30 [get_ports {hdmi_data_0[15]}]
set_property PACKAGE_PIN Y28 [get_ports {hdmi_data_0[16]}]
set_property PACKAGE_PIN AF28 [get_ports {hdmi_data_0[17]}]
set_property PACKAGE_PIN V22 [get_ports {hdmi_data_0[18]}]
set_property PACKAGE_PIN AA27 [get_ports {hdmi_data_0[19]}]
set_property PACKAGE_PIN U22 [get_ports {hdmi_data_0[20]}]
set_property PACKAGE_PIN N28 [get_ports {hdmi_data_0[21]}]
set_property PACKAGE_PIN V21 [get_ports {hdmi_data_0[22]}]
set_property PACKAGE_PIN AC22 [get_ports {hdmi_data_0[23]}]
set_property IOSTANDARD LVCMOS25 [get_ports {hdmi_data_0[*]}]

# SPDIF Audio Interface
set_property PACKAGE_PIN AC21 [get_ports spdif_out_0]
set_property IOSTANDARD LVCMOS25 [get_ports spdif_out_0]

# LEDs
set_property PACKAGE_PIN W21 [get_ports {leds_0[0]}]
set_property IOSTANDARD LVCMOS25 [get_ports {leds_0[0]}]
set_property PACKAGE_PIN Y21 [get_ports {leds_0[1]}]
set_property IOSTANDARD LVCMOS25 [get_ports {leds_0[1]}]
set_property PACKAGE_PIN G2 [get_ports {leds_0[2]}]
set_property IOSTANDARD LVCMOS15 [get_ports {leds_0[2]}]
set_property PACKAGE_PIN A17 [get_ports {leds_0[3]}]
set_property IOSTANDARD LVCMOS15 [get_ports {leds_0[3]}]
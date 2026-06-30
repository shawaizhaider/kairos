`timescale 1ns / 1ps
`default_nettype none

module top_wrapper (
    input  wire        clk_74_25mhz,
    input  wire        clk_locked,
    input  wire        sys_rst,
    input  wire        btn_continue,
    input  wire        iic_scl_i,
    output wire        iic_scl_o,
    output wire        iic_scl_t,
    input  wire        iic_sda_i,
    output wire        iic_sda_o,
    output wire        iic_sda_t,
    output wire        hdmi_out_clk,
    output wire        hdmi_hsync,
    output wire        hdmi_vsync,
    output wire        hdmi_data_e,
    output wire [23:0] hdmi_data,
    output wire [3:0]  leds
);

    wire [1:0] btn;
    assign btn[0] = sys_rst;
    assign btn[1] = btn_continue;

    top_level u_top_level (
        .clk_74_25mhz(clk_74_25mhz),
        .clk_locked(clk_locked),
        .btn(btn),
        .hdmi_out_clk(hdmi_out_clk),
        .hdmi_hsync(hdmi_hsync),
        .hdmi_vsync(hdmi_vsync),
        .hdmi_data_e(hdmi_data_e),
        .hdmi_data(hdmi_data),
        .iic_scl_i(iic_scl_i),
        .iic_scl_o(iic_scl_o),
        .iic_scl_t(iic_scl_t),
        .iic_sda_i(iic_sda_i),
        .iic_sda_o(iic_sda_o),
        .iic_sda_t(iic_sda_t)
    );

    assign leds = 4'b0000;

endmodule

`default_nettype wire

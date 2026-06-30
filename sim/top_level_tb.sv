`timescale 1ns / 1ps
`default_nettype none

module top_level_tb;

    logic clk_74_25mhz;
    logic clk_locked;
    logic [1:0] btn;
    logic hdmi_out_clk;
    logic hdmi_hsync;
    logic hdmi_vsync;
    logic hdmi_data_e;
    logic [23:0] hdmi_data;
    logic iic_scl_i;
    logic iic_scl_o;
    logic iic_scl_t;
    logic iic_sda_i;
    logic iic_sda_o;
    logic iic_sda_t;

    top_level uut (
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

    always begin
        #5;
        clk_74_25mhz = !clk_74_25mhz;
    end

    initial begin
        $dumpfile("top_level.vcd");
        $dumpvars(0, top_level_tb);
        $display("Starting Sim\n");
        clk_74_25mhz = 0;
        clk_locked = 0;
        btn = 2'b00;
        iic_scl_i = 1'b1;
        iic_sda_i = 1'b1;
        #20;
        clk_locked = 1;
        #20;
        btn[0] = 1'b1;
        #20;
        btn[0] = 1'b0;
        #20;
        btn[1] = 1'b1;
        #20;
        btn[1] = 1'b0;
        repeat (200) begin
            #10;
        end
        $display("hdmi_out_clk=%0b hdmi_hsync=%0b hdmi_vsync=%0b hdmi_data_e=%0b hdmi_data=%h", hdmi_out_clk, hdmi_hsync, hdmi_vsync, hdmi_data_e, hdmi_data);
        $display("iic_scl_o=%0b iic_scl_t=%0b iic_sda_o=%0b iic_sda_t=%0b", iic_scl_o, iic_scl_t, iic_sda_o, iic_sda_t);
        $finish;
    end

endmodule // top_level_tb

`default_nettype wire

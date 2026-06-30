`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 05/09/2026 01:39:10 PM
// Design Name: 
// Module Name: spdif_tx_wrapper
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module spdif_tx_wrapper #(
    parameter CLK_HZ = 74250000
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, ASSOCIATED_BUSIF s_axis" *)
    input  wire        clk,
    
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        rst_n,
    
    // AXI-Stream Input (Perfectly matches the Data FIFO)
    input  wire [31:0] s_axis_tdata,
    input  wire [3:0]  s_axis_tkeep, 
    input  wire        s_axis_tlast, 
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    
    // Physical Output
    output wire        spdif_out,

    // NEW: Hardware Switch Input for Payload Muting
    input  wire        vid_switch
);

    // Convert the Active-Low AXI reset into Active-High for our custom logic
    wire rst_high = ~rst_n;

    // Payload Muting: Pass data if switch is 1, pass PCM zero (silence) if 0.
    wire [31:0] safe_audio_data = vid_switch ? s_axis_tdata : 32'h00000000;

    // Instantiate the SystemVerilog audio engine
    spdif_tx #(
        .CLK_HZ(CLK_HZ)
    ) u_spdif_tx (
        .clk(clk),
        .rst(rst_high),
        .s_axis_tdata(safe_audio_data), // <-- Intercepted payload
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .spdif_out(spdif_out)
    );

endmodule

//`timescale 1ns / 1ps

//module spdif_tx_wrapper #(
//    parameter CLK_HZ = 74250000
//) (
//    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *)
//    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst_n, ASSOCIATED_BUSIF s_axis" *)
//    input  wire        clk,
    
//    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *)
//    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
//    input  wire        rst_n,
    
//    // AXI-Stream Input (Perfectly matches the Data FIFO)
//    input  wire [31:0] s_axis_tdata,
//    input  wire [3:0]  s_axis_tkeep, 
//    input  wire        s_axis_tlast, 
//    input  wire        s_axis_tvalid,
//    output wire        s_axis_tready,
    
//    // Physical Output
//    output wire        spdif_out
//);

//    // Convert the Active-Low AXI reset into Active-High for our custom logic
//    wire rst_high = ~rst_n;

//    // Instantiate the SystemVerilog audio engine
//    spdif_tx #(
//        .CLK_HZ(CLK_HZ)
//    ) u_spdif_tx (
//        .clk(clk),
//        .rst(rst_high),
//        .s_axis_tdata(s_axis_tdata),
//        .s_axis_tvalid(s_axis_tvalid),
//        .s_axis_tready(s_axis_tready),
//        .spdif_out(spdif_out)
//    );

//endmodule
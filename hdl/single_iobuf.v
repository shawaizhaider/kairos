`timescale 1ns / 1ps

module single_iobuf (
    input  wire I,   // Input from your custom logic
    output wire O,   // Output to your custom logic
    input  wire T,   // Tristate control
    inout  wire IO   // The physical external pin
);

    // This explicitly calls the hardware IOBUF primitive inside the FPGA
    IOBUF IOBUF_inst (
        .O(O),   
        .I(I),   
        .T(T),   
        .IO(IO)  
    );

endmodule
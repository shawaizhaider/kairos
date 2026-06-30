`timescale 1ns / 1ps
`default_nettype none

module frame_buffer #(
    parameter FMA_COUNT=2,
    parameter ITERS_BITS=4, 
    parameter WIDTH=1280,   // UPGRADED for 720p
    parameter HEIGHT=720    // UPGRADED for 720p
) (
    input wire sys_clk_in,
    input wire hdmi_clk_in,
    input wire rst_in,
    input wire mandelbrot_iters_valid_in,
    input wire [FMA_COUNT*ITERS_BITS-1:0] mandelbrot_iters_in,
    input wire [$clog2(WIDTH*HEIGHT)-1:0]  addr_write_in,
    input wire [$clog2(1280)-1:0]  x_draw_in,
    input wire [$clog2(720)-1:0] y_draw_in,
    input wire swap_in, 
    output logic [7:0] red_out,
    output logic [7:0] green_out,
    output logic [7:0] blue_out,
    output logic GPU_writing_to_BRAM_A_out 
);

    logic GPU_writing_to_BRAM_A; 
    assign GPU_writing_to_BRAM_A_out = GPU_writing_to_BRAM_A;

    always_ff @(posedge sys_clk_in) begin
        if (rst_in) begin
            GPU_writing_to_BRAM_A <= 1;
        end else if (swap_in) begin
            GPU_writing_to_BRAM_A <= swap_in ? !GPU_writing_to_BRAM_A : GPU_writing_to_BRAM_A;
        end
    end

    logic clock_a, clock_b;
    assign clock_a = GPU_writing_to_BRAM_A ? sys_clk_in : hdmi_clk_in;
    assign clock_b = !GPU_writing_to_BRAM_A ? sys_clk_in : hdmi_clk_in;

    logic [ITERS_BITS-1:0] out_a;
    logic [ITERS_BITS-1:0] out_b;
    logic [ITERS_BITS-1:0] iters_out;
    assign iters_out = !GPU_writing_to_BRAM_A ? out_a : out_b;

    logic [16*8-1:0] red_gradient = {8'd66, 8'd25, 8'd9, 8'd4, 8'd0, 8'd12, 8'd24, 8'd57, 8'd134, 8'd211, 8'd241, 8'd248, 8'd255, 8'd204, 8'd153, 8'd0};
    logic [16*8-1:0] green_gradient = {8'd30, 8'd7, 8'd1, 8'd4, 8'd7, 8'd44, 8'd82, 8'd125, 8'd181, 8'd236, 8'd233, 8'd201, 8'd170, 8'd128, 8'd87, 8'd0};
    logic [16*8-1:0] blue_gradient = {8'd15, 8'd26, 8'd47, 8'd73, 8'd100, 8'd138, 8'd177, 8'd209, 8'd229, 8'd248, 8'd191, 8'd95, 8'd0, 8'd0, 8'd0, 8'd0};

    always_comb begin
        if (x_draw_in < WIDTH && y_draw_in < HEIGHT) begin
            red_out = red_gradient[16*8 - 8*(iters_out+1) +: 8];
            green_out = green_gradient[16*8 - 8*(iters_out+1) +: 8];
            blue_out = blue_gradient[16*8 - 8*(iters_out+1) +: 8];
        end else begin
            red_out = 8'b0;
            green_out = 8'b0;
            blue_out = 8'b0;
        end
    end

    logic writing_iters_flag;
    logic [$clog2(FMA_COUNT):0] iters_index;
    logic [FMA_COUNT*ITERS_BITS-1:0] mandelbrot_iters_buffer;
    logic [ITERS_BITS-1:0] iters_to_write;

    logic write_enable_a, write_enable_b;
    assign write_enable_a = GPU_writing_to_BRAM_A && writing_iters_flag;
    assign write_enable_b = !GPU_writing_to_BRAM_A && writing_iters_flag;

    logic read_enable_a, read_enable_b;
    assign read_enable_a = !write_enable_a;
    assign read_enable_b = !write_enable_b;

    always_ff @(posedge sys_clk_in) begin
        if (rst_in) begin
            writing_iters_flag <= 0;
            iters_index <= 0;
            mandelbrot_iters_buffer <= 0;
            iters_to_write <= 0;
        end else begin
            if (mandelbrot_iters_valid_in) begin
                mandelbrot_iters_buffer <= mandelbrot_iters_in;
                writing_iters_flag <= 1;
                iters_index <= 0;
                iters_to_write <= mandelbrot_iters_in[ITERS_BITS*FMA_COUNT - (0+1)*ITERS_BITS +: ITERS_BITS];
            end else if (writing_iters_flag) begin
                iters_index <= iters_index + 1;
                writing_iters_flag <= iters_index != FMA_COUNT - 1;
                iters_to_write <= mandelbrot_iters_buffer[ITERS_BITS*FMA_COUNT - (iters_index+1 + 1)*ITERS_BITS +: ITERS_BITS];
            end
        end
    end

    localparam int ADDR_W = $clog2(2*WIDTH*HEIGHT);
    localparam logic [ADDR_W-1:0] BRAM_HALF = WIDTH * HEIGHT;

    logic [ADDR_W-1:0] addr_write_GPU, addr_read_HDMI;
    assign addr_write_GPU = addr_write_in + iters_index;
    assign addr_read_HDMI = x_draw_in * HEIGHT + y_draw_in;

    logic [ADDR_W-1:0] addr_a, addr_b;
    assign addr_a = GPU_writing_to_BRAM_A ? addr_write_GPU : addr_read_HDMI;
    assign addr_b = !GPU_writing_to_BRAM_A ? addr_write_GPU : addr_read_HDMI;

    logic [ADDR_W-1:0] addr_b_offset;
    assign addr_b_offset = addr_b + BRAM_HALF;

    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(ITERS_BITS),                        
        .RAM_DEPTH(2*WIDTH*HEIGHT),       
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"), 
        .INIT_FILE("")                     
    ) memory_BRAM (
        .addra(addr_a),         
        .dina(iters_to_write),  
        .clka(clock_a),         
        .wea(write_enable_a),   
        .regcea(read_enable_a), 
        .douta(out_a),          
        .ena(1'b1),             
        .rsta(1'b0),            

        .addrb(addr_b_offset),   
        .dinb(iters_to_write),  
        .clkb(clock_b),         
        .web(write_enable_b),   
        .regceb(read_enable_b), 
        .doutb(out_b),          
        .enb(1'b1),             
        .rstb(1'b0)             
    );
endmodule

`default_nettype none
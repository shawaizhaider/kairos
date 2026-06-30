`timescale 1ns / 1ps
`default_nettype none

module top_level(
    input wire clk_74_25mhz,
    input wire clk_locked,
    input wire [1:0] btn, // two momentary button switches
    output logic hdmi_out_clk,
    output logic hdmi_hsync,
    output logic hdmi_vsync,
    output logic hdmi_data_e,
    output logic [23:0] hdmi_data,
    input wire iic_scl_i,
    output logic iic_scl_o,
    output logic iic_scl_t,
    input wire iic_sda_i,
    output logic iic_sda_o,
    output logic iic_sda_t
);
    wire clk_pixel = clk_74_25mhz;
    logic sys_rst;
    assign sys_rst = btn[0] || !clk_locked;

    logic iic_scl_oe;
    logic iic_sda_oe;
    wire iic_scl_in = iic_scl_i;
    wire iic_sda_in = iic_sda_i;

    assign iic_scl_o = 1'b0;
    assign iic_scl_t = ~iic_scl_oe;
    assign iic_sda_o = 1'b0;
    assign iic_sda_t = ~iic_sda_oe;

    logic adv_init_done;
    logic adv_init_error;
    adv7511_init adv_init (
        .clk(clk_pixel),
        .rst(sys_rst),
        .scl_in(iic_scl_in),
        .sda_in(iic_sda_in),
        .scl_oe(iic_scl_oe),
        .sda_oe(iic_sda_oe),
        .done(adv_init_done),
        .error(adv_init_error)
    );

    logic sys_continue, clean_btn_out, clean_btn_out_prev;
    debouncer btn1_db(
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .dirty_in(btn[1]),
        .clean_out(clean_btn_out)
    );

    always_ff @(posedge clk_pixel) begin
        sys_continue <= (clean_btn_out_prev == 0 && clean_btn_out == 1);
        clean_btn_out_prev <= clean_btn_out;
    end

    // START HDMI SETUP
    logic [10:0] hcount, hcount_unscaled;
    logic [9:0] vcount, vcount_unscaled;
    logic vert_sync;
    logic hor_sync;
    logic active_draw;
    logic new_frame;
    logic [5:0] frame_count;

    video_sig_gen mvg(
        .clk_pixel_in(clk_pixel),
        .rst_in(sys_rst),
        .hcount_out(hcount_unscaled),
        .vcount_out(vcount_unscaled),
        .vs_out(vert_sync),
        .hs_out(hor_sync),
        .ad_out(active_draw),
        .nf_out(new_frame),
        .fc_out(frame_count)
    );

    assign hcount = hcount_unscaled;
    assign vcount = vcount_unscaled;

    logic [7:0] red, green, blue;

    assign hdmi_out_clk = clk_pixel;
    assign hdmi_hsync = hor_sync;
    assign hdmi_vsync = vert_sync;
    assign hdmi_data_e = active_draw;
    assign hdmi_data = {red, green, blue};
    // END HDMI SETUP

    // START GPU SETUP

    localparam PRIVATE_REG_WIDTH=32; // UPGRADED
    localparam PRIVATE_REG_COUNT=16;
    localparam INSTRUCTION_WIDTH=32;
    localparam INSTRUCTION_COUNT=100;
    localparam DATA_CACHE_WIDTH=32;  // UPGRADED
    localparam DATA_CACHE_DEPTH=4096;

    localparam FIXED_POINT=24;       // UPGRADED
    localparam WORD_WIDTH=32;        // UPGRADED
    
    // DROPPED TO 32 TO PREVENT VIVADO RAM CRASH
    localparam FMA_COUNT=32;         
    localparam LINE_WIDTH=FMA_COUNT * 3 * WORD_WIDTH;

    localparam ADDR_LENGTH=$clog2(36000 / LINE_WIDTH);

    localparam WIDTH=1280;
    localparam HEIGHT=720;
    localparam ITERS_BITS=4;

    logic [WORD_WIDTH*FMA_COUNT-1:0] fma_out_bus;
    logic [FMA_COUNT-1:0] fma_valid_bus;
    logic [WORD_WIDTH*FMA_COUNT-1:0] write_buffer_fma_out;
    logic [FMA_COUNT-1:0] write_buffer_fma_valid_out;
    logic [3*WORD_WIDTH*FMA_COUNT-1:0] write_buffer_line_out;
    logic write_buffer_line_valid;

    logic [0:INSTRUCTION_WIDTH-1] memory_instr_in;
    logic memory_instr_valid_in;
    logic [LINE_WIDTH-1:0] memory_abc_out;
    logic memory_use_new_c_out;
    logic memory_fma_output_can_be_valid_out;
    logic memory_abc_valid_out;
    logic frame_buffer_swap_out;
    logic mandelbrot_iters_valid_out;
    logic [ITERS_BITS*FMA_COUNT-1:0] mandelbrot_iters_out;
    logic [$clog2(WIDTH*HEIGHT)-1:0] mandelbrot_addr_out;
    logic [LINE_WIDTH-1:0] write_buffer_out;
    logic [LINE_WIDTH-1:0] bram_temp_in_out;

    logic [PRIVATE_REG_WIDTH-1:0] controller_reg_a, controller_reg_b, controller_reg_c;
    logic [15:0] iters_out; 
    logic [3:0] reg_index_in;
    logic [PRIVATE_REG_WIDTH-1:0] reg_out;
    logic [7:0] instr_index_out;

    localparam int FMA_SLICE_WIDTH = 3 * WORD_WIDTH;

    generate
        for (genvar fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin : gen_fma
            fma #(
                .WIDTH(WORD_WIDTH),
                .FIXED_POINT(FIXED_POINT)
            ) fma_inst (
                .clk_in(clk_pixel),
                .rst_in(sys_rst),
                .abc(memory_abc_out[(FMA_COUNT - fma_id - 1) * FMA_SLICE_WIDTH +: FMA_SLICE_WIDTH]),
                .valid_in(memory_abc_valid_out),
                .c_valid_in(memory_use_new_c_out),
                .output_can_be_valid_in(memory_fma_output_can_be_valid_out),
                .out(fma_out_bus[(FMA_COUNT - fma_id - 1) * WORD_WIDTH +: WORD_WIDTH]),
                .valid_out(fma_valid_bus[FMA_COUNT - fma_id - 1])
            );
        end
    endgenerate
    

    fma_write_buffer #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .LINE_WIDTH(LINE_WIDTH)
    ) write_buffer (
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .fma_out(write_buffer_fma_out),
        .fma_valid_out(write_buffer_fma_valid_out),
        .line_out(write_buffer_line_out),
        .line_valid(write_buffer_line_valid)
    );

    memory #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .LINE_WIDTH(LINE_WIDTH),
        .ADDR_LENGTH(ADDR_LENGTH),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .ITERS_BITS(ITERS_BITS),
        .WIDTH(WIDTH),    
        .HEIGHT(HEIGHT)   
    ) main_memory (
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .controller_reg_a(controller_reg_a),
        .controller_reg_b(controller_reg_b),
        .controller_reg_c(controller_reg_c),
        .write_buffer_read_in(write_buffer_line_out),
        .write_buffer_valid_in(write_buffer_line_valid),
        .instr_in(memory_instr_in),
        .instr_valid_in(memory_instr_valid_in),
        .abc_out(memory_abc_out),
        .abc_valid_out(memory_abc_valid_out),
        .use_new_c_out(memory_use_new_c_out),
        .fma_output_can_be_valid_out(memory_fma_output_can_be_valid_out),
        .frame_buffer_swap_out(frame_buffer_swap_out),
        .mandelbrot_iters_valid_out(mandelbrot_iters_valid_out),
        .mandelbrot_iters_out(mandelbrot_iters_out),
        .mandelbrot_addr_out(mandelbrot_addr_out),
        .write_buffer_out(write_buffer_out), 
        .bram_temp_in_out(bram_temp_in_out)   
    );

    controller #(
        .PROGRAM_FILE("mandelbrot_720.mem"),
        .PRIVATE_REG_WIDTH(PRIVATE_REG_WIDTH),
        .PRIVATE_REG_COUNT(PRIVATE_REG_COUNT),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .INSTRUCTION_COUNT(INSTRUCTION_COUNT),
        .DATA_CACHE_WIDTH(DATA_CACHE_WIDTH),
        .DATA_CACHE_DEPTH(DATA_CACHE_DEPTH)
    ) controller_module (
        .clk_in(clk_pixel),
        .rst_in(sys_rst),
        .continue_in(sys_continue),
        .instr_out(memory_instr_in),
        .reg_a_out(controller_reg_a),
        .reg_b_out(controller_reg_b),
        .reg_c_out(controller_reg_c),
        .instr_valid_for_memory_out(memory_instr_valid_in),
        .iters_out(iters_out), 
        .reg_index_in(reg_index_in), 
        .reg_out(reg_out), 
        .instr_index_out(instr_index_out) 
    );

    always_comb begin
           write_buffer_fma_out = fma_out_bus;
           write_buffer_fma_valid_out = fma_valid_bus;
    end

    // END GPU SETUP
    
    // START FRAME BUFFER SETUP

    logic GPU_writing_to_BRAM_A_out;

    frame_buffer #(
        .FMA_COUNT(FMA_COUNT),
        .ITERS_BITS(ITERS_BITS),
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT)
    ) fb (
        .sys_clk_in(clk_pixel),
        .hdmi_clk_in(clk_pixel),
        .rst_in(sys_rst),
        .mandelbrot_iters_valid_in(mandelbrot_iters_valid_out),
        .mandelbrot_iters_in(mandelbrot_iters_out),
        .addr_write_in(mandelbrot_addr_out),
        .x_draw_in(hcount),
        .y_draw_in(vcount),
        .swap_in(frame_buffer_swap_out),
        .red_out(red),
        .green_out(green),
        .blue_out(blue),
        .GPU_writing_to_BRAM_A_out(GPU_writing_to_BRAM_A_out)
    );
    // END FRAME BUFFER SETUP
    
    assign reg_index_in = 4'b0;

endmodule // top_level

`default_nettype wire
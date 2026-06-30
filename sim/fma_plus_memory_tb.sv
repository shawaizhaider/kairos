`timescale 1ns / 1ps
`default_nettype none

module fma_plus_memory_tb;

    localparam INSTRUCTION_WIDTH = 32;
    localparam FIXED_POINT = 24;
    localparam WORD_WIDTH = 32;
    localparam FMA_COUNT = 32;
    localparam LINE_WIDTH = FMA_COUNT * 3 * WORD_WIDTH;
    localparam ADDR_LENGTH = $clog2(36000 / LINE_WIDTH);

    // make logics for inputs and outputs!
    logic clk_in;
    logic rst_in;

    // logics for FMAs
    logic [WORD_WIDTH*FMA_COUNT-1:0] fma_out_bus;
    logic [FMA_COUNT-1:0] fma_valid_bus;

    // logics for fma write buffer
    logic [3*WORD_WIDTH*FMA_COUNT-1:0] write_buffer_line_out;
    logic write_buffer_line_valid;

    // logics for memory
    logic [0:INSTRUCTION_WIDTH-1] memory_instr_in;
    logic memory_instr_valid_in;
    logic [LINE_WIDTH-1:0] memory_abc_out;
    logic memory_use_new_c_out, memory_abc_valid_out;
    logic memory_fma_output_can_be_valid_out;
    logic [WORD_WIDTH-1:0] controller_reg_a, controller_reg_b, controller_reg_c;

    generate
        for (genvar fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin : gen_fma
            fma #(
                .WIDTH(WORD_WIDTH),
                .FIXED_POINT(FIXED_POINT)
            ) fma_inst (
                .clk_in(clk_in),
                .rst_in(rst_in),
                .abc(memory_abc_out[(FMA_COUNT - fma_id - 1) * 3 * WORD_WIDTH +: 3 * WORD_WIDTH]),
                .valid_in(memory_abc_valid_out),
                .c_valid_in(memory_use_new_c_out),
                .output_can_be_valid_in(memory_fma_output_can_be_valid_out),
                .out(fma_out_bus[(FMA_COUNT - fma_id - 1) * WORD_WIDTH +: WORD_WIDTH]),
                .valid_out(fma_valid_bus[FMA_COUNT - fma_id - 1])
            );
        end
    endgenerate

    // Instantiate write buffer!
    fma_write_buffer #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .LINE_WIDTH(LINE_WIDTH)
    ) write_buffer (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .fma_out(fma_out_bus),
        .fma_valid_out(fma_valid_bus),
        .line_out(write_buffer_line_out),
        .line_valid(write_buffer_line_valid)
    );

    // Instantiate memory module!
    memory #(
        .FMA_COUNT(FMA_COUNT),
        .WORD_WIDTH(WORD_WIDTH),
        .FIXED_POINT(FIXED_POINT),
        .LINE_WIDTH(LINE_WIDTH),
        .ADDR_LENGTH(ADDR_LENGTH),
        .INSTRUCTION_WIDTH(INSTRUCTION_WIDTH),
        .WIDTH(1280),
        .HEIGHT(720),
        .ITERS_BITS(4)
    ) main_memory (
        .clk_in(clk_in),
        .rst_in(rst_in),
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
        .frame_buffer_swap_out(),
        .mandelbrot_iters_valid_out(),
        .mandelbrot_iters_out(),
        .mandelbrot_addr_out(),
        .write_buffer_out(),
        .bram_temp_in_out()
    );

    // Declare testbench variables here
    logic [INSTRUCTION_WIDTH-1:0] addr;

    always begin
        #5;
        clk_in = !clk_in;
    end

    //initial block...this is our test simulation
    initial begin
        $dumpfile("fma_plus_memory.vcd"); //file to store value change dump (vcd)
        $dumpvars(0, fma_plus_memory_tb); //store everything at the current level and below
        $display("Starting Sim\n"); //print nice message
        clk_in = 0; //initialize clk (super important)
        rst_in = 0; //initialize rst (super important)
        controller_reg_a = 0;
        controller_reg_b = 0;
        controller_reg_c = 0;
        memory_instr_in = 0;
        memory_instr_valid_in = 0;
        #10  //wait a little bit of time at beginning
        rst_in = 1; //reset system
        #10; //hold high for a few clock cycles
        rst_in = 0;
        #10;

        // Goal for this testbench is to compute (1*2 + 3), (4*5 + 6) in parallel
        
        //////////////////////////////////////////////////
        // Step 1: load some values into memory
        //////////////////////////////////////////////////

        // op code is SMA        addr is 0_0000_0001
        addr = 32'b0110___0000___0000_0000_0000_0001___0000___0000;
        memory_instr_in = addr;
        memory_instr_valid_in = 1;
        #10;
        // Give instructions that fill the line at that address with DATA
        // op code is LOADI
        memory_instr_in = 32'b0111___0000___0000_0000_0000_0001___0000___0000;
        #10;
        memory_instr_in = 32'b0111___0001___0000_0000_0000_0010___0000___0000;
        #10;
        memory_instr_in = 32'b0111___0010___0000_0000_0000_0011___0000___0000;
        #10;
        memory_instr_in = 32'b0111___0011___0000_0000_0000_0100___0000___0000;
        #10;
        memory_instr_in = 32'b0111___0100___0000_0000_0000_0101___0000___0000;
        #10;
        memory_instr_in = 32'b0111___0101___0000_0000_0000_0110___0000___0000;
        #10; 
        // op code is SENDL
        memory_instr_in = 32'b1000___0000___0000_0000_0000_0000___0000___0000;
        // BRAM is written to in one cycle
        #10;

        // op code is WRITEB (replace_c is 1)
        memory_instr_in = 32'b1010___0001___0000_0000_0000_0000___0000___0000;
        // BRAM takes two cycles to read, then send to FMA blocks
        #10;
        // default instruction is NOP
        memory_instr_in = 32'b0000___0000___0000_0000_0000_0000___0000___0000;
        #10;
        // FMAs are computing...
        #10;
        // At this point, the FMAs should be DONE COMPUTING!

        //////////////////////////////////////////////////
        // Step 2: Give FMAs new a and b values, chaining off old c values
        //////////////////////////////////////////////////

        // CHAIN C OFF OLD VALUES
        // op code is WRITEB (replace_c is 0)
        memory_instr_in = 32'b1010___0000___0000_0000_0000_0000___0000___0000;
        // BRAM takes two cycles to read, then send to FMA blocks
        #10;
        // default instruction is NOP
        memory_instr_in = 32'b0000___0000___0000_0000_0000_0000___0000___0000;
        #10;
        // FMAs are computing...
        #10;
        // At this point, the FMAs should be DONE COMPUTING!
        
        // REPLACE C WITH NEW VALUE
        // op code is WRITEB (replace_c is 1)
        memory_instr_in = 32'b1010___0001___0000_0000_0000_0000___0000___0000;
        // BRAM takes two cycles to read, then send to FMA blocks
        #10;
        // default instruction is NOP
        memory_instr_in = 32'b0000___0000___0000_0000_0000_0000___0000___0000;
        #10;
        // FMAs are computing...
        #10;
        // At this point, the FMAs should be DONE COMPUTING!
        #10;

        //////////////////////////////////////////////////
        // Step 3: Connect FMAs to write buffer
        //////////////////////////////////////////////////

        // MOREOVER... not only are the FMAs done computing,
        // but we've done three FMA computations. That means
        // we have a full line ready to send to memory.
        // The write buffer sends the line automatically.

        //////////////////////////////////////////////////
        // Step 4: Connect write buffer to put outputs back in memory
        //////////////////////////////////////////////////

        // Give the write buffer one cycle to display its values.
        #10;
        // Write buffer sets line_valid high!
        #10;
        // op code is LOADB                 addr is 2
        memory_instr_in = 32'b1001___0000___0000_0000_0000_0010___0000___0000;
        #10;
        // Output from FMAs should be in BRAM!

        // default instruction is NOP
        memory_instr_in = 32'b0000___0000___0000_0000_0000_0000___0000___0000;
        #50;

        //////////////////////////////////////////////////
        // Step 5: Connect the controller to memory (with matrix mult program!)
        //////////////////////////////////////////////////

        // THIS TESTBENCH IS DONE.
        // MAKE A NEW TESTBENCH THAT WIRES UP CONTROLLER TO CONTROL INSTR_IN.

        //for (int cycle = 0; cycle < 64; cycle = cycle + 1) begin
        //    $display("State %1d | Executing %4b", uut.state, uut.instr[0:3]);
        //    #10;
        //end

        $display("memory_abc_valid_out=%0b memory_use_new_c_out=%0b memory_fma_output_can_be_valid_out=%0b", memory_abc_valid_out, memory_use_new_c_out, memory_fma_output_can_be_valid_out);
        $finish;

    end

endmodule // fma_plus_memory_tb

`default_nettype wire

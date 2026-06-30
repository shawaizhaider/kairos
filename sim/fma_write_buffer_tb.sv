`timescale 1ns / 1ps
`default_nettype none

module fma_write_buffer_tb;

  parameter FMA_COUNT = 32;  // number of FMAs to prepare data for in a simultaneous read
  parameter WORD_WIDTH = 32;  // number of bits per number aka width of a word
  parameter LINE_WIDTH = FMA_COUNT * 3 * WORD_WIDTH;  // width of a line, FMA_COUNT * 3 * WORD_WIDTH

  //make logics for inputs and outputs!
  logic clk_in;
  logic rst_in;
  logic [WORD_WIDTH * FMA_COUNT - 1 : 0] fma_out;
  logic [FMA_COUNT - 1 : 0] fma_valid_out;
  logic [3 * WORD_WIDTH * FMA_COUNT - 1 : 0] line_out;
  logic line_valid;

  fma_write_buffer #(.FMA_COUNT(FMA_COUNT), .WORD_WIDTH(WORD_WIDTH), .LINE_WIDTH(LINE_WIDTH)) uut  // uut = unit under test
          (.clk_in(clk_in),
           .rst_in(rst_in),
           .fma_out(fma_out),
           .fma_valid_out(fma_valid_out),
           .line_out(line_out),
           .line_valid(line_valid));

  always begin
    #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    clk_in = !clk_in;
  end

  //initial block...this is our test simulation
  initial begin
    $dumpfile("fma_write_buffer.vcd"); //file to store value change dump (vcd)
    $dumpvars(0, fma_write_buffer_tb); //store everything at the current level and below
    $display("Starting Sim\n"); //print nice message
    clk_in = 0; //initialize clk (super important)
    rst_in = 0; //initialize rst (super important)
    #10  //wait a little bit of time at beginning
    rst_in = 1; //reset system
    #10; //hold high for a few clock cycles
    rst_in = 0;
    #10;

    fma_out = '0;
    fma_valid_out = '0;

    for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
      fma_out[fma_id * WORD_WIDTH +: WORD_WIDTH] = 32'h0100_0000 + $unsigned(fma_id);
    end

    fma_valid_out[0] = 1'b1;
    #10;
    fma_valid_out[1] = 1'b1;
    #10;
    fma_valid_out[2] = 1'b1;
    #10;

    fma_valid_out = '0;
    #10;

    if (!line_valid) begin
      $fatal(1, "fma_write_buffer_tb: expected line_valid after three valid phrases");
    end

    if (line_out[0 +: WORD_WIDTH] !== 32'h0100_0000 ||
        line_out[FMA_COUNT * WORD_WIDTH +: WORD_WIDTH] !== 32'h0100_0000 ||
        line_out[2 * FMA_COUNT * WORD_WIDTH +: WORD_WIDTH] !== 32'h0100_0000) begin
      $fatal(1, "fma_write_buffer_tb: unexpected packed line contents");
    end

    $finish;

  end

endmodule // fma_memory_buffer_tb

`default_nettype wire

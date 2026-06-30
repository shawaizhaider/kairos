`timescale 1ns / 1ps
`default_nettype none

module fma_tb;

  localparam WIDTH = 32;
  localparam FIXED_POINT = 24;
  //make logics for inputs and outputs!
  logic clk_in;
  logic rst_in;
  logic [WIDTH-1:0] a, b, c;
  logic [3*WIDTH-1:0] abc;
  logic a_valid_in, b_valid_in, c_valid_in;
  logic compute;
  logic [WIDTH-1:0] out; 
  logic valid_out;

  assign abc = {a, b, c};

  fma #(.WIDTH(WIDTH), .FIXED_POINT(FIXED_POINT)) uut  // uut = unit under test
          (.clk_in(clk_in),
           .rst_in(rst_in),
           .abc(abc),
           .valid_in(a_valid_in && b_valid_in),
           .c_valid_in(c_valid_in),
           .output_can_be_valid_in(compute),
           .out(out),
           .valid_out(valid_out));

  always begin
    #5;  //every 5 ns switch...so period of clock is 10 ns...100 MHz clock
    clk_in = !clk_in;
  end

  //initial block...this is our test simulation
  initial begin
    $dumpfile("fma.vcd"); //file to store value change dump (vcd)
    $dumpvars(0,fma_tb); //store everything at the current level and below
    $display("Starting Sim\n"); //print nice message
    clk_in = 0; //initialize clk (super important)
    rst_in = 0; //initialize rst (super important)
    #10  //wait a little bit of time at beginning
    rst_in = 1; //reset system
    #10; //hold high for a few clock cycles
    rst_in=0;
    #10;
    a=32'h0200_0000; // 2.0 in 8.24 fixed point
    b=32'h0180_0000; // 1.5 in 8.24 fixed point
    a_valid_in = 1;
    b_valid_in = 1;
    c_valid_in = 0;
    compute = 1;
    #10; // 1 cycle later
    a_valid_in = 0;
    b_valid_in = 0;
    compute = 0;
    $display("%h * %h = %h", a, b, out);  // should be 3.0
    $display("valid_out=%0b", valid_out);

    #10; // let's test another, more complicated multiplication
    a=32'h0520_0000; // 5.125 in 8.24 fixed point
    b=32'h0600_0000; // 6.0 in 8.24 fixed point
    a_valid_in = 1;
    b_valid_in = 1;
    c_valid_in = 0;
    compute = 1;
    #10; // 1 cycle later
    a_valid_in = 0;
    b_valid_in = 0;
    compute = 0;
    $display("%h * %h = %h", a, b, out);  // should be 33.75 with the accumulated c value
    $display("valid_out=%0b", valid_out);

    #10; // now if we reset the c value we get just the multiplication from above
    a=32'h0520_0000; // 5.125 in 8.24 fixed point
    b=32'h0600_0000; // 6.0 in 8.24 fixed point
    c=32'h0000_0000; // 0
    a_valid_in = 1;
    b_valid_in = 1;
    c_valid_in = 1;
    compute = 1;
    #10; // 1 cycle later
    a_valid_in = 0;
    b_valid_in = 0;
    c_valid_in = 0;
    compute = 0;
    $display("%h * %h = %h", a, b, out);  // should be 30.75
    $display("valid_out=%0b", valid_out);

    $display("\nThe first two multiplications are a \"dot product\"\nwhere the answer is saved and added to the next result.\nThe third line resets the c value to 0.\n");

    $finish;

  end

endmodule // fma_tb

`default_nettype wire

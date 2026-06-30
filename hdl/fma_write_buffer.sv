`timescale 1ns / 1ps
`default_nettype none

`define WRITE_BUFFER_OUTPUT(FMA_ID, PHRASE) line_out[PHRASE*FMA_COUNT*WORD_WIDTH + FMA_ID*WORD_WIDTH +: WORD_WIDTH]

module fma_write_buffer #(
    parameter FMA_COUNT = 2,  
    parameter WORD_WIDTH = 32,  // UPGRADED to 32
    parameter LINE_WIDTH = FMA_COUNT * 3 * WORD_WIDTH  // Now dynamically calculates
) (
    input wire clk_in,
    input wire rst_in,
    input wire [WORD_WIDTH * FMA_COUNT - 1 : 0] fma_out,
    input wire [FMA_COUNT - 1 : 0] fma_valid_out,
    output logic [3 * WORD_WIDTH * FMA_COUNT - 1 : 0] line_out,
    output logic line_valid
);

    // A "word" is a single number. A "phrase" is all FMA c outputs.
    localparam ADDR_LENGTH =  $clog2(36000 / (WORD_WIDTH * FMA_COUNT * 3));
    logic [1:0] phrase_in;

    logic increment_phrase;
    assign increment_phrase = (fma_valid_out != 0);

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            line_valid <= 0;
            phrase_in <= 0;
            line_out <= 0;
        end else begin
            if (phrase_in != 2'b11) begin
                if (increment_phrase) begin
                    phrase_in <= phrase_in + 2'b01;
                    line_valid <= phrase_in == 2'b10;

                    for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                        `WRITE_BUFFER_OUTPUT(fma_id, phrase_in) <= fma_out[fma_id * WORD_WIDTH +: WORD_WIDTH];
                    end
                end
            end else begin
                line_valid <= 0;
                phrase_in <= 0;
                line_out <= 0;
            end
        end
    end

endmodule
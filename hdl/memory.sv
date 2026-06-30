`timescale 1ns / 1ps
`default_nettype none

// Macros
`define BRAM_TEMP(FMA_ID, ABC) bram_temp_in[LINE_WIDTH - (FMA_ID*3 + ABC + 1) * WORD_WIDTH +: WORD_WIDTH]
`define MEM_WRITE_BUFFER_OUTPUT(FMA_ID, PHRASE) write_buffer_read_in_buffer[PHRASE*FMA_COUNT*WORD_WIDTH + (FMA_COUNT-FMA_ID-1)*WORD_WIDTH +: WORD_WIDTH]
`define MEM_WRITE_BUFFER_OUTPUT_WITHOUT_LAST_BIT(FMA_ID, PHRASE) write_buffer_read_in_buffer[PHRASE*FMA_COUNT*WORD_WIDTH + (FMA_COUNT-FMA_ID-1)*WORD_WIDTH +: WORD_WIDTH-1]
`define SHUFFLE_VAL(ABC) (reg_vals[12-(ABC+1)*4 +: 4])

module memory #(
    parameter FMA_COUNT = 2,  
    parameter WORD_WIDTH = 32, 
    parameter FIXED_POINT = 24, 
    parameter LINE_WIDTH = FMA_COUNT * 3 * WORD_WIDTH, // Dynamically calculates
    parameter ADDR_LENGTH = $clog2(36000 / (FMA_COUNT * 3 * WORD_WIDTH)),
    parameter INSTRUCTION_WIDTH = 32,      
    parameter WIDTH = 1280,    
    parameter HEIGHT = 720,     
    parameter ITERS_BITS = 4
) (
    input wire clk_in,
    input wire rst_in,
    input wire [WORD_WIDTH-1:0] controller_reg_a,
    input wire [WORD_WIDTH-1:0] controller_reg_b,
    input wire [WORD_WIDTH-1:0] controller_reg_c,
    input wire [LINE_WIDTH - 1 : 0] write_buffer_read_in,
    input wire write_buffer_valid_in,
    input wire [0 : INSTRUCTION_WIDTH - 1] instr_in,
    input wire instr_valid_in,
    output logic [LINE_WIDTH - 1 : 0] abc_out,  
    output logic use_new_c_out,
    output logic fma_output_can_be_valid_out,
    output logic abc_valid_out,
    output logic frame_buffer_swap_out,
    output logic mandelbrot_iters_valid_out,
    output logic [ITERS_BITS*FMA_COUNT-1:0] mandelbrot_iters_out,
    output logic [$clog2(WIDTH*HEIGHT)-1:0] mandelbrot_addr_out,
    output logic [LINE_WIDTH-1:0] write_buffer_out, 
    output logic [LINE_WIDTH-1:0] bram_temp_in_out  
);

    enum logic[3:0] {
        OP_NOP     = 4'b0000,  
        OP_END     = 4'b0001,  
        OP_XOR     = 4'b0010,  
        OP_ADDI    = 4'b0011,  
        OP_BGE     = 4'b0100,  
        OP_JUMP    = 4'b0101,  
        OP_FBSWAP  = 4'b0110,  
        OP_LOADI   = 4'b0111,  
        OP_ADD     = 4'b1000,  
        OP_LOADB   = 4'b1001,  
        OP_LOAD    = 4'b1010,  
        OP_WRITEB  = 4'b1011,  
        OP_WRITE   = 4'b1100,    
        OP_OR      = 4'b1101, 
        OP_SENDITERS = 4'b1110,
        OP_PAUSE   = 4'b1111     
    } isa;

    logic [3*4-1:0] reg_vals;
    assign reg_vals = {instr_in[4:7], instr_in[24:27], instr_in[28:31]};
    logic [ITERS_BITS*FMA_COUNT-1:0] mandelbrot_iters;
    logic [ADDR_LENGTH - 1 : 0] addr;
    logic [LINE_WIDTH - 1 : 0] bram_temp_in;
    logic [LINE_WIDTH - 1 : 0] bram_in;
    logic [LINE_WIDTH - 1 : 0] write_buffer_read_in_buffer;
    
    assign write_buffer_out = write_buffer_read_in_buffer;
    assign bram_temp_in_out = bram_temp_in;
    
    logic bram_read;
    logic bram_write;
    logic [1:0] bram_write_ready;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            addr <= 0;
            bram_temp_in <= 0;
            bram_in <= 0;
            abc_out <= 0;
            abc_valid_out <= 0;
            use_new_c_out <= 0;
            fma_output_can_be_valid_out <= 0;
            bram_read <= 0;
            bram_write <= 0;
            bram_write_ready <= 0;
            write_buffer_read_in_buffer <= 0;
            mandelbrot_iters <= -1;
        end else begin
            if (write_buffer_valid_in) begin
                write_buffer_read_in_buffer <= write_buffer_read_in;
            end

            mandelbrot_iters_valid_out <= instr_valid_in && instr_in[0:3] == OP_SENDITERS;
            frame_buffer_swap_out <= instr_valid_in && instr_in[0:3] == OP_FBSWAP;

            if (instr_valid_in) begin
                case (instr_in[0:3])
                    OP_NOP: begin
                    end
                    OP_FBSWAP: begin
                    end
                    OP_LOADI: begin
                        if (instr_in[28:31] == 4'b0001) begin
                            // LOAD HIGH HACK: Splice immediate into the upper 16 bits of the 32-bit target
                            bram_temp_in[LINE_WIDTH - (instr_in[4:7]+1) * WORD_WIDTH + 16 +: 16] <= instr_in[8:23];
                        end else begin
                            // NORMAL LOADI: Sign-extend 16-bit immediate into the full 32-bit target
                            bram_temp_in[LINE_WIDTH - (instr_in[4:7]+1) * WORD_WIDTH +: WORD_WIDTH] <= {{(WORD_WIDTH-16){instr_in[8]}}, instr_in[8:23]};
                        end
                    end
                    OP_LOADB: begin
                        for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                            for (int abc = 0; abc < 3; abc = abc + 1) begin
                                if (`SHUFFLE_VAL(abc) == 4'b0000) begin 
                                    `BRAM_TEMP(fma_id, abc) <= 0;
                                end else if (`SHUFFLE_VAL(abc) <= 4'b0011) begin 
                                    `BRAM_TEMP(fma_id, abc) <= `MEM_WRITE_BUFFER_OUTPUT(fma_id, (`SHUFFLE_VAL(abc) - 4'b0001));
                                end else if (`SHUFFLE_VAL(abc) <= 4'b0110) begin 
                                    `BRAM_TEMP(fma_id, abc) <= 2*`MEM_WRITE_BUFFER_OUTPUT(fma_id, (`SHUFFLE_VAL(abc) - 4'b0011 - 4'b0001));
                                end else if (`SHUFFLE_VAL(abc) >= 4'b1101) begin 
                                    `BRAM_TEMP(fma_id, abc) <= -(`MEM_WRITE_BUFFER_OUTPUT(fma_id, (4'b1111 - `SHUFFLE_VAL(abc))));
                                end else begin
                                end
                            end
                        end
                    end
                    OP_LOAD: begin
                        for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                            `BRAM_TEMP(fma_id, instr_in[4:7]) <= controller_reg_b + fma_id * controller_reg_c;
                        end
                    end
                    OP_WRITEB: begin
                        use_new_c_out <= (instr_in[4:7] == 4'b0001);
                        fma_output_can_be_valid_out <= (instr_in[24:27] == 4'b0001);
                        addr <= instr_in[8:23];
                        bram_write <= 1'b1;
                    end
                    OP_WRITE: begin
                        use_new_c_out <= (instr_in[4:7] == 4'b0001);
                        fma_output_can_be_valid_out <= (instr_in[24:27] == 4'b0001);
                        abc_out <= bram_temp_in;
                        abc_valid_out <= 1'b1;
                    end
                    OP_OR: begin
                        for (int fma_id = 0; fma_id < FMA_COUNT; fma_id = fma_id + 1) begin
                            if (mandelbrot_iters[ITERS_BITS*FMA_COUNT - (fma_id+1)*ITERS_BITS +: ITERS_BITS] == (1<<ITERS_BITS)-1) begin
                                // The (4 << FIXED_POINT) handles the 24-bit dynamic shift correctly
                                if (`MEM_WRITE_BUFFER_OUTPUT_WITHOUT_LAST_BIT(fma_id, 4'b0010) >= (4 << FIXED_POINT)) begin
                                    mandelbrot_iters[ITERS_BITS*FMA_COUNT - (fma_id+1)*ITERS_BITS +: ITERS_BITS] <= controller_reg_a[6-1:6-ITERS_BITS];
                                end
                            end
                        end
                    end
                    OP_SENDITERS: begin
                        mandelbrot_iters_out <= mandelbrot_iters;
                        mandelbrot_addr_out <= HEIGHT*controller_reg_a + controller_reg_b;
                        mandelbrot_iters <= -1;
                    end
                    default: begin
                    end
                endcase
            end else begin
                abc_valid_out <= 0;
                fma_output_can_be_valid_out <= 0;
            end
        end
    end

endmodule

`default_nettype wire
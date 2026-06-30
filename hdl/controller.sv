`timescale 1ns / 1ps
`default_nettype none

module controller #(
    parameter PROGRAM_FILE="mandelbrot_720.mem",
    parameter PRIVATE_REG_WIDTH=32,  // UPGRADED to 32
    parameter PRIVATE_REG_COUNT=16,  
    parameter INSTRUCTION_WIDTH=32,  
    parameter INSTRUCTION_COUNT=512, 
    parameter DATA_CACHE_WIDTH=32,   // UPGRADED to 32
    parameter DATA_CACHE_DEPTH=4096  
) (
    input wire clk_in,
    input wire rst_in,
    input wire continue_in, 
    output logic [0:INSTRUCTION_WIDTH-1] instr_out, 
    output logic [PRIVATE_REG_WIDTH-1:0] reg_a_out, 
    output logic [PRIVATE_REG_WIDTH-1:0] reg_b_out,
    output logic [PRIVATE_REG_WIDTH-1:0] reg_c_out,
    output logic instr_valid_for_memory_out,
    output logic [15:0] iters_out, 
    input wire [3:0] reg_index_in, 
    output logic [PRIVATE_REG_WIDTH-1:0] reg_out, // Changed to dynamic width
    output logic [7:0] instr_index_out 
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

    enum {
        IDLE=0,
        LOAD_INSTRUCTION=1,
        EXECUTE_INSTRUCTION=2
    } state;

    logic [PRIVATE_REG_WIDTH-1:0] registers [0:PRIVATE_REG_COUNT-1];
    logic compare_reg;

    logic [PRIVATE_REG_WIDTH-1:0] reg0, reg1, reg2, reg3, reg4, reg5, reg6, reg7, reg8, reg9, reg10, reg11, reg12, reg13, reg14, reg15;
    assign reg0 = registers[0];
    assign reg1 = registers[1];
    assign reg2 = registers[2];
    assign reg3 = registers[3];
    assign reg4 = registers[4];
    assign reg5 = registers[5];
    assign reg6 = registers[6];
    assign reg7 = registers[7];
    assign reg8 = registers[8];
    assign reg9 = registers[9];
    assign reg10 = registers[10];
    assign reg11 = registers[11];
    assign reg12 = registers[12];
    assign reg13 = registers[13];
    assign reg14 = registers[14];
    assign reg15 = registers[15];

    assign reg_out = registers[reg_index_in]; 
    assign iters_out = reg15[15:0];

    localparam INSTRUCTION_DEPTH = $clog2(INSTRUCTION_COUNT);
    logic [0:INSTRUCTION_DEPTH-1] instruction_index;
    logic [0:INSTRUCTION_DEPTH-1] prefetching_index;
    logic [0:INSTRUCTION_WIDTH-1] current_instruction;
    logic [0:INSTRUCTION_WIDTH-1] prefetched_instruction;

    assign instr_index_out = instruction_index;

    assign prefetching_index = (instruction_index < INSTRUCTION_COUNT - 1) ? instruction_index + 1 : instruction_index;

    xilinx_true_dual_port_read_first_2_clock_ram #(
        .RAM_WIDTH(INSTRUCTION_WIDTH),
        .RAM_DEPTH(INSTRUCTION_COUNT),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),     
        .INIT_FILE("mandelbrot_720.mem")    
    ) instruction_buffer (
        .clka(clk_in),                   
        .addra(instruction_index),       
        .douta(current_instruction),     
        .ena(state != IDLE),             
        .regcea(1'b1),                   
        .wea(1'b0),                      
        .dina(),                         
        .rsta(rst_in),                   

        .clkb(clk_in),                   
        .addrb(prefetching_index),       
        .doutb(prefetched_instruction),  
        .enb(state != IDLE),             
        .regceb(1'b1),   
        .web(1'b0),                      
        .dinb(),                         
        .rstb(rst_in)                    
    );

    logic instr_ready, just_used_prefetch;
    logic [0:INSTRUCTION_WIDTH-1] instr;
    assign instr = current_instruction;
    assign instr_out = current_instruction;

    assign reg_a_out = registers[instr[4:7]];
    assign reg_b_out = registers[instr[24:27]];
    assign reg_c_out = registers[instr[28:31]];

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            state <= LOAD_INSTRUCTION;
            instr_ready <= 0;
            instruction_index <= 0;
            just_used_prefetch <= 0;
            compare_reg <= 0;
            for (int i = 0; i < PRIVATE_REG_COUNT; i = i + 1) begin
                registers[i] <= 0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (continue_in) begin
                        state <= LOAD_INSTRUCTION;
                        instr_ready <= 0;
                    end
                end

                LOAD_INSTRUCTION: begin
                    instr_ready <= 1'b1;
                    if (instr_ready) begin
                        state <= EXECUTE_INSTRUCTION;
                        instruction_index <= instruction_index + 1'b1;
                    end
                end

                EXECUTE_INSTRUCTION: begin
                    case (instr[0:3])

                        OP_NOP: begin
                        end

                        OP_END: begin
                            state <= IDLE;
                            compare_reg <= 0;
                            for (int i = 0; i < PRIVATE_REG_COUNT; i = i + 1) begin
                                registers[i] <= 0;
                            end
                        end

                        OP_XOR: begin
                            registers[instr[4:7]] <= registers[instr[4:7]] ^ registers[instr[24:27]];
                        end

                        OP_ADDI: begin
                            if (instr[28:31] == 4'b0001) begin
                                // LOAD HIGH HACK: Shifts 16-bit immediate into the upper 16 bits
                                registers[instr[4:7]] <= {instr[8:23], 16'b0} + registers[instr[24:27]];
                            end else begin
                                // NORMAL ADDI: Dynamically sign-extends the 16-bit immediate to match register width
                                registers[instr[4:7]] <= {{(PRIVATE_REG_WIDTH-16){instr[8]}}, instr[8:23]} + registers[instr[24:27]];
                            end
                        end

                        OP_BGE: begin
                            compare_reg <= registers[instr[4:7]] >= registers[instr[24:27]];
                        end

                        OP_JUMP: begin
                            if (compare_reg) begin
                                instr_ready <= 0;
                                compare_reg <= 0;
                                instruction_index <= instr[8:23];
                            end
                        end

                        OP_ADD: begin
                            registers[instr[4:7]] <= registers[instr[24:27]] + registers[instr[28:31]];
                        end

                        OP_PAUSE: begin
                            state <= IDLE;
                        end

                        default: begin
                        end
                    endcase 

                    if (instr[0:3] != OP_END && instr[0:3] != OP_PAUSE) begin
                        state <= LOAD_INSTRUCTION;
                    end
                end

                default: begin
                end
            endcase
            
            instr_valid_for_memory_out <= (state == LOAD_INSTRUCTION && instr_ready); 
        end
    end

endmodule

`default_nettype wire
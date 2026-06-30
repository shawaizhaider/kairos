`timescale 1ns / 1ps
`default_nettype none

// I2C init sequencer for ADV7511 via PCA9548 on ZC706 with HPD gating.
module adv7511_init #(
    parameter int CLK_HZ = 74250000,
    parameter int I2C_HZ = 100000,
    // 200ms startup delay required by ADV7511 before I2C communication
    parameter int START_DELAY_CYCLES = 14850000, 
    parameter int HPD_POLL_DELAY_CYCLES = 742500
) (
    input  wire clk,
    input  wire rst,
    input  wire scl_in,
    input  wire sda_in,
    output logic scl_oe,
    output logic sda_oe,
    output logic done,
    output logic error
);

    localparam int I2C_DIV = (I2C_HZ > 0) ? (CLK_HZ / (I2C_HZ * 2)) : 1;
    localparam int I2C_DIV_W = (I2C_DIV <= 1) ? 1 : $clog2(I2C_DIV);

    logic [I2C_DIV_W-1:0] div_cnt;
    wire tick = (div_cnt == I2C_DIV - 1);

    always_ff @(posedge clk) begin
        if (rst) begin
            div_cnt <= '0;
        end else if (tick) begin
            div_cnt <= '0;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    localparam int START_W = (START_DELAY_CYCLES <= 1) ? 1 : $clog2(START_DELAY_CYCLES + 1);
    logic [START_W-1:0] start_cnt;

    wire start_ready = (START_DELAY_CYCLES == 0) ? 1'b1 : (start_cnt == START_DELAY_CYCLES[START_W-1:0]);

    always_ff @(posedge clk) begin
        if (rst) begin
            start_cnt <= '0;
        end else if (!start_ready) begin
            start_cnt <= start_cnt + 1'b1;
        end
    end

    localparam int HPD_W = (HPD_POLL_DELAY_CYCLES <= 1) ? 1 : $clog2(HPD_POLL_DELAY_CYCLES + 1);
    logic [HPD_W-1:0] hpd_cnt;
    logic load_hpd_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            hpd_cnt <= '0;
        end else if (load_hpd_cnt) begin
            hpd_cnt <= HPD_POLL_DELAY_CYCLES[HPD_W-1:0];
        end else if (hpd_cnt != 0) begin
            hpd_cnt <= hpd_cnt - 1'b1;
        end
    end

    typedef struct packed {
        logic [6:0] addr;
        logic [7:0] reg_addr;
        logic [7:0] reg_data;
        logic       use_reg;
        logic       is_read;
    } i2c_txn_t;

    // Total transactions updated to 19 to include new GC and Aspect Ratio packets
    localparam int TXN_COUNT = 19; 
    localparam int HPD_TXN_IDX = 1;

    function automatic i2c_txn_t get_txn(input int idx);
        case (idx)
            // PCA9548: select channel 1 (0x02)
            0:  get_txn = '{7'h74, 8'h00, 8'h02, 1'b0, 1'b0};
            
            // Read HPD state (0x42[6]) - Addr fixed to 0x39
            1:  get_txn = '{7'h39, 8'h42, 8'h00, 1'b1, 1'b1};
            
            // Power up: Default is 0x50. Clearing bit 6 = 0x10
            2:  get_txn = '{7'h39, 8'h41, 8'h10, 1'b1, 1'b0};
            
            // Fixed registers
            3:  get_txn = '{7'h39, 8'h98, 8'h03, 1'b1, 1'b0};
            4:  get_txn = '{7'h39, 8'h9A, 8'hE0, 1'b1, 1'b0};
            5:  get_txn = '{7'h39, 8'h9C, 8'h30, 1'b1, 1'b0};
            6:  get_txn = '{7'h39, 8'h9D, 8'h01, 1'b1, 1'b0};
            7:  get_txn = '{7'h39, 8'hA2, 8'hA4, 1'b1, 1'b0};
            8:  get_txn = '{7'h39, 8'hA3, 8'hA4, 1'b1, 1'b0};
            9:  get_txn = '{7'h39, 8'hE0, 8'hD0, 1'b1, 1'b0};
            10: get_txn = '{7'h39, 8'hF9, 8'h00, 1'b1, 1'b0};
            
            // Enable General Control (GC) packet via 0x40[7]
            11: get_txn = '{7'h39, 8'h40, 8'h80, 1'b1, 1'b0};
            
            // Video input/output mode
            12: get_txn = '{7'h39, 8'h15, 8'h00, 1'b1, 1'b0};
            // Claude Fix: 0x34 defines Input Style 1 (R/G/B pin mapping correctly interpreted)
            13: get_txn = '{7'h39, 8'h16, 8'h34, 1'b1, 1'b0};
            // Claude Fix: 0x17[1]=1 explicitly declares 16:9 Input Aspect Ratio
            14: get_txn = '{7'h39, 8'h17, 8'h02, 1'b1, 1'b0};
            
            // AVI InfoFrame 
            15: get_txn = '{7'h39, 8'h55, 8'h00, 1'b1, 1'b0};
            16: get_txn = '{7'h39, 8'h56, 8'h28, 1'b1, 1'b0};
            
            // Clock delay setup
            17: get_txn = '{7'h39, 8'hBA, 8'h60, 1'b1, 1'b0};
            
            // HDMI Mode setup (0xAF[1]=1)
            18: get_txn = '{7'h39, 8'hAF, 8'h02, 1'b1, 1'b0};
            
            default: get_txn = '{7'h39, 8'h00, 8'h00, 1'b1, 1'b0};
        endcase
    endfunction

    typedef enum logic [4:0] {
        ST_IDLE,
        ST_START_A,
        ST_START_B,
        ST_SEND_LOW,
        ST_SEND_HIGH,
        ST_ACK_LOW,
        ST_ACK_HIGH,
        ST_RECV_LOW,
        ST_RECV_HIGH,
        ST_MASTER_ACK_LOW,
        ST_MASTER_ACK_HIGH,
        ST_STOP_A,
        ST_STOP_B,
        ST_STOP_C,
        ST_HPD_WAIT,
        ST_DONE
    } state_t;

    state_t state;

    localparam int TXN_W = (TXN_COUNT <= 1) ? 1 : $clog2(TXN_COUNT);
    logic [TXN_W-1:0] txn_idx;
    logic [1:0] byte_idx;
    logic [2:0] bit_idx;
    logic read_stage;
    logic nack_retry; // Added flag for NACK recovery

    i2c_txn_t txn;
    logic [7:0] current_byte;
    logic [1:0] byte_count;
    logic [7:0] read_data;
    logic hpd_state;

    always_comb begin
        txn = get_txn(txn_idx);
        if (txn.is_read) begin
            byte_count = read_stage ? 2'd1 : 2'd2;
        end else begin
            byte_count = txn.use_reg ? 2'd3 : 2'd2;
        end

        if (byte_idx == 2'd0) begin
            current_byte = {txn.addr, (txn.is_read && read_stage)};
        end else if (byte_idx == 2'd1 && (txn.use_reg || (txn.is_read && !read_stage))) begin
            current_byte = txn.reg_addr;
        end else begin
            current_byte = txn.reg_data;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            txn_idx <= '0;
            byte_idx <= 2'd0;
            bit_idx <= 3'd7;
            read_stage <= 1'b0;
            read_data <= 8'h00;
            hpd_state <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            load_hpd_cnt <= 1'b0;
            nack_retry <= 1'b0;
        end else if (tick) begin
            load_hpd_cnt <= 1'b0;
            case (state)
                ST_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    nack_retry <= 1'b0;
                    if (start_ready) begin
                        txn_idx <= '0;
                        byte_idx <= 2'd0;
                        bit_idx <= 3'd7;
                        read_stage <= 1'b0;
                        state <= ST_START_A;
                    end
                end
                ST_START_A: begin
                    state <= ST_START_B;
                end
                ST_START_B: begin
                    bit_idx <= 3'd7;
                    state <= ST_SEND_LOW;
                end
                ST_SEND_LOW: begin
                    state <= ST_SEND_HIGH;
                end
                ST_SEND_HIGH: begin
                    if (!scl_in) begin
                        state <= ST_SEND_HIGH; 
                    end else if (bit_idx == 3'd0) begin
                        state <= ST_ACK_LOW;
                    end else begin
                        bit_idx <= bit_idx - 1'b1;
                        state <= ST_SEND_LOW;
                    end
                end
                ST_ACK_LOW: begin
                    state <= ST_ACK_HIGH;
                end
                ST_ACK_HIGH: begin
                    if (!scl_in) begin
                        state <= ST_ACK_HIGH; 
                    end else begin
                        if (sda_in) begin
                            // NACK Detected: Set error, prep for retry, and generate STOP condition
                            error <= 1'b1;
                            nack_retry <= 1'b1;
                            state <= ST_STOP_A;
                        end else begin
                            // Normal ACK Path
                            if (byte_idx + 1'b1 < byte_count) begin
                                byte_idx <= byte_idx + 1'b1;
                                bit_idx <= 3'd7;
                                state <= ST_SEND_LOW;
                            end else begin
                                if (txn.is_read && !read_stage) begin
                                    read_stage <= 1'b1;
                                    byte_idx <= 2'd0;
                                    bit_idx <= 3'd7;
                                    state <= ST_START_A;
                                end else if (txn.is_read && read_stage) begin
                                    bit_idx <= 3'd7;
                                    read_data <= 8'h00;
                                    state <= ST_RECV_LOW;
                                end else begin
                                    state <= ST_STOP_A;
                                end
                            end
                        end
                    end
                end
                ST_RECV_LOW: begin
                    state <= ST_RECV_HIGH;
                end
                ST_RECV_HIGH: begin
                    if (!scl_in) begin
                        state <= ST_RECV_HIGH; 
                    end else begin
                        read_data[bit_idx] <= sda_in;
                        if (bit_idx == 3'd0) begin
                            state <= ST_MASTER_ACK_LOW;
                        end else begin
                            bit_idx <= bit_idx - 1'b1;
                            state <= ST_RECV_LOW;
                        end
                    end
                end
                ST_MASTER_ACK_LOW: begin
                    if (txn_idx == HPD_TXN_IDX) begin
                        hpd_state <= read_data[6];
                    end
                    state <= ST_MASTER_ACK_HIGH;
                end
                ST_MASTER_ACK_HIGH: begin
                    if (!scl_in) begin
                        state <= ST_MASTER_ACK_HIGH; 
                    end else begin
                        state <= ST_STOP_A;
                    end
                end
                ST_STOP_A: begin
                    state <= ST_STOP_B;
                end
                ST_STOP_B: begin
                    if (!scl_in) begin
                        state <= ST_STOP_B; 
                    end else begin
                        state <= ST_STOP_C;
                    end
                end
                ST_STOP_C: begin
                    read_stage <= 1'b0;
                    
                    if (nack_retry) begin
                        // NACK Recovery logic: Wait bus to clear, then reset transaction pointer
                        nack_retry <= 1'b0;
                        txn_idx <= '0;
                        byte_idx <= 2'd0;
                        bit_idx <= 3'd7;
                        state <= ST_START_A;
                    end else if (txn_idx == HPD_TXN_IDX && !hpd_state) begin
                        load_hpd_cnt <= 1'b1;
                        state <= ST_HPD_WAIT;
                    end else if (txn_idx + 1'b1 < TXN_COUNT[TXN_W-1:0]) begin
                        txn_idx <= txn_idx + 1'b1;
                        byte_idx <= 2'd0;
                        bit_idx <= 3'd7;
                        state <= ST_START_A;
                    end else begin
                        done <= 1'b1;
                        state <= ST_DONE;
                    end
                end
                ST_HPD_WAIT: begin
                    if (hpd_cnt == 0) begin
                        byte_idx <= 2'd0;
                        bit_idx <= 3'd7;
                        state <= ST_START_A;
                    end
                end
                ST_DONE: begin
                    done <= 1'b1;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    always_comb begin
        scl_oe = 1'b0;
        sda_oe = 1'b0;
        case (state)
            ST_START_B: begin
                scl_oe = 1'b0;
                sda_oe = 1'b1;
            end
            ST_SEND_LOW: begin
                scl_oe = 1'b1;
                sda_oe = (current_byte[bit_idx] == 1'b0);
            end
            ST_SEND_HIGH: begin
                scl_oe = 1'b0;
                sda_oe = (current_byte[bit_idx] == 1'b0);
            end
            ST_ACK_LOW: begin
                scl_oe = 1'b1;
                sda_oe = 1'b0;
            end
            ST_ACK_HIGH: begin
                scl_oe = 1'b0;
                sda_oe = 1'b0;
            end
            ST_RECV_LOW: begin
                scl_oe = 1'b1;
                sda_oe = 1'b0;
            end
            ST_RECV_HIGH: begin
                scl_oe = 1'b0;
                sda_oe = 1'b0;
            end
            ST_MASTER_ACK_LOW: begin
                scl_oe = 1'b1;
                sda_oe = 1'b0;
            end
            ST_MASTER_ACK_HIGH: begin
                scl_oe = 1'b0;
                sda_oe = 1'b0;
            end
            ST_STOP_A: begin
                scl_oe = 1'b1;
                sda_oe = 1'b1;
            end
            ST_STOP_B: begin
                scl_oe = 1'b0;
                sda_oe = 1'b1;
            end
            ST_STOP_C: begin
                scl_oe = 1'b0;
                sda_oe = 1'b0;
            end
            default: begin
                scl_oe = 1'b0;
                sda_oe = 1'b0;
            end
        endcase
    end

endmodule

`default_nettype wire
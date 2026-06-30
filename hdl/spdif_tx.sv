`timescale 1ns / 1ps
`default_nettype none

module spdif_tx #(
    parameter int CLK_HZ = 74250000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output logic       s_axis_tready,
    output logic       spdif_out
);

    // ?? BMC clock: 6.144 MHz from 74.25 MHz (Claude's Perfect Math) ??
    localparam logic [31:0] PHASE_INC = 32'd355_423_375;

    logic [31:0] phase_acc;
    logic        bmc_tick;

    always_ff @(posedge clk) begin
        if (rst) {bmc_tick, phase_acc} <= 33'h0;
        else     {bmc_tick, phase_acc} <= {1'b0, phase_acc} + PHASE_INC;
    end

    // ?? Counters ??
    logic [6:0] bit_cnt;    // 0-127
    logic [7:0] frame_cnt;  // 0-191

    wire [5:0] sub_tick = bit_cnt[5:0];
    wire       half     = sub_tick[0];
    wire [4:0] bit_idx  = sub_tick[5:1];
    wire       in_sub_b = bit_cnt[6];

    // ?? AXI-Stream handshake ??
    logic [31:0] audio_latch;
    logic        audio_valid;

    always_ff @(posedge clk) begin
        if (rst) begin
            s_axis_tready <= 1'b0;
            audio_valid   <= 1'b0;
            audio_latch   <= 32'h0;
        end else begin
            if (s_axis_tready && s_axis_tvalid) begin
                audio_latch   <= s_axis_tdata;
                audio_valid   <= 1'b1;
                s_axis_tready <= 1'b0;
            end else if (!audio_valid && !s_axis_tready) begin
                s_axis_tready <= 1'b1;
            end
            if (bmc_tick && bit_cnt == 7'd127) begin
                audio_valid <= 1'b0;
            end
        end
    end

    // ?? Subframe word construction (Fixed Parity Width & Restored Metadata) ??
    wire c_bit = (frame_cnt == 8'd25); // 48kHz Metadata Flag
    wire [2:0] vuc = {c_bit, 1'b0, 1'b0};

    // 27-bit payloads
    wire [26:0] a_payload = {vuc, audio_latch[15:0],  8'h00}; 
    wire [26:0] b_payload = {vuc, audio_latch[31:16], 8'h00}; 
    wire [26:0] a_silence = {vuc, 24'h0};
    wire [26:0] b_silence = {vuc, 24'h0};

    // 32-bit Words (Exactly 1 Parity + 27 Payload + 4 Preamble = 32)
    wire [31:0] sub_a_word = {^a_payload, a_payload, 4'h0};
    wire [31:0] sub_b_word = {^b_payload, b_payload, 4'h0};
    wire [31:0] sub_a_silence_word = {^a_silence, a_silence, 4'h0};
    wire [31:0] sub_b_silence_word = {^b_silence, b_silence, 4'h0};

    // ?? Registered subframes (CLAUDE'S FIX: Only ONE Driver!) ??
    logic [31:0] sub_a_reg, sub_b_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            sub_a_reg <= 32'h0;
            sub_b_reg <= 32'h0;
        end else if (bmc_tick && bit_cnt == 7'd127) begin
            sub_a_reg <= audio_valid ? sub_a_word : sub_a_silence_word;
            sub_b_reg <= audio_valid ? sub_b_word : sub_b_silence_word;
        end
    end

    // ?? Preamble patterns ??
    wire [7:0] preamble_pattern =
        in_sub_b            ? 8'hE4 :   // W
        (frame_cnt == 8'd0) ? 8'hE8 :   // B
                              8'hE2;    // M

    wire current_data_bit = in_sub_b ? sub_b_reg[bit_idx] : sub_a_reg[bit_idx];

    // ?? BMC output engine (Restored Polarity Inversion) ??
    logic spdif_reg;
    logic preamble_invert;
    assign spdif_out = spdif_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            spdif_reg <= 1'b0;
            bit_cnt   <= 7'd0;
            frame_cnt <= 8'd0;
            preamble_invert <= 1'b0;
        end else if (bmc_tick) begin

            if (sub_tick == 6'd0) begin
                preamble_invert <= spdif_reg;
                spdif_reg       <= preamble_pattern[7] ^ spdif_reg;
            end else if (sub_tick < 6'd8) begin
                spdif_reg       <= preamble_pattern[7 - sub_tick] ^ preamble_invert;
            end else begin
                // Standard BMC encoding
                if (!half) begin
                    spdif_reg <= ~spdif_reg;
                end else if (current_data_bit) begin
                    spdif_reg <= ~spdif_reg;
                end
            end

            // Advance frame counters
            if (bit_cnt == 7'd127) begin
                bit_cnt   <= 7'd0;
                frame_cnt <= (frame_cnt == 8'd191) ? 8'd0 : frame_cnt + 8'd1;
            end else begin
                bit_cnt <= bit_cnt + 7'd1;
            end
        end
    end
endmodule
`default_nettype wire
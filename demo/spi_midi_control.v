// spi_midi_control.v
//
// Copyright (C) 2020 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

`default_nettype none

`include "notes.vh"

module spi_midi_control #(
    parameter [3:0] CHANNELS = 3,
    parameter [6:0] MIDI_NOTE_BASE = 7'h3c
) (
    input clk,
    input reset,

    input spi_csn,
    input spi_clk,
    input spi_mosi,
    output spi_miso,
    input spi_write_en,

    output reg read_needed,

    // Status input

    input [3:0] status_note,
    input [1:0] status_octave,
    input [3:0] status_channel,
    input status_note_on,

    input [CHANNELS - 1:0] status_note_off,

    // Control output

    output reg [CHANNELS - 1:0] key_on,
    output reg [CHANNELS - 1:0] key_off,

    output reg [3:0] note,
    output reg [1:0] octave
);
    localparam MAX_RX_LENGTH = 24;

    reg spi_clk_r;
    reg spi_csn_r;

    reg [MAX_RX_LENGTH - 1:0] send_buffer;
    reg [MAX_RX_LENGTH - 1:0] receive_buffer;

    reg midi_input_valid;
    reg [23:0] midi_status_encoded_r;
    reg midi_output_sent;

    assign spi_miso = send_buffer[0];

    wire spi_csn_rose = spi_csn && !spi_csn_r;
    wire spi_csn_fell = !spi_csn && spi_csn_r;
    wire spi_clk_rose = spi_clk && !spi_clk_r;

    always @(posedge clk) begin
        if (reset) begin
            spi_clk_r <= 0;
            spi_csn_r <= 1;
            read_needed <= 0;

            midi_input_valid <= 0;
            midi_output_sent <= 0;
        end else begin
            spi_clk_r <= spi_clk;
            spi_csn_r <= spi_csn;

            midi_input_valid <= 0;
            midi_output_sent <= 0;

            if (midi_status_valid) begin
                read_needed <= 1;
                midi_status_encoded_r <= midi_status_encoded;
            end

            if (spi_csn_fell) begin
                send_buffer <= midi_status_encoded_r;

                if (!spi_write_en) begin
                    read_needed <= 0;
                end
            end else if (!spi_csn && spi_clk_rose) begin
                send_buffer <= send_buffer >> 1;
                receive_buffer <= {spi_mosi, receive_buffer[MAX_RX_LENGTH - 1:1]};
            end

            if (spi_csn_rose) begin
                if (spi_write_en) begin
                    midi_input_valid <= 1;
                end else begin
                    midi_output_sent <= 1;
                end
            end
        end
    end

    always @(posedge clk) begin
        if (reset || !midi_output_valid) begin
            key_on <= 0;
            key_off <= 0;
        end else begin
            key_on <= decoded_key_on;
            key_off <= decoded_key_off;
            note <= decoded_note;
            octave <= decoded_octave;
        end
    end

    // MIDI note decoding (control by BT client):

    wire [CHANNELS - 1:0] decoded_key_on;
    wire [CHANNELS - 1:0] decoded_key_off;
    wire [3:0] decoded_note;
    wire [1:0] decoded_octave;
    wire midi_output_valid;

    midi_decoder #(
        .CHANNELS(CHANNELS),
        .MIDI_NOTE_BASE(MIDI_NOTE_BASE)
    ) midi_decoder (
        .clk(clk),
        .reset(reset),

        .midi_in(receive_buffer),
        .input_valid(midi_input_valid),

        .key_on(decoded_key_on),
        .key_off(decoded_key_off),
        .note(decoded_note),
        .octave(decoded_octave),
        .output_valid(midi_output_valid)
    );

    // MIDI status input queing (step 1, for eventually encoding and sending to client)

    wire note_on_to_encode;
    wire [3:0] note_to_encode;
    wire [1:0] octave_to_encode;
    wire [3:0] channel_to_encode;
    wire status_buffer_output_valid;

    midi_status_input_buffer #(
        .CHANNELS(CHANNELS)
    ) midi_status_input_buffer (
        .clk(clk),
        .reset(reset),

        // Inputs from user / tracker control

        .note_on(status_note_on),
        .note_in(status_note),
        .octave_in(status_octave),
        .channel_in(status_channel),

        .note_off(status_note_off),

        // Output to encode

        .note_on_out(note_on_to_encode),
        .note_out(note_to_encode),
        .octave_out(octave_to_encode),
        .channel_out(channel_to_encode),
        .output_valid(status_buffer_output_valid),
        .output_ack(midi_output_sent)
    );

    // MIDI note encoding (step 2, for sending status to BT client):

    wire [23:0] midi_status_encoded;
    wire midi_status_valid;

    midi_encoder #(
        .CHANNELS(CHANNELS),
        .MIDI_NOTE_BASE(MIDI_NOTE_BASE)
    ) midi_encoder (
        .clk(clk),
        .reset(reset),

        .note_on(note_on_to_encode),
        .note(note_to_encode),
        .octave(octave_to_encode),
        .channel(channel_to_encode),
        .input_valid(status_buffer_output_valid),

        .midi_out(midi_status_encoded),
        .output_valid(midi_status_valid)
    );

endmodule

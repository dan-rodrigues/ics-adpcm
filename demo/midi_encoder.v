// midi_encoder.v
//
// Copyright (C) 2020 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

module midi_encoder #(
    parameter [3:0] CHANNELS = 3,
    parameter [6:0] MIDI_NOTE_BASE = 7'h00
) (
    input clk,
    input reset,

    input note_on,
    input [3:0] note,
    input [1:0] octave,
    input [3:0] channel,
    input input_valid,

    output reg [23:0] midi_out,
    output reg output_valid,
);
    reg note_on_r;
    reg [3:0] note_r;
    reg [1:0] octave_r;
    reg [3:0] channel_r;
    reg output_valid_d;

    always @(posedge clk) begin
        note_on_r <= note_on;
        note_r <= note;
        octave_r <= octave;
        channel_r <= channel;
    end

    always @(posedge clk) begin
        if (reset) begin
            output_valid <= 0;
            output_valid_d <= 0;
        end else begin
            midi_out <= midi_encoded;
            output_valid_d <= input_valid;
            output_valid <= output_valid_d;
        end
    end

    wire [3:0] midi_command = note_on_r ? 4'b1001 : 4'b1000;
    wire [7:0] midi_status = {
        midi_command, channel_r
    };

    wire [7:0] midi_note = octave_r * 12 + note_r + MIDI_NOTE_BASE;
    wire [7:0] midi_velocity = 8'h7f;

    wire [23:0] midi_encoded = {
        midi_velocity, midi_note, midi_status
    };

endmodule
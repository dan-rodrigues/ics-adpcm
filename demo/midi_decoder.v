// midi_decoder.v
//
// Copyright (C) 2020 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

module midi_decoder #(
    parameter [3:0] CHANNELS = 3,
    parameter [6:0] MIDI_NOTE_BASE = 7'h00
) (
    input clk,
    input reset,

    input [23:0] midi_in,
    input input_valid,

    output reg [CHANNELS - 1:0] key_on,
    output reg [CHANNELS - 1:0] key_off,

    output reg [3:0] note,
    output reg [1:0] octave,
    // (possibly "velocity" too later)

    output reg output_valid
);
    reg [23:0] midi_in_r;

    always @(posedge clk) begin
        if (input_valid) begin
            midi_in_r <= midi_in;
        end
    end

    wire [7:0] midi_status = midi_in_r[7:0];

    wire [3:0] midi_status_channel = midi_status[3:0];
    wire [3:0] midi_status_command = midi_status[7:4];

    // Note / octave decoding:

    wire [7:0] midi_offset_note = midi_in[15:8] - MIDI_NOTE_BASE;

    reg octave_adjusting;
    reg [7:0] raw_note;

    always @(posedge clk) begin
        if (reset) begin
            output_valid <= 0;
            octave_adjusting <= 0;
        end else begin
            output_valid <= 0;

            if (octave_adjusting) begin
                if (raw_note >= 12) begin
                    raw_note <= raw_note - 12;
                    octave <= octave + 1;
                end else begin
                    note <= raw_note[3:0];
                    octave_adjusting <= 0;
                    output_valid <= 1;
                end
            end else if (input_valid) begin
                raw_note <= midi_offset_note;
                octave_adjusting <= 1;
                octave <= 0;
            end
        end
    end

    // Message decoding:

    reg [1:0] midi_msg;

    localparam [1:0]
        MSG_NOTE_ON = 0,
        MSG_NOTE_OFF = 1,
        MSG_UNKNOWN = 2;

    always @* begin
        case (midi_status_command)
            4'b1001:
                midi_msg = MSG_NOTE_ON;
            4'b1000:
                midi_msg = MSG_NOTE_OFF;
            default:
                midi_msg = MSG_UNKNOWN;
        endcase
    end

    // Key command output:

    wire [CHANNELS - 1:0] key_mask = 1 << midi_status_channel;

    always @(posedge clk) begin
        if (reset || input_valid) begin
            key_on <= 0;
            key_off <= 0;
        end else begin
            case (midi_msg)
                MSG_NOTE_ON:
                    key_on <= key_mask;
                MSG_NOTE_OFF:
                    key_off <= key_mask;
            endcase
        end
    end

endmodule
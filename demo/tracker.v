// tracker.v
//
// Copyright (C) 2020 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

`default_nettype none

`include "notes.vh"

module tracker(
    input clk,
    input reset,
    input stop,

    input [7:0] tempo,

    output reg [3:0] note_1,
    output reg [3:0] note_2,
    output reg [1:0] octave_1,
    output reg [1:0] octave_2,
    output reg playing,
    output reg finished,

    output reg [1:0] key_on,
    output reg [1:0] key_off,

    output reg tempo_tick
);
    // Command loading:

    reg [23:0] current_cmd;

    wire [4:0] cmd_duration = current_cmd[16:12];
    wire [1:0] cmd_octave_2 = current_cmd[11:10];
    wire [3:0] cmd_note_2 = current_cmd[9:6];
    wire [1:0] cmd_octave_1 = current_cmd[5:4];
    wire [3:0] cmd_note_1 = current_cmd[3:0];

    reg [5:0] track_index;

    reg new_cmd;

    always @(posedge clk) begin
        new_cmd <= 0;
        finished <= 0;

        if (reset) begin
            current_cmd <= 0;
            track_index <= 0;
            finished <= 0;
            playing <= 0;
        end else if (advance_index) begin
            current_cmd <= track[track_index];
            track_index <= track_index + 1;
            new_cmd <= 1;
            playing <= 1;
        end else if (track_end_reached || stopped) begin
            finished <= 1;
            playing <= 0;
        end
    end

    // Command handling:

    reg advance_index;
    reg track_end_reached;
    reg stopped;

    reg [4:0] duration_counter;

    always @(posedge clk) begin
        advance_index <= 0;
        key_on <= 0;
        key_off <= 0;

        if (reset) begin
            advance_index <= 1;
            duration_counter <= 0;
            track_end_reached <= 0;
            stopped <= 0;
        end else if (stop) begin
            key_off <= 2'b11;
            stopped <= 1;
        end else if (current_cmd[23]) begin
            track_end_reached <= 1;
        end else if (new_cmd) begin
            duration_counter <= cmd_duration;

            note_1 <= cmd_note_1;
            note_2 <= cmd_note_2;

            octave_1 <= cmd_octave_1;
            octave_2 <= cmd_octave_2;

            key_on <= {cmd_note_2 != `NOTE_UNDEFINED, cmd_note_1 != `NOTE_UNDEFINED};
        end else if (!finished && !advance_index && tempo_tick) begin
            if (duration_counter > 0) begin
                duration_counter <= duration_counter - 1;
            end else begin
                key_off <= 2'b11;

                advance_index <= 1;
            end
        end
    end

    // Command prescaler:

    reg [7:0] tempo_counter;

    always @(posedge clk) begin
        tempo_tick <= 0;

        if (reset) begin
            tempo_tick <= 0;
        end else if (prescaler_tick) begin
            tempo_counter <= tempo_counter + 1;
        end else if (tempo_counter > (255 - tempo)) begin
            tempo_counter <= 0;
            tempo_tick <= 1;
        end
    end

    reg [21:0] prescaler;
    wire prescaler_tick = prescaler[12];

    always @(posedge clk) begin
        if (reset) begin
            prescaler <= 0;
        end else begin
            prescaler <= (prescaler_tick ? 0 : prescaler + 1);
        end
    end

    // --- Track ---

    // It's easy enough to manually transcribe a bar or two of music here
    // Anything more complicated would be created externally

    localparam [23:0] TRACK_END = {24{1'b1}};

    reg [23:0] track [0:63];

    initial begin
        track[0] = cmd_transpose(8, 1, `NOTE_G, -3);
        track[1] = cmd_transpose(8, 1, `NOTE_FS, -3);
        track[2] = cmd_transpose(8, 1, `NOTE_F, -3);
        track[3] = cmd_transpose(8, 1, `NOTE_D, -3);
        track[4] = cmd_rest(8);

        track[5] = cmd_transpose(8, 1, `NOTE_E, -4);
        track[6] = cmd_rest(8);

        // ---

        track[7] = cmd_transpose(8, 0, `NOTE_G, -3);
        track[8] = cmd_transpose(8, 0, `NOTE_A, -3);

        track[9] = cmd_transpose(8, 1, `NOTE_C, -3);
        track[10] = cmd_rest(8);

        track[11] = cmd_transpose(8, 0, `NOTE_A, -3);
        track[12] = cmd_transpose(8, 1, `NOTE_C, -3);
        track[13] = cmd_transpose(8, 1, `NOTE_D, -3);
        track[14] = cmd_rest(16);

        // ---

        track[15] = cmd_transpose(8, 1, `NOTE_G, -3);
        track[16] = cmd_transpose(8, 1, `NOTE_FS, -3);
        track[17] = cmd_transpose(8, 1, `NOTE_F, -3);
        track[18] = cmd_transpose(8, 1, `NOTE_D, -3);
        track[19] = cmd_rest(8);

        track[20] = cmd_transpose(8, 1, `NOTE_E, -4);
        track[21] = cmd_rest(8);

        // ---

        track[22] = cmd_transpose(8, 2, `NOTE_C, -5);
        track[23] = cmd_rest(8);
        track[24] = cmd_transpose(8, 2, `NOTE_C, -5);
        track[25] = cmd_transpose(8, 2, `NOTE_C, -5);
        track[26] = cmd_rest(8);

        // ---

        track[27] = cmd_rest(16);
        track[28] = cmd_rest(16);

        // ---

        track[29] = cmd_transpose(8, 1, `NOTE_G, -3);
        track[30] = cmd_transpose(8, 1, `NOTE_FS, -3);
        track[31] = cmd_transpose(8, 1, `NOTE_F, -3);
        track[32] = cmd_transpose(8, 1, `NOTE_D, -3);
        track[33] = cmd_rest(8);

        track[34] = cmd_transpose(8, 1, `NOTE_E, -4);
        track[35] = cmd_rest(8);

        // ---

        track[36] = cmd_transpose(8, 0, `NOTE_G, -3);
        track[37] = cmd_transpose(8, 0, `NOTE_A, -3);

        track[38] = cmd_transpose(8, 1, `NOTE_C, -3);
        track[39] = cmd_rest(8);

        track[40] = cmd_transpose(8, 0, `NOTE_A, -3);
        track[41] = cmd_transpose(8, 1, `NOTE_C, -3);
        track[42] = cmd_transpose(8, 1, `NOTE_D, -3);
        track[43] = cmd_rest(16);

        // ---

        track[44] = cmd_transpose(8, 1, `NOTE_DS, -5);
        track[45] = cmd_rest(16);
        track[46] = cmd_transpose(8, 1, `NOTE_D, -5);
        track[47] = cmd_rest(16);
        track[48] = cmd_transpose(8, 1, `NOTE_C, -5);
        track[49] = cmd_rest(16);

        // ---

        track[50] = cmd_rest(16);
        track[51] = cmd_rest(16);
        track[52] = cmd_rest(16);
        track[53] = cmd_rest(16);

        // ---

        track[54] = TRACK_END;
    end

    // --- Convenience functions ---

    function [23:0] cmd_rest;
        input [4:0] duration;

        cmd_rest = cmd(duration, 0, `NOTE_UNDEFINED, 0, `NOTE_UNDEFINED);
    endfunction

    function [23:0] cmd_transpose;
        input [4:0] duration;
        input [1:0] octave;
        input [3:0] note;
        input signed [3:0] shift;

        if (shift < 0 && ($signed({1'b0, note}) + shift) < 0) begin
            cmd_transpose = cmd(duration, octave, note, octave - 1, note + shift - 4);
        end else if (shift >= 0 && ($signed({1'b0, note}) + shift >= 12)) begin
            cmd_transpose = cmd(duration, octave, note, octave + 1, note + shift + 4);
        end else begin
            cmd_transpose = cmd(duration, octave, note, octave, note + shift);
        end

    endfunction

    function [23:0] cmd;
        input [4:0] duration;
        input [1:0] octave_2;
        input [3:0] note_2;
        input [1:0] octave_1;
        input [3:0] note_1;

        cmd = {duration, octave_2, note_2, octave_1, note_1};
    endfunction

endmodule

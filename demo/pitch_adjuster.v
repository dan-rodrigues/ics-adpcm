// pitch_adjuster.v
//
// Copyright (C) 2020 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

// Favoring simplicity over accuracy or speed here

`default_nettype none

`include "notes.vh"

module pitch_adjuster(
    input clk,
    input reset,

    input reference_pitch_valid,
    input [15:0] reference_pitch,
    input [3:0] target_note,
    input [1:0] octave,

    output reg [15:0] adjusted_pitch,
    output reg adjusted_pitch_valid
);
    localparam [31:0] sqrt2_12 = 32'h10f39;

    reg [3:0] note_delta;

    reg adjusting;

    always @(posedge clk) begin
        if (reset) begin
            adjusted_pitch_valid <= 0;
            adjusting <= 0;
        end else if (adjusting) begin
            if (note_delta == 0) begin
                adjusting <= 0;
                adjusted_pitch_valid <= 1;
            end else begin
                adjusted_pitch <= (adjusted_pitch * sqrt2_12) / 32'h10000;
                note_delta <= note_delta - 1;
            end
        end else if (reference_pitch_valid) begin
            // It's assumed the reference note is always C (encoded as 0)
            note_delta <= target_note;
            adjusted_pitch <= reference_pitch << octave;

            adjusted_pitch_valid <= 0;
            adjusting <= 1;
        end
    end

endmodule

// midi_status_input_buffer.v
//
// Copyright (C) 2020 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

module midi_status_input_buffer #(
    parameter [3:0] CHANNELS = 3
) (
    input clk,
    input reset,

    input note_on,
    input [3:0] note_in,
    input [1:0] octave_in,
    input [3:0] channel_in,

    input [CHANNELS - 1:0] note_off,

    // Output to encode

    output reg note_on_out,
    output reg [3:0] note_out,
    output reg [1:0] octave_out,
    output reg [3:0] channel_out,
    output reg output_valid,
    input output_ack
);
    reg [CHANNELS - 1:0] channels_pending;

    reg [3:0] note_mem [0:CHANNELS - 1];
    reg [1:0] octave_mem [0:CHANNELS - 1];
    reg [CHANNELS - 1:0] note_on_mem;

    reg awaiting_ack;

    always @(posedge clk) begin
        if (reset) begin
            output_valid <= 0;
            channels_pending <= 0;
            awaiting_ack <= 0;
        end else begin
            if (|note_off) begin
                note_on_mem <= note_on_mem & ~note_off;
                channels_pending <= channels_pending | note_off;
            end

            if (note_on) begin
                note_mem[channel_in] <= note_in;
                note_on_mem[channel_in] <= 1;
                octave_mem[channel_in] <= octave_in;
                channels_pending[channel_in] <= 1;
            end

            output_valid <= 0;

            if (awaiting_ack && output_ack) begin
                awaiting_ack <= 0;
            end else if (!awaiting_ack && |channels_pending) begin
                channel_out <= next_queued_channel;
                note_out <= note_mem[next_queued_channel];
                note_on_out <= note_on_mem[next_queued_channel];
                octave_out <= octave_mem[next_queued_channel];

                channels_pending[next_queued_channel] <= 0;

                awaiting_ack <= 1;
                output_valid <= 1;
            end
        end
    end

    reg [3:0] next_queued_channel;

    integer i;
    always @* begin
        next_queued_channel = 0;

        for (i = CHANNELS - 1; i >= 0; i = i - 1) begin
            if (channels_pending[i]) begin
                next_queued_channel = i;
            end
        end
    end

endmodule

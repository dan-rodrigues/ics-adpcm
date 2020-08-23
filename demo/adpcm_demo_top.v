// adpcm_demo_top.v
//
// Copyright (C) 2020 Dan Rodrigues <danrr.gh.oss@gmail.com>
//
// SPDX-License-Identifier: MIT

// This is a demo of the ics_adpcm.v module for the ULX3S board using the headphone jack
//
// It can be controlled using the 3 horizontal buttons for key-on (C, E, G notes)
// It can also start / stop a preloaded track using the 2 horizontal buttons

`default_nettype none

`include "notes.vh"

module adpcm_demo_top #(
    parameter integer CLK_FREQ = 50000000,
    parameter signed [7:0] VOLUME = 8'h10
) (
    input clk_25mhz,

    input [6:0] btn,

    output [7:0] led,

    output [3:0] audio_l,
    output [3:0] audio_r,
    output [3:0] audio_v
);
    // --- PLL (50MHz) ---

    wire pll_locked;
    wire clk;

    pll pll(
        .clkin(clk_25mhz),
        .clkout0(clk),
        .locked(pll_locked)
    );

    // --- Reset generator ---

    reg [23:0] reset_counter = 0;
    wire reset = !reset_counter[23];

    always @(posedge clk) begin
        if (!pll_locked) begin
            reset_counter <= 0;
        end else if (reset) begin
            reset_counter <= reset_counter + 1;
        end
    end

    // --- DAC ---

    reg [15:0] output_l_valid, output_r_valid;

    always @(posedge clk) begin
        if (output_valid) begin
            output_l_valid <= output_l;
            output_r_valid <= output_r;
        end
    end

    // Analog:

    dacpwm #(
        .C_pcm_bits(16),
        .C_dac_bits(4)
    ) dacpwm [1:0] (
        .clk(clk),

        .pcm({output_l_valid, output_r_valid}),
        .dac({audio_l, audio_r})
    );

    // SPDIF:

    wire [15:0] spdif_selected_sample = spdif_channel_select ? output_r_valid : output_l_valid;
    wire [23:0] spdif_pcm_in = {spdif_selected_sample, 8'b0};

    wire spdif;
    wire spdif_channel_select;
    assign audio_v = {2'b00, spdif, 1'b0};

    spdif_tx #(
      .C_clk_freq(CLK_FREQ),
      .C_sample_freq(44100)
    ) spdif_tx (
      .clk(clk),
      .data_in(spdif_pcm_in),
      .address_out(spdif_channel_select),
      .spdif_out(spdif)
    );

    // --- Pitch adjustment ---

    wire [15:0] adjusted_pitch;
    wire adjusted_pitch_valid;

    reg [1:0] octave;

    always @(posedge clk) begin
        if (reset) begin
            octave <= 0;
        end else if (trigger[0]) begin
            octave <= octave + 1;
        end
    end

    pitch_adjuster pitch_adjuster(
        .clk(clk),
        .reset(reset),

        .reference_pitch(reference_pitch),
        .target_note(target_note),
        .octave(target_octave),
        .reference_pitch_valid(pitch_needs_adjusting),

        .adjusted_pitch(adjusted_pitch),
        .adjusted_pitch_valid(adjusted_pitch_valid)
    );

    // --- Tracker (optional automatic playback) ---

    // User control:
    
    reg tracker_start;
    reg tracker_continue;
    reg tracker_stop;

    always @(posedge clk) begin
        tracker_start <= 0;
        tracker_stop <= 0;

        if (reset) begin
            tracker_continue <= 0;
            tracker_stop <= 0;
        end else if (tracker_finished && tracker_continue) begin
            tracker_start <= 1;
        end else if (trigger[1]) begin
            tracker_start <= 1;
            tracker_continue <= 1;
            tracker_stop <= 0;
        end else if (trigger[2]) begin
            tracker_continue <= 0;
            tracker_stop <= 1;
        end 
    end

    // Tracker:

    wire tracker_finished; 
    wire tracker_playing;
    wire [3:0] tracker_note_1, tracker_note_2;
    wire [1:0] tracker_octave_1, tracker_octave_2;

    wire [1:0] tracker_key_on, tracker_key_off;

    wire tracker_tempo_tick;

    reg [3:0] tracker_prescaler_tick_counter;
    assign led[3] = tracker_prescaler_tick_counter[3] && tracker_playing;

    always @(posedge clk) begin
        if (reset) begin
            tracker_prescaler_tick_counter <= 0;
        end else if (tracker_tempo_tick) begin
            tracker_prescaler_tick_counter <= tracker_prescaler_tick_counter + 1;
        end
    end

    tracker tracker(
        .clk(clk),
        .reset(reset || tracker_start),
        .stop(tracker_stop),

        .tempo(48),

        .finished(tracker_finished),
        .playing(tracker_playing),

        .note_1(tracker_note_1),
        .note_2(tracker_note_2),
        .octave_1(tracker_octave_1),
        .octave_2(tracker_octave_2),

        .key_on(tracker_key_on),
        .key_off(tracker_key_off),

        .tempo_tick(tracker_tempo_tick)
    );

    // --- Channel start / stop control ---

    wire [2:0] user_pending_start = {trigger[6], trigger[4], trigger[5]};
    wire [2:0] user_pending_stop = {released[6], released[4], released[5]};

    wire [2:0] tracker_pending_start = {1'b0, tracker_key_on};
    wire [2:0] tracker_pending_stop = {1'b0, tracker_key_off};

    wire [2:0] pending_start = !tracker_playing ? user_pending_start : tracker_pending_start;
    wire [2:0] pending_stop = !tracker_playing ? user_pending_stop : tracker_pending_stop;

    // --- Channel control ---

    // Note selection:

    reg [3:0] target_note;
    reg [1:0] target_octave;

    always @* begin
        case (channel_being_configured)
            0: target_note = !tracker_playing ? `NOTE_C : tracker_note_1;
            1: target_note = !tracker_playing ? `NOTE_E : tracker_note_2;
            2: target_note = `NOTE_G;
            default: target_note = `NOTE_A;
        endcase
    end

    always @* begin
        if (!tracker_playing) begin
            target_octave = octave;
        end else begin
            case (channel_being_configured)
                0: target_octave = tracker_octave_1;
                1: target_octave = tracker_octave_2;
                default: target_octave = 0;
            endcase
        end
    end

    // Channel configuration (channel registers):

    wire reg_write_complete = (reg_index == (REG_PITCH + 1));
    wire [7:0] ch_write_address = reg_index + channel_being_configured * 8;

    reg ch_write_en;
    reg [2:0] reg_index;
    reg channel_writing;

    reg pitch_needs_adjusting;

    reg [2:0] channels_pending_start;
    reg [2:0] channels_pending_config;
    reg [1:0] channel_being_configured;

    always @(posedge clk) begin
        pitch_needs_adjusting <= 0;

        channels_pending_start <= 0;
        channels_pending_config <= channels_pending_config | pending_start;

        if (reset) begin
            channels_pending_config <= 0;
            channel_writing <= 0;
            ch_write_en <= 0;
        end else if (channel_writing) begin
            if (adjusted_pitch_valid) begin
                ch_write_en <= 1;
            end
                
            if (ch_write_ready) begin
                reg_index <= reg_index + 1;
                ch_write_en <= 0;
            end

            if (reg_write_complete) begin
                channel_writing <= 0;
                ch_write_en <= 0;
                channels_pending_start[channel_being_configured] <= 1;
                channels_pending_config[channel_being_configured] <= 0;
            end
        end else if (channels_pending_config) begin
            channel_being_configured <=
                channels_pending_config[0] ? 0 :
                channels_pending_config[1] ? 1 :
                channels_pending_config[2] ? 2 : 0;

            reg_index <= 0;
            channel_writing <= 1;
            pitch_needs_adjusting <= 1;

            ch_write_en <= 0;
        end
    end

    // Channel start / stop control (global registers)

    reg gb_write_en;
    reg [0:0] gb_write_address;
    reg [2:0] gb_write_data;

    reg [2:0] channels_to_start, channels_to_stop;

    always @(posedge clk) begin
        channels_to_start <= channels_to_start | channels_pending_start;
        channels_to_stop <= channels_to_stop | pending_stop;

        if (reset) begin
            gb_write_en <= 0;
        end else if (|channels_to_start && !gb_write_busy) begin
            gb_write_data <= channels_to_start;
            gb_write_address <= 1'h00;
            gb_write_en <= 1;

            channels_to_start <= 0;
        end else if (|channels_to_stop && !gb_write_busy) begin
            gb_write_data <= channels_to_stop;
            gb_write_address <= 1'h01;
            gb_write_en <= 1;

            channels_to_stop <= 0;
        end

        if (gb_write_ready) begin
            gb_write_en <= 0;
        end
    end

    // Sample selection:

    localparam [1:0]
        S_PIANO = 0,
        S_STEEL_DRUM = 1,
        S_SQUARE_WAVE = 2;

    localparam [1:0] S_TOTAL = 3;

    reg [1:0] selected_sample;

    always @(posedge clk) begin
        if (reset) begin
            selected_sample <= S_PIANO;
        end else begin
            if (trigger[3]) begin
                selected_sample <= ((selected_sample != (S_TOTAL - 1)) ? selected_sample + 1 : 0);
            end
        end
    end

    // Sample attribute selection:

    reg [15:0] reference_pitch;
    reg [15:0] sample_start_address, sample_loop_address, sample_end_address;
    reg sample_is_looped;

    always @* begin
        case (selected_sample)
            S_PIANO: begin
                sample_start_address = PIANO_BLOCK_START;
                sample_loop_address = -1;
                sample_end_address = PIANO_BLOCK_END;

                sample_is_looped = 0;
                reference_pitch = 5160 / 2;
            end
            S_STEEL_DRUM: begin
                sample_start_address = STEEL_DRUM_BLOCK_START;
                sample_loop_address = -1;
                sample_end_address = STEEL_DRUM_BLOCK_END;

                sample_is_looped = 0;
                reference_pitch = 2896 / 2;
            end
            S_SQUARE_WAVE: begin
                sample_start_address = SQUARE_BLOCK_START;
                sample_loop_address = SQUARE_BLOCK_START;
                sample_end_address = SQUARE_BLOCK_END;

                sample_is_looped = 1;

                // Middle C = 261hz
                // 261 / (44100 / 255) = 1.509
                // 4096 * 1.509 = 6180.86
                reference_pitch = 6181;
            end
            default: begin
                sample_start_address = 0;
                sample_loop_address = 0;
                sample_end_address = 0;

                sample_is_looped = 1;
                reference_pitch = 0;
            end
        endcase
    end

    // Register write data selection:

    reg [7:0] volume_left, volume_right;

    // Low volumes are better for headphones, anything above 10h is very loud

    always @(posedge clk) begin
        if (reset) begin
            volume_left <= VOLUME;
            volume_right <= VOLUME;
        end
    end

    localparam [2:0]
        REG_START = 0,
        REG_FLAGS = 1,
        REG_END = 2,
        REG_LOOP = 3,
        REG_VOLUMES = 4,
        REG_PITCH = 5;

    reg [15:0] ch_write_data;

    always @* begin
        case (reg_index[2:0])
            REG_START: ch_write_data = sample_start_address;
            REG_FLAGS: ch_write_data = {15'b0, sample_is_looped};
            REG_END: ch_write_data = sample_end_address;
            REG_LOOP: ch_write_data = sample_loop_address;
            REG_VOLUMES: ch_write_data = {volume_right, volume_left};
            REG_PITCH: ch_write_data = adjusted_pitch;
            default: ch_write_data = 0;
        endcase
    end

    // --- Button debouncing ---

    wire [6:0] level, trigger, released;

    debouncer #(
        .BTN_COUNT(7)
    ) debouncer (
        .clk(clk),
        .reset(reset),

        .btn({btn[6:1], ~btn[0]}),

        .level(level),
        .trigger(trigger),
        .released(released)
    );

    // --- PCM memory ---

    reg [15:0] pcm_ram [0:65535];
    reg [15:0] pcm_read_data;
    reg pcm_data_ready;

    always @(posedge clk) begin
        pcm_read_data <= pcm_ram[pcm_read_address[15:0]];
        pcm_data_ready <= pcm_address_valid;
    end

    // Preloaded samples:

    localparam PIANO_BLOCK_START = 0;
    localparam PIANO_BLOCK_END = 24;

    localparam STEEL_DRUM_BLOCK_START = PIANO_BLOCK_END;
    localparam STEEL_DRUM_BLOCK_END = STEEL_DRUM_BLOCK_START + 7;

    localparam SQUARE_BLOCK_START = STEEL_DRUM_BLOCK_END;
    localparam SQUARE_BLOCK_END = SQUARE_BLOCK_START + 1;

    initial begin
        $readmemh("samples/piano.hex", pcm_ram, PIANO_BLOCK_START * 512);
        $readmemh("samples/steel_drum.hex", pcm_ram, STEEL_DRUM_BLOCK_START * 512);
        $readmemh("samples/square.hex", pcm_ram, SQUARE_BLOCK_START * 512);
    end

    // Unassigned LEDs:

    assign led[7:4] = 0;

    // --- ADPCM ---

    wire output_valid;
    wire [15:0] output_l, output_r;

    wire pcm_address_valid;
    wire [23:0] pcm_read_address;

    wire ch_write_ready;
    wire gb_write_busy;
    wire gb_write_ready;

    ics_adpcm #(
        .OUTPUT_INTERVAL(CLK_FREQ / 44100),
        .CHANNELS(3)
    ) adpcm (
        .clk(clk),
        .reset(reset),

        .ch_write_ready(ch_write_ready),

        .ch_write_address(ch_write_address),
        .ch_write_data(ch_write_data),
        .ch_write_en(ch_write_en),
        .ch_write_byte_mask(2'b11),

        .gb_write_address(gb_write_address),
        .gb_write_data(gb_write_data),
        .gb_write_en(gb_write_en),

        .gb_write_busy(gb_write_busy),
        .gb_write_ready(gb_write_ready),
        .gb_playing(led[2:0]),

        .status_read_address(0),
        .status_read_request(0),

        .pcm_read_address(pcm_read_address),
        .pcm_read_data(pcm_read_data),
        .pcm_data_ready(pcm_data_ready),
        .pcm_address_valid(pcm_address_valid),

        .output_valid(output_valid),
        .output_l(output_l),
        .output_r(output_r)
    );

endmodule

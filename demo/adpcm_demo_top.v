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

    input ftdi_txd,
    output ftdi_rxd,

    input [6:0] btn,

    output [7:0] led,

    output [3:0] audio_l,
    output [3:0] audio_r,
    output [3:0] audio_v,

    // ESP32 ("sd_d" pins in .lpf were renamed to their "wifi_gpio" equivalent)

    output wifi_en,

    input wifi_gpio5,
    input wifi_gpio16,
    input wifi_gpio2,
    input wifi_gpio4,

    output wifi_gpio12,
    output wifi_gpio13,

    input  wifi_txd,
    output wifi_rxd
);
    // --- MIDI control over bluetooth ---

    localparam [3:0] MIDI_CHANNELS = 3;

    assign wifi_en = 1;

    // UART for console:

    assign wifi_rxd = ftdi_txd;
    assign ftdi_rxd = wifi_txd;

    reg [3:0] esp_sync_ff [0:1];

    // ESP32 inputs:

    wire esp_write_en = esp_sync_ff[1][3];
    wire esp_spi_mosi = esp_sync_ff[1][2];
    wire esp_spi_clk = esp_sync_ff[1][1];
    wire esp_spi_csn = esp_sync_ff[1][0];

    always @(posedge clk) begin
        esp_sync_ff[1] <= esp_sync_ff[0];
        esp_sync_ff[0] <= {wifi_gpio2, wifi_gpio4, wifi_gpio16, wifi_gpio5};
    end

    // ESP32 outputs:

    assign wifi_gpio12 = esp_spi_miso;
    assign wifi_gpio13 = esp_read_needed;

    wire esp_spi_miso;
    wire esp_read_needed;

    // MIDI outputs:

    wire [MIDI_CHANNELS - 1:0] midi_key_on;
    wire [MIDI_CHANNELS - 1:0] midi_key_off;
    wire [3:0] midi_note;
    wire [1:0] midi_octave;

    assign led[7:4] = midi_key_on;

    reg [MIDI_CHANNELS - 1:0] status_note_off, status_note_off_r;

    always @(posedge clk) begin
        if (reset) begin
            status_note_off <= 0;
            status_note_off_r <= 0;
        end else begin
            status_note_off <= 0;

            if (status_note_off_r != channels_to_stop) begin
                status_note_off_r <= channels_to_stop;
                status_note_off <= channels_to_stop;
            end
        end
    end

    // MIDI priority over other inputs (if inputs are pending):

    reg [MIDI_CHANNELS - 1:0] midi_pending_key_on;

    always @(posedge clk) begin
        if (reset) begin
            midi_pending_key_on <= 0;
        end else begin 
            midi_pending_key_on <= (midi_pending_key_on | midi_key_on) & ~channels_pending_start;
        end
    end

    spi_midi_control #(
        .CHANNELS(MIDI_CHANNELS)
    ) midi_control (
        .clk(clk),
        .reset(reset),

        // ESP32

        .spi_csn(esp_spi_csn),
        .spi_clk(esp_spi_clk),
        .spi_mosi(esp_spi_mosi),
        .spi_miso(esp_spi_miso),
        .spi_write_en(esp_write_en),

        .read_needed(esp_read_needed),

        // Status input

        .status_note_on(channel_writing_started),
        .status_note(target_note),
        .status_octave(target_octave),
        .status_channel(channel_being_configured),

        .status_note_off(status_note_off),

        // Control output

        .key_on(midi_key_on),
        .key_off(midi_key_off),
        .note(midi_note),
        .octave(midi_octave)
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

    reg [1:0] user_octave;

    always @(posedge clk) begin
        if (reset) begin
            user_octave <= 0;
        end else if (trigger[0]) begin
            user_octave <= user_octave + 1;
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
    wire [2 * 4 - 1:0] tracker_notes;
    wire [2 * 2 - 1:0] tracker_octaves;

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

        .note_1(tracker_notes[3:0]),
        .note_2(tracker_notes[7:4]),
        .octave_1(tracker_octaves[1:0]),
        .octave_2(tracker_octaves[3:2]),

        .key_on(tracker_key_on),
        .key_off(tracker_key_off),

        .tempo_tick(tracker_tempo_tick)
    );

    // --- Channel start / stop control ---

    localparam [0:0] FORCE_MIDI_CONTROL = 0;

    localparam [1:0]
        CONFIG_SOURCE_MIDI = 0,
        CONFIG_SOURCE_BUTTON = 1,
        CONFIG_SOURCE_TRACKER = 2;

    reg [1:0] config_source;

    wire midi_keys_pending = |(
        midi_key_on | midi_pending_key_on |
        midi_key_off
    );

    always @* begin
        if (FORCE_MIDI_CONTROL || midi_keys_pending) begin
            config_source = CONFIG_SOURCE_MIDI;
        end else if (tracker_playing) begin
            config_source = CONFIG_SOURCE_TRACKER;
        end else begin
            config_source = CONFIG_SOURCE_BUTTON;
        end
    end

    wire [2:0] user_pending_start = {trigger[6], trigger[4], trigger[5]};
    wire [2:0] user_pending_stop = {released[6], released[4], released[5]};

    wire [2:0] tracker_pending_start = {1'b0, tracker_key_on};
    wire [2:0] tracker_pending_stop = {1'b0, tracker_key_off};

    reg [2:0] pending_start;
    reg [2:0] pending_stop;

    always @* begin
        case (config_source)
            CONFIG_SOURCE_MIDI: begin
                pending_start = midi_key_on;
                pending_stop = midi_key_off;
            end
            CONFIG_SOURCE_TRACKER: begin
                pending_start = tracker_pending_start;
                pending_stop = tracker_pending_stop;
            end
            CONFIG_SOURCE_BUTTON: begin
                pending_start = user_pending_start;
                pending_stop = user_pending_stop;
            end
        endcase
    end

    // --- Channel control ---

    // Note selection:

    reg [3:0] target_note;

    wire [4 * 3 - 1:0] button_notes = {`NOTE_G, `NOTE_E, `NOTE_C};

    always @* begin
        case (config_source)
            CONFIG_SOURCE_MIDI:
                target_note = midi_note;
            CONFIG_SOURCE_TRACKER:
                target_note = tracker_notes[channel_being_configured * 4+:4];
            CONFIG_SOURCE_BUTTON:
                target_note = button_notes[channel_being_configured * 4+:4];
            default:
                target_note = `NOTE_G;
        endcase
    end

    // Octave selection:

    reg [1:0] target_octave;

    always @* begin
        case (config_source)
            CONFIG_SOURCE_MIDI:
                target_octave = midi_octave;
            CONFIG_SOURCE_TRACKER:
                target_octave = tracker_octaves[channel_being_configured * 2+:2];
            CONFIG_SOURCE_BUTTON:
                target_octave = user_octave;
            default:
                target_octave = 0;
        endcase
    end

    // Channel configuration (channel registers):

    wire reg_write_complete = (reg_index == (REG_PITCH + 1));
    wire [7:0] ch_write_address = reg_index + channel_being_configured * 8;

    reg ch_write_en;
    reg [2:0] reg_index;
    reg channel_writing;
    reg channel_writing_started;

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
            channel_writing_started <= 0;
            ch_write_en <= 0;
        end else if (channel_writing) begin
            channel_writing_started <= 0;

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
            channel_writing_started <= 1;
            pitch_needs_adjusting <= 1;

            ch_write_en <= 0;
        end
    end

    // Channel start / stop control (global registers)

    reg gb_write_en;
    reg [0:0] gb_write_address;
    reg [2:0] gb_write_data;

    reg [2:0] channels_to_start, channels_to_stop;
    reg [2:0] channels_stopped;

    always @(posedge clk) begin
        channels_to_start <= channels_to_start | channels_pending_start;
        channels_to_stop <= channels_to_stop | pending_stop;
        channels_stopped <= 0;

        if (reset) begin
            gb_write_en <= 0;
            channels_stopped <= 0;
        end else if (|channels_to_start && !gb_write_busy) begin
            gb_write_data <= channels_to_start;
            gb_write_address <= 1'h00;
            gb_write_en <= 1;

            channels_to_start <= 0;
        end else if (|channels_to_stop && !gb_write_busy) begin
            gb_write_data <= channels_to_stop;
            gb_write_address <= 1'h01;
            gb_write_en <= 1;

            channels_stopped <= channels_to_stop;
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

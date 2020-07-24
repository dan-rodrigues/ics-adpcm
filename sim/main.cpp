#include <iostream>
#include <memory>
#include <deque>
#include <fstream>
#include <iterator>
#include <vector>
#include <getopt.h>

#include <stdint.h>

#include "tinywav.hpp"
#include "json.hpp"
#include "DSPControl.hpp"
#include "Serialization.hpp"
#include "TestConfig.hpp"

#include "Vics_adpcm.h"

#if VM_TRACE
#include <verilated_vcd_c.h>
#endif

using nlohmann::json;

// verilator specific: called by $time in Verilog
static vluint64_t main_time = 0;
double sc_time_stamp() {
    return main_time;
}

std::unique_ptr<Vics_adpcm> tb = std::make_unique<Vics_adpcm>();

std::vector<AudioChannel> configure_channels_from_json(const std::string &json_path);
void write_channel_context(const AudioChannel &context, uint8_t channel);

// DSP write

struct DSPWrite {
    uint16_t address;
    uint16_t data;
};

std::deque<DSPWrite> dsp_write_queue;
void queue_write(uint16_t address, uint16_t data);
void handle_pending_writes();
void handle_pcm_read();

// DSP read

bool channels_did_end(uint8_t channel);

// PCM reading

std::vector<uint16_t> pcm_memory;

// WAV capture

std::vector<int16_t> wav_capture;
bool capture_wav_output();
void write_wav(const std::string &path);

// Debug output capture

std::vector<DebugADPCM> debug_adpcm_capture;
void capture_debug_outputs();
void write_debug_adpcm_capture(const std::string &path);

// Assertions

bool assert_debug_adpcm_matches(const std::string &referencePath);
bool assert_wav_reference_matches(const std::string &referencePath);

int main(int argc, const char * argv[]) {
    Verilated::commandArgs(argc, argv);

    std::string wav_path = "reference.wav";
    std::string adpcm_capture_path = "adpcm_reference.json";

    std::string channel_config_json_path;
    std::string adpcm_capture_reference_json_path;
    std::string wav_reference_path;
    std::string test_config_path;

    const option options[] = {
        {.name = "ch-config", .has_arg = required_argument, .flag = NULL, .val = 'c'},
        {.name = "adpcm-capture-reference", .has_arg = required_argument, .flag = NULL, .val = 'a'},
        {.name = "wav-reference", .has_arg = required_argument, .flag = NULL, .val = 'r'},
        {.name = "test-config", .has_arg = required_argument, .flag = NULL, .val = 't'}
    };

    int opt = 0;
    while ((opt = getopt_long(argc, (char **)argv, "w:", &options[0], NULL)) != -1) {
        switch (opt) {
            case 'c':
                channel_config_json_path = optarg;
                break;
            case 't':
                test_config_path = optarg;
                break;
            case 'r':
                wav_reference_path = optarg;
                break;
            case 'a':
                adpcm_capture_reference_json_path = optarg;
                break;
            case 'w':
                wav_path = optarg;
                break;
            case '?':
                return EXIT_FAILURE;
        }
    }

    // Load test config

    if (test_config_path.empty()) {
        std::cerr << "Test config path must be provided (-t arg)" << std::endl;
        return EXIT_FAILURE;
    }

    std::ifstream config_stream(test_config_path, std::ios::in);
    if (config_stream.fail()) {
        std::cerr << "Failed to open test config file: " << test_config_path << std::endl;
        return EXIT_FAILURE;
    }

    json test_config_json;
    config_stream >> test_config_json;
    auto config = test_config_json.get<TestConfig>();
    config_stream.close();

    // Load test (AD)PCM file

    if (config.sample_path.empty()) {
        std::cerr << "Expected PCM file path in test config" << std::endl;
        return EXIT_FAILURE;
    }

    std::ifstream pcm_stream(config.sample_path, std::ios::binary | std::ios::in);
    if (pcm_stream.fail()) {
        std::cerr << "Failed to open PCM file: " << config.sample_path << std::endl;
        return EXIT_FAILURE;
    }

    std::vector<uint8_t> pcm(std::istreambuf_iterator<char>(pcm_stream), {});
    pcm_stream.close();

    auto channel_configs = configure_channels_from_json(channel_config_json_path);

    size_t pcm_end_address = 0;
    for (auto i : channel_configs) {
        // /2 since pcm_memory is 16bit
        pcm_end_address = std::max(pcm_end_address, (size_t)i.sample_end_address / 2);
    }

    // 1M PCM memory for now, resize as needed later
    const size_t pcm_memory_size = 0x1000000;
    if (pcm_end_address == 0) {
        // Wraparound case for very last word in memory
        pcm_end_address = pcm_memory_size;
    }

    if (pcm_end_address > pcm_memory_size) {
        std::cerr << "PCM end address exceeds memory size: " << pcm_end_address << std::endl;
        return EXIT_FAILURE;
    }

    size_t pcm_last_defined_address = std::max(pcm.size() / 2, pcm_end_address);
    pcm_memory.resize(pcm_last_defined_address);

    if (pcm_end_address / 4 >= pcm_memory.size()) {
        std::cerr << "PCM memory isn't large enough to reach defined end address" << std::endl;
        return EXIT_FAILURE;
    }

    // Load the samples to the channel-defined address
    for (auto config : channel_configs) {
        size_t pcm_base_address = config.sample_start_address / 4;
        for (size_t i = 0; i < pcm.size() / 2; i++) {
            pcm_memory[pcm_base_address + i] = pcm[i * 2 + 0] | pcm[i * 2 + 1] << 8;
        }
    }

    tb->reset = 1;
    tb->host_write_en = 0;
    tb->host_read_en = 0;
    tb->clk = 0;
    tb->eval();

    tb->clk = 1;
    tb->eval();

    tb->reset = 0;
    tb->clk = 0;
    tb->eval();

#if VM_TRACE
    Verilated::traceEverOn(true);
    std::unique_ptr<VerilatedVcdC> tfp = std::make_unique<VerilatedVcdC>();

    std::string vcd_filename = "dsp.vcd";
    tb->trace(tfp.get(), 99);
    tfp->open(vcd_filename.c_str());
    assert(tfp->isOpen());
#endif

    bool end_reached = false;

    while (!Verilated::gotFinish() && ((main_time < config.test_duration) && !end_reached)) {
        tb->clk = 1;
        tb->eval();
#if VM_TRACE
        tfp->dump(main_time);
#endif
        main_time++;

        // Handle writes / reads on the negedge
        handle_pending_writes();
        handle_pcm_read();

        tb->clk = 0;
        tb->eval();
#if VM_TRACE
        tfp->dump(main_time);
#endif
        main_time++;

        capture_debug_outputs();

        if (capture_wav_output()) {
            if ((wav_capture.size() / 2) >= config.sample_count) {
                end_reached = true;
                break;
            }
        }

        // Did ALL configured channels end?
        uint8_t channel_mask = (1 << channel_configs.size()) - 1;
        if (channels_did_end(channel_mask)) {
            end_reached = true;
        }
    }

    tb->final();
#if VM_TRACE
    tfp->close();
#endif

    if (!end_reached) {
        std::cerr << "Simulator timed out waiting for channel to end" << std::endl;
    }

    bool tests_passed = true;
    tests_passed &= assert_debug_adpcm_matches(adpcm_capture_reference_json_path);
    tests_passed &= assert_wav_reference_matches(wav_reference_path);

    write_wav(wav_path);
    write_debug_adpcm_capture(adpcm_capture_path);

    return tests_passed ? EXIT_SUCCESS : EXIT_FAILURE;
}

std::vector<AudioChannel> configure_channels_from_json(const std::string &json_path) {
    std::ifstream channel_config_stream;
    channel_config_stream.open(json_path, std::ios::in);
    json j;
    channel_config_stream >> j;
    auto channel_configs = j.get<std::vector<AudioChannel>>();
    channel_config_stream.close();

    // Configure channels
    for (uint8_t channel = 0; channel < channel_configs.size(); channel++) {
        write_channel_context(channel_configs[channel], channel);
    }

    // Play configured channels
    queue_write(0x100, (1 << channel_configs.size()) - 1);

    return channel_configs;
}

void write_channel_context(const AudioChannel &context, uint8_t channel) {
    uint8_t channel_reg_address = channel * 0x08;
    queue_write(channel_reg_address++, context.sample_start_address / 0x800);
    queue_write(channel_reg_address++, context.flags & 0xff);
    queue_write(channel_reg_address++, context.sample_end_address / 0x800);
    queue_write(channel_reg_address++, context.sample_loop_address / 0x800);
    queue_write(channel_reg_address++, context.volumes.left | context.volumes.right << 8);
    queue_write(channel_reg_address++, context.pitch);
}

void queue_write(uint16_t address, uint16_t data) {
    DSPWrite pending_write;
    pending_write.address = address;
    pending_write.data = data;
    dsp_write_queue.push_back(pending_write);
}

// Perform 1 write per cycle, if needed

void handle_pending_writes() {
    if (tb->host_write_en && !tb->host_ready) {
        return;
    }

    tb->host_write_en = 0;

    if (dsp_write_queue.empty()) {
        return;
    }

    auto pending_write = dsp_write_queue.front();
    dsp_write_queue.pop_front();

    tb->host_write_en = 1;
    tb->host_address = pending_write.address;
    tb->host_write_data = pending_write.data;
    tb->host_write_byte_mask = 0x03;
}

void handle_pcm_read() {
    if (!tb->pcm_address_valid) {
        tb->pcm_data_ready = 0;
        // Data should be cleared to prevent accidental reliance on old data
        // The tests should fail in that case
        tb->pcm_read_data = 0;
        return;
    }

    uint32_t address = tb->pcm_read_address;

    if (address & 0x01) {
        std::cerr << "Expected only even address (16bit accesses)" << std::endl;
        return;
    }

    address /= 2;
    if (address >= pcm_memory.size()) {
        std::cerr << "Attempted out of bounds PCM read" << std::endl;
        return;
    }

    tb->pcm_read_data = pcm_memory[address];
    tb->pcm_data_ready = 1;
}

bool capture_wav_output() {
    if (!tb->output_valid) {
        return false;
    }

    wav_capture.push_back(tb->output_l);
    wav_capture.push_back(tb->output_r);

    return true;
}

void write_wav(const std::string &path) {
    if (wav_capture.size() < 2) {
        std::cerr << "Cannot write WAV output as there isn't any" << std::endl;
        return;
    }

    TinyWav tw;
    bool open_status = tinywav_open_write(
        &tw,
        2,
        44100,
        TW_INT16,
        TW_INTERLEAVED,
        path.c_str()
    );

    if (open_status) {
        std::cerr << "Failed to open WAV output file for writing" << std::endl;
        return;
    }

    tinywav_write_f(&tw, &wav_capture[0], (int)(wav_capture.size() / 2));

    tinywav_close_write(&tw);
}

void capture_debug_outputs() {
    if (!tb->dbg_adpcm_valid) {
        return;
    }

    DebugADPCM adpcm_capture;
    adpcm_capture.predictor = tb->dbg_adpcm_predictor;
    adpcm_capture.step_index = tb->dbg_adpcm_step_index;
    adpcm_capture.time = main_time;
    debug_adpcm_capture.push_back(adpcm_capture);
}

void write_debug_adpcm_capture(const std::string &path) {
    json j;
    j["adpcm_capture"] = json(debug_adpcm_capture);

    std::ofstream stream(path);
    if (stream.fail()) {
        std::cerr << "Failed to open ADPCM debug capture file: " << path << std::endl;
        return;
    }

    stream << j.dump(4) << std::endl;
    stream.close();
}

bool assert_debug_adpcm_matches(const std::string &referencePath) {
    std::ifstream stream;
    stream.exceptions(std::ios::failbit);
    stream.open(referencePath, std::ios::in);
    json refrence_json;
    stream >> refrence_json;
    stream.close();

    auto reference_captures = refrence_json["adpcm_capture"].get<std::vector<DebugADPCM>>();

    if (reference_captures.size() != debug_adpcm_capture.size()) {
        std::cout << "Warning: ADPCM debug capture is not equally sized to reference" << "\n";
    }

    size_t diff_length = std::min(reference_captures.size(), debug_adpcm_capture.size());

    bool does_match = true;

    for (size_t i = 0; i < diff_length; i++) {
        auto time = debug_adpcm_capture[i].time;
        if (reference_captures[i].predictor != debug_adpcm_capture[i].predictor) {
            std::cerr << "ADPCM debug: predictor mismatch at: " << time << std::endl;
            does_match = false;
            break;
        }

        if (reference_captures[i].step_index != debug_adpcm_capture[i].step_index) {
            std::cerr << "ADPCM debug: step_index mismatch at: " << time << std::endl;
            does_match = false;
            break;
        }
    }

    if (does_match) {
        std::cout << "Debug ADPCM capture matches" << "\n";
    }

    return does_match;
}

bool assert_wav_reference_matches(const std::string &referencePath) {
    if (wav_capture.size() < 2) {
        std::cerr << "No WAV capture to compare reference to" << std::endl;
        return false;
    }

    TinyWav tw;
    if (tinywav_open_read(&tw, referencePath.c_str(), TW_INTERLEAVED, TW_INT16)) {
        std::cerr << "Failed to open reference WAV file" << std::endl;
        return false;
    }

    if (tw.numChannels != 2) {
        std::cerr << "Expected reference WAV to be stereo" << std::endl;
        return false;
    }

    size_t reference_sample_count = tw.h.Subchunk2Size / 2;
    if (reference_sample_count != wav_capture.size()) {
        std::cerr << "Reference WAV has mismatched size: ";
        std::cerr << "Reference: " << reference_sample_count << ", Captured: " << wav_capture.size() << std::endl;
    }

    std::vector<int16_t> reference_samples;
    reference_samples.resize(reference_sample_count);
    tinywav_read_f(&tw, &reference_samples[0], (int)reference_sample_count / 2);

    size_t diff_length = std::min(reference_samples.size(), wav_capture.size());
    for (size_t i = 0; i < diff_length; i++) {
        if (reference_samples[i] != wav_capture[i]) {
            std::cerr << "Reference WAV mismatch at: " << i << " ";
            std::cerr << "(stereo sample: " << i / 2 << ")" << std::endl;
            return false;
        }
    }

    std::cout << "Reference WAV matches" << "\n";

    return true;
}

bool channels_did_end(uint8_t channel_mask) {
    return (tb->host_read_data & channel_mask) == channel_mask;
}

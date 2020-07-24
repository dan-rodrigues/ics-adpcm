#include "Serialization.hpp"

#include <limits>

void to_json(json& j, const DebugADPCM &p) {
    j = json{
        {"predictor", p.predictor},
        {"step_index", p.step_index},
        {"time", p.time}
    };
}

void from_json(const json& j, DebugADPCM &p) {
    j.at("predictor").get_to(p.predictor);
    j.at("step_index").get_to(p.step_index);
    j.at("time").get_to(p.time);
}

void to_json(json& j, const AudioChannel &p) {
    j = json{
        {"sample_start_address", p.sample_start_address},
        {"sample_end_address", p.sample_end_address},
        {"sample_loop_address", p.sample_loop_address},
        {"flags", p.flags},
        {"volume_left", p.volumes.left},
        {"volume_right", p.volumes.right},
        {"pitch", p.pitch}
    };
}

void from_json(const json& j, AudioChannel &p) {
    j.at("sample_start_address").get_to(p.sample_start_address);
    j.at("sample_end_address").get_to(p.sample_end_address);
    j.at("sample_loop_address").get_to(p.sample_loop_address);
    j.at("flags").get_to(p.flags);
    j.at("volume_left").get_to(p.volumes.left);
    j.at("volume_right").get_to(p.volumes.right);
    j.at("pitch").get_to(p.pitch);
}

void to_json(json& j, const TestConfig &p) {
    j = json{
        {"sample_path", p.sample_path},
        {"test_duration", p.test_duration}
    };
}

void from_json(const json& j, TestConfig &p) {
    j.at("sample_path").get_to(p.sample_path);
    j.at("test_duration").get_to(p.test_duration);
    if (j.contains("sample_count")) {
        j.at("sample_count").get_to(p.sample_count);
    } else {
        p.sample_count = std::numeric_limits<uint64_t>::max();
    }
}

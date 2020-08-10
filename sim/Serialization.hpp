#ifndef Serialization_hpp
#define Serialization_hpp

#include "Control.hpp"
#include "json.hpp"
#include "TestConfig.hpp"

using nlohmann::json;

void to_json(json& j, const DebugADPCM &p);
void from_json(const json& j, DebugADPCM &p);

void to_json(json& j, const AudioChannel &p);
void from_json(const json& j, AudioChannel &p);

void to_json(json& j, const TestConfig &p);
void from_json(const json& j, TestConfig &p);

#endif /* Serialization_hpp */

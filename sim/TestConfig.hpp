#ifndef TestConfig_hpp
#define TestConfig_hpp

#include <stdint.h>
#include <string>

struct TestConfig {
    std::string sample_path;
    uint64_t test_duration;
    uint64_t sample_count;
};

#endif /* TestConfig_hpp */

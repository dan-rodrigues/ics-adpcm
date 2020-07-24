#ifndef adpcm_dsp_hpp
#define adpcm_dsp_hpp

#include <stdint.h>

struct DebugADPCM {
    uint64_t time;
    int16_t predictor;
    int8_t step_index;
};

enum AudioFlags {
    AUDIO_FLAG_LOOP = 1 << 0,
    AUDIO_FLAG_ADPCM = 1 << 1
};

struct AudioVolumes {
    int8_t left, right;
};

struct AudioChannel {
    uint32_t sample_start_address;

    AudioFlags flags;

    uint32_t sample_end_address;
    uint32_t sample_loop_address;
    AudioVolumes volumes;
    uint16_t pitch;
};

#endif /* adpcm_dsp_hpp */

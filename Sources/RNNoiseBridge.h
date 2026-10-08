#ifndef RNNoiseBridge_h
#define RNNoiseBridge_h

#include "rnnoise.h"

static inline DenoiseState *MeetRecRNNoiseCreate(void) {
    return rnnoise_create(NULL);
}

static inline void MeetRecRNNoiseDestroy(DenoiseState *state) {
    rnnoise_destroy(state);
}

static inline int MeetRecRNNoiseFrameSize(void) {
    return rnnoise_get_frame_size();
}

static inline float MeetRecRNNoiseProcess(DenoiseState *state, float *out, const float *in) {
    return rnnoise_process_frame(state, out, in);
}

#endif

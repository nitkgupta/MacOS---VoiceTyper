//
//  VoiceTyper-Bridging-Header.h
//  VoiceTyper
//
//  Bridging header to expose whisper.cpp C API to Swift.
//  This file is referenced in Build Settings → SWIFT_OBJC_BRIDGING_HEADER.
//

#ifndef VoiceTyper_Bridging_Header_h
#define VoiceTyper_Bridging_Header_h

// whisper.cpp C API
// Uncomment these when whisper.cpp is added as a submodule
// #include "whisper.h"

// For now, we define the minimal C interface we need as stubs
// so the Swift code compiles without the whisper.cpp source.

#ifdef WHISPER_AVAILABLE

#include "whisper.h"

#else

// Stub types for compilation without whisper.cpp
// These match the whisper.h API signatures we use

#include <stdbool.h>
#include <stdint.h>

typedef struct whisper_context whisper_context;
typedef struct whisper_full_params whisper_full_params;

typedef enum {
    WHISPER_SAMPLING_GREEDY,
    WHISPER_SAMPLING_BEAM_SEARCH,
} whisper_sampling_strategy;

// Initialize from file
struct whisper_context * whisper_init_from_file(const char * path_model);

// Free context
void whisper_free(struct whisper_context * ctx);

// Get default full params
struct whisper_full_params whisper_full_default_params(enum whisper_sampling_strategy strategy);

// Run full transcription
int whisper_full(
    struct whisper_context * ctx,
    struct whisper_full_params params,
    const float * samples,
    int n_samples);

// Get number of segments
int whisper_full_n_segments(struct whisper_context * ctx);

// Get segment text
const char * whisper_full_get_segment_text(struct whisper_context * ctx, int i_segment);

#endif // WHISPER_AVAILABLE

#endif /* VoiceTyper_Bridging_Header_h */

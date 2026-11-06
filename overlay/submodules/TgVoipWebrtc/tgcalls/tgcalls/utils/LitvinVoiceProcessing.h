#ifndef LITVIN_VOICE_PROCESSING_H
#define LITVIN_VOICE_PROCESSING_H

#include <memory>

#include "modules/audio_processing/include/audio_processing.h"

namespace litvin {

// Capture post-processor for 1:1 calls. Returns nullptr when the voice changer
// is off (or disabled for calls), so the default WebRTC pipeline is untouched.
std::unique_ptr<webrtc::CustomProcessing> CreateVoiceChangerProcessing();

} // namespace litvin

#endif

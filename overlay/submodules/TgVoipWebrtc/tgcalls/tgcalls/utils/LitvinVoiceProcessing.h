#ifndef LITVIN_VOICE_PROCESSING_H
#define LITVIN_VOICE_PROCESSING_H

#include <memory>

#include "modules/audio_processing/include/audio_processing.h"

namespace litvin {

// Capture post-processor for 1:1 calls. Returns nullptr when the voice changer
// is off (or disabled for calls), so the default WebRTC pipeline is untouched.
std::unique_ptr<webrtc::CustomProcessing> CreateVoiceChangerProcessing();

// For group calls, where Telegram already installs its own capture
// post-processor (audio level + noise suppression): runs `inner` first and the
// voice changer after it. Returns `inner` unchanged when the voice changer is off.
std::unique_ptr<webrtc::CustomProcessing> WrapWithVoiceChanger(std::unique_ptr<webrtc::CustomProcessing> inner);

} // namespace litvin

#endif

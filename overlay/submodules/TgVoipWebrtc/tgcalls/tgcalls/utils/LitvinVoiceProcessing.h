#ifndef LITVIN_VOICE_PROCESSING_H
#define LITVIN_VOICE_PROCESSING_H

#include <memory>

#include "modules/audio_processing/include/audio_processing.h"

namespace litvin {

// Capture post-processor for 1:1 calls. Always installed: it passes audio
// through untouched while the voice changer is off and re-reads the Litvin
// settings about twice a second, so the voice can be changed during a call.
std::unique_ptr<webrtc::CustomProcessing> CreateVoiceChangerProcessing();

// For group calls, where Telegram already installs its own capture
// post-processor (audio level + noise suppression): runs `inner` first and the
// voice changer after it.
std::unique_ptr<webrtc::CustomProcessing> WrapWithVoiceChanger(std::unique_ptr<webrtc::CustomProcessing> inner);

} // namespace litvin

#endif

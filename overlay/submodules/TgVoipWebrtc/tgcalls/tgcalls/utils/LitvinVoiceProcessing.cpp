#include "utils/LitvinVoiceProcessing.h"

#include <string>

#include "modules/audio_processing/audio_buffer.h"
#include "utils/LitvinVoiceDsp.h"

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#endif

namespace litvin {

namespace {

#ifdef __APPLE__
bool readPreference(const char *key, double *value) {
    CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key, kCFStringEncodingUTF8);
    if (!cfKey) {
        return false;
    }
    CFPropertyListRef ref = CFPreferencesCopyAppValue(cfKey, kCFPreferencesCurrentApplication);
    CFRelease(cfKey);
    if (!ref) {
        return false;
    }
    bool found = false;
    if (CFGetTypeID(ref) == CFBooleanGetTypeID()) {
        *value = CFBooleanGetValue((CFBooleanRef)ref) ? 1.0 : 0.0;
        found = true;
    } else if (CFGetTypeID(ref) == CFNumberGetTypeID()) {
        found = CFNumberGetValue((CFNumberRef)ref, kCFNumberDoubleType, value);
    }
    CFRelease(ref);
    return found;
}
#else
bool readPreference(const char *, double *) {
    return false;
}
#endif

VoiceSettings currentSettings() {
    VoiceSettings settings;
    double value = 0.0;
    if (readPreference("litvin.voice.preset", &value)) {
        settings.preset = (int)value;
    }
    if (readPreference("litvin.voice.pitch", &value)) {
        settings.pitch = value;
    }
    if (readPreference("litvin.voice.strength", &value)) {
        settings.strength = value;
    }
    if (readPreference("litvin.voice.volume", &value)) {
        settings.volume = value;
    }
    if (readPreference("litvin.voice.echo", &value)) {
        settings.echo = value;
    }
    if (readPreference("litvin.voice.calls", &value)) {
        settings.calls = value != 0.0;
    }
    return settings;
}

class VoiceChangerProcessing : public webrtc::CustomProcessing {
public:
    explicit VoiceChangerProcessing(const VoiceSettings &settings) :
    _settings(settings) {
    }

    void Initialize(int sample_rate_hz, int num_channels) override {
        (void)num_channels;
        _sampleRate = sample_rate_hz > 0 ? sample_rate_hz : 48000;
        _dsp.reset(new VoiceDsp(_settings, (float)_sampleRate));
    }

    void Process(webrtc::AudioBuffer *buffer) override {
        if (!buffer || !_dsp || buffer->num_channels() == 0) {
            return;
        }
        float *const *channels = buffer->channels();
        const size_t frames = buffer->num_frames();
        float *samples = channels[0];
        for (size_t i = 0; i < frames; i++) {
            float value = _dsp->processSample(samples[i] / 32768.0f) * 32767.0f;
            samples[i] = std::max(-32768.0f, std::min(32767.0f, value));
        }
        for (size_t channel = 1; channel < buffer->num_channels(); channel++) {
            for (size_t i = 0; i < frames; i++) {
                channels[channel][i] = samples[i];
            }
        }
    }

    std::string ToString() const override {
        return "LitvinVoiceChanger";
    }

    void SetRuntimeSetting(webrtc::AudioProcessing::RuntimeSetting setting) override {
        (void)setting;
    }

private:
    VoiceSettings _settings;
    int _sampleRate = 48000;
    std::unique_ptr<VoiceDsp> _dsp;
};

} // namespace

std::unique_ptr<webrtc::CustomProcessing> CreateVoiceChangerProcessing() {
    VoiceSettings settings = currentSettings();
    if (!settings.calls || !settings.isActive()) {
        return nullptr;
    }
    return std::make_unique<VoiceChangerProcessing>(settings);
}

} // namespace litvin

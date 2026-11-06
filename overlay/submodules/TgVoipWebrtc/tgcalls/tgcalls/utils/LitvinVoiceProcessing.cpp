#include "utils/LitvinVoiceProcessing.h"

#include <string>
#include <utility>

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

class ChainedProcessing : public webrtc::CustomProcessing {
public:
    ChainedProcessing(std::unique_ptr<webrtc::CustomProcessing> first, std::unique_ptr<webrtc::CustomProcessing> second) :
    _first(std::move(first)),
    _second(std::move(second)) {
    }

    void Initialize(int sample_rate_hz, int num_channels) override {
        if (_first) {
            _first->Initialize(sample_rate_hz, num_channels);
        }
        if (_second) {
            _second->Initialize(sample_rate_hz, num_channels);
        }
    }

    void Process(webrtc::AudioBuffer *buffer) override {
        if (_first) {
            _first->Process(buffer);
        }
        if (_second) {
            _second->Process(buffer);
        }
    }

    std::string ToString() const override {
        return "LitvinChainedProcessing";
    }

    void SetRuntimeSetting(webrtc::AudioProcessing::RuntimeSetting setting) override {
        if (_first) {
            _first->SetRuntimeSetting(setting);
        }
        if (_second) {
            _second->SetRuntimeSetting(setting);
        }
    }

private:
    std::unique_ptr<webrtc::CustomProcessing> _first;
    std::unique_ptr<webrtc::CustomProcessing> _second;
};

} // namespace

std::unique_ptr<webrtc::CustomProcessing> WrapWithVoiceChanger(std::unique_ptr<webrtc::CustomProcessing> inner) {
    std::unique_ptr<webrtc::CustomProcessing> voice = CreateVoiceChangerProcessing();
    if (!voice) {
        return inner;
    }
    if (!inner) {
        return voice;
    }
    return std::make_unique<ChainedProcessing>(std::move(inner), std::move(voice));
}

std::unique_ptr<webrtc::CustomProcessing> CreateVoiceChangerProcessing() {
    VoiceSettings settings = currentSettings();
    if (!settings.isActive()) {
        return nullptr;
    }
    return std::make_unique<VoiceChangerProcessing>(settings);
}

} // namespace litvin

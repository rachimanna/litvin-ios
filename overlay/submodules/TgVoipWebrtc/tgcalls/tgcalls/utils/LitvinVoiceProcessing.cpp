#include "utils/LitvinVoiceProcessing.h"

#include <algorithm>
#include <string>
#include <utility>

#include "modules/audio_processing/audio_buffer.h"
#include "LitvinVoiceDsp.hpp"
#include "LitvinVoiceSettingsStore.hpp"

namespace litvin {

namespace {

class VoiceChangerProcessing : public webrtc::CustomProcessing {
public:
    VoiceChangerProcessing() = default;

    void Initialize(int sample_rate_hz, int num_channels) override {
        (void)num_channels;
        _sampleRate = sample_rate_hz > 0 ? sample_rate_hz : 48000;
        _engine.reset(new VoiceEngine((float)_sampleRate));
        _engine->setSettings(currentVoiceSettings());
        _framesSinceRefresh = 0;
    }

    void Process(webrtc::AudioBuffer *buffer) override {
        if (!buffer || buffer->num_channels() == 0) {
            return;
        }
        if (!_engine) {
            Initialize(48000, (int)buffer->num_channels());
        }
        // Process() runs every 10 ms: refresh settings every ~0.5 s.
        if (++_framesSinceRefresh >= 50) {
            _framesSinceRefresh = 0;
            VoiceSettings settings = currentVoiceSettings();
            if (settings != _engine->settings()) {
                _engine->setSettings(settings);
            }
        }
        if (!_engine->isActive()) {
            return;
        }
        float *const *channels = buffer->channels();
        const size_t frames = buffer->num_frames();
        float *samples = channels[0];
        for (size_t i = 0; i < frames; i++) {
            samples[i] = _engine->processSample(samples[i] / 32768.0f) * 32767.0f;
        }
        for (size_t channel = 1; channel < buffer->num_channels(); channel++) {
            std::copy(samples, samples + frames, channels[channel]);
        }
    }

    std::string ToString() const override {
        return "LitvinVoiceChanger";
    }

    void SetRuntimeSetting(webrtc::AudioProcessing::RuntimeSetting setting) override {
        (void)setting;
    }

private:
    int _sampleRate = 48000;
    int _framesSinceRefresh = 0;
    std::unique_ptr<VoiceEngine> _engine;
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

std::unique_ptr<webrtc::CustomProcessing> CreateVoiceChangerProcessing() {
    return std::make_unique<VoiceChangerProcessing>();
}

std::unique_ptr<webrtc::CustomProcessing> WrapWithVoiceChanger(std::unique_ptr<webrtc::CustomProcessing> inner) {
    std::unique_ptr<webrtc::CustomProcessing> voice = CreateVoiceChangerProcessing();
    if (!inner) {
        return voice;
    }
    return std::make_unique<ChainedProcessing>(std::move(inner), std::move(voice));
}

} // namespace litvin

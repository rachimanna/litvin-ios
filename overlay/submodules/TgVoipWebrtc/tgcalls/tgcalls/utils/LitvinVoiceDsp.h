#ifndef LITVIN_VOICE_DSP_H
#define LITVIN_VOICE_DSP_H

// Litvin voice changer DSP (header-only, no WebRTC dependency).
// Same algorithm as LitvinVoiceChanger.swift (voice messages); keep in sync.

#include <algorithm>
#include <cmath>
#include <vector>

namespace litvin {

struct VoiceSettings {
    int preset = 0;          // 0 off, 1 angry, 2 girl, 3 child, 4 pixel, 5 robot, 6 vocal
    double pitch = 0.0;      // semitones, -12 ... 12
    double strength = 1.0;   // 0 = original voice, 1 = only effect
    double volume = 1.0;     // 0 ... 2
    double echo = 0.0;       // 0 ... 1
    bool voiceMessages = true;
    bool calls = true;

    bool isActive() const {
        return preset != 0 || std::fabs(pitch) > 0.01 || echo > 0.01 || std::fabs(volume - 1.0) > 0.01;
    }
};

class VoiceDsp {
public:
    VoiceDsp(const VoiceSettings &settings, float sampleRate) :
    _settings(settings),
    _sampleRate(sampleRate) {
        float ratio = 1.0f;
        switch (settings.preset) {
            case 1: ratio = 0.78f; break;
            case 2: ratio = 1.45f; break;
            case 3: ratio = 1.85f; break;
            case 4: ratio = 1.2f; break;
            default: break;
        }
        ratio *= (float)std::pow(2.0, settings.pitch / 12.0);
        _pitchRatio = ratio;
        _strength = (float)std::max(0.0, std::min(1.0, settings.strength));
        _volume = (float)std::max(0.0, std::min(2.0, settings.volume));
        float echo = (float)std::max(0.0, std::min(1.0, settings.echo));
        if (settings.preset == 6) {
            echo = std::max(echo, 0.45f);
        }
        _echo = echo;

        _pitchWindow = std::max(256.0f, 0.04f * sampleRate);
        _pitchBuffer.assign(kPitchBufferSize, 0.0f);
        _combBuffer.assign(std::max(1, (int)(0.006f * sampleRate)), 0.0f);
        const float reverbSeconds[3] = { 0.0297f, 0.0371f, 0.0411f };
        for (int k = 0; k < 3; k++) {
            _reverbBuffers[k].assign(std::max(1, (int)(reverbSeconds[k] * sampleRate)), 0.0f);
            _reverbIndices[k] = 0;
        }
    }

    // Samples are normalized to [-1, 1].
    float processSample(float input) {
        float wet = input;
        if (std::fabs(_pitchRatio - 1.0f) > 0.001f) {
            wet = pitchShift(wet);
        }

        switch (_settings.preset) {
            case 1:
                wet = std::tanh(wet * 2.6f) * 0.75f;
                break;
            case 5: {
                _ringPhase += 2.0f * (float)M_PI * 52.0f / _sampleRate;
                if (_ringPhase > 2.0f * (float)M_PI) {
                    _ringPhase -= 2.0f * (float)M_PI;
                }
                float ring = wet * std::sin(_ringPhase) * 1.6f;
                float delayed = _combBuffer[_combIndex];
                float combined = ring + delayed * 0.55f;
                _combBuffer[_combIndex] = combined;
                _combIndex = (_combIndex + 1) % (int)_combBuffer.size();
                wet = combined * 0.7f;
                break;
            }
            case 4: {
                if (_holdCounter == 0) {
                    const float levels = 24.0f;
                    _holdValue = std::round(wet * levels) / levels;
                }
                _holdCounter = (_holdCounter + 1) % 6;
                wet = _holdValue;
                break;
            }
            default:
                break;
        }

        float mixed = input * (1.0f - _strength) + wet * _strength;

        if (_echo > 0.001f) {
            float reverb = 0.0f;
            for (int k = 0; k < 3; k++) {
                int index = _reverbIndices[k];
                float delayed = _reverbBuffers[k][index];
                _reverbBuffers[k][index] = mixed + delayed * (0.55f + 0.3f * _echo);
                _reverbIndices[k] = (index + 1) % (int)_reverbBuffers[k].size();
                reverb += delayed;
            }
            mixed = mixed + reverb * 0.33f * _echo;
        }

        return mixed * _volume;
    }

private:
    static const int kPitchBufferSize = 8192;

    float pitchShift(float input) {
        _pitchBuffer[_pitchWrite] = input;

        _pitchPhase += (1.0f - _pitchRatio) / _pitchWindow;
        if (_pitchPhase >= 1.0f) {
            _pitchPhase -= 1.0f;
        } else if (_pitchPhase < 0.0f) {
            _pitchPhase += 1.0f;
        }
        float phase2 = _pitchPhase + 0.5f;
        if (phase2 >= 1.0f) {
            phase2 -= 1.0f;
        }

        float tap1 = readDelayed(_pitchPhase * _pitchWindow);
        float tap2 = readDelayed(phase2 * _pitchWindow);
        float gain1 = 1.0f - std::fabs(2.0f * _pitchPhase - 1.0f);
        float gain2 = 1.0f - std::fabs(2.0f * phase2 - 1.0f);

        _pitchWrite = (_pitchWrite + 1) % kPitchBufferSize;
        return (tap1 * gain1 + tap2 * gain2) * 1.45f;
    }

    float readDelayed(float delay) const {
        float position = (float)_pitchWrite - delay - 1.0f;
        int base = (int)std::floor(position);
        float fraction = position - (float)base;
        base = ((base % kPitchBufferSize) + kPitchBufferSize) % kPitchBufferSize;
        int next = (base + 1) % kPitchBufferSize;
        return _pitchBuffer[base] * (1.0f - fraction) + _pitchBuffer[next] * fraction;
    }

    VoiceSettings _settings;
    float _sampleRate = 48000.0f;
    float _pitchRatio = 1.0f;
    float _strength = 1.0f;
    float _volume = 1.0f;
    float _echo = 0.0f;

    std::vector<float> _pitchBuffer;
    int _pitchWrite = 0;
    float _pitchPhase = 0.0f;
    float _pitchWindow = 1920.0f;

    float _ringPhase = 0.0f;
    std::vector<float> _combBuffer;
    int _combIndex = 0;

    int _holdCounter = 0;
    float _holdValue = 0.0f;

    std::vector<float> _reverbBuffers[3];
    int _reverbIndices[3] = { 0, 0, 0 };
};

} // namespace litvin

#endif

#ifndef LITVIN_VOICE_DSP_HPP
#define LITVIN_VOICE_DSP_HPP

// Litvin voice changer, header-only C++17. One implementation for both voice
// messages (via LitvinVoiceKit ObjC wrapper) and calls (tgcalls capture
// post-processing).
//
// Core: streaming phase vocoder (STFT, 75% overlap) that changes pitch and
// formants independently. The spectral envelope (formants, i.e. the "size" of
// the voice) is estimated by cepstral smoothing, the excitation (pitch
// harmonics) is shifted by the pitch ratio, then re-shaped by the envelope
// warped by the formant ratio. That is what makes a child or a girl sound like
// one instead of a sped-up tape.

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdint>
#include <vector>

namespace litvin {

enum VoicePreset : int {
    VoicePresetOff = 0,
    VoicePresetAngry = 1,
    VoicePresetGirl = 2,
    VoicePresetChild = 3,
    VoicePresetPixel = 4,
    VoicePresetRobot = 5,
    VoicePresetVocal = 6,
    VoicePresetMan = 7,
};

struct VoiceSettings {
    int preset = VoicePresetOff;
    double pitch = 0.0;     // extra semitones, -12 ... 12
    double strength = 1.0;  // 0 = original voice, 1 = only effect
    double volume = 1.0;    // 0 ... 2
    double echo = 0.0;      // 0 ... 1

    bool isActive() const {
        return preset != VoicePresetOff || std::fabs(pitch) > 0.01 || echo > 0.01 || std::fabs(volume - 1.0) > 0.01;
    }

    bool operator==(const VoiceSettings &other) const {
        return preset == other.preset && pitch == other.pitch && strength == other.strength && volume == other.volume && echo == other.echo;
    }
    bool operator!=(const VoiceSettings &other) const {
        return !(*this == other);
    }
};

class VoiceEngine {
public:
    explicit VoiceEngine(float sampleRate) {
        _sampleRate = sampleRate > 0.0f ? sampleRate : 48000.0f;
        _n = _sampleRate >= 30000.0f ? 1024 : 512;
        _hop = _n / 4;
        _bins = _n / 2 + 1;
        _lifter = std::max(8, (int)std::lround(0.0016 * _sampleRate * ((double)_n / 1024.0) * (48000.0 / _sampleRate)));
        _lifter = std::min(_lifter, _n / 4);

        _window.resize(_n);
        for (int i = 0; i < _n; i++) {
            _window[i] = 0.5f - 0.5f * std::cos(2.0f * (float)M_PI * (float)i / (float)_n);
        }
        // Hann analysis + synthesis at 75% overlap sums to 1.5.
        _olaGain = 1.0f / 1.5f;

        _inFifo.assign(_n, 0.0f);
        _outAccum.assign(_n * 2, 0.0f);
        _outFifo.assign(_hop, 0.0f);
        _lastPhase.assign(_bins, 0.0f);
        _sumPhase.assign(_bins, 0.0f);
        _mag.assign(_bins, 0.0f);
        _freq.assign(_bins, 0.0f);
        _env.assign(_bins, 1.0f);
        _synMag.assign(_bins, 0.0f);
        _synFreq.assign(_bins, 0.0f);
        _fft.assign(_n, std::complex<float>());
        _tmp.assign(_n, std::complex<float>());
        _dryDelay.assign(_n, 0.0f);

        _twiddle.resize(_n / 2);
        for (int i = 0; i < _n / 2; i++) {
            _twiddle[i] = std::polar(1.0f, -2.0f * (float)M_PI * (float)i / (float)_n);
        }
        _bitrev.resize(_n);
        int bits = 0;
        while ((1 << bits) < _n) {
            bits++;
        }
        for (int i = 0; i < _n; i++) {
            int r = 0;
            for (int b = 0; b < bits; b++) {
                if (i & (1 << b)) {
                    r |= 1 << (bits - 1 - b);
                }
            }
            _bitrev[i] = r;
        }

        _chorusBuffer.assign((size_t)(0.05f * _sampleRate) + 4, 0.0f);
        const float reverbSeconds[4] = { 0.0297f, 0.0371f, 0.0411f, 0.0437f };
        for (int k = 0; k < 4; k++) {
            _reverbBuffers[k].assign((size_t)std::max(1.0f, reverbSeconds[k] * _sampleRate), 0.0f);
            _reverbIndex[k] = 0;
        }
        _allpass.assign((size_t)std::max(1.0f, 0.005f * _sampleRate), 0.0f);

        setSettings(VoiceSettings());
    }

    void setSettings(const VoiceSettings &settings) {
        _settings = settings;
        float pitch = 1.0f;
        float formant = 1.0f;
        _robot = false;
        _drive = 0.0f;
        _pixel = false;
        _chorus = false;
        switch (settings.preset) {
            case VoicePresetAngry: pitch = 0.80f; formant = 0.88f; _drive = 2.4f; break;
            case VoicePresetGirl: pitch = 1.55f; formant = 1.18f; break;
            case VoicePresetMan: pitch = 0.70f; formant = 0.86f; break;
            case VoicePresetChild: pitch = 1.80f; formant = 1.33f; break;
            case VoicePresetPixel: pitch = 1.20f; formant = 1.08f; _pixel = true; break;
            case VoicePresetRobot: pitch = 1.0f; formant = 1.0f; _robot = true; break;
            case VoicePresetVocal: pitch = 1.0f; formant = 1.0f; _chorus = true; break;
            default: break;
        }
        pitch *= (float)std::pow(2.0, settings.pitch / 12.0);
        _pitch = std::max(0.25f, std::min(4.0f, pitch));
        _formant = formant;
        _usePhaseVocoder = std::fabs(_pitch - 1.0f) > 0.001f || std::fabs(_formant - 1.0f) > 0.001f || _robot;
        _strength = (float)std::max(0.0, std::min(1.0, settings.strength));
        _volume = (float)std::max(0.0, std::min(2.0, settings.volume));
        float echo = (float)std::max(0.0, std::min(1.0, settings.echo));
        if (settings.preset == VoicePresetVocal) {
            echo = std::max(echo, 0.4f);
        }
        _echo = echo;
        _active = settings.isActive();
    }

    const VoiceSettings &settings() const {
        return _settings;
    }

    bool isActive() const {
        return _active;
    }

    // In-place processing of normalized samples ([-1, 1]).
    void process(float *samples, int count) {
        if (!_active) {
            return;
        }
        for (int i = 0; i < count; i++) {
            samples[i] = processSample(samples[i]);
        }
    }

    float processSample(float input) {
        // Dry path delayed by the vocoder latency so the mix does not comb.
        float dry = _dryDelay[_dryIndex];
        _dryDelay[_dryIndex] = input;
        _dryIndex = (_dryIndex + 1) % _n;

        float wet;
        if (_usePhaseVocoder) {
            wet = vocoderSample(input);
            // Slow automatic gain: the shifted voice keeps the loudness of the original.
            const float coef = 1.0f / (0.25f * _sampleRate);
            _dryPower += (dry * dry - _dryPower) * coef;
            _wetPower += (wet * wet - _wetPower) * coef;
            if (_wetPower > 1e-7f) {
                float target = std::sqrt(_dryPower / _wetPower);
                target = std::max(0.5f, std::min(4.0f, target));
                _agc += (target - _agc) * coef * 4.0f;
            }
            wet *= _agc;
        } else {
            wet = dry;
        }

        if (_drive > 0.0f) {
            wet = std::tanh(wet * _drive) * 0.8f;
        }
        if (_pixel) {
            if (_holdCounter == 0) {
                const float levels = 20.0f;
                _holdValue = std::round(wet * levels) / levels;
            }
            _holdCounter = (_holdCounter + 1) % std::max(2, (int)(_sampleRate / 8000.0f));
            wet = _holdValue;
        }
        if (_chorus) {
            wet = chorusSample(wet);
        }

        float mixed = dry * (1.0f - _strength) + wet * _strength;

        if (_echo > 0.001f) {
            mixed = reverbSample(mixed);
        }
        float out = mixed * _volume;
        return std::max(-1.0f, std::min(1.0f, out));
    }

private:
    float vocoderSample(float input) {
        _inFifo[_inPos] = input;
        float out = _outFifo[_outPos];
        _inPos++;
        _outPos++;
        if (_outPos >= _hop) {
            _outPos = 0;
        }
        if (_inPos >= _n) {
            _inPos = _n - _hop;
            processFrame();
            // Shift the input buffer by one hop.
            std::copy(_inFifo.begin() + _hop, _inFifo.end(), _inFifo.begin());
        }
        return out;
    }

    void fftInPlace(std::vector<std::complex<float>> &a, bool inverse) {
        for (int i = 0; i < _n; i++) {
            int j = _bitrev[i];
            if (i < j) {
                std::swap(a[i], a[j]);
            }
        }
        for (int len = 2; len <= _n; len <<= 1) {
            int step = _n / len;
            for (int i = 0; i < _n; i += len) {
                for (int j = 0; j < len / 2; j++) {
                    std::complex<float> w = _twiddle[j * step];
                    if (inverse) {
                        w = std::conj(w);
                    }
                    std::complex<float> u = a[i + j];
                    std::complex<float> v = a[i + j + len / 2] * w;
                    a[i + j] = u + v;
                    a[i + j + len / 2] = u - v;
                }
            }
        }
        if (inverse) {
            float scale = 1.0f / (float)_n;
            for (int i = 0; i < _n; i++) {
                a[i] *= scale;
            }
        }
    }

    void computeEnvelope() {
        // Cepstral smoothing of the log magnitude spectrum.
        for (int k = 0; k < _bins; k++) {
            _tmp[k] = std::complex<float>(std::log(_mag[k] + 1e-6f), 0.0f);
        }
        for (int k = _bins; k < _n; k++) {
            _tmp[k] = _tmp[_n - k];
        }
        fftInPlace(_tmp, true);
        for (int q = _lifter + 1; q < _n - _lifter; q++) {
            _tmp[q] = 0.0f;
        }
        // Gentle taper on the last coefficients avoids ringing in the envelope.
        _tmp[_lifter] *= 0.5f;
        _tmp[_n - _lifter] *= 0.5f;
        fftInPlace(_tmp, false);
        for (int k = 0; k < _bins; k++) {
            _env[k] = std::exp(_tmp[k].real());
        }
    }

    float envelopeAt(float bin) const {
        if (bin <= 0.0f) {
            return _env[0];
        }
        if (bin >= (float)(_bins - 1)) {
            return _env[_bins - 1] * 0.5f;
        }
        int i = (int)bin;
        float f = bin - (float)i;
        return _env[i] * (1.0f - f) + _env[i + 1] * f;
    }

    void processFrame() {
        for (int i = 0; i < _n; i++) {
            _fft[i] = std::complex<float>(_inFifo[i] * _window[i], 0.0f);
        }
        fftInPlace(_fft, false);

        const float expected = 2.0f * (float)M_PI * (float)_hop / (float)_n;
        for (int k = 0; k < _bins; k++) {
            float mag = std::abs(_fft[k]);
            float phase = std::arg(_fft[k]);
            float delta = phase - _lastPhase[k];
            _lastPhase[k] = phase;
            delta -= (float)k * expected;
            delta = delta - 2.0f * (float)M_PI * std::round(delta / (2.0f * (float)M_PI));
            _freq[k] = (float)k + delta / expected;
            _mag[k] = mag;
        }

        computeEnvelope();

        std::fill(_synMag.begin(), _synMag.end(), 0.0f);
        std::fill(_synFreq.begin(), _synFreq.end(), 0.0f);
        for (int k = 0; k < _bins; k++) {
            int j = (int)std::lround((float)k * _pitch);
            if (j >= _bins) {
                break;
            }
            float excitation = _mag[k] / (_env[k] + 1e-6f);
            _synMag[j] += excitation;
            _synFreq[j] = _freq[k] * _pitch;
        }
        float inEnergy = 0.0f;
        float outEnergy = 0.0f;
        for (int j = 0; j < _bins; j++) {
            _synMag[j] *= envelopeAt((float)j / _formant);
            inEnergy += _mag[j] * _mag[j];
            outEnergy += _synMag[j] * _synMag[j];
        }
        // Keep the loudness of the original frame (pitching up / robot lose energy).
        float gain = 1.0f;
        if (outEnergy > 1e-9f && inEnergy > 1e-9f) {
            gain = std::sqrt(inEnergy / outEnergy);
            gain = std::max(0.25f, std::min(6.0f, gain));
        }
        _frameGain += (gain - _frameGain) * 0.35f;
        for (int j = 0; j < _bins; j++) {
            _synMag[j] *= _frameGain;
        }

        for (int j = 0; j < _bins; j++) {
            float phase;
            if (_robot) {
                // Same phase pattern every frame -> constant buzz at sampleRate / hop.
                // Alternating 0/pi puts the pulse in the middle of the frame, where
                // the synthesis window is open.
                phase = (j & 1) ? (float)M_PI : 0.0f;
            } else {
                _sumPhase[j] += _synFreq[j] * expected;
                _sumPhase[j] = _sumPhase[j] - 2.0f * (float)M_PI * std::floor(_sumPhase[j] / (2.0f * (float)M_PI));
                phase = _sumPhase[j];
            }
            _fft[j] = std::polar(_synMag[j], phase);
        }
        for (int j = _bins; j < _n; j++) {
            _fft[j] = std::conj(_fft[_n - j]);
        }
        fftInPlace(_fft, true);

        for (int i = 0; i < _n; i++) {
            _outAccum[i] += _fft[i].real() * _window[i] * _olaGain;
        }
        for (int i = 0; i < _hop; i++) {
            _outFifo[i] = _outAccum[i];
        }
        std::copy(_outAccum.begin() + _hop, _outAccum.begin() + _hop + _n, _outAccum.begin());
        std::fill(_outAccum.begin() + _n, _outAccum.end(), 0.0f);
    }

    float chorusSample(float input) {
        size_t size = _chorusBuffer.size();
        _chorusBuffer[_chorusIndex] = input;
        _chorusPhase += 2.0f * (float)M_PI * 0.35f / _sampleRate;
        if (_chorusPhase > 2.0f * (float)M_PI) {
            _chorusPhase -= 2.0f * (float)M_PI;
        }
        float out = input * 0.7f;
        for (int v = 0; v < 2; v++) {
            float delayMs = 18.0f + 7.0f * std::sin(_chorusPhase + (float)v * (float)M_PI);
            float delay = delayMs * 0.001f * _sampleRate;
            float pos = (float)_chorusIndex - delay;
            while (pos < 0.0f) {
                pos += (float)size;
            }
            size_t i0 = (size_t)pos % size;
            size_t i1 = (i0 + 1) % size;
            float frac = pos - std::floor(pos);
            out += (_chorusBuffer[i0] * (1.0f - frac) + _chorusBuffer[i1] * frac) * 0.45f;
        }
        _chorusIndex = (_chorusIndex + 1) % size;
        return out * 0.8f;
    }

    float reverbSample(float input) {
        float sum = 0.0f;
        float feedback = 0.6f + 0.25f * _echo;
        for (int k = 0; k < 4; k++) {
            std::vector<float> &buf = _reverbBuffers[k];
            float delayed = buf[_reverbIndex[k]];
            buf[_reverbIndex[k]] = input + delayed * feedback;
            _reverbIndex[k] = (_reverbIndex[k] + 1) % buf.size();
            sum += delayed;
        }
        // One all-pass to diffuse the comb echoes.
        float ap = _allpass[_allpassIndex];
        float v = sum * 0.25f + ap * 0.5f;
        _allpass[_allpassIndex] = v;
        _allpassIndex = (_allpassIndex + 1) % _allpass.size();
        float diffused = ap - v * 0.5f;
        return input + diffused * 0.55f * _echo;
    }

    float _sampleRate = 48000.0f;
    int _n = 1024;
    int _hop = 256;
    int _bins = 513;
    int _lifter = 77;
    float _olaGain = 1.0f;
    float _frameGain = 1.0f;
    float _dryPower = 0.0f;
    float _wetPower = 0.0f;
    float _agc = 1.0f;

    VoiceSettings _settings;
    bool _active = false;
    bool _usePhaseVocoder = false;
    float _pitch = 1.0f;
    float _formant = 1.0f;
    bool _robot = false;
    float _drive = 0.0f;
    bool _pixel = false;
    bool _chorus = false;
    float _strength = 1.0f;
    float _volume = 1.0f;
    float _echo = 0.0f;

    std::vector<float> _window;
    std::vector<float> _inFifo;
    std::vector<float> _outAccum;
    std::vector<float> _outFifo;
    int _inPos = 0;
    int _outPos = 0;
    std::vector<float> _lastPhase;
    std::vector<float> _sumPhase;
    std::vector<float> _mag;
    std::vector<float> _freq;
    std::vector<float> _env;
    std::vector<float> _synMag;
    std::vector<float> _synFreq;
    std::vector<std::complex<float>> _fft;
    std::vector<std::complex<float>> _tmp;
    std::vector<std::complex<float>> _twiddle;
    std::vector<int> _bitrev;

    std::vector<float> _dryDelay;
    int _dryIndex = 0;

    int _holdCounter = 0;
    float _holdValue = 0.0f;

    std::vector<float> _chorusBuffer;
    size_t _chorusIndex = 0;
    float _chorusPhase = 0.0f;

    std::vector<float> _reverbBuffers[4];
    size_t _reverbIndex[4];
    std::vector<float> _allpass;
    size_t _allpassIndex = 0;
};

} // namespace litvin

#endif

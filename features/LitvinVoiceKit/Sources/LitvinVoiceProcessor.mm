#import "LitvinVoiceKit/LitvinVoiceProcessor.h"

#include <memory>
#include <vector>

#include "LitvinVoiceDsp.hpp"
#include "LitvinVoiceSettingsStore.hpp"

@implementation LitvinVoiceProcessor {
    std::unique_ptr<litvin::VoiceEngine> _engine;
    std::vector<float> _buffer;
    double _sampleRate;
    NSInteger _samplesSinceRefresh;
}

- (instancetype)initWithSampleRate:(double)sampleRate {
    self = [super init];
    if (self != nil) {
        _sampleRate = sampleRate > 0.0 ? sampleRate : 48000.0;
        _engine.reset(new litvin::VoiceEngine((float)_sampleRate));
        _engine->setSettings(litvin::currentVoiceSettings());
        _samplesSinceRefresh = 0;
    }
    return self;
}

- (void)processInt16Samples:(int16_t *)samples count:(NSInteger)count {
    if (samples == NULL || count <= 0) {
        return;
    }
    _samplesSinceRefresh += count;
    if (_samplesSinceRefresh >= (NSInteger)(_sampleRate * 0.5)) {
        _samplesSinceRefresh = 0;
        litvin::VoiceSettings settings = litvin::currentVoiceSettings();
        if (settings != _engine->settings()) {
            _engine->setSettings(settings);
        }
    }
    if (!_engine->isActive()) {
        return;
    }
    if ((NSInteger)_buffer.size() < count) {
        _buffer.resize((size_t)count);
    }
    for (NSInteger i = 0; i < count; i++) {
        _buffer[(size_t)i] = (float)samples[i] / 32768.0f;
    }
    _engine->process(_buffer.data(), (int)count);
    for (NSInteger i = 0; i < count; i++) {
        float v = _buffer[(size_t)i] * 32767.0f;
        if (v > 32767.0f) {
            v = 32767.0f;
        } else if (v < -32768.0f) {
            v = -32768.0f;
        }
        samples[i] = (int16_t)v;
    }
}

@end

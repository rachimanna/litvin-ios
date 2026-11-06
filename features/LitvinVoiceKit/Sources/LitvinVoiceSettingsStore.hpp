#ifndef LITVIN_VOICE_SETTINGS_STORE_HPP
#define LITVIN_VOICE_SETTINGS_STORE_HPP

// Reads the voice changer settings saved by the Litvin settings screen
// (NSUserDefaults keys "litvin.voice.*") through CoreFoundation, so plain C++
// (tgcalls) can use them too.

#include "LitvinVoiceDsp.hpp"

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#endif

namespace litvin {

inline bool readVoicePreference(const char *key, double *value) {
#ifdef __APPLE__
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
#else
    (void)key;
    (void)value;
    return false;
#endif
}

inline VoiceSettings currentVoiceSettings() {
    VoiceSettings settings;
    double value = 0.0;
    if (readVoicePreference("litvin.voice.preset", &value)) {
        settings.preset = (int)value;
    }
    if (readVoicePreference("litvin.voice.pitch", &value)) {
        settings.pitch = value;
    }
    if (readVoicePreference("litvin.voice.strength", &value)) {
        settings.strength = value;
    }
    if (readVoicePreference("litvin.voice.volume", &value)) {
        settings.volume = value;
    }
    if (readVoicePreference("litvin.voice.echo", &value)) {
        settings.echo = value;
    }
    return settings;
}

} // namespace litvin

#endif

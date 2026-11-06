load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# Header-only C++ voice engine, shared by voice messages (LitvinVoiceKit) and
# calls (TgVoipWebrtc / tgcalls).
cc_library(
    name = "LitvinVoiceDsp",
    hdrs = [
        "Sources/LitvinVoiceDsp.hpp",
        "Sources/LitvinVoiceSettingsStore.hpp",
    ],
    includes = [
        "Sources",
    ],
    visibility = [
        "//visibility:public",
    ],
)

objc_library(
    name = "LitvinVoiceKit",
    enable_modules = True,
    module_name = "LitvinVoiceKit",
    srcs = glob([
        "Sources/*.mm",
    ]),
    hdrs = glob([
        "Sources/PublicHeaders/LitvinVoiceKit/*.h",
    ]),
    includes = [
        "Sources/PublicHeaders",
    ],
    copts = [
        "-std=c++17",
    ],
    deps = [
        ":LitvinVoiceDsp",
    ],
    sdk_frameworks = [
        "Foundation",
        "CoreFoundation",
    ],
    visibility = [
        "//visibility:public",
    ],
)

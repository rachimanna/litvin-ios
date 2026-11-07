load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "LitvinSettings",
    module_name = "LitvinSettings",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [],
    deps = [
        "//submodules/ComponentFlow:ComponentFlow",
        "//submodules/TelegramUI/Components/Gifts/GiftItemComponent:GiftItemComponent",
        "//submodules/SSignalKit/SwiftSignalKit:SwiftSignalKit",
        "//submodules/Postbox:Postbox",
        "//submodules/TelegramCore:TelegramCore",
        "//submodules/Display:Display",
        "//submodules/AccountContext:AccountContext",
        "//submodules/TelegramPresentationData:TelegramPresentationData",
        "//submodules/ItemListUI:ItemListUI",
        "//submodules/PresentationDataUtils:PresentationDataUtils",
        "//submodules/AsyncDisplayKit:AsyncDisplayKit",
        "//submodules/UIKitRuntimeUtils:UIKitRuntimeUtils",
    ],
    visibility = [
        "//visibility:public",
    ],
)

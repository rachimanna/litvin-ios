import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

private enum LitvinSection: Int32 {
    case privacy
    case history
    case media
    case vault
    case discovery
    case tools
    case about
}

private enum LitvinEntry: ItemListNodeEntry {
    case privacyHeader(PresentationTheme, String)
    case ghostMode(PresentationTheme, String, Bool)
    case ghostNoTyping(PresentationTheme, String, Bool)
    case ghostNoOnline(PresentationTheme, String, Bool)
    case ghostSchedule(PresentationTheme, String, Bool)

    case historyHeader(PresentationTheme, String)
    case saveDeleted(PresentationTheme, String, Bool)
    case saveEdits(PresentationTheme, String, Bool)
    case antiAds(PresentationTheme, String, Bool)

    case mediaHeader(PresentationTheme, String)
    case screenshotBypass(PresentationTheme, String, Bool)
    case forwardBypass(PresentationTheme, String, Bool)
    case infiniteSelfDestruct(PresentationTheme, String, Bool)
    case forwardScrub(PresentationTheme, String, Bool)

    case vaultHeader(PresentationTheme, String)
    case doubleBottom(PresentationTheme, String, Bool)
    case chatVault(PresentationTheme, String, Bool)

    case discoveryHeader(PresentationTheme, String)
    case channelDigest(PresentationTheme, String, Bool)
    case contactProfile(PresentationTheme, String, Bool)

    case toolsHeader(PresentationTheme, String)
    case proxyPool(PresentationTheme, String, Bool)
    case localAI(PresentationTheme, String, Bool)
    case contextExport(PresentationTheme, String)

    case aboutHeader(PresentationTheme, String)
    case aboutVersion(PresentationTheme, String, String)
    case aboutGithub(PresentationTheme, String)

    var section: ItemListSectionId {
        switch self {
        case .privacyHeader, .ghostMode, .ghostNoTyping, .ghostNoOnline, .ghostSchedule:
            return LitvinSection.privacy.rawValue
        case .historyHeader, .saveDeleted, .saveEdits, .antiAds:
            return LitvinSection.history.rawValue
        case .mediaHeader, .screenshotBypass, .forwardBypass, .infiniteSelfDestruct, .forwardScrub:
            return LitvinSection.media.rawValue
        case .vaultHeader, .doubleBottom, .chatVault:
            return LitvinSection.vault.rawValue
        case .discoveryHeader, .channelDigest, .contactProfile:
            return LitvinSection.discovery.rawValue
        case .toolsHeader, .proxyPool, .localAI, .contextExport:
            return LitvinSection.tools.rawValue
        case .aboutHeader, .aboutVersion, .aboutGithub:
            return LitvinSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .privacyHeader: return 0
        case .ghostMode: return 1
        case .ghostNoTyping: return 2
        case .ghostNoOnline: return 3
        case .ghostSchedule: return 4
        case .historyHeader: return 10
        case .saveDeleted: return 11
        case .saveEdits: return 12
        case .antiAds: return 13
        case .mediaHeader: return 20
        case .screenshotBypass: return 21
        case .forwardBypass: return 22
        case .infiniteSelfDestruct: return 23
        case .forwardScrub: return 24
        case .vaultHeader: return 30
        case .doubleBottom: return 31
        case .chatVault: return 32
        case .discoveryHeader: return 40
        case .channelDigest: return 41
        case .contactProfile: return 42
        case .toolsHeader: return 50
        case .proxyPool: return 51
        case .localAI: return 52
        case .contextExport: return 53
        case .aboutHeader: return 60
        case .aboutVersion: return 61
        case .aboutGithub: return 62
        }
    }

    static func < (lhs: LitvinEntry, rhs: LitvinEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! LitvinSettingsArguments
        switch self {
        case let .privacyHeader(_, t), let .historyHeader(_, t), let .mediaHeader(_, t),
             let .vaultHeader(_, t), let .discoveryHeader(_, t), let .toolsHeader(_, t), let .aboutHeader(_, t):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: t, sectionId: self.section)

        case let .ghostMode(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.ghostMode, v) }
        case let .ghostNoTyping(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.ghostNoTyping, v) }
        case let .ghostNoOnline(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.ghostNoOnline, v) }
        case let .ghostSchedule(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.ghostScheduleEnabled, v) }
        case let .saveDeleted(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.saveDeleted, v) }
        case let .saveEdits(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.saveEditHistory, v) }
        case let .antiAds(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.antiAds, v) }
        case let .screenshotBypass(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.screenshotBypass, v) }
        case let .forwardBypass(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.forwardBypass, v) }
        case let .infiniteSelfDestruct(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.infiniteSelfDestruct, v) }
        case let .forwardScrub(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.forwardScrub, v) }
        case let .doubleBottom(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.doubleBottom, v) }
        case let .chatVault(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.chatVault, v) }
        case let .channelDigest(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.channelDigest, v) }
        case let .contactProfile(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.contactProfile, v) }
        case let .proxyPool(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.proxyPool, v) }
        case let .localAI(_, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks) { v in args.toggle(\.localAI, v) }
        case let .contextExport(_, title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: self.section, style: .blocks) { args.openContextExport() }
        case let .aboutVersion(_, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: nil)
        case let .aboutGithub(_, title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "github.com/rachimanna/litvin-ios", sectionId: self.section, style: .blocks) { args.openGithub() }
        }
    }
}

private final class LitvinSettingsArguments {
    let toggle: (WritableKeyPath<LitvinPreferences, Bool>, Bool) -> Void
    let openContextExport: () -> Void
    let openGithub: () -> Void

    init(toggle: @escaping (WritableKeyPath<LitvinPreferences, Bool>, Bool) -> Void,
         openContextExport: @escaping () -> Void,
         openGithub: @escaping () -> Void) {
        self.toggle = toggle
        self.openContextExport = openContextExport
        self.openGithub = openGithub
    }
}

public func litvinSettingsController(context: AccountContext) -> ViewController {
    let arguments = LitvinSettingsArguments(
        toggle: { keyPath, value in
            let _ = updateLitvinPreferences(accountManager: context.sharedContext.accountManager) { prefs in
                var p = prefs
                p[keyPath: keyPath] = value
                return p
            }.start()
        },
        openContextExport: {
            // Hook: features/ContextExport presents its controller here.
        },
        openGithub: {
            if let url = URL(string: "https://github.com/rachimanna/litvin-ios") {
                UIApplication.shared.open(url)
            }
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.litvinPreferences])
    )
    |> map { presentationData, shared -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let p = shared.entries[SharedDataKeys.litvinPreferences]?.get(LitvinPreferences.self) ?? .default
        let theme = presentationData.theme

        var entries: [LitvinEntry] = []
        entries.append(.privacyHeader(theme, "PRIVACY & GHOST"))
        entries.append(.ghostMode(theme, "Ghost mode (no read)", p.ghostMode))
        entries.append(.ghostNoTyping(theme, "Hide typing", p.ghostNoTyping))
        entries.append(.ghostNoOnline(theme, "Hide online", p.ghostNoOnline))
        entries.append(.ghostSchedule(theme, "Scheduled ghost + alibi", p.ghostScheduleEnabled))

        entries.append(.historyHeader(theme, "HISTORY"))
        entries.append(.saveDeleted(theme, "Save deleted messages", p.saveDeleted))
        entries.append(.saveEdits(theme, "Save edit history", p.saveEditHistory))
        entries.append(.antiAds(theme, "Hide channel ads", p.antiAds))

        entries.append(.mediaHeader(theme, "MEDIA"))
        entries.append(.screenshotBypass(theme, "Screenshots in protected chats", p.screenshotBypass))
        entries.append(.forwardBypass(theme, "Forward from no-forward chats", p.forwardBypass))
        entries.append(.infiniteSelfDestruct(theme, "View one-time media without timer", p.infiniteSelfDestruct))
        entries.append(.forwardScrub(theme, "Scrub forward metadata", p.forwardScrub))

        entries.append(.vaultHeader(theme, "VAULT"))
        entries.append(.doubleBottom(theme, "Double bottom (second PIN)", p.doubleBottom))
        entries.append(.chatVault(theme, "Chat vault", p.chatVault))

        entries.append(.discoveryHeader(theme, "DISCOVERY"))
        entries.append(.channelDigest(theme, "Channel digest", p.channelDigest))
        entries.append(.contactProfile(theme, "Contact profile", p.contactProfile))

        entries.append(.toolsHeader(theme, "TOOLS"))
        entries.append(.proxyPool(theme, "MTProto proxy pool", p.proxyPool))
        entries.append(.localAI(theme, "On-device AI", p.localAI))
        entries.append(.contextExport(theme, "Export / import state"))

        entries.append(.aboutHeader(theme, "ABOUT"))
        entries.append(.aboutVersion(theme, "Version", LITVIN_VERSION))
        entries.append(.aboutGithub(theme, "Source"))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData),
                                                      title: .text("Litvin"),
                                                      leftNavigationButton: nil,
                                                      rightNavigationButton: nil,
                                                      backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
                                                      animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData),
                                          entries: entries,
                                          style: .blocks,
                                          animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}

public let LITVIN_VERSION = "0.1.0"

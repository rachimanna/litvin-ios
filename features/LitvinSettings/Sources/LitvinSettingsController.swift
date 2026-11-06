import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

public let litvinVersion = "0.3.0"

private final class LitvinSettingsArguments {
    let toggle: (String, Bool) -> Void
    let toggleGhost: (Bool) -> Void
    let openVoiceChanger: () -> Void
    let openSource: () -> Void

    init(toggle: @escaping (String, Bool) -> Void, toggleGhost: @escaping (Bool) -> Void, openVoiceChanger: @escaping () -> Void, openSource: @escaping () -> Void) {
        self.toggle = toggle
        self.toggleGhost = toggleGhost
        self.openVoiceChanger = openVoiceChanger
        self.openSource = openSource
    }
}

private enum LitvinSettingsSection: Int32 {
    case ghost
    case voice
    case messages
    case privacy
    case about
}

private struct LitvinSettingsState: Equatable {
    var ghostMode: Bool
    var voicePreset: String
    var keepDeleted: Bool
    var bypassProtection: Bool
    var unlimitedViewOnce: Bool

    static func current() -> LitvinSettingsState {
        let voice = LitvinVoiceSettings.current
        return LitvinSettingsState(
            ghostMode: LitvinFlags.ghostMode,
            voicePreset: voice.isActive ? voice.preset.title : "Выключено",
            keepDeleted: LitvinFlags.keepDeleted,
            bypassProtection: LitvinFlags.bypassProtection,
            unlimitedViewOnce: LitvinFlags.unlimitedViewOnce
        )
    }
}

private enum LitvinSettingsEntry: ItemListNodeEntry {
    case ghostMode(String, Bool)
    case ghostInfo(String)
    case voiceChanger(String, String)
    case voiceInfo(String)
    case messagesHeader(String)
    case keepDeleted(String, Bool)
    case keepDeletedInfo(String)
    case privacyHeader(String)
    case bypassProtection(String, Bool)
    case bypassProtectionInfo(String)
    case unlimitedViewOnce(String, Bool)
    case unlimitedViewOnceInfo(String)
    case aboutHeader(String)
    case version(String, String)
    case source(String, String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .ghostMode, .ghostInfo:
            return LitvinSettingsSection.ghost.rawValue
        case .voiceChanger, .voiceInfo:
            return LitvinSettingsSection.voice.rawValue
        case .messagesHeader, .keepDeleted, .keepDeletedInfo:
            return LitvinSettingsSection.messages.rawValue
        case .privacyHeader, .bypassProtection, .bypassProtectionInfo, .unlimitedViewOnce, .unlimitedViewOnceInfo:
            return LitvinSettingsSection.privacy.rawValue
        case .aboutHeader, .version, .source, .info:
            return LitvinSettingsSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostMode: return -4
        case .ghostInfo: return -3
        case .voiceChanger: return -2
        case .voiceInfo: return -1
        case .messagesHeader: return 0
        case .keepDeleted: return 1
        case .keepDeletedInfo: return 2
        case .privacyHeader: return 3
        case .bypassProtection: return 4
        case .bypassProtectionInfo: return 5
        case .unlimitedViewOnce: return 6
        case .unlimitedViewOnceInfo: return 7
        case .aboutHeader: return 8
        case .version: return 9
        case .source: return 10
        case .info: return 11
        }
    }

    static func ==(lhs: LitvinSettingsEntry, rhs: LitvinSettingsEntry) -> Bool {
        switch lhs {
        case let .ghostMode(a1, a2):
            if case let .ghostMode(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .ghostInfo(a):
            if case let .ghostInfo(b) = rhs { return a == b }
            return false
        case let .voiceChanger(a1, a2):
            if case let .voiceChanger(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .voiceInfo(a):
            if case let .voiceInfo(b) = rhs { return a == b }
            return false
        case let .messagesHeader(a):
            if case let .messagesHeader(b) = rhs { return a == b }
            return false
        case let .keepDeleted(a1, a2):
            if case let .keepDeleted(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .keepDeletedInfo(a):
            if case let .keepDeletedInfo(b) = rhs { return a == b }
            return false
        case let .privacyHeader(a):
            if case let .privacyHeader(b) = rhs { return a == b }
            return false
        case let .bypassProtection(a1, a2):
            if case let .bypassProtection(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .bypassProtectionInfo(a):
            if case let .bypassProtectionInfo(b) = rhs { return a == b }
            return false
        case let .unlimitedViewOnce(a1, a2):
            if case let .unlimitedViewOnce(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .unlimitedViewOnceInfo(a):
            if case let .unlimitedViewOnceInfo(b) = rhs { return a == b }
            return false
        case let .aboutHeader(a):
            if case let .aboutHeader(b) = rhs { return a == b }
            return false
        case let .version(a1, a2):
            if case let .version(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .source(a1, a2):
            if case let .source(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .info(a):
            if case let .info(b) = rhs { return a == b }
            return false
        }
    }

    static func <(lhs: LitvinSettingsEntry, rhs: LitvinSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! LitvinSettingsArguments
        switch self {
        case let .ghostMode(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleGhost(value)
            })
        case let .voiceChanger(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openVoiceChanger()
            })
        case let .ghostInfo(text), let .voiceInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .messagesHeader(text), let .privacyHeader(text), let .aboutHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .keepDeleted(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(LitvinFlags.keepDeletedKey, value)
            })
        case let .bypassProtection(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(LitvinFlags.bypassProtectionKey, value)
            })
        case let .unlimitedViewOnce(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(LitvinFlags.unlimitedViewOnceKey, value)
            })
        case let .keepDeletedInfo(text), let .bypassProtectionInfo(text), let .unlimitedViewOnceInfo(text), let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .version(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .source(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openSource()
            })
        }
    }
}

private func litvinSettingsEntries(state: LitvinSettingsState) -> [LitvinSettingsEntry] {
    return [
        .ghostMode("Призрачный режим", state.ghostMode),
        .ghostInfo("Собеседники не видят, что ты прочитал сообщения, печатаешь, прослушал голосовое или был онлайн. Если ты сам отправишь сообщение, Telegram покажет тебя в сети."),
        .voiceChanger("Смена голоса", state.voicePreset),
        .voiceInfo("Злой, девушка, ребёнок, пиксель, робот, вокал — для голосовых и звонков."),
        .messagesHeader("СООБЩЕНИЯ"),
        .keepDeleted("Удалённые сообщения", state.keepDeleted),
        .keepDeletedInfo("Если собеседник удалит сообщение, оно останется в чате, станет немного прозрачным и получит пометку «удалено» рядом со временем."),
        .privacyHeader("ЗАЩИЩЁННЫЕ ЧАТЫ"),
        .bypassProtection("Обход запрета копирования", state.bypassProtection),
        .bypassProtectionInfo("В каналах и чатах с запретом можно копировать, пересылать, сохранять медиа и делать скриншоты. Пересылка из таких чатов отправляется копией."),
        .unlimitedViewOnce("Одноразовые медиа без лимита", state.unlimitedViewOnce),
        .unlimitedViewOnceInfo("Фото, видео, кружки и голосовые «просмотр один раз» можно открывать сколько угодно — они не исчезают и не отмечаются просмотренными."),
        .aboutHeader("LITVIN"),
        .version("Версия", litvinVersion),
        .source("Исходный код", "GitHub"),
        .info("Неофициальный клиент на Telegram API."),
    ]
}

public func litvinSettingsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(LitvinSettingsState.current(), ignoreRepeated: true)
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = LitvinSettingsArguments(toggle: { key, value in
        LitvinFlags.setEnabled(key, value)
        statePromise.set(LitvinSettingsState.current())
    }, toggleGhost: { value in
        LitvinFlags.setGhostMode(value)
        statePromise.set(LitvinSettingsState.current())
    }, openVoiceChanger: {
        pushControllerImpl?(litvinVoiceChangerController(context: context))
    }, openSource: {
        if let url = URL(string: "https://github.com/rachimanna/litvin-ios") {
            UIApplication.shared.open(url)
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Litvin"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: litvinSettingsEntries(state: state), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        statePromise.set(LitvinSettingsState.current())
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    return controller
}

import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

public let litvinVersion = "1.0.0"

private final class LitvinSettingsArguments {
    let toggle: (String, Bool) -> Void
    let toggleGhost: (Bool) -> Void
    let toggleAutoReply: (Bool) -> Void
    let updateAutoReplyText: (String) -> Void
    let openVoiceChanger: () -> Void
    let openSource: () -> Void

    init(toggle: @escaping (String, Bool) -> Void, toggleGhost: @escaping (Bool) -> Void, toggleAutoReply: @escaping (Bool) -> Void, updateAutoReplyText: @escaping (String) -> Void, openVoiceChanger: @escaping () -> Void, openSource: @escaping () -> Void) {
        self.toggle = toggle
        self.toggleGhost = toggleGhost
        self.toggleAutoReply = toggleAutoReply
        self.updateAutoReplyText = updateAutoReplyText
        self.openVoiceChanger = openVoiceChanger
        self.openSource = openSource
    }
}

private enum LitvinSettingsSection: Int32 {
    case ghost
    case voice
    case messages
    case extras
    case autoReply
    case privacy
    case about
}

private struct LitvinSettingsState: Equatable {
    var ghostMode: Bool
    var voicePreset: String
    var keepDeleted: Bool
    var bypassProtection: Bool
    var unlimitedViewOnce: Bool
    var topBadge: Bool
    var antiAds: Bool
    var editHistory: Bool
    var confetti: Bool
    var localTranscription: Bool
    var autoReply: Bool
    var autoReplyText: String

    static func current() -> LitvinSettingsState {
        let voice = LitvinVoiceSettings.current
        return LitvinSettingsState(
            ghostMode: LitvinFlags.ghostMode,
            voicePreset: voice.isActive ? voice.preset.title : "Выключено",
            keepDeleted: LitvinFlags.keepDeleted,
            bypassProtection: LitvinFlags.bypassProtection,
            unlimitedViewOnce: LitvinFlags.unlimitedViewOnce,
            topBadge: LitvinFlags.topBadge,
            antiAds: LitvinFlags.antiAds,
            editHistory: LitvinFlags.editHistory,
            confetti: LitvinFlags.confetti,
            localTranscription: LitvinFlags.localTranscription,
            autoReply: LitvinFlags.autoReply,
            autoReplyText: LitvinFlags.autoReplyText
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
    case extrasHeader(String)
    case extraSwitch(Int32, String, String, Bool)
    case extrasInfo(String)
    case autoReplyHeader(String)
    case autoReply(String, Bool)
    case autoReplyText(String)
    case autoReplyInfo(String)
    case privacyHeader(String)
    case bypassProtection(String, Bool)
    case bypassProtectionInfo(String)
    case unlimitedViewOnce(String, Bool)
    case unlimitedViewOnceInfo(String)
    case topBadge(String, Bool)
    case topBadgeInfo(String)
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
        case .extrasHeader, .extraSwitch, .extrasInfo:
            return LitvinSettingsSection.extras.rawValue
        case .autoReplyHeader, .autoReply, .autoReplyText, .autoReplyInfo:
            return LitvinSettingsSection.autoReply.rawValue
        case .privacyHeader, .bypassProtection, .bypassProtectionInfo, .unlimitedViewOnce, .unlimitedViewOnceInfo:
            return LitvinSettingsSection.privacy.rawValue
        case .topBadge, .topBadgeInfo, .aboutHeader, .version, .source, .info:
            return LitvinSettingsSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostMode: return 0
        case .ghostInfo: return 1
        case .voiceChanger: return 2
        case .voiceInfo: return 3
        case .messagesHeader: return 10
        case .keepDeleted: return 11
        case .keepDeletedInfo: return 12
        case .extrasHeader: return 20
        case let .extraSwitch(index, _, _, _): return 21 + index
        case .extrasInfo: return 39
        case .autoReplyHeader: return 40
        case .autoReply: return 41
        case .autoReplyText: return 42
        case .autoReplyInfo: return 43
        case .privacyHeader: return 50
        case .bypassProtection: return 51
        case .bypassProtectionInfo: return 52
        case .unlimitedViewOnce: return 53
        case .unlimitedViewOnceInfo: return 54
        case .topBadge: return 60
        case .topBadgeInfo: return 61
        case .aboutHeader: return 70
        case .version: return 71
        case .source: return 72
        case .info: return 73
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
        case let .extrasHeader(a):
            if case let .extrasHeader(b) = rhs { return a == b }
            return false
        case let .extraSwitch(a1, a2, a3, a4):
            if case let .extraSwitch(b1, b2, b3, b4) = rhs { return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4 }
            return false
        case let .extrasInfo(a):
            if case let .extrasInfo(b) = rhs { return a == b }
            return false
        case let .autoReplyHeader(a):
            if case let .autoReplyHeader(b) = rhs { return a == b }
            return false
        case let .autoReply(a1, a2):
            if case let .autoReply(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .autoReplyText(a):
            if case let .autoReplyText(b) = rhs { return a == b }
            return false
        case let .autoReplyInfo(a):
            if case let .autoReplyInfo(b) = rhs { return a == b }
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
        case let .topBadge(a1, a2):
            if case let .topBadge(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .topBadgeInfo(a):
            if case let .topBadgeInfo(b) = rhs { return a == b }
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
        case let .extraSwitch(_, key, title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(key, value)
            })
        case let .autoReply(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggleAutoReply(value)
            })
        case let .autoReplyText(text):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: LitvinFlags.defaultAutoReplyText, maxLength: ItemListMultilineInputItemTextLimit(value: 300, display: false), sectionId: self.section, style: .blocks, textUpdated: { value in
                arguments.updateAutoReplyText(value)
            })
        case let .extrasInfo(text), let .autoReplyInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .messagesHeader(text), let .privacyHeader(text), let .aboutHeader(text), let .extrasHeader(text), let .autoReplyHeader(text):
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
        case let .topBadge(title, value):
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(LitvinFlags.topBadgeKey, value)
            })
        case let .topBadgeInfo(text):
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
        .voiceInfo("Злой, девушка, ребёнок, пиксель, робот, вокал. Включается один раз — и работает в голосовых, звонках и групповых звонках."),
        .messagesHeader("СООБЩЕНИЯ"),
        .keepDeleted("Удалённые сообщения", state.keepDeleted),
        .keepDeletedInfo("Если собеседник удалит сообщение, оно останется в чате, станет немного прозрачным и получит пометку «удалено» рядом со временем."),
        .extrasHeader("ЕЩЁ"),
        .extraSwitch(0, LitvinFlags.antiAdsKey, "Без рекламы в каналах", state.antiAds),
        .extraSwitch(1, LitvinFlags.editHistoryKey, "История правок", state.editHistory),
        .extraSwitch(2, LitvinFlags.localTranscriptionKey, "Голосовые в текст", state.localTranscription),
        .extraSwitch(3, LitvinFlags.confettiKey, "Конфетти", state.confetti),
        .extrasInfo("История правок: долгое нажатие на изменённое сообщение → «История правок». Голосовые в текст распознаются прямо на телефоне, без Premium. Конфетти летит, когда ты пишешь «С днём рождения», «Поздравляю», «Ура» или 🎉. Статистика переписки и «Прочитать для собеседника» — долгое нажатие на чат в списке чатов."),
        .autoReplyHeader("АВТООТВЕТ"),
        .autoReply("Автоответ в личных чатах", state.autoReply),
        .autoReplyText(state.autoReplyText),
        .autoReplyInfo("Пока включено, каждому, кто напишет в личку, придёт этот текст (не чаще раза в 30 минут одному человеку). Работает, пока Litvin запущен."),
        .privacyHeader("ЗАЩИЩЁННЫЕ ЧАТЫ"),
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
        NotificationCenter.default.post(name: Notification.Name("LitvinFlagsChanged"), object: nil)
        statePromise.set(LitvinSettingsState.current())
    }, toggleGhost: { value in
        LitvinFlags.setGhostMode(value)
        statePromise.set(LitvinSettingsState.current())
    }, toggleAutoReply: { value in
        LitvinFlags.setAutoReply(value)
        statePromise.set(LitvinSettingsState.current())
    }, updateAutoReplyText: { value in
        LitvinFlags.setAutoReplyText(value)
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

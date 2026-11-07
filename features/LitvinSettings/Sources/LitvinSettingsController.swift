import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import LitvinCore

public let litvinVersion = "0.3.0"

private final class LitvinArguments {
    let toggle: (String, Bool) -> Void
    let action: (String) -> Void
    init(toggle: @escaping (String, Bool) -> Void, action: @escaping (String) -> Void) {
        self.toggle = toggle
        self.action = action
    }
}

private struct LitvinEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let key: String
    let value: Bool?
    let header: Bool
    static func < (a: Self, b: Self) -> Bool { a.stableId < b.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! LitvinArguments
        if header { return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: section) }
        if let value {
            return ItemListSwitchItem(presentationData: presentationData, title: title, value: value, sectionId: section, style: .blocks, updated: { args.toggle(key, $0) })
        }
        return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "", sectionId: section, style: .blocks, action: { args.action(key) })
    }
}

private let toggles: [(String, String, WritableKeyPath<LitvinOptions, Bool>, Int32)] = [
    ("ghostMode", "Режим призрака", \.ghostMode, 0),
    ("ghostNoTyping", "Не показывать набор текста", \.ghostNoTyping, 0),
    ("ghostNoOnline", "Не показывать онлайн", \.ghostNoOnline, 0),
    ("ghostScheduleEnabled", "Призрак по расписанию", \.ghostScheduleEnabled, 0),
    ("alibiEnabled", "Онлайн по расписанию", \.alibiEnabled, 0),
    ("antiAds", "Скрывать рекламу каналов", \.antiAds, 1),
    ("screenshotBypass", "Скриншоты защищённых каналов", \.screenshotBypass, 1),
    ("forwardBypass", "Копирование защищённых сообщений", \.forwardBypass, 1),
    ("infiniteSelfDestruct", "Не отправлять просмотр медиа", \.infiniteSelfDestruct, 1),
    ("forwardScrub", "Пересылка без автора и цитаты", \.forwardScrub, 1),
    ("saveDeleted", "Сохранять удалённый текст", \.saveDeleted, 2),
    ("saveEditHistory", "Сохранять историю правок", \.saveEditHistory, 2),
    ("messageNotes", "Личные заметки на сообщениях", \.messageNotes, 2),
    ("channelDigest", "Собирать дайджест каналов", \.channelDigest, 3),
    ("contactProfile", "Локальная статистика общения", \.contactProfile, 3),
]

public func litvinSettingsController(context: AccountContext) -> ViewController {
    let refresh = ValuePromise<Int>(0, ignoreRepeated: false)
    var revision = 0
    let args = LitvinArguments(toggle: { key, value in
        if key == "localPremium" {
            LitvinAppearance.update(account: context.account.peerId.toInt64()) { $0.premium = value }
            revision += 1; refresh.set(revision); return
        }
        guard let row = toggles.first(where: { $0.0 == key }) else { return }
        LitvinPolicy.update { $0[keyPath: row.2] = value }
        revision += 1
        refresh.set(revision)
    }, action: { key in
        LitvinTools.open(key, context: context)
    })

    let state = combineLatest(context.sharedContext.presentationData, refresh.get(), litvinAppearanceUpdates())
    |> deliverOnMainQueue
    |> map { presentationData, _, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let options = LitvinPolicy.options
        let headings = ["ПРИВАТНОСТЬ", "СООБЩЕНИЯ", "ЛОКАЛЬНЫЕ ДАННЫЕ", "ИНСТРУМЕНТЫ"]
        var entries: [LitvinEntry] = []
        var id: Int32 = 0
        func add(_ title: String, key: String = "", value: Bool? = nil, section: Int32, header: Bool = false) {
            entries.append(LitvinEntry(stableId: id, section: section, title: title, key: key, value: value, header: header))
            id += 1
        }
        for section in Int32(0)...Int32(3) {
            add(headings[Int(section)], section: section, header: true)
            for toggle in toggles where toggle.3 == section {
                add(toggle.1, key: toggle.0, value: options[keyPath: toggle.2], section: section)
            }
            if section == 0 { add("Настроить расписание", key: "schedule", section: section) }
            if section == 2 {
                add("Удалённые сообщения", key: "deleted", section: section)
                add("История правок", key: "edits", section: section)
                add("Мои заметки", key: "notes", section: section)
            }
            if section == 3 {
                add("Локальный Premium", key: "localPremium", value: LitvinAppearance.state(account: context.account.peerId.toInt64()).premium, section: section)
                add("Локальное оформление, номер и подарки", key: "appearance", section: section)
                for row in [("Каналы дайджеста", "channels"), ("Дайджест", "digest"), ("Статистика контактов", "contacts"), ("Скрытые чаты и PIN", "hidden"), ("Шифрованный локальный архив", "vault"), ("Пул прокси", "proxies"), ("Экспорт / импорт", "backup"), ("Установка через ESign", "esign"), ("О Litvin", "about")] {
                    add(row.0, key: row.1, section: section)
                }
            }
        }
        let controller = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Litvin"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controller, (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false), args))
    }
    return ItemListController(context: context, state: state)
}

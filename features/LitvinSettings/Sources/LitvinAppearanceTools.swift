import Foundation
import UIKit
import AccountContext
import TelegramCore
import SwiftSignalKit

public enum LitvinAppearanceTools {
    public static func show(context: AccountContext) {
        let account = context.account.peerId.toInt64()
        let controller = LitvinAppearanceRowsController(title: "Локальное оформление")
        controller.refresh = {
            let state = LitvinAppearance.state(account: account)
            return [
                .init(title: "Локальный Premium", detail: state.premium ? "Включён" : "Выключен", action: {
                    LitvinAppearance.update(account: account) { $0.premium.toggle() }; controller.reload()
                }),
                .init(title: "Изменить локальный номер", detail: state.phone ?? "Настоящий номер", action: { editPhone(account: account) }),
                .init(title: "Локальные звёзды", detail: state.stars.map(String.init) ?? "Настоящий баланс", action: { editStars(account: account) }),
                .init(title: "Локальные подарки", detail: "Выбрать собеседника и подарок", action: { choosePeer(context: context) }),
                .init(title: "Сбросить локальное оформление", detail: "Показать исходные данные аккаунта", action: {
                    LitvinAppearance.reset(account: account); controller.reload()
                })
            ]
        }
        LitvinAppearanceUI.list(controller)
    }

    public static func phoneMenu(account: Int64, changeReal: @escaping () -> Void) {
        let controller = LitvinAppearanceRowsController(title: "Мой номер")
        controller.rows = [
            .init(title: "Изменить локальный номер", detail: "Отображение только на этом устройстве", action: { editPhone(account: account) }),
            .init(title: "Изменить номер Telegram", detail: "Официальная смена номера аккаунта", action: {
                controller.dismiss(animated: true, completion: changeReal)
            })
        ]
        LitvinAppearanceUI.list(controller)
    }

    public static func editPhone(account: Int64) {
        LitvinAppearanceUI.prompt("Изменить локальный номер", message: "Любое отображаемое значение до 64 символов. Пустое поле возвращает настоящий номер. Номер для входа не меняется.", fields: [("Локальный номер", LitvinAppearance.state(account: account).phone ?? "", false)]) { values in
            let phone = (values.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard LitvinAppearance.update(account: account, { $0.phone = phone.isEmpty ? nil : phone }) else {
                LitvinAppearanceUI.info("Проверь номер", "Не более 64 символов без переносов строк."); return
            }
        }
    }

    public static func editStars(account: Int64) {
        LitvinAppearanceUI.prompt("Локальные звёзды", message: "Только отображение в «Мои звёзды». Покупки используют настоящий баланс. Пустое поле возвращает настоящий баланс.", fields: [("Количество звёзд", LitvinAppearance.state(account: account).stars.map(String.init) ?? "", false)]) { values in
            let text = (values.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = Int64(text)
            guard text.isEmpty || (amount.map { (0...LitvinAppearance.maximumStars).contains($0) } ?? false) else {
                LitvinAppearanceUI.info("Проверь количество", "Введи целое число от 0 до \(LitvinAppearance.maximumStars)."); return
            }
            LitvinAppearance.update(account: account) { $0.stars = text.isEmpty ? nil : amount }
        }
    }

    static func choosePeer(context: AccountContext) {
        LitvinAppearanceUI.prompt("Выбрать собеседника", message: "Введи имя из своих чатов или контактов.", fields: [("Имя", "", false)]) { values in
            guard let query = values.first?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return }
            let _ = (context.engine.contacts.searchLocalPeers(query: query) |> take(1) |> deliverOnMainQueue).startStandalone(next: { peers in
                let controller = LitvinAppearanceRowsController(title: "Выбрать собеседника")
                controller.rows = peers.compactMap { item in
                    guard let peer = item.peer, case .user = peer else { return nil }
                    return .init(title: peer.compactDisplayTitle, detail: "Локальные подарки в профиле", action: { showGifts(context: context, peer: peer.id.toInt64()) })
                }
                if controller.rows.isEmpty { controller.rows = [.init(title: "Ничего не найдено", detail: "Можно открыть профиль собеседника и выбрать «Локальные подарки».", action: {})] }
                LitvinAppearanceUI.list(controller)
            })
        }
    }

    public static func showGifts(context: AccountContext, peer: Int64) {
        let account = context.account.peerId.toInt64()
        let controller = LitvinAppearanceRowsController(title: "Локальные подарки")
        controller.refresh = {
            var rows: [LitvinAppearanceRowsController.Row] = [
                .init(title: "Отправить подарок", detail: "Выбрать в каталоге", action: { LitvinGiftCatalog.show(context: context, peer: peer) })
            ]
            rows += litvinLocalGifts(account: account, peer: peer).map { gift in
                .init(title: litvinGiftTitle(gift), detail: "Виден только тебе. Нажми, чтобы убрать.", action: {
                    LitvinAppearance.update(account: account) { state in
                        state.gifts[String(peer)]?.removeValue(forKey: litvinGiftKey(gift))
                        if state.gifts[String(peer)]?.isEmpty == true { state.gifts.removeValue(forKey: String(peer)) }
                    }
                })
            }
            return rows
        }
        LitvinAppearanceUI.list(controller)
    }

}

import Foundation
import UIKit
import AccountContext
import TelegramCore
import SwiftSignalKit
import LitvinCore

public enum LitvinAppearanceTools {
    public static func show(context: AccountContext) {
        let account = context.account.peerId.toInt64()
        let controller = LitvinRowsController(title: "Локальное оформление")
        controller.refresh = {
            let state = LitvinAppearance.state(account: account)
            return [
                .init(title: "Локальный Premium", detail: state.premium ? "Включён" : "Выключен", action: {
                    LitvinAppearance.update(account: account) { $0.premium.toggle() }; controller.reload()
                }),
                .init(title: "Изменить локальный номер", detail: state.phone ?? "Настоящий номер", action: { editPhone(account: account) }),
                .init(title: "Локальные звёзды", detail: state.stars.map(String.init) ?? "Настоящий баланс", action: { editStars(account: account) }),
                .init(title: "Локальные NFT-подарки", detail: "Выбрать собеседника и подарок", action: { choosePeer(context: context) }),
                .init(title: "Сбросить локальное оформление", detail: "Показать исходные данные аккаунта", action: {
                    LitvinAppearance.reset(account: account); controller.reload()
                })
            ]
        }
        LitvinTools.list(controller)
    }

    public static func phoneMenu(account: Int64, changeReal: @escaping () -> Void) {
        let controller = LitvinRowsController(title: "Мой номер")
        controller.rows = [
            .init(title: "Изменить локальный номер", detail: "Отображение только на этом устройстве", action: { editPhone(account: account) }),
            .init(title: "Изменить номер Telegram", detail: "Официальная смена номера аккаунта", action: {
                controller.dismiss(animated: true, completion: changeReal)
            })
        ]
        LitvinTools.list(controller)
    }

    public static func editPhone(account: Int64) {
        LitvinTools.prompt("Изменить локальный номер", message: "Любое отображаемое значение до 64 символов. Пустое поле возвращает настоящий номер. Номер для входа не меняется.", fields: [("Локальный номер", LitvinAppearance.state(account: account).phone ?? "", false)]) { values in
            let phone = (values.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard LitvinAppearance.update(account: account, { $0.phone = phone.isEmpty ? nil : phone }) else {
                LitvinTools.info("Проверь номер", "Не более 64 символов без переносов строк."); return
            }
        }
    }

    public static func editStars(account: Int64) {
        LitvinTools.prompt("Локальные звёзды", message: "Только отображение в «Мои звёзды». Покупки используют настоящий баланс. Пустое поле возвращает настоящий баланс.", fields: [("Количество звёзд", LitvinAppearance.state(account: account).stars.map(String.init) ?? "", false)]) { values in
            let text = (values.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = Int64(text)
            guard text.isEmpty || (amount.map { (0...LitvinAppearance.maximumStars).contains($0) } ?? false) else {
                LitvinTools.info("Проверь количество", "Введи целое число от 0 до \(LitvinAppearance.maximumStars)."); return
            }
            LitvinAppearance.update(account: account) { $0.stars = text.isEmpty ? nil : amount }
        }
    }

    static func choosePeer(context: AccountContext) {
        LitvinTools.prompt("Выбрать собеседника", message: "Введи имя из своих чатов или контактов.", fields: [("Имя", "", false)]) { values in
            guard let query = values.first?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return }
            let _ = (context.engine.contacts.searchLocalPeers(query: query) |> take(1) |> deliverOnMainQueue).startStandalone(next: { peers in
                let controller = LitvinRowsController(title: "Выбрать собеседника")
                controller.rows = peers.compactMap { item in
                    guard let peer = item.peer, case .user = peer else { return nil }
                    return .init(title: peer.compactDisplayTitle, detail: "Локальные подарки в профиле", action: { showGifts(context: context, peer: peer.id.toInt64()) })
                }
                if controller.rows.isEmpty { controller.rows = [.init(title: "Ничего не найдено", detail: "Можно открыть профиль собеседника и выбрать «Локальные NFT-подарки».", action: {})] }
                LitvinTools.list(controller)
            })
        }
    }

    public static func showGifts(context: AccountContext, peer: Int64) {
        let account = context.account.peerId.toInt64()
        let controller = LitvinRowsController(title: "Локальные NFT-подарки")
        controller.refresh = {
            var rows: [LitvinRowsController.Row] = [
                .init(title: "Добавить NFT-подарок", detail: "Вставить ссылку t.me/nft на любой существующий подарок", action: { addGift(context: context, peer: peer) })
            ]
            rows += litvinLocalGifts(account: account, peer: peer).map { gift in
                .init(title: "\(gift.title) #\(gift.number)", detail: "Виден только тебе. Нажми, чтобы убрать.", action: {
                    LitvinAppearance.update(account: account) { state in
                        state.gifts[String(peer)]?.removeValue(forKey: gift.slug)
                        if state.gifts[String(peer)]?.isEmpty == true { state.gifts.removeValue(forKey: String(peer)) }
                    }
                })
            }
            return rows
        }
        LitvinTools.list(controller)
    }

    static func addGift(context: AccountContext, peer: Int64) {
        LitvinTools.prompt("Добавить NFT-подарок", message: "Ссылка вида https://t.me/nft/PlushPepe-123 или его slug. Загрузим оформление из Telegram и сохраним локально.", fields: [("Ссылка или slug", "", false)]) { values in
            guard let raw = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            let slug: String
            if raw.contains("://") {
                guard let url = URL(string: raw), url.scheme == "https", url.host?.lowercased() == "t.me", url.pathComponents.count == 3, url.pathComponents[1] == "nft", url.query == nil, url.fragment == nil else {
                    LitvinTools.info("Неверная ссылка", "Нужна ссылка https://t.me/nft/Название-Номер."); return
                }
                slug = url.lastPathComponent
            } else { slug = raw }
            guard slug.count <= 128, slug.range(of: "^[A-Za-z0-9]+-[0-9]+$", options: .regularExpression) != nil else {
                LitvinTools.info("Неверный подарок", "Укажи название и номер, например PlushPepe-123."); return
            }
            let _ = (context.engine.payments.getUniqueStarGift(slug: slug) |> deliverOnMainQueue).startStandalone(next: { gift in
                guard let data = try? JSONEncoder().encode(gift), LitvinAppearance.update(account: context.account.peerId.toInt64(), { $0.gifts[String(peer), default: [:]][gift.slug] = data }) else {
                    LitvinTools.info("Не удалось сохранить", "Максимум 100 локальных подарков."); return
                }
                LitvinTools.info("Подарок добавлен", "Он появится во вкладке подарков этого профиля только у тебя. Если вкладка ещё не появилась, открой профиль заново.")
            }, error: { _ in LitvinTools.info("Подарок недоступен", "Проверь ссылку и подключение к Telegram.") })
        }
    }
}

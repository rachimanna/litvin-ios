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
                .init(title: "Подарки без списания звёзд", detail: litvinGiftPreviewEnabled(account: account) ? "Включено • видны только на этом устройстве" : "Выключено", action: { let enabled = litvinGiftPreviewEnabled(account: account); LitvinAppearance.update(account: account) { $0.giftPreviewEnabled = !enabled }; controller.reload() }),
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

}

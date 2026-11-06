import Foundation
import UIKit
import AccountContext
import TelegramCore
import LitvinCore

enum LitvinVaultTools {
    static func show(context: AccountContext) {
        let account = context.account.peerId.toInt64()
        let controller = LitvinRowsController(title: "Шифрованная локальная история")
        controller.protectedAccount = account
        let vault = LitvinPrivateArchive.forAccount(account)
        controller.refresh = {
            var rows: [LitvinRowsController.Row] = [
                .init(title: "Добавить чат в хранилище", detail: "Переносит локальный текст, правки и заметки Litvin в зашифрованный файл.", action: { choose(account: account) }),
                .init(title: "Закрыть хранилище", detail: "Удаляет ключи открытых архивов из памяти.", action: { vault.lockAllPeers() }),
                .init(title: "Что защищается", detail: "Оригинальная база Telegram и её медиа не изменяются.", action: {
                    LitvinTools.info("Границы защиты", "Паролем шифруется только локальная история Litvin: текст, правки и заметки выбранного чата. Исходные сообщения и медиа в Telegram остаются в штатной базе. Пока хранилище закрыто, новые тексты Litvin не записывает. Пароль не сохраняется и не восстанавливается.")
                }),
            ]
            rows += vault.peers.map { peer in
                let state = vault.snapshot(peer: peer)
                let title = state?.messages.values.first?.peerTitle ?? String(peer)
                return .init(title: title, detail: state == nil ? "Закрыт" : "Открыт • \(state?.messages.count ?? 0) сообщений", action: {
                    if state == nil { unlock(account: account, peer: peer) { showPeer(account: account, peer: peer) } }
                    else { showPeer(account: account, peer: peer) }
                })
            }
            return rows
        }
        LitvinTools.list(controller)
    }
    private static func choose(account: Int64) {
        let state = LitvinArchive.forAccount(account).snapshot()
        let groups = Dictionary(grouping: state.messages.values, by: { $0.peer })
        let controller = LitvinRowsController(title: "Выбери локальную историю")
        controller.protectedAccount = account
        controller.rows = groups.keys.sorted().map { peer in
            .init(title: groups[peer]?.first?.peerTitle ?? String(peer), detail: "\(groups[peer]?.count ?? 0) сообщений", action: {
                LitvinTools.prompt("Пароль хранилища", message: "Не менее 12 символов. Переносится только история Litvin, а не база Telegram.", fields: [("Пароль", "", true), ("Повтори пароль", "", true)]) { values in
                    guard values.count == 2, values[0] == values[1] else { LitvinTools.info("Пароли не совпадают", "Попробуй снова."); return }
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try LitvinArchive.forAccount(account).moveToPrivateArchive(peer: peer, passphrase: values[0])
                            DispatchQueue.main.async { LitvinTools.info("История зашифрована", "Ключ останется в памяти до сворачивания приложения или команды «Закрыть хранилище».") }
                        } catch { DispatchQueue.main.async { LitvinTools.failure(error) } }
                    }
                }
            })
        }
        LitvinTools.list(controller)
    }
    static func unlock(account: Int64, peer: Int64, completion: @escaping () -> Void) {
        LitvinTools.prompt("Пароль истории чата", fields: [("Пароль", "", true)]) { values in
            guard let password = values.first else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try LitvinPrivateArchive.forAccount(account).unlock(peer: peer, passphrase: password)
                    DispatchQueue.main.async(execute: completion)
                } catch { DispatchQueue.main.async { LitvinTools.info("История не открыта", "Неверный пароль или повреждённый файл.") } }
            }
        }
    }
    private static func showPeer(account: Int64, peer: Int64) {
        let controller = LitvinRowsController(title: "Защищённая история")
        controller.protectedAccount = account
        controller.refresh = {
            guard let state = LitvinPrivateArchive.forAccount(account).snapshot(peer: peer) else { return [.init(title: "Хранилище закрыто", detail: "Введи пароль в разделе хранилища.", action: {})] }
            return state.messages.values.sorted { $0.timestamp > $1.timestamp }.prefix(500).map { record in
                let note = state.notes[record.key]?.text ?? ""
                let versions = state.edits[record.key] ?? []
                return .init(title: "\(record.deleted ? "Удалено • " : "")\(LitvinTools.date(Double(record.timestamp)))", detail: record.text, action: {
                    LitvinTools.info("Сообщение \(record.message)", record.text + (note.isEmpty ? "" : "\n\nЗаметка: \(note)") + (versions.isEmpty ? "" : "\n\nПравки:\n" + versions.map { $0.text }.joined(separator: "\n→\n")))
                })
            }
        }
        LitvinTools.list(controller)
    }
}

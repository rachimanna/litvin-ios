import Foundation
import UIKit
import UniformTypeIdentifiers
import AccountContext
import TelegramCore
import TelegramUIPreferences
import SwiftSignalKit
import LitvinCore

private struct LitvinBackupFile: Codable {
    let version: Int
    let account: Int64
    let options: LitvinOptions
    let local: Data
    let telegram: LitvinAccountContextState
    let theme: PresentationThemeSettings
    let proxies: ProxySettings
    let vaults: [String: Data]?
}

enum LitvinBackup {
    static func show(context: AccountContext, vault: Bool) {
        let controller = LitvinRowsController(title: vault ? "Шифрованный локальный архив" : "Экспорт / импорт")
        let account = context.account.peerId.toInt64()
        controller.rows = [
            .init(title: "Экспортировать с паролем", detail: "История, заметки, настройки, папки, темы, список стикеров и закреплённые чаты. Пароль не менее 12 символов.", action: {
                LitvinTools.prompt("Пароль архива", fields: [("Пароль", "", true), ("Повтори пароль", "", true)]) { values in
                    guard values.count == 2, values[0] == values[1], values[0].count >= 12 else { LitvinTools.info("Проверь пароль", "Нужно не менее 12 символов, оба поля должны совпасть."); return }
                    let settings = context.sharedContext.accountManager.transaction { transaction -> (PresentationThemeSettings, ProxySettings) in
                        let theme = transaction.getSharedData(ApplicationSpecificSharedDataKeys.presentationThemeSettings)?.get(PresentationThemeSettings.self) ?? PresentationThemeSettings.defaultSettings
                        let proxies = transaction.getSharedData(SharedDataKeys.proxySettings)?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
                        return (theme, proxies)
                    }
                    let _ = (combineLatest(litvinExportAccountContext(account: context.account), settings)
                    |> take(1)).startStandalone(next: { telegram, settings in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do {
                                let backup = LitvinBackupFile(version: 1, account: account, options: LitvinPolicy.options, local: try LitvinArchive.forAccount(account).exportData(), telegram: telegram, theme: settings.0, proxies: settings.1, vaults: try LitvinPrivateArchive.forAccount(account).encryptedFiles())
                                let content = try JSONEncoder().encode(backup)
                                guard content.count <= 20 * 1024 * 1024 else { throw LitvinArchiveError.tooLarge }
                                let encrypted = try LitvinVault.seal(content, account: account, passphrase: values[0])
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Litvin-\(UUID().uuidString).litvin")
                                try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
                                DispatchQueue.main.async {
                                    let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                    share.popoverPresentationController?.sourceView = controller.view
                                    share.popoverPresentationController?.sourceRect = controller.view.bounds
                                    share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: url) }
                                    controller.present(share, animated: true)
                                }
                            } catch { DispatchQueue.main.async { LitvinTools.failure(error) } }
                        }
                    })
                }
            }),
            .init(title: "Восстановить из файла", detail: "Для того же аккаунта. Локальные данные и настройки заменятся; папки, закрепления и установка стикеров синхронизируются Telegram.", action: {
                controller.documentHandler = { url in
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                        guard ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 30 * 1024 * 1024 else { throw LitvinArchiveError.tooLarge }
                        let encrypted = try Data(contentsOf: url)
                        LitvinTools.prompt("Открыть архив", message: "После проверки пароля потребуется подтвердить замену данных.", fields: [("Пароль", "", true)]) { values in
                            guard let password = values.first else { return }
                            DispatchQueue.global(qos: .userInitiated).async {
                                do {
                                    let data = try LitvinVault.open(encrypted, account: account, passphrase: password)
                                    let backup = try JSONDecoder().decode(LitvinBackupFile.self, from: data)
                                    guard backup.version == 1, backup.account == account, backup.telegram.account == account, backup.telegram.filters.count <= 100, backup.telegram.stickers.count <= 1000, backup.telegram.pinned.count <= 100, backup.telegram.archivedPinned.count <= 100 else { throw LitvinArchiveError.invalidBackup }
                                    DispatchQueue.main.async { confirmRestore(backup, context: context) }
                                } catch { DispatchQueue.main.async { LitvinTools.info("Архив не открыт", "Неверный пароль, другой аккаунт или повреждённый файл.") } }
                            }
                        }
                    } catch { LitvinTools.failure(error) }
                }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
                picker.delegate = controller
                controller.present(picker, animated: true)
            }),
            .init(title: "О защите архива", detail: "AES-GCM, пароль не сохраняется. Файл не содержит сессий входа и ключей Telegram.", action: {
                LitvinTools.info("Что шифруется", "Шифруется экспортируемый файл. Оригинальная база Telegram и уже загруженное медиа остаются в штатном хранилище клиента. Это не шифрование всех чатов на диске. Пароль восстановить нельзя.")
            }),
        ]
        LitvinTools.list(controller)
    }

    private static func confirmRestore(_ backup: LitvinBackupFile, context: AccountContext) {
        let alert = UIAlertController(title: "Заменить данные?", message: "Текущая локальная история и заметки заменятся. Папки и закрепления также изменятся на других устройствах этого аккаунта.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Восстановить", style: .destructive, handler: { _ in
            do {
                try LitvinArchive.forAccount(backup.account).importData(backup.local)
                try LitvinPrivateArchive.forAccount(backup.account).importEncryptedFiles(backup.vaults ?? [:])
                LitvinPolicy.replace(backup.options)
                let theme = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { _ in backup.theme })
                let proxies = updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { _ in backup.proxies }) |> map { _ -> Void in }
                let telegram = litvinRestoreAccountContext(account: context.account, state: backup.telegram)
                let packs: [Signal<Void, NoError>] = backup.telegram.stickers.map { pack in
                    context.engine.stickers.loadedStickerPack(reference: .id(id: pack.id, accessHash: pack.accessHash), forceActualized: false)
                    |> filter { result in if case .fetching = result { return false }; return true }
                    |> take(1)
                    |> mapToSignal { result -> Signal<Void, NoError> in
                        if case let .result(info, items, _) = result {
                            return context.engine.stickers.addStickerPackInteractively(info: info._parse(), items: items, noDelay: true) |> map { _ -> Void in }
                        }
                        return .single(())
                    }
                }
                let _ = (combineLatest([theme, proxies, telegram] + packs)
                |> deliverOnMainQueue).startStandalone(completed: { LitvinTools.info("Восстановлено", "Перезапусти приложение, чтобы все экраны перечитали настройки. Недоступные на сервере стикерпаки восстановить нельзя.") })
            } catch { LitvinTools.failure(error) }
        }))
        LitvinTools.present(alert)
    }
}

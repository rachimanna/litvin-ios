import Foundation
import UIKit
import AccountContext
import TelegramCore
import SwiftSignalKit
import LitvinCore

enum LitvinProxyPool {
    private static var pools: [Int64: Pool] = [:]
    static func start(context: AccountContext) {
        let id = context.account.peerId.toInt64()
        if pools[id] == nil { pools[id] = Pool(context: context) }
    }
    static func show(context: AccountContext) {
        start(context: context)
        let controller = LitvinRowsController(title: "Пул прокси")
        controller.rows = [
            .init(title: "Автоматический выбор", detail: LitvinPolicy.options.proxyPool ? "Включён • нажми, чтобы отключить" : "Выключен • нажми, чтобы включить", action: {
                LitvinPolicy.update { $0.proxyPool.toggle() }
                LitvinTools.info("Пул прокси", LitvinPolicy.options.proxyPool ? "Включён. При отказе активного прокси будет выбран доступный с наименьшим временем ответа." : "Автовыбор выключен.")
            }),
            .init(title: "Добавить MTProto-прокси", detail: "Только собственные или доверенные серверы; автоматических списков нет.", action: {
                LitvinTools.prompt("MTProto-прокси", fields: [("Сервер", "", false), ("Порт", "443", false), ("Секрет в hex", "", true)]) { values in
                    guard values.count == 3, !values[0].isEmpty, values[0].count <= 253, !values[0].contains(where: { $0.isWhitespace }), let port = Int32(values[1]), (1...65535).contains(port), let secret = parseSecret(values[2]) else { LitvinTools.info("Проверь прокси", "Нужны адрес сервера, порт 1–65535 и корректный MTProto-секрет."); return }
                    let server = ProxyServerSettings(host: values[0], port: port, connection: .mtp(secret: secret))
                    let _ = updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                        var updated = current
                        if !updated.servers.contains(server) { updated.servers.append(server) }
                        return updated
                    }).startStandalone(completed: { DispatchQueue.main.async { LitvinTools.info("Добавлен", "Прокси доступен и в стандартных настройках Telegram.") } })
                }
            }),
            .init(title: "Проверить серверы", detail: "Проверка MTProto-соединения, а не только открытого TCP-порта.", action: {
                guard let pool = pools[context.account.peerId.toInt64()] else { return }
                let rows = pool.values.sorted { $0.key.host < $1.key.host }.map { server, status -> LitvinRowsController.Row in
                    let text: String
                    switch status { case .checking: text = "Проверяется"; case .notAvailable: text = "Недоступен"; case let .available(rtt): text = "\(Int(rtt * 1000)) мс" }
                    return .init(title: "\(server.host):\(server.port)", detail: text, action: {
                        let _ = updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                            var updated = current; updated.enabled = true; updated.activeServer = server; return updated
                        }).startStandalone()
                    })
                }
                LitvinTools.list(LitvinRowsController(title: "Доступность прокси", rows: rows))
            }),
        ]
        LitvinTools.list(controller)
    }
    private static func parseSecret(_ input: String) -> Data? {
        let text = input.lowercased()
        guard text.count % 2 == 0, (32...1024).contains(text.count), text.allSatisfy({ $0.isHexDigit }) else { return nil }
        var bytes = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        guard bytes.count == 16 || (bytes.first == 0xdd && bytes.count == 17) || (bytes.first == 0xee && bytes.count > 17) else { return nil }
        return bytes
    }

    private final class Pool {
        weak var context: AccountContext?
        let statuses: ProxyServersStatuses
        var disposable: Disposable?
        var values: [ProxyServerSettings: ProxyServerStatus] = [:]
        private var lastChange = Date.distantPast
        init(context: AccountContext) {
            self.context = context
            let settings = context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
            |> map { view -> ProxySettings in view.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings }
            self.statuses = ProxyServersStatuses(network: context.account.network, servers: settings |> map { Array($0.servers.prefix(20)) })
            self.disposable = (combineLatest(settings, statuses.statuses()) |> deliverOnMainQueue).start(next: { [weak self] settings, values in
                guard let self, let context = self.context else { return }
                self.values = values
                guard LitvinPolicy.options.proxyPool, Date().timeIntervalSince(self.lastChange) > 60 else { return }
                if let active = settings.activeServer, settings.enabled {
                    switch values[active] { case .available?, .checking?: return; default: break }
                }
                let available = values.compactMap { server, status -> (ProxyServerSettings, Double)? in
                    if case let .available(rtt) = status { return (server, rtt) }; return nil
                }.sorted { $0.1 < $1.1 }
                guard let server = available.first?.0 else { return }
                self.lastChange = Date()
                let _ = updateProxySettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
                    guard current.servers.contains(server) else { return current }
                    var updated = current; updated.enabled = true; updated.activeServer = server; return updated
                }).startStandalone()
            })
        }
        deinit { disposable?.dispose() }
    }
}

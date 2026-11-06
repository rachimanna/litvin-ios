import Foundation
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import AccountContext
import TelegramCore
import SwiftSignalKit
import LitvinCore

final class LitvinRowsController: UITableViewController {
    struct Row {
        let title: String
        let detail: String
        let action: () -> Void
    }
    var rows: [Row] = []
    var refresh: (() -> [Row])?
    var documentHandler: ((URL) -> Void)?
    private var observer: NSObjectProtocol?

    init(title: String, rows: [Row] = []) {
        super.init(style: .insetGrouped)
        self.title = title
        self.rows = rows
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        observer = NotificationCenter.default.addObserver(forName: LitvinArchive.changed, object: nil, queue: .main) { [weak self] _ in self?.reload() }
        reload()
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    func reload() { if let refresh { rows = refresh() }; tableView.reloadData() }
    @objc private func close() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        let row = rows[indexPath.row]
        cell.textLabel?.text = row.title
        cell.detailTextLabel?.text = row.detail
        cell.detailTextLabel?.numberOfLines = 3
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        rows[indexPath.row].action()
    }
}

extension LitvinRowsController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        documentHandler?(url)
    }
}

public enum LitvinTools {
    private static var lifecycleObserver: NSObjectProtocol?
    public static func initialize(context: AccountContext) {
        if lifecycleObserver == nil {
            lifecycleObserver = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in LitvinProtection.concealAll() }
        }
        LitvinProxyPool.start(context: context)
    }
    static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
              var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        while let next = top.presentedViewController { top = next }
        return top
    }
    static func present(_ controller: UIViewController) {
        topController()?.present(controller, animated: true)
    }
    static func list(_ controller: LitvinRowsController) { present(UINavigationController(rootViewController: controller)) }
    static func info(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert)
    }
    static func prompt(_ title: String, message: String = "", fields: [(String, String, Bool)], save: @escaping ([String]) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for field in fields {
            alert.addTextField { text in
                text.placeholder = field.0
                text.text = field.1
                text.isSecureTextEntry = field.2
                text.autocorrectionType = .no
                text.autocapitalizationType = .none
            }
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { _ in
            save(alert.textFields?.map { $0.text ?? "" } ?? [])
        }))
        present(alert)
    }
    static func failure(_ error: Error) {
        if let error = error as? LitvinProtectionError {
            switch error {
            case .cooldown: info("Подожди минуту", "Слишком много неверных попыток."); return
            case .invalidPIN: info("Не удалось открыть", "Проверь PIN или пароль и попробуй снова."); return
            default: break
            }
        }
        info("Не удалось выполнить действие", String(describing: error))
    }
    static func date(_ timestamp: Double) -> String {
        DateFormatter.localizedString(from: Date(timeIntervalSince1970: timestamp), dateStyle: .short, timeStyle: .short)
    }

    static func open(_ key: String, context: AccountContext) {
        let account = context.account.peerId.toInt64()
        let store = LitvinArchive.forAccount(account)
        switch key {
        case "schedule": schedule()
        case "deleted": records(title: "Удалённые сообщения", account: account, source: { store.snapshot().messages.values.filter { $0.deleted }.sorted { $0.timestamp > $1.timestamp } })
        case "edits": records(title: "История правок", account: account, source: { store.snapshot().edits.values.flatMap { $0 }.sorted { $0.capturedAt > $1.capturedAt } })
        case "notes": notes(account: account)
        case "channels": channels(account: account)
        case "digest": records(title: "Дайджест", account: account, source: { store.digest() })
        case "contacts": contacts(account: account)
        case "hidden": hidden(account: account)
        case "vault": LitvinBackup.show(context: context, vault: true)
        case "backup": LitvinBackup.show(context: context, vault: false)
        case "proxies": LitvinProxyPool.show(context: context)
        default: info("Litvin \(litvinVersion)", "Данные хранятся на этом устройстве отдельно для каждого аккаунта. История начинается после включения записи. ИИ отсутствует.\n\nРасписание онлайн действует, пока приложение запущено. Изменения рекламы и защиты экрана применяются при повторном открытии чата.")
        }
    }

    static func schedule() {
        let o = LitvinPolicy.options
        func time(_ value: Int) -> String { String(format: "%02d:%02d", value / 60, value % 60) }
        prompt("Расписание", message: "По местному времени. Онлайн по расписанию работает, пока приложение запущено. Призрак имеет приоритет.", fields: [("Призрак с ЧЧ:ММ", time(o.ghostStartMinute), false), ("Призрак до ЧЧ:ММ", time(o.ghostEndMinute), false), ("Онлайн с ЧЧ:ММ", time(o.alibiStartMinute), false), ("Онлайн до ЧЧ:ММ", time(o.alibiEndMinute), false)]) { values in
            let times = values.compactMap { value -> Int? in
                let parts = value.split(separator: ":")
                guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
                return h * 60 + m
            }
            guard times.count == 4 else { info("Неверное время", "Введи время в формате ЧЧ:ММ."); return }
            LitvinPolicy.update { $0.ghostStartMinute = times[0]; $0.ghostEndMinute = times[1]; $0.alibiStartMinute = times[2]; $0.alibiEndMinute = times[3] }
        }
    }

    static func records(title: String, account: Int64, source: @escaping () -> [LitvinMessageRecord]) {
        let controller = LitvinRowsController(title: title)
        controller.refresh = {
            let messages = source()
            if messages.isEmpty { return [.init(title: "Пока пусто", detail: "Записываются сообщения, доступные клиенту после включения функции.", action: {})] }
            return messages.prefix(500).map { record in
                .init(title: "\(record.peerTitle.isEmpty ? String(record.peer) : record.peerTitle) • \(date(Double(record.timestamp)))", detail: record.text.isEmpty ? "Медиа без текста" : record.text, action: {
                    info("Сообщение \(record.message)", record.text)
                })
            }
        }
        list(controller)
    }

    public static func editNote(account: Int64, peer: Int64, namespace: Int32, message: Int32) {
        let store = LitvinArchive.forAccount(account)
        let key = "\(peer):\(namespace):\(message)"
        let current = store.snapshot().notes[key]
        prompt("Личная заметка", message: "Видна только тебе на этом устройстве. Пустой текст удаляет заметку. Цвет: 0–5; напоминание — через N минут.", fields: [("Текст", current?.text ?? "", false), ("Метка", current?.tag ?? "", false), ("Цвет 0–5", String(current?.color ?? 0), false), ("Напомнить через минут", "", false)]) { values in
            guard values.count == 4 else { return }
            let identifier = "litvin.note.\(account).\(key)"
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            if values[0].isEmpty { store.setNote(key: key, note: nil); return }
            guard values[0].count <= 4000, values[1].count <= 100, let color = Int(values[2]), (0...5).contains(color), values[3].isEmpty || (Int(values[3]).map { (1...525600).contains($0) } ?? false) else { info("Проверь поля", "Текст до 4000 символов, метка до 100, цвет 0–5, положительное число минут."); return }
            let minutes = Int(values[3])
            let reminder = minutes.map { Date().timeIntervalSince1970 + Double($0 * 60) }
            store.setNote(key: key, note: LitvinMessageNote(text: values[0], tag: values[1], color: color, reminder: reminder))
            if let minutes {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { DispatchQueue.main.async { info("Заметка сохранена", "Для напоминаний разреши уведомления в настройках iOS.") }; return }
                    let content = UNMutableNotificationContent()
                    content.title = "Litvin: личное напоминание"
                    content.body = "Открой свои заметки в настройках Litvin."
                    content.sound = .default
                    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes * 60), repeats: false)))
                }
            }
        }
    }

    static func notes(account: Int64) {
        let controller = LitvinRowsController(title: "Мои заметки")
        controller.refresh = {
            let state = LitvinArchive.forAccount(account).snapshot()
            return state.notes.sorted { $0.key < $1.key }.map { key, note in
                .init(title: note.tag.isEmpty ? key : "\(note.tag) • \(key)", detail: note.text, action: {
                    let parts = key.split(separator: ":")
                    if parts.count == 3, let peer = Int64(parts[0]), let namespace = Int32(parts[1]), let message = Int32(parts[2]) { editNote(account: account, peer: peer, namespace: namespace, message: message) }
                })
            }
        }
        list(controller)
    }

    static func channels(account: Int64) {
        let controller = LitvinRowsController(title: "Каналы дайджеста")
        let store = LitvinArchive.forAccount(account)
        controller.refresh = {
            let state = store.snapshot()
            let groups = Dictionary(grouping: state.messages.values.filter { $0.channel }, by: { $0.peer })
            return groups.keys.sorted().map { peer in
                let selected = state.digestPeers.contains(peer)
                return .init(title: "\(selected ? "✓ " : "")\(groups[peer]?.first?.peerTitle ?? String(peer))", detail: "\(groups[peer]?.count ?? 0) сохранённых сообщений", action: {
                    var peers = Set(store.snapshot().digestPeers)
                    if peers.contains(peer) { peers.remove(peer) } else { peers.insert(peer) }
                    store.setDigestPeers(Array(peers))
                })
            }
        }
        list(controller)
    }

    static func contacts(account: Int64) {
        let controller = LitvinRowsController(title: "Статистика общения")
        controller.refresh = {
            let state = LitvinArchive.forAccount(account).snapshot()
            let groups = Dictionary(grouping: state.messages.values.filter { !$0.channel }, by: { $0.peer })
            return groups.keys.sorted().map { peer in
                let messages = (groups[peer] ?? []).sorted { $0.timestamp < $1.timestamp }
                let sent = messages.filter { $0.outgoing }.count
                var delays: [Int32] = []
                var pendingIncoming: Int32?
                for message in messages {
                    if message.outgoing, let incoming = pendingIncoming {
                        if message.timestamp >= incoming { delays.append(message.timestamp - incoming) }
                        pendingIncoming = nil
                    } else if !message.outgoing && pendingIncoming == nil { pendingIncoming = message.timestamp }
                }
                let median = delays.sorted().dropFirst(delays.count / 2).first
                let detail = "Отправлено: \(sent), получено: \(messages.count - sent). Медиана твоего ответа: \(median.map { String($0 / 60) + " мин" } ?? "нет данных"). Только локально наблюдавшиеся сообщения."
                return .init(title: messages.last?.peerTitle ?? String(peer), detail: detail, action: {
                    records(title: "Хронология общения", account: account, source: { Array(messages.reversed()) })
                })
            }
        }
        list(controller)
    }

    static func hidden(account: Int64) {
        let controller = LitvinRowsController(title: "Скрытые чаты")
        let store = LitvinArchive.forAccount(account)
        func choosePeers() {
            controller.refresh = {
                let groups = Dictionary(grouping: store.snapshot().messages.values, by: { $0.peer })
                let selected = LitvinProtection.hiddenPeers(account: account)
                return groups.keys.sorted().map { peer in
                    .init(title: "\(selected.contains(peer) ? "✓ " : "")\(groups[peer]?.first?.peerTitle ?? String(peer))", detail: String(peer), action: {
                        var peers = LitvinProtection.hiddenPeers(account: account)
                        if peers.contains(peer) { peers.remove(peer) } else { peers.insert(peer) }
                        LitvinProtection.setHiddenPeers(account: account, peers: peers)
                        controller.reload()
                    })
                }
            }
            controller.reload()
        }
        controller.rows = [
            .init(title: "Настроить отдельный PIN", detail: "Не менее 6 символов. Не заменяет пароль Telegram.", action: {
                let setup = { prompt("Новый PIN скрытых чатов", fields: [("PIN", "", true), ("Повтори PIN", "", true)]) { values in
                    guard values.count == 2, values[0] == values[1] else { info("PIN не совпадают", "Попробуй ещё раз."); return }
                    do { try LitvinProtection.configure(account: account, pin: values[0]); info("PIN сохранён", "Чаты скрываются при блокировке раздела и сворачивании приложения.") } catch { failure(error) }
                } }
                if LitvinProtection.configured(account: account) { authenticate(account: account, completion: setup) } else { setup() }
            }),
            .init(title: "Выбрать чаты", detail: "В списке — ранее открытые чаты с включённой локальной историей.", action: { authenticate(account: account, completion: choosePeers) }),
            .init(title: "Показать скрытые чаты", detail: "После PIN вернись в список чатов.", action: { authenticate(account: account, completion: { info("Разблокировано", "Вернись в список чатов. При сворачивании они снова скроются.") }) }),
            .init(title: "Скрыть сейчас", detail: "Выбранные чаты будут убраны из списка.", action: { LitvinProtection.conceal(account: account); info("Скрыто", "Вернись в список чатов.") }),
        ]
        list(controller)
    }
    static func authenticate(account: Int64, completion: @escaping () -> Void) {
        prompt("PIN скрытых чатов", fields: [("PIN", "", true)]) { values in
            guard let pin = values.first else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                do { try LitvinProtection.reveal(account: account, pin: pin); DispatchQueue.main.async(execute: completion) }
                catch { DispatchQueue.main.async { failure(error) } }
            }
        }
    }

    public static func showMessageHistory(account: Int64, peer: Int64, namespace: Int32, message: Int32) {
        let key = "\(peer):\(namespace):\(message)"
        let store = LitvinArchive.forAccount(account)
        records(title: "История сообщения", account: account, source: { (store.snapshot().edits[key] ?? []) + [store.snapshot().messages[key]].compactMap { $0 } })
    }

    public static func showFakeGift(in view: UIView) {
        let picker = UIAlertController(title: "Локальный подарок", message: "Демонстрация только на твоём экране. Ничего не отправляется и не оплачивается.", preferredStyle: .actionSheet)
        for emoji in ["🎂", "⭐️", "❤️", "🏆", "🎉"] {
            picker.addAction(UIAlertAction(title: emoji, style: .default, handler: { _ in
                let button = UIButton(type: .system)
                button.setTitle("\(emoji)  Локальный подарок\nТолько на этом экране • нажми, чтобы убрать", for: .normal)
                button.titleLabel?.numberOfLines = 2
                button.titleLabel?.textAlignment = .center
                button.backgroundColor = .secondarySystemBackground
                button.layer.cornerRadius = 16
                button.translatesAutoresizingMaskIntoConstraints = false
                button.addAction(UIAction { [weak button] _ in button?.removeFromSuperview() }, for: .touchUpInside)
                view.addSubview(button)
                NSLayoutConstraint.activate([button.centerXAnchor.constraint(equalTo: view.centerXAnchor), button.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80), button.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -32), button.heightAnchor.constraint(equalToConstant: 90)])
            }))
        }
        picker.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        picker.popoverPresentationController?.sourceView = view
        picker.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(picker)
    }
}

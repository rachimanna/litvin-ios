import Foundation
import JavaScriptCore
import Display
import AccountContext
import PresentationDataUtils

// Litvin plugins: small JavaScript files run by iOS JavaScriptCore.
//
// A plugin is a .js file with a header:
//
//   // @name        Shrug
//   // @description .shrug sends ¯\_(ツ)_/¯
//   // @author      Litvin
//   // @version     1.0
//
//   litvin.command("shrug", "Пожать плечами", function (args) {
//       return (args ? args + " " : "") + "¯\\_(ツ)_/¯";
//   });
//
//   litvin.onOutgoingMessage(function (text) {
//       return text.replace(/:\)/g, "😊");   // return a string to change the text,
//   });                                      // null to cancel sending, nothing to keep it.
//
// API: litvin.command(name, description, fn), litvin.onOutgoingMessage(fn),
// litvin.storage.get(key) / litvin.storage.set(key, value), litvin.log(...).
// Plugins have no access to files, network or the account: only to the text
// of messages you send.
//
// AyuGram / exteraGram plugins are Python scripts for Android Telegram and
// cannot run on iOS; they are recognised and explained instead of installed.

public struct LitvinPluginInfo: Codable, Equatable {
    public var id: String
    public var name: String
    public var description: String
    public var author: String
    public var version: String
    public var enabled: Bool
    public var fileName: String
    public var commands: [String]
}

public enum LitvinPluginFile {
    case litvin(LitvinPluginInfo, source: String)
    case android(name: String, description: String, author: String, version: String)
    case unknown
}

public func litvinIsPluginFileName(_ fileName: String) -> Bool {
    let lower = fileName.lowercased()
    return lower.hasSuffix(".litvin.js") || lower.hasSuffix(".litvin") || lower.hasSuffix(".litvinplugin") || lower.hasSuffix(".plugin") || lower.hasSuffix(".js")
}

private func litvinHeaderValue(_ source: String, _ key: String) -> String? {
    for line in source.components(separatedBy: .newlines).prefix(60) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("//") else {
            continue
        }
        let body = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
        if body.hasPrefix("@" + key) {
            let value = body.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty {
                return value
            }
        }
    }
    return nil
}

private func litvinPythonValue(_ source: String, _ key: String) -> String? {
    let pattern = "^\\s*" + NSRegularExpression.escapedPattern(for: key) + "\\s*=\\s*[\"']([^\"']*)[\"']"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
        return nil
    }
    let range = NSRange(source.startIndex..., in: source)
    if let match = regex.firstMatch(in: source, options: [], range: range), let valueRange = Range(match.range(at: 1), in: source) {
        return String(source[valueRange])
    }
    return nil
}

public func litvinParsePluginFile(source: String, fileName: String) -> LitvinPluginFile {
    let isPython = source.contains("from base_plugin import") || source.contains("BasePlugin") || litvinPythonValue(source, "__id__") != nil
    if isPython {
        return .android(
            name: litvinPythonValue(source, "__name__") ?? fileName,
            description: litvinPythonValue(source, "__description__") ?? "",
            author: litvinPythonValue(source, "__author__") ?? "",
            version: litvinPythonValue(source, "__version__") ?? ""
        )
    }
    guard source.contains("litvin.") else {
        return .unknown
    }
    var baseName = fileName
    for suffix in [".litvin.js", ".litvinplugin", ".litvin", ".plugin", ".js"] where baseName.lowercased().hasSuffix(suffix) {
        baseName = String(baseName.dropLast(suffix.count))
        break
    }
    let name = litvinHeaderValue(source, "name") ?? baseName
    let rawId = litvinHeaderValue(source, "id") ?? name
    let id = rawId.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
    let info = LitvinPluginInfo(
        id: id.isEmpty ? UUID().uuidString : id,
        name: name,
        description: litvinHeaderValue(source, "description") ?? "",
        author: litvinHeaderValue(source, "author") ?? "",
        version: litvinHeaderValue(source, "version") ?? "1.0",
        enabled: true,
        fileName: fileName,
        commands: []
    )
    return .litvin(info, source: source)
}

private final class LitvinPluginRuntime {
    let id: String
    let context: JSContext
    private(set) var commands: [String: JSValue] = [:]
    private(set) var commandNames: [String] = []
    private var outgoingHandlers: [JSValue] = []

    init?(id: String, source: String) {
        guard let context = JSContext() else {
            return nil
        }
        self.id = id
        self.context = context
        context.name = "Litvin plugin \(id)"
        context.exceptionHandler = { _, exception in
            NSLog("[Litvin plugin \(id)] %@", exception?.toString() ?? "error")
        }

        guard let api = JSValue(newObjectIn: context), let storage = JSValue(newObjectIn: context) else {
            return nil
        }
        let command: @convention(block) (JSValue, JSValue, JSValue) -> Void = { [weak self] name, second, third in
            guard let self, name.isString, let rawName = name.toString() else {
                return
            }
            let key = rawName.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". /"))
            let handler = second.isObject && !second.isString ? second : third
            guard !key.isEmpty, handler.isObject else {
                return
            }
            if self.commands[key] == nil {
                self.commandNames.append(key)
            }
            self.commands[key] = handler
        }
        let onOutgoing: @convention(block) (JSValue) -> Void = { [weak self] handler in
            guard let self, handler.isObject else {
                return
            }
            self.outgoingHandlers.append(handler)
        }
        let log: @convention(block) () -> Void = {
            let args = JSContext.currentArguments()?.compactMap { ($0 as? JSValue)?.toString() } ?? []
            NSLog("[Litvin plugin \(id)] %@", args.joined(separator: " "))
        }
        let storageGet: @convention(block) (String) -> Any? = { key in
            return UserDefaults.standard.object(forKey: "litvin.plugin.\(id).\(key)")
        }
        let storageSet: @convention(block) (String, JSValue) -> Void = { key, value in
            let defaultsKey = "litvin.plugin.\(id).\(key)"
            if value.isUndefined || value.isNull {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            } else if value.isNumber {
                UserDefaults.standard.set(value.toDouble(), forKey: defaultsKey)
            } else if value.isBoolean {
                UserDefaults.standard.set(value.toBool(), forKey: defaultsKey)
            } else {
                UserDefaults.standard.set(value.toString() ?? "", forKey: defaultsKey)
            }
        }
        api.setObject(unsafeBitCast(command, to: AnyObject.self), forKeyedSubscript: "command" as NSString)
        api.setObject(unsafeBitCast(onOutgoing, to: AnyObject.self), forKeyedSubscript: "onOutgoingMessage" as NSString)
        api.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
        storage.setObject(unsafeBitCast(storageGet, to: AnyObject.self), forKeyedSubscript: "get" as NSString)
        storage.setObject(unsafeBitCast(storageSet, to: AnyObject.self), forKeyedSubscript: "set" as NSString)
        api.setObject(storage, forKeyedSubscript: "storage" as NSString)
        api.setObject("1.0", forKeyedSubscript: "version" as NSString)
        context.setObject(api, forKeyedSubscript: "litvin" as NSString)
        context.evaluateScript("var console = { log: litvin.log, warn: litvin.log, error: litvin.log };")

        context.evaluateScript(source)
    }

    // nil = cancel sending.
    func transform(_ text: String) -> String? {
        var current = text
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix(".") {
            let body = trimmed.dropFirst()
            let parts = body.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            if let first = parts.first {
                let name = first.lowercased()
                if let handler = self.commands[name] {
                    let args = parts.count > 1 ? String(parts[1]) : ""
                    let result = handler.call(withArguments: [args])
                    if let result, result.isString, let value = result.toString() {
                        current = value
                    } else if result == nil || result!.isNull || result!.isUndefined {
                        return nil
                    }
                }
            }
        }
        for handler in self.outgoingHandlers {
            guard let result = handler.call(withArguments: [current]) else {
                continue
            }
            if result.isNull {
                return nil
            }
            if result.isString, let value = result.toString() {
                current = value
            }
        }
        return current
    }
}

public final class LitvinPluginManager {
    public static let shared = LitvinPluginManager()

    private static let indexKey = "litvin.plugins.index"
    public static let didChangeNotification = Notification.Name("LitvinPluginsChanged")

    public private(set) var plugins: [LitvinPluginInfo] = []
    private var runtimes: [String: LitvinPluginRuntime] = [:]
    private var loaded = false

    private init() {
    }

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let url = base.appendingPathComponent("Litvin/Plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceURL(_ id: String) -> URL {
        return self.directory.appendingPathComponent("\(id).js")
    }

    private func loadIfNeeded() {
        if self.loaded {
            return
        }
        self.loaded = true
        if let data = UserDefaults.standard.data(forKey: LitvinPluginManager.indexKey), let list = try? JSONDecoder().decode([LitvinPluginInfo].self, from: data) {
            self.plugins = list
        }
        for plugin in self.plugins where plugin.enabled {
            self.startRuntime(plugin.id)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(self.plugins) {
            UserDefaults.standard.set(data, forKey: LitvinPluginManager.indexKey)
        }
        NotificationCenter.default.post(name: LitvinPluginManager.didChangeNotification, object: nil)
    }

    private func startRuntime(_ id: String) {
        guard let source = try? String(contentsOf: self.sourceURL(id), encoding: .utf8), let runtime = LitvinPluginRuntime(id: id, source: source) else {
            return
        }
        self.runtimes[id] = runtime
        if let index = self.plugins.firstIndex(where: { $0.id == id }) {
            self.plugins[index].commands = runtime.commandNames
        }
    }

    public func allPlugins() -> [LitvinPluginInfo] {
        self.loadIfNeeded()
        return self.plugins
    }

    @discardableResult
    public func install(_ info: LitvinPluginInfo, source: String) -> Bool {
        self.loadIfNeeded()
        do {
            try source.write(to: self.sourceURL(info.id), atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        var info = info
        info.enabled = true
        if let index = self.plugins.firstIndex(where: { $0.id == info.id }) {
            self.plugins[index] = info
        } else {
            self.plugins.append(info)
        }
        self.runtimes[info.id] = nil
        self.startRuntime(info.id)
        self.save()
        return true
    }

    public func setEnabled(_ id: String, _ enabled: Bool) {
        self.loadIfNeeded()
        guard let index = self.plugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        self.plugins[index].enabled = enabled
        if enabled {
            self.startRuntime(id)
        } else {
            self.runtimes[id] = nil
        }
        self.save()
    }

    public func remove(_ id: String) {
        self.loadIfNeeded()
        self.runtimes[id] = nil
        self.plugins.removeAll(where: { $0.id == id })
        try? FileManager.default.removeItem(at: self.sourceURL(id))
        self.save()
    }

    /// Applies every enabled plugin to the text of an outgoing message.
    /// Returns nil when a plugin cancels sending.
    public func transformOutgoingText(_ text: String) -> String? {
        self.loadIfNeeded()
        if self.runtimes.isEmpty {
            return text
        }
        var current = text
        for plugin in self.plugins where plugin.enabled {
            guard let runtime = self.runtimes[plugin.id] else {
                continue
            }
            guard let result = runtime.transform(current) else {
                return nil
            }
            current = result
        }
        return current
    }
}

// Example plugin shipped with Litvin ("Установить пример" in the plugins screen).
public let litvinExamplePluginSource = #"""
// @name        Litvin Tools
// @description Команды .shrug .time .flip .mock и автозамена :) → 😊
// @author      Litvin
// @version     1.0

litvin.command("shrug", "Пожать плечами", function (args) {
    return (args ? args + " " : "") + "¯\\_(ツ)_/¯";
});

litvin.command("time", "Текущее время", function () {
    var d = new Date();
    function two(n) { return (n < 10 ? "0" : "") + n; }
    return "🕒 " + two(d.getHours()) + ":" + two(d.getMinutes());
});

litvin.command("flip", "Перевернуть текст", function (args) {
    return args.split("").reverse().join("");
});

litvin.command("mock", "ТаКоЙ ТеКсТ", function (args) {
    var out = "";
    for (var i = 0; i < args.length; i++) {
        out += i % 2 ? args[i].toLowerCase() : args[i].toUpperCase();
    }
    return out;
});

litvin.onOutgoingMessage(function (text) {
    return text.replace(/:\)/g, "😊").replace(/:\(/g, "😔").replace(/<3/g, "❤️");
});
"""#

/// The "launch this plugin in Litvin" window shown when a plugin file is opened.
public func litvinPluginInstallController(context: AccountContext, source: String, fileName: String, installed: @escaping (LitvinPluginInfo) -> Void) -> ViewController? {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    switch litvinParsePluginFile(source: source, fileName: fileName) {
    case let .litvin(info, source):
        var details: [String] = []
        if !info.description.isEmpty {
            details.append(info.description)
        }
        var meta: [String] = []
        if !info.author.isEmpty {
            meta.append("Автор: \(info.author)")
        }
        meta.append("Версия \(info.version)")
        details.append(meta.joined(separator: " · "))
        let exists = LitvinPluginManager.shared.allPlugins().contains(where: { $0.id == info.id })
        details.append(exists ? "Этот плагин уже установлен — он будет обновлён." : "Плагин работает только с текстом сообщений, которые ты отправляешь. Удалить его можно в Настройки → Litvin → Плагины.")
        return textAlertController(context: context, title: "🧩 \(info.name)", text: details.joined(separator: "\n\n"), actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: exists ? "Обновить" : "Запустить в Litvin", action: {
                if LitvinPluginManager.shared.install(info, source: source) {
                    installed(info)
                }
            })
        ], actionLayout: .vertical)
    case let .android(name, description, author, version):
        var text = "Это плагин для Android-клиентов (AyuGram, exteraGram). Он написан на Python и вызывает код Android-версии Telegram, поэтому на iPhone он работать не может.\n\nLitvin поддерживает свои плагины на JavaScript — их можно добавить в Настройки → Litvin → Плагины."
        let meta = [description, author.isEmpty ? "" : "Автор: \(author)", version.isEmpty ? "" : "Версия \(version)"].filter { !$0.isEmpty }
        if !meta.isEmpty {
            text = meta.joined(separator: "\n") + "\n\n" + text
        }
        return textAlertController(context: context, title: "🤖 \(name)", text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ])
    case .unknown:
        return nil
    }
}

import Foundation

public struct LitvinMessageRecord: Codable, Equatable {
    public var account: Int64
    public var peer: Int64
    public var namespace: Int32
    public var message: Int32
    public var author: Int64?
    public var timestamp: Int32
    public var text: String
    public var outgoing: Bool
    public var channel: Bool
    public var peerTitle: String
    public var deleted: Bool
    public var capturedAt: Double

    public var key: String { "\(peer):\(namespace):\(message)" }
    public init(account: Int64, peer: Int64, namespace: Int32, message: Int32, author: Int64?, timestamp: Int32, text: String, outgoing: Bool, channel: Bool, peerTitle: String, deleted: Bool = false) {
        self.account = account
        self.peer = peer
        self.namespace = namespace
        self.message = message
        self.author = author
        self.timestamp = timestamp
        self.text = text
        self.outgoing = outgoing
        self.channel = channel
        self.peerTitle = peerTitle
        self.deleted = deleted
        self.capturedAt = Date().timeIntervalSince1970
    }
}

public struct LitvinMessageNote: Codable, Equatable {
    public var text: String
    public var tag: String
    public var color: Int
    public var reminder: Double?
    public init(text: String, tag: String = "", color: Int = 0, reminder: Double? = nil) {
        self.text = text
        self.tag = tag
        self.color = color
        self.reminder = reminder
    }
}

public struct LitvinPresenceEvent: Codable {
    public let peer: Int64
    public let timestamp: Double
    public let online: Bool
}

public struct LitvinLocalState: Codable {
    public var version = 1
    public var account: Int64
    public var messages: [String: LitvinMessageRecord] = [:]
    public var edits: [String: [LitvinMessageRecord]] = [:]
    public var notes: [String: LitvinMessageNote] = [:]
    public var presences: [LitvinPresenceEvent] = []
    public var digestPeers: [Int64] = []
    public init(account: Int64) { self.account = account }
}

public final class LitvinArchive {
    public static let changed = Notification.Name("app.litvin.archiveChanged")
    private static let registryLock = NSLock()
    private static var stores: [Int64: LitvinArchive] = [:]
    public static func forAccount(_ account: Int64) -> LitvinArchive {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let store = stores[account] { return store }
        let store = LitvinArchive(account: account)
        stores[account] = store
        return store
    }

    private let queue: DispatchQueue
    private let file: URL
    private var state: LitvinLocalState
    private var pendingSave: DispatchWorkItem?
    public let account: Int64

    private init(account: Int64) {
        self.account = account
        self.queue = DispatchQueue(label: "app.litvin.archive.\(account)")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Litvin/\(account)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var protectedDirectory = directory
        try? protectedDirectory.setResourceValues(excluded)
        self.file = directory.appendingPathComponent("local-state.json")
        if let data = try? Data(contentsOf: self.file),
           let saved = try? JSONDecoder().decode(LitvinLocalState.self, from: data), saved.account == account, saved.version == 1 {
            self.state = saved
        } else {
            self.state = LitvinLocalState(account: account)
        }
    }

    public func snapshot() -> LitvinLocalState { queue.sync { state } }

    public func observe(_ record: LitvinMessageRecord) {
        guard record.account == account else { return }
        let vault = LitvinPrivateArchive.forAccount(account)
        if vault.isProtected(record.peer) { vault.observe(record); return }
        let options = LitvinPolicy.options
        guard options.saveDeleted || options.saveEditHistory || options.channelDigest || options.contactProfile else { return }
        queue.async {
            if let previous = self.state.messages[record.key], previous.text == record.text, previous.deleted == record.deleted { return }
            var captured = record
            if self.state.messages[record.key]?.deleted == true { captured.deleted = true }
            self.state.messages[record.key] = captured
            self.trim()
            self.saveSoon()
        }
    }

    public func beforeEdit(_ record: LitvinMessageRecord) {
        guard record.account == account else { return }
        let vault = LitvinPrivateArchive.forAccount(account)
        if vault.isProtected(record.peer) { vault.observe(record, beforeEdit: true); return }
        guard LitvinPolicy.options.saveEditHistory else { return }
        queue.async {
            var history = self.state.edits[record.key] ?? []
            if history.last?.text != record.text {
                history.append(record)
                self.state.edits[record.key] = Array(history.suffix(50))
                self.trim()
                self.saveSoon()
            }
        }
    }

    public func markDeleted(peer: Int64?, namespace: Int32? = nil, ids: [Int32]) {
        LitvinPrivateArchive.forAccount(account).markDeleted(peer: peer, namespace: namespace, ids: ids)
        guard LitvinPolicy.options.saveDeleted else { return }
        queue.async {
            let ids = Set(ids)
            for key in Array(self.state.messages.keys) {
                guard var record = self.state.messages[key], ids.contains(record.message),
                      peer != nil || !record.channel,
                      peer == nil || record.peer == peer,
                      namespace == nil || record.namespace == namespace else { continue }
                record.deleted = true
                self.state.messages[key] = record
            }
            self.saveSoon()
        }
    }

    public func setNote(key: String, note: LitvinMessageNote?) {
        if let component = key.split(separator: ":").first, let peer = Int64(component), LitvinPrivateArchive.forAccount(account).isProtected(peer) {
            LitvinPrivateArchive.forAccount(account).note(peer: peer, key: key, value: note)
            return
        }
        queue.async {
            if let note, (note.text.count > 4000 || note.tag.count > 100 || !(0...5).contains(note.color)) { return }
            if note != nil && self.state.notes[key] == nil && self.state.notes.count >= 5000 { return }
            self.state.notes[key] = note
            self.saveSoon()
        }
    }

    public func setDigestPeers(_ peers: [Int64]) {
        queue.async {
            self.state.digestPeers = Array(Set(peers)).sorted()
            self.saveSoon()
        }
    }

    public func observePresence(peer: Int64, online: Bool) {
        guard LitvinPolicy.options.contactProfile else { return }
        queue.async {
            if self.state.presences.last(where: { $0.peer == peer })?.online == online { return }
            self.state.presences.append(LitvinPresenceEvent(peer: peer, timestamp: Date().timeIntervalSince1970, online: online))
            self.state.presences = Array(self.state.presences.suffix(5000))
            self.saveSoon()
        }
    }

    public func digest() -> [LitvinMessageRecord] {
        let state = snapshot()
        let peers = Set(state.digestPeers)
        return state.messages.values.filter { $0.channel && !$0.deleted && peers.contains($0.peer) }
            .sorted { a, b in
                // A small length bonus keeps useful posts ahead of one-line updates.
                let scoreA = Double(a.timestamp) + Double(min(a.text.count, 1000)) * 2
                let scoreB = Double(b.timestamp) + Double(min(b.text.count, 1000)) * 2
                return scoreA == scoreB ? a.key < b.key : scoreA > scoreB
            }.prefix(200).map { $0 }
    }

    public func exportData() throws -> Data { try JSONEncoder().encode(snapshot()) }

    public func importData(_ data: Data) throws {
        guard data.count <= 20 * 1024 * 1024 else { throw LitvinArchiveError.tooLarge }
        let imported = try JSONDecoder().decode(LitvinLocalState.self, from: data)
        guard imported.version == 1, imported.account == account,
              imported.messages.count <= 5000, imported.notes.count <= 5000,
              imported.edits.count <= 5000, imported.presences.count <= 5000 else { throw LitvinArchiveError.invalidBackup }
        guard imported.messages.allSatisfy({ $0.key == $0.value.key && $0.value.account == account }),
              imported.edits.values.allSatisfy({ $0.count <= 50 && $0.allSatisfy { $0.account == account } }) else { throw LitvinArchiveError.invalidBackup }
        guard imported.messages.values.allSatisfy({ $0.text.count <= 16384 }),
              imported.edits.values.reduce(0, { $0 + $1.count }) <= 5000,
              imported.notes.values.allSatisfy({ $0.text.count <= 4000 && $0.tag.count <= 100 && (0...5).contains($0.color) }) else { throw LitvinArchiveError.invalidBackup }
        queue.sync {
            state = imported
            saveSoon()
        }
    }

    public func clear() {
        queue.sync {
            state = LitvinLocalState(account: account)
            pendingSave?.cancel()
            try? FileManager.default.removeItem(at: file)
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    public func moveToPrivateArchive(peer: Int64, passphrase: String) throws {
        try queue.sync {
            var selected = LitvinLocalState(account: account)
            selected.messages = state.messages.filter { $0.value.peer == peer }
            selected.edits = state.edits.filter { $0.key.hasPrefix("\(peer):") }
            selected.notes = state.notes.filter { $0.key.hasPrefix("\(peer):") }
            let vault = LitvinPrivateArchive.forAccount(account)
            try vault.create(peer: peer, passphrase: passphrase, state: selected)
            do {
                var remaining = state
                remaining.messages = remaining.messages.filter { $0.value.peer != peer }
                remaining.edits = remaining.edits.filter { !$0.key.hasPrefix("\(peer):") }
                remaining.notes = remaining.notes.filter { !$0.key.hasPrefix("\(peer):") }
                try JSONEncoder().encode(remaining).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                state = remaining
            } catch {
                try? vault.rollbackNewArchive(peer: peer)
                throw error
            }
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    private func trim() {
        if state.messages.count > 5000 {
            let keep = Set(state.messages.values.sorted { $0.capturedAt > $1.capturedAt }.prefix(5000).map { $0.key })
            state.messages = state.messages.filter { keep.contains($0.key) }
            state.edits = state.edits.filter { keep.contains($0.key) }
        }
        if state.edits.count > 5000 {
            state.edits = Dictionary(uniqueKeysWithValues: state.edits.sorted { $0.key < $1.key }.prefix(5000).map { ($0.key, $0.value) })
        }
        var versions = state.edits.values.reduce(0) { $0 + $1.count }
        if versions > 5000 {
            let oldest = state.edits.sorted { ($0.value.last?.capturedAt ?? 0) < ($1.value.last?.capturedAt ?? 0) }
            for (key, records) in oldest where versions > 5000 {
                state.edits.removeValue(forKey: key)
                versions -= records.count
            }
        }
    }

    private func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let data = try? JSONEncoder().encode(self.state) else { return }
            do {
                try data.write(to: self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
            } catch {
                NSLog("Litvin local archive could not be saved: %@", String(describing: error))
            }
        }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

public enum LitvinArchiveError: Error { case tooLarge, invalidBackup }

import Foundation

/// Encrypts Litvin's own local text archive. Telegram's Postbox is independent.
public final class LitvinPrivateArchive {
    private static let registryLock = NSLock()
    private static var instances: [Int64: LitvinPrivateArchive] = [:]
    public static func forAccount(_ account: Int64) -> LitvinPrivateArchive {
        registryLock.lock()
        defer { registryLock.unlock() }
        if let value = instances[account] { return value }
        let value = LitvinPrivateArchive(account: account)
        instances[account] = value
        return value
    }
    public static func lockAll() {
        registryLock.lock()
        let values = Array(instances.values)
        registryLock.unlock()
        for value in values { value.lockAllPeers() }
    }

    public let account: Int64
    private let directory: URL
    private let lock = NSRecursiveLock()
    private let queue = DispatchQueue(label: "app.litvin.private-archive-writer")
    private var protected = Set<Int64>()
    private var sessions: [Int64: LitvinVault.Session] = [:]
    private var contents: [Int64: LitvinLocalState] = [:]
    private var pending: [Int64: DispatchWorkItem] = [:]
    private var dirty = Set<Int64>()

    private init(account: Int64) {
        self.account = account
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Litvin/\(account)/vault", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var url = directory; try? url.setResourceValues(values)
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if url.pathExtension == "litvin", let peer = Int64(url.deletingPathExtension().lastPathComponent) { protected.insert(peer) }
        }
    }
    private func file(_ peer: Int64) -> URL { directory.appendingPathComponent("\(peer).litvin") }
    public var peers: [Int64] { lock.lock(); defer { lock.unlock() }; return protected.sorted() }
    public func isProtected(_ peer: Int64) -> Bool { lock.lock(); defer { lock.unlock() }; return protected.contains(peer) }
    public func snapshot(peer: Int64) -> LitvinLocalState? { lock.lock(); defer { lock.unlock() }; return contents[peer] }

    public func create(peer: Int64, passphrase: String, state: LitvinLocalState) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !protected.contains(peer), state.account == account,
              state.messages.values.allSatisfy({ $0.peer == peer && $0.account == account }) else { throw LitvinProtectionError.invalidData }
        let session = try LitvinVault.newSession(account: account, passphrase: passphrase)
        let encrypted = try session.seal(JSONEncoder().encode(state))
        try encrypted.write(to: file(peer), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        protected.insert(peer)
        sessions[peer] = session
        contents[peer] = state
    }

    public func unlock(peer: Int64, passphrase: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let size = (try FileManager.default.attributesOfItem(atPath: file(peer).path)[.size] as? NSNumber)?.intValue ?? Int.max
        guard size <= 30 * 1024 * 1024 else { throw LitvinArchiveError.tooLarge }
        let (session, plain) = try LitvinVault.unlockSession(Data(contentsOf: file(peer)), account: account, passphrase: passphrase)
        let state = try JSONDecoder().decode(LitvinLocalState.self, from: plain)
        guard state.account == account, state.messages.count <= 5000,
              state.messages.values.allSatisfy({ $0.peer == peer && $0.account == account }) else { throw LitvinProtectionError.invalidData }
        sessions[peer] = session
        contents[peer] = state
    }

    public func observe(_ record: LitvinMessageRecord, beforeEdit: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        guard record.account == account, sessions[record.peer] != nil, var state = contents[record.peer] else { return }
        if beforeEdit {
            var history = state.edits[record.key] ?? []
            if history.last?.text != record.text { history.append(record) }
            state.edits[record.key] = Array(history.suffix(20))
        } else {
            if state.messages[record.key]?.text == record.text && state.messages[record.key]?.deleted == record.deleted { return }
            state.messages[record.key] = record
        }
        if state.messages.count > 1000 {
            let keep = Set(state.messages.values.sorted { $0.capturedAt > $1.capturedAt }.prefix(1000).map { $0.key })
            state.messages = state.messages.filter { keep.contains($0.key) }
            state.edits = state.edits.filter { keep.contains($0.key) }
        }
        var versions = state.edits.values.reduce(0) { $0 + $1.count }
        for key in state.edits.keys.sorted() where versions > 2000 {
            versions -= state.edits.removeValue(forKey: key)?.count ?? 0
        }
        contents[record.peer] = state
        saveSoon(record.peer)
    }

    public func markDeleted(peer: Int64?, namespace: Int32?, ids: [Int32]) {
        lock.lock()
        defer { lock.unlock() }
        let ids = Set(ids)
        for candidate in Array(contents.keys) where peer == nil || candidate == peer {
            guard var state = contents[candidate] else { continue }
            for key in Array(state.messages.keys) {
                guard var record = state.messages[key], ids.contains(record.message), peer != nil || !record.channel,
                      namespace == nil || namespace == record.namespace else { continue }
                record.deleted = true; state.messages[key] = record
            }
            contents[candidate] = state
            saveSoon(candidate)
        }
    }
    public func note(peer: Int64, key: String, value: LitvinMessageNote?) {
        lock.lock()
        defer { lock.unlock() }
        guard var state = contents[peer], sessions[peer] != nil else { return }
        state.notes[key] = value
        contents[peer] = state
        saveSoon(peer)
    }

    public func lockAllPeers() {
        lock.lock()
        defer { lock.unlock() }
        for peer in Array(sessions.keys) { try? flush(peer) }
        for item in pending.values { item.cancel() }
        pending.removeAll()
        contents.removeAll()
        sessions.removeAll()
        dirty.removeAll()
        DispatchQueue.main.async { NotificationCenter.default.post(name: LitvinArchive.changed, object: nil) }
    }

    public func encryptedFiles() throws -> [String: Data] {
        lock.lock()
        defer { lock.unlock() }
        for peer in sessions.keys { try flush(peer) }
        let size = try protected.reduce(0) { current, peer in
            current + ((try FileManager.default.attributesOfItem(atPath: file(peer).path)[.size] as? NSNumber)?.intValue ?? 0)
        }
        guard size <= 20 * 1024 * 1024 else { throw LitvinArchiveError.tooLarge }
        return try Dictionary(uniqueKeysWithValues: protected.map { (String($0), try Data(contentsOf: file($0))) })
    }

    public func importEncryptedFiles(_ files: [String: Data]) throws {
        lock.lock()
        defer { lock.unlock() }
        guard files.count <= 100, files.allSatisfy({ Int64($0.key) != nil && $0.value.count <= 20 * 1024 * 1024 }) else { throw LitvinArchiveError.invalidBackup }
        // The surrounding backup envelope is already authenticated before import.
        // Individual archives stay locked until their own passphrase is entered.
        lockAllPeers()
        for (key, data) in files {
            guard let peer = Int64(key) else { throw LitvinArchiveError.invalidBackup }
            try data.write(to: file(peer), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            protected.insert(peer)
        }
    }

    public func rollbackNewArchive(peer: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        pending[peer]?.cancel(); pending[peer] = nil
        try FileManager.default.removeItem(at: file(peer))
        sessions[peer] = nil; contents[peer] = nil; protected.remove(peer)
        dirty.remove(peer)
    }
    private func flush(_ peer: Int64) throws {
        guard dirty.contains(peer), let session = sessions[peer], let state = contents[peer] else { return }
        try session.seal(JSONEncoder().encode(state)).write(to: file(peer), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        dirty.remove(peer)
    }
    private func saveSoon(_ peer: Int64) {
        dirty.insert(peer)
        pending[peer]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }
            do { try self.flush(peer) }
            catch { NSLog("Litvin encrypted archive write failed: %@", String(describing: error)) }
            DispatchQueue.main.async { NotificationCenter.default.post(name: LitvinArchive.changed, object: nil) }
        }
        pending[peer] = work
        queue.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

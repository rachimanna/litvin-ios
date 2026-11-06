import Foundation
import CryptoKit
import CommonCrypto
import Security

public enum LitvinProtectionError: Error { case invalidPIN, notConfigured, invalidData, keychain(Int32), cooldown }

private struct LitvinPINRecord: Codable {
    let salt: Data
    let hash: Data
}

public enum LitvinProtection {
    private static let lock = NSRecursiveLock()
    private static var revealed = Set<Int64>()
    private static var failures: [Int64: (Int, Double)] = [:]
    private static let service = "app.litvin.private-chats.v1"

    public static func hiddenPeers(account: Int64) -> Set<Int64> {
        Set((UserDefaults.standard.array(forKey: "litvin.hidden.\(account)") as? [String] ?? []).compactMap(Int64.init))
    }
    public static func setHiddenPeers(account: Int64, peers: Set<Int64>) {
        UserDefaults.standard.set(peers.sorted().map(String.init), forKey: "litvin.hidden.\(account)")
        notify()
    }
    public static func shouldHide(account: Int64, peer: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !revealed.contains(account) && hiddenPeers(account: account).contains(peer)
    }
    public static func concealAll() {
        lock.lock()
        revealed.removeAll()
        lock.unlock()
        notify()
    }
    public static func conceal(account: Int64) {
        lock.lock()
        revealed.remove(account)
        lock.unlock()
        notify()
    }
    public static func configured(account: Int64) -> Bool { (try? read(account: account)) != nil }

    public static func configure(account: Int64, pin: String) throws {
        guard pin.count >= 6, pin.count <= 128 else { throw LitvinProtectionError.invalidPIN }
        let salt = try random(16)
        let record = LitvinPINRecord(salt: salt, hash: try derive(pin: pin, salt: salt))
        let data = try JSONEncoder().encode(record)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: String(account)]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(insert as CFDictionary, nil)
            guard result == errSecSuccess else { throw LitvinProtectionError.keychain(result) }
        } else if status != errSecSuccess { throw LitvinProtectionError.keychain(status) }
        conceal(account: account)
    }

    public static func reveal(account: Int64, pin: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if let failure = failures[account], failure.1 > ProcessInfo.processInfo.systemUptime { throw LitvinProtectionError.cooldown }
        let record = try read(account: account)
        let actual = try derive(pin: pin, salt: record.salt)
        var difference: UInt8 = 0
        guard actual.count == record.hash.count else { throw LitvinProtectionError.invalidData }
        for (a, b) in zip(actual, record.hash) { difference |= a ^ b }
        guard difference == 0 else {
            let count = (failures[account]?.0 ?? 0) + 1
            failures[account] = (count, ProcessInfo.processInfo.systemUptime + (count >= 5 ? 60 : 0))
            throw LitvinProtectionError.invalidPIN
        }
        failures[account] = nil
        revealed.insert(account)
        notify()
    }

    private static func read(account: Int64) throws -> LitvinPINRecord {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: String(account), kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw LitvinProtectionError.notConfigured }
        return try JSONDecoder().decode(LitvinPINRecord.self, from: data)
    }

    public static func random(_ count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw LitvinProtectionError.keychain(status) }
        return data
    }
    public static func derive(pin: String, salt: Data) throws -> Data {
        guard !pin.isEmpty, salt.count == 16 else { throw LitvinProtectionError.invalidData }
        let password = Array(pin.utf8)
        var key = Data(count: 32)
        let status = password.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                key.withUnsafeMutableBytes { k in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), p.baseAddress!.assumingMemoryBound(to: Int8.self), password.count, s.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600_000, k.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw LitvinProtectionError.invalidData }
        return key
    }
    private static func notify() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: LitvinPolicy.changed, object: nil) }
    }
}

public enum LitvinVault {
    private struct Envelope: Codable {
        let version: Int
        let account: Int64
        let salt: Data
        let ciphertext: Data
    }
    public static func seal(_ data: Data, account: Int64, passphrase: String) throws -> Data {
        guard passphrase.count >= 12, passphrase.count <= 1024 else { throw LitvinProtectionError.invalidPIN }
        let salt = try LitvinProtection.random(16)
        var raw = try LitvinProtection.derive(pin: passphrase, salt: salt)
        defer { raw.resetBytes(in: 0..<raw.count) }
        let key = SymmetricKey(data: raw)
        let box = try AES.GCM.seal(data, using: key, authenticating: Data("Litvin.vault.v1.\(account)".utf8))
        guard let ciphertext = box.combined else { throw LitvinProtectionError.invalidData }
        return try JSONEncoder().encode(Envelope(version: 1, account: account, salt: salt, ciphertext: ciphertext))
    }
    public static func open(_ data: Data, account: Int64, passphrase: String) throws -> Data {
        guard data.count <= 30 * 1024 * 1024, !passphrase.isEmpty, passphrase.count <= 1024 else { throw LitvinProtectionError.invalidData }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, envelope.account == account, envelope.ciphertext.count >= 28 else { throw LitvinProtectionError.invalidData }
        var raw = try LitvinProtection.derive(pin: passphrase, salt: envelope.salt)
        defer { raw.resetBytes(in: 0..<raw.count) }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: envelope.ciphertext), using: SymmetricKey(data: raw), authenticating: Data("Litvin.vault.v1.\(account)".utf8))
    }
}

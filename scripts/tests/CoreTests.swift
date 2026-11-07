import Foundation

@main struct CoreTests {
    static func main() throws {
        let account = Int64.random(in: 100_000_000...999_999_999)
        let original = LitvinPolicy.options
        defer { LitvinPolicy.replace(original); LitvinArchive.forAccount(account).clear() }
        defer { LitvinAppearance.reset(account: account); LitvinAppearance.reset(account: account + 1) }
        precondition(LitvinAppearance.state(account: account) == LitvinAppearanceState())
        precondition(LitvinAppearance.update(account: account) { $0.premium = true; $0.phone = "+123456789"; $0.stars = 123456789 })
        precondition(LitvinAppearance.premium(account: account, peer: account, original: false))
        precondition(!LitvinAppearance.premium(account: account, peer: account + 1, original: false))
        precondition(LitvinAppearance.phone(account: account, peer: account, original: "real") == "+123456789")
        precondition(LitvinAppearance.phone(account: account, peer: account + 1, original: "real") == "real")
        precondition(LitvinAppearance.state(account: account + 1) == LitvinAppearanceState())
        precondition(!LitvinAppearance.update(account: account) { $0.stars = -1 })
        precondition(!LitvinAppearance.update(account: account) { $0.phone = "bad\nnumber" })
        precondition(LitvinAppearance.state(account: account).stars == 123456789)
        precondition(LitvinAppearance.update(account: account) { $0.gifts["42"] = ["Test-1": Data([1, 2, 3])] })
        precondition(LitvinAppearance.state(account: account).gifts["42"]?["Test-1"] == Data([1, 2, 3]))
        LitvinAppearance.reset(account: account)
        precondition(LitvinAppearance.state(account: account) == LitvinAppearanceState())
        LitvinPolicy.replace(LitvinOptions())
        precondition(!LitvinPolicy.ghostActive)
        LitvinPolicy.update { $0.ghostMode = true; $0.alibiEnabled = true; $0.alibiStartMinute = 0; $0.alibiEndMinute = 0 }
        precondition(LitvinPolicy.suppressTyping)
        precondition(LitvinPolicy.suppressReadReceipts)
        precondition(!LitvinPolicy.onlineStatus(requested: true), "Ghost must override alibi")
        precondition(LitvinPolicy.inWindow(start: 0, end: 0))
        precondition(!LitvinPolicy.inWindow(start: -1, end: 100))
        precondition(LitvinTextDiff.describe(before: "a👩‍💻b", after: "a🌍b").contains("🌍"))
        precondition(LitvinTextDiff.describe(before: "", after: "hello").contains("hello"))

        let plain = Data("private archive fixture".utf8)
        let encrypted = try LitvinVault.seal(plain, account: account, passphrase: "long-enough-passphrase")
        precondition(encrypted != plain)
        let opened = try LitvinVault.open(encrypted, account: account, passphrase: "long-enough-passphrase")
        precondition(opened == plain)
        do { _ = try LitvinVault.open(encrypted, account: account, passphrase: "incorrect"); fatalError("Wrong password accepted") } catch {}
        do { _ = try LitvinVault.open(encrypted, account: account + 1, passphrase: "long-enough-passphrase"); fatalError("Cross-account archive accepted") } catch {}

        LitvinPolicy.update { $0.saveDeleted = true; $0.saveEditHistory = true }
        let store = LitvinArchive.forAccount(account)
        let direct = LitvinMessageRecord(account: account, peer: 10, namespace: 0, message: 1, author: 10, timestamp: 100, text: "before", outgoing: false, channel: false, peerTitle: "Direct")
        let channel = LitvinMessageRecord(account: account, peer: 20, namespace: 0, message: 1, author: 20, timestamp: 100, text: "channel", outgoing: false, channel: true, peerTitle: "Channel")
        store.observe(direct)
        store.observe(channel)
        store.beforeEdit(direct)
        store.markDeleted(peer: nil, namespace: 0, ids: [1])
        let state = store.snapshot()
        precondition(state.messages[direct.key]?.deleted == true)
        precondition(state.messages[channel.key]?.deleted == false, "Global deletion must not match channel message IDs")
        precondition(state.edits[direct.key]?.first?.text == "before")
        store.observe(direct)
        precondition(store.snapshot().messages[direct.key]?.deleted == true, "Stale loaded history must not clear a deletion marker")
        let export = try store.exportData()
        try store.importData(export)
        precondition(store.snapshot().messages.count == 2)
        try store.moveToPrivateArchive(peer: direct.peer, passphrase: "vault-specific-password")
        let vault = LitvinPrivateArchive.forAccount(account)
        precondition(vault.isProtected(direct.peer))
        precondition(store.snapshot().messages[direct.key] == nil, "Vault text remained in the ordinary archive")
        precondition(vault.snapshot(peer: direct.peer)?.messages[direct.key]?.text == direct.text)
        vault.lockAllPeers()
        precondition(vault.snapshot(peer: direct.peer) == nil)
        do { try vault.unlock(peer: direct.peer, passphrase: "wrong-password"); fatalError("Wrong vault password accepted") } catch {}
        try vault.unlock(peer: direct.peer, passphrase: "vault-specific-password")
        precondition(vault.snapshot(peer: direct.peer)?.messages[direct.key]?.text == direct.text)
        try vault.rollbackNewArchive(peer: direct.peer)
        do { try LitvinArchive.forAccount(account + 1).importData(export); fatalError("Cross-account state accepted") } catch {}
        LitvinArchive.forAccount(account + 1).clear()
        print("PASS: ghost policy, authenticated encryption, vault move/lock/unlock, Unicode diff, account isolation, edit history, global-delete isolation and backup round-trip")
    }
}

import Foundation

@main struct AppearanceTests {
    static func main() {
        let mixedGifts = ["local-a", "purchased-b", "local-c", "purchased-d"]
        let (pages, selected) = litvinGiftPagerSelection(items: mixedGifts, selected: "purchased-d")
        precondition(pages[selected] == "purchased-d")
        let (refreshedPages, refreshedIndex) = litvinGiftPagerSelection(items: ["another"], selected: "tapped")
        precondition(refreshedPages[refreshedIndex] == "tapped")
        let account = Int64.random(in: 100_000_000...999_999_999)
        defer { LitvinAppearance.reset(account: account); LitvinAppearance.reset(account: account + 1) }
        precondition(LitvinAppearance.state(account: account) == LitvinAppearanceState())
        precondition(LitvinAppearance.state(account: account).giftPreviewEnabled == false)
        precondition(LitvinAppearance.update(account: account) { $0.premium = true; $0.phone = "+123456789"; $0.stars = 123456789 })
        precondition(LitvinAppearance.premium(account: account, peer: account, original: false))
        precondition(!LitvinAppearance.premium(account: account, peer: account + 1, original: false))
        precondition(LitvinAppearance.phone(account: account, peer: account, original: "real") == "+123456789")
        precondition(LitvinAppearance.phone(account: account, peer: account + 1, original: "real") == "real")
        precondition(LitvinAppearance.state(account: account + 1) == LitvinAppearanceState())
        precondition(!LitvinAppearance.update(account: account) { $0.stars = -1 })
        precondition(!LitvinAppearance.update(account: account) { $0.phone = "bad\nnumber" })
        precondition(LitvinAppearance.state(account: account).stars == 123456789)
        precondition(LitvinAppearance.update(account: account) { $0.giftPreviewEnabled = true; $0.giftPreviewPrice = 1000 })
        precondition(LitvinAppearance.state(account: account).giftPreviewEnabled == true)
        precondition(!LitvinAppearance.update(account: account) { $0.giftPreviewPrice = -1 })
        precondition(LitvinAppearance.state(account: account).giftPreviewPrice == 1000)
        precondition(LitvinAppearance.update(account: account) { $0.gifts["42"] = ["Test-1": Data([1, 2, 3])] })
        precondition(LitvinAppearance.state(account: account).gifts["42"]?["Test-1"] == Data([1, 2, 3]))
        LitvinAppearance.reset(account: account)
        precondition(LitvinAppearance.state(account: account) == LitvinAppearanceState())
        print("PASS: local appearance persistence, account/peer isolation, bounds and reset")
    }
}

import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

// "Статистика переписки": computed on the device from the messages that are
// already downloaded for this chat (up to the last 30 000).
private struct LitvinChatStats: Equatable {
    var total: Int = 0
    var mine: Int = 0
    var theirs: Int = 0
    var voice: Int = 0
    var media: Int = 0
    var words: Int = 0
    var firstDate: Int32 = 0
    var lastDate: Int32 = 0
    var activeDays: Int = 0
    var busiestDay: String = ""
    var busiestDayCount: Int = 0
    var hours: [Int] = Array(repeating: 0, count: 24)
    var topEmoji: [(String, Int)] = []
    var longestText: Int = 0

    static func ==(lhs: LitvinChatStats, rhs: LitvinChatStats) -> Bool {
        return lhs.total == rhs.total && lhs.mine == rhs.mine && lhs.lastDate == rhs.lastDate && lhs.words == rhs.words
    }
}

private func litvinComputeStats(postbox: Postbox, peerId: PeerId, accountPeerId: PeerId) -> Signal<LitvinChatStats, NoError> {
    return postbox.transaction { transaction -> LitvinChatStats in
        var stats = LitvinChatStats()
        var days: [String: Int] = [:]
        var emoji: [String: Int] = [:]
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "ru_RU")
        dayFormatter.dateFormat = "d MMMM yyyy"
        let calendar = Calendar.current

        transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 30000, { message in
            if message.media.contains(where: { $0 is TelegramMediaAction }) {
                return true
            }
            stats.total += 1
            let outgoing = !message.flags.contains(.Incoming) || message.author?.id == accountPeerId
            if outgoing {
                stats.mine += 1
            } else {
                stats.theirs += 1
            }
            for media in message.media {
                if let file = media as? TelegramMediaFile, file.isVoice || file.isInstantVideo {
                    stats.voice += 1
                } else if media is TelegramMediaImage || media is TelegramMediaFile {
                    stats.media += 1
                }
            }
            if !message.text.isEmpty {
                stats.words += message.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
                stats.longestText = max(stats.longestText, message.text.count)
                for character in message.text where character.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) {
                    emoji[String(character), default: 0] += 1
                }
            }
            if stats.lastDate == 0 || message.timestamp > stats.lastDate {
                stats.lastDate = message.timestamp
            }
            if stats.firstDate == 0 || message.timestamp < stats.firstDate {
                stats.firstDate = message.timestamp
            }
            let date = Date(timeIntervalSince1970: Double(message.timestamp))
            stats.hours[calendar.component(.hour, from: date)] += 1
            days[dayFormatter.string(from: date), default: 0] += 1
            return true
        })

        stats.activeDays = days.count
        if let busiest = days.max(by: { $0.value < $1.value }) {
            stats.busiestDay = busiest.key
            stats.busiestDayCount = busiest.value
        }
        stats.topEmoji = Array(emoji.sorted(by: { $0.value > $1.value }).prefix(5))
        return stats
    }
}

private enum LitvinStatsEntry: ItemListNodeEntry {
    case header(Int32, String)
    case row(Int32, Int32, String, String)
    case text(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .row(section, _, _, _), let .text(section, _, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 100
        case let .row(section, index, _, _), let .text(section, index, _):
            return section * 100 + 1 + index
        }
    }

    static func ==(lhs: LitvinStatsEntry, rhs: LitvinStatsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(a1, a2), .header(b1, b2)):
            return a1 == b1 && a2 == b2
        case let (.row(a1, a2, a3, a4), .row(b1, b2, b3, b4)):
            return a1 == b1 && a2 == b2 && a3 == b3 && a4 == b4
        case let (.text(a1, a2, a3), .text(b1, b2, b3)):
            return a1 == b1 && a2 == b2 && a3 == b3
        default:
            return false
        }
    }

    static func <(lhs: LitvinStatsEntry, rhs: LitvinStatsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .row(_, _, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .text(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func litvinPercent(_ part: Int, _ total: Int) -> String {
    if total == 0 {
        return "0%"
    }
    return "\(Int((Double(part) * 100.0 / Double(total)).rounded()))%"
}

private func litvinHourBars(_ hours: [Int]) -> String {
    let maxValue = max(1, hours.max() ?? 1)
    let blocks: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    var bars = ""
    for value in hours {
        let level = value == 0 ? 0 : max(1, Int((Double(value) / Double(maxValue) * 7.0).rounded()))
        bars.append(blocks[min(7, level)])
    }
    return bars
}

private func litvinStatsEntries(stats: LitvinChatStats?, peerTitle: String) -> [LitvinStatsEntry] {
    guard let stats else {
        return [.text(0, 0, "Считаю…")]
    }
    if stats.total == 0 {
        return [.text(0, 0, "В чате пока нет загруженных сообщений.")]
    }
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "ru_RU")
    dateFormatter.dateFormat = "d MMMM yyyy"

    var entries: [LitvinStatsEntry] = []
    entries.append(.header(0, "СООБЩЕНИЯ"))
    entries.append(.row(0, 0, "Всего", "\(stats.total)"))
    entries.append(.row(0, 1, "От тебя", "\(stats.mine) · \(litvinPercent(stats.mine, stats.total))"))
    entries.append(.row(0, 2, "От \(peerTitle)", "\(stats.theirs) · \(litvinPercent(stats.theirs, stats.total))"))
    entries.append(.row(0, 3, "Голосовые и кружки", "\(stats.voice)"))
    entries.append(.row(0, 4, "Фото, видео, файлы", "\(stats.media)"))
    entries.append(.row(0, 5, "Слов", "\(stats.words)"))
    entries.append(.row(0, 6, "Самое длинное сообщение", "\(stats.longestText) симв."))

    entries.append(.header(1, "ВРЕМЯ"))
    entries.append(.row(1, 0, "Первое сообщение", dateFormatter.string(from: Date(timeIntervalSince1970: Double(stats.firstDate)))))
    entries.append(.row(1, 1, "Дней общения", "\(stats.activeDays)"))
    if !stats.busiestDay.isEmpty {
        entries.append(.row(1, 2, "Самый активный день", "\(stats.busiestDay) · \(stats.busiestDayCount)"))
    }
    if let peakHour = stats.hours.indices.max(by: { stats.hours[$0] < stats.hours[$1] }) {
        entries.append(.row(1, 3, "Чаще всего пишете", String(format: "%02d:00–%02d:00", peakHour, (peakHour + 1) % 24)))
    }
    entries.append(.text(1, 4, "По часам, 0 → 23:\n" + litvinHourBars(stats.hours)))

    if !stats.topEmoji.isEmpty {
        entries.append(.header(2, "ЛЮБИМЫЕ ЭМОДЗИ"))
        for (index, item) in stats.topEmoji.enumerated() {
            entries.append(.row(2, Int32(index), item.0, "\(item.1)"))
        }
    }
    entries.append(.text(3, 0, "Считается по сообщениям, загруженным на этот телефон."))
    return entries
}

public func litvinChatStatsController(context: AccountContext, peerId: PeerId) -> ViewController {
    let statsPromise = Promise<LitvinChatStats?>(nil)
    statsPromise.set(litvinComputeStats(postbox: context.account.postbox, peerId: peerId, accountPeerId: context.account.peerId) |> map(Optional.init))

    let peerTitle = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    |> map { peer -> String in
        return peer?.compactDisplayTitle ?? "собеседника"
    }

    let signal = combineLatest(context.sharedContext.presentationData, statsPromise.get(), peerTitle)
    |> deliverOnMainQueue
    |> map { presentationData, stats, peerTitle -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Статистика"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: litvinStatsEntries(stats: stats, peerTitle: peerTitle), style: .blocks, animateChanges: false)
        return (controllerState, (listState, Void()))
    }

    return ItemListController(context: context, state: signal)
}

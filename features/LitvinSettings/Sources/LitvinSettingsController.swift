import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

public let litvinVersion = "0.1.0"

private final class LitvinSettingsArguments {
    let openSource: () -> Void

    init(openSource: @escaping () -> Void) {
        self.openSource = openSource
    }
}

private enum LitvinSettingsSection: Int32 {
    case about
}

private enum LitvinSettingsEntry: ItemListNodeEntry {
    case header(String)
    case version(String, String)
    case source(String, String)
    case info(String)

    var section: ItemListSectionId {
        return LitvinSettingsSection.about.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .header: return 0
        case .version: return 1
        case .source: return 2
        case .info: return 3
        }
    }

    static func ==(lhs: LitvinSettingsEntry, rhs: LitvinSettingsEntry) -> Bool {
        switch lhs {
        case let .header(a):
            if case let .header(b) = rhs { return a == b }
            return false
        case let .version(a1, a2):
            if case let .version(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .source(a1, a2):
            if case let .source(b1, b2) = rhs { return a1 == b1 && a2 == b2 }
            return false
        case let .info(a):
            if case let .info(b) = rhs { return a == b }
            return false
        }
    }

    static func <(lhs: LitvinSettingsEntry, rhs: LitvinSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! LitvinSettingsArguments
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .version(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .source(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openSource()
            })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func litvinSettingsEntries() -> [LitvinSettingsEntry] {
    return [
        .header("LITVIN"),
        .version("Version", litvinVersion),
        .source("Source", "GitHub"),
        .info("Unofficial client built on the Telegram API."),
    ]
}

public func litvinSettingsController(context: AccountContext) -> ViewController {
    let arguments = LitvinSettingsArguments(openSource: {
        if let url = URL(string: "https://github.com/rachimanna/litvin-ios") {
            UIApplication.shared.open(url)
        }
    })

    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Litvin"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: litvinSettingsEntries(), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}

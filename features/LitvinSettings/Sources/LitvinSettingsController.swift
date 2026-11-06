import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

private enum LitvinSection: Int32 {
    case about
}

private enum LitvinEntry: ItemListNodeEntry {
    case placeholder(PresentationTheme, String, String)
    case github(PresentationTheme, String)

    var section: ItemListSectionId { return LitvinSection.about.rawValue }

    var stableId: Int32 {
        switch self {
        case .placeholder: return 0
        case .github: return 1
        }
    }

    static func < (lhs: LitvinEntry, rhs: LitvinEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let args = arguments as! LitvinSettingsArguments
        switch self {
        case let .placeholder(_, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .github(_, title):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: "github.com/rachimanna/litvin-ios", sectionId: self.section, style: .blocks, action: { args.openGithub() })
        }
    }
}

private final class LitvinSettingsArguments {
    let openGithub: () -> Void
    init(openGithub: @escaping () -> Void) {
        self.openGithub = openGithub
    }
}

public let litvinVersion = "0.1.0"

public func litvinSettingsController(context: AccountContext) -> ViewController {
    let arguments = LitvinSettingsArguments(openGithub: {
        if let url = URL(string: "https://github.com/rachimanna/litvin-ios") {
            UIApplication.shared.open(url)
        }
    })

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState<LitvinEntry>, LitvinEntry.ItemGenerationArguments)) in
        let theme = presentationData.theme
        let entries: [LitvinEntry] = [
            .placeholder(theme, "Version", litvinVersion),
            .github(theme, "Source"),
        ]
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Litvin"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back),
            animateChanges: false
        )
        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: entries,
            style: .blocks,
            animateChanges: false
        )
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}

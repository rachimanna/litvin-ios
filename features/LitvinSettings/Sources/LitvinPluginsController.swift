import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

private final class LitvinPluginsArguments {
    let toggle: (String, Bool) -> Void
    let remove: (String) -> Void
    let add: () -> Void
    let installExample: () -> Void

    init(toggle: @escaping (String, Bool) -> Void, remove: @escaping (String) -> Void, add: @escaping () -> Void, installExample: @escaping () -> Void) {
        self.toggle = toggle
        self.remove = remove
        self.add = add
        self.installExample = installExample
    }
}

private enum LitvinPluginsEntry: ItemListNodeEntry {
    case installedHeader
    case empty
    case pluginSwitch(Int32, LitvinPluginInfo)
    case pluginInfo(Int32, String)
    case pluginDelete(Int32, LitvinPluginInfo)
    case addHeader
    case add
    case example
    case addInfo

    var section: ItemListSectionId {
        switch self {
        case .installedHeader, .empty:
            return 0
        case let .pluginSwitch(index, _), let .pluginInfo(index, _), let .pluginDelete(index, _):
            return 1 + index
        case .addHeader, .add, .example, .addInfo:
            return 10_000
        }
    }

    var stableId: Int32 {
        switch self {
        case .installedHeader: return 0
        case .empty: return 1
        case let .pluginSwitch(index, _): return 100 + index * 10
        case let .pluginInfo(index, _): return 100 + index * 10 + 1
        case let .pluginDelete(index, _): return 100 + index * 10 + 2
        case .addHeader: return 1_000_000
        case .add: return 1_000_001
        case .example: return 1_000_002
        case .addInfo: return 1_000_003
        }
    }

    static func ==(lhs: LitvinPluginsEntry, rhs: LitvinPluginsEntry) -> Bool {
        switch (lhs, rhs) {
        case (.installedHeader, .installedHeader), (.empty, .empty), (.addHeader, .addHeader), (.add, .add), (.example, .example), (.addInfo, .addInfo):
            return true
        case let (.pluginSwitch(a1, a2), .pluginSwitch(b1, b2)), let (.pluginDelete(a1, a2), .pluginDelete(b1, b2)):
            return a1 == b1 && a2 == b2
        case let (.pluginInfo(a1, a2), .pluginInfo(b1, b2)):
            return a1 == b1 && a2 == b2
        default:
            return false
        }
    }

    static func <(lhs: LitvinPluginsEntry, rhs: LitvinPluginsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! LitvinPluginsArguments
        switch self {
        case .installedHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "МОИ ПЛАГИНЫ", sectionId: self.section)
        case .empty:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Плагинов пока нет. Нажми на файл плагина в любом чате или добавь его ниже."), sectionId: self.section)
        case let .pluginSwitch(_, info):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: litvinRowIcon("puzzlepiece.extension.fill", .green), title: info.name, value: info.enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(info.id, value)
            })
        case let .pluginInfo(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .pluginDelete(_, info):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Удалить", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.remove(info.id)
            })
        case .addHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ДОБАВИТЬ", sectionId: self.section)
        case .add:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Добавить плагин из Файлов", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case .example:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Установить пример «Litvin Tools»", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.installExample()
            })
        case .addInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Плагины Litvin — файлы .litvin.js или .js. Можно добавить сколько угодно, каждый включается и выключается отдельно.\n\nПлагины AyuGram и exteraGram сделаны для Android (Python), на iPhone они не запускаются."), sectionId: self.section)
        }
    }
}

private func litvinPluginsEntries(_ plugins: [LitvinPluginInfo]) -> [LitvinPluginsEntry] {
    var entries: [LitvinPluginsEntry] = [.installedHeader]
    if plugins.isEmpty {
        entries.append(.empty)
    }
    for (index, plugin) in plugins.enumerated() {
        let i = Int32(index)
        entries.append(.pluginSwitch(i, plugin))
        var lines: [String] = []
        if !plugin.description.isEmpty {
            lines.append(plugin.description)
        }
        if !plugin.commands.isEmpty {
            lines.append("Команды: " + plugin.commands.map { "." + $0 }.joined(separator: " "))
        }
        var meta: [String] = []
        if !plugin.author.isEmpty {
            meta.append(plugin.author)
        }
        meta.append("v\(plugin.version)")
        lines.append(meta.joined(separator: " · "))
        entries.append(.pluginInfo(i, lines.joined(separator: "\n")))
        entries.append(.pluginDelete(i, plugin))
    }
    entries.append(.addHeader)
    entries.append(.add)
    entries.append(.example)
    entries.append(.addInfo)
    return entries
}

private final class LitvinPluginPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let picked: (URL) -> Void

    init(picked: @escaping (URL) -> Void) {
        self.picked = picked
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            self.picked(url)
        }
    }
}

public func litvinPluginsController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(LitvinPluginManager.shared.allPlugins(), ignoreRepeated: true)
    var presentImpl: ((ViewController) -> Void)?
    var presentNativeImpl: ((UIViewController) -> Void)?
    var pickerDelegate: LitvinPluginPickerDelegate?

    let reload = {
        statePromise.set(LitvinPluginManager.shared.allPlugins())
    }

    let arguments = LitvinPluginsArguments(toggle: { id, value in
        LitvinPluginManager.shared.setEnabled(id, value)
        reload()
    }, remove: { id in
        LitvinPluginManager.shared.remove(id)
        reload()
    }, add: {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.item], asCopy: true)
        let delegate = LitvinPluginPickerDelegate(picked: { url in
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                return
            }
            if let controller = litvinPluginInstallController(context: context, source: source, fileName: url.lastPathComponent, installed: { _ in
                reload()
            }) {
                presentImpl?(controller)
            } else {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                presentImpl?(textAlertController(context: context, title: "Не плагин", text: "В этом файле нет плагина Litvin.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
            }
        })
        pickerDelegate = delegate
        picker.delegate = delegate
        presentNativeImpl?(picker)
    }, installExample: {
        if case let .litvin(info, source) = litvinParsePluginFile(source: litvinExamplePluginSource, fileName: "litvin-tools.litvin.js") {
            LitvinPluginManager.shared.install(info, source: source)
            reload()
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, plugins -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Плагины"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: litvinPluginsEntries(plugins), style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.didAppear = { _ in
        reload()
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    presentNativeImpl = { [weak controller] c in
        var top = controller?.view.window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        top?.present(c, animated: true)
        _ = pickerDelegate
    }
    return controller
}

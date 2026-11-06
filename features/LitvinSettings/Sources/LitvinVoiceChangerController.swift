import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils

private final class LitvinVoiceArguments {
    let update: ((inout LitvinVoiceSettings) -> Void) -> Void
    let reset: () -> Void

    init(update: @escaping ((inout LitvinVoiceSettings) -> Void) -> Void, reset: @escaping () -> Void) {
        self.update = update
        self.reset = reset
    }
}

private enum LitvinVoiceSection: Int32 {
    case presets
    case tuning
    case scope
}

private enum LitvinVoiceEntry: ItemListNodeEntry {
    case presetsHeader
    case preset(LitvinVoiceSettings.Preset, Bool)
    case tuningHeader
    case pitch(Double)
    case strength(Double)
    case volume(Double)
    case echo(Double)
    case reset
    case tuningInfo
    case scopeHeader
    case voiceMessages(Bool)
    case calls(Bool)
    case scopeInfo

    var section: ItemListSectionId {
        switch self {
        case .presetsHeader, .preset:
            return LitvinVoiceSection.presets.rawValue
        case .tuningHeader, .pitch, .strength, .volume, .echo, .reset, .tuningInfo:
            return LitvinVoiceSection.tuning.rawValue
        case .scopeHeader, .voiceMessages, .calls, .scopeInfo:
            return LitvinVoiceSection.scope.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .presetsHeader: return 0
        case let .preset(preset, _): return 1 + Int32(preset.rawValue)
        case .tuningHeader: return 20
        case .pitch: return 21
        case .strength: return 22
        case .volume: return 23
        case .echo: return 24
        case .reset: return 25
        case .tuningInfo: return 26
        case .scopeHeader: return 30
        case .voiceMessages: return 31
        case .calls: return 32
        case .scopeInfo: return 33
        }
    }

    static func ==(lhs: LitvinVoiceEntry, rhs: LitvinVoiceEntry) -> Bool {
        switch (lhs, rhs) {
        case (.presetsHeader, .presetsHeader), (.tuningHeader, .tuningHeader), (.reset, .reset), (.tuningInfo, .tuningInfo), (.scopeHeader, .scopeHeader), (.scopeInfo, .scopeInfo):
            return true
        case let (.preset(a1, a2), .preset(b1, b2)):
            return a1 == b1 && a2 == b2
        case let (.pitch(a), .pitch(b)), let (.strength(a), .strength(b)), let (.volume(a), .volume(b)), let (.echo(a), .echo(b)):
            return a == b
        case let (.voiceMessages(a), .voiceMessages(b)), let (.calls(a), .calls(b)):
            return a == b
        default:
            return false
        }
    }

    static func <(lhs: LitvinVoiceEntry, rhs: LitvinVoiceEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! LitvinVoiceArguments
        switch self {
        case .presetsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ГОЛОС", sectionId: self.section)
        case let .preset(preset, selected):
            return ItemListCheckboxItem(presentationData: presentationData, title: preset.title, style: .left, checked: selected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.update { $0.preset = preset }
            })
        case .tuningHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "НАСТРОЙКА", sectionId: self.section)
        case let .pitch(value):
            let rounded = Int(value.rounded())
            let text = rounded == 0 ? "0" : (rounded > 0 ? "+\(rounded)" : "\(rounded)")
            return LitvinSliderItem(presentationData: presentationData, title: "Высота тона", valueText: text, value: Float(value), minimumValue: -12.0, maximumValue: 12.0, sectionId: self.section, updated: { value in
                arguments.update { $0.pitch = Double(value.rounded()) }
            })
        case let .strength(value):
            return LitvinSliderItem(presentationData: presentationData, title: "Сила эффекта", valueText: "\(Int((value * 100.0).rounded()))%", value: Float(value), minimumValue: 0.0, maximumValue: 1.0, sectionId: self.section, updated: { value in
                arguments.update { $0.strength = Double(value) }
            })
        case let .volume(value):
            return LitvinSliderItem(presentationData: presentationData, title: "Громкость", valueText: "\(Int((value * 100.0).rounded()))%", value: Float(value), minimumValue: 0.0, maximumValue: 2.0, sectionId: self.section, updated: { value in
                arguments.update { $0.volume = Double(value) }
            })
        case let .echo(value):
            return LitvinSliderItem(presentationData: presentationData, title: "Эхо", valueText: "\(Int((value * 100.0).rounded()))%", value: Float(value), minimumValue: 0.0, maximumValue: 1.0, sectionId: self.section, updated: { value in
                arguments.update { $0.echo = Double(value) }
            })
        case .reset:
            return ItemListActionItem(presentationData: presentationData, title: "Сбросить ползунки", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.reset()
            })
        case .tuningInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("«Сила эффекта» на 0% — твой обычный голос, на 100% — только эффект. Высота тона добавляется к выбранному голосу."), sectionId: self.section)
        case .scopeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ГДЕ ПРИМЕНЯТЬ", sectionId: self.section)
        case let .voiceMessages(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Голосовые сообщения", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.voiceMessages = value }
            })
        case let .calls(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Звонки", value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.calls = value }
            })
        case .scopeInfo:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Для звонков голос выбирается в начале звонка: поменяй настройки до звонка. Работает в звонках один на один, не в групповых."), sectionId: self.section)
        }
    }
}

private func litvinVoiceEntries(_ settings: LitvinVoiceSettings) -> [LitvinVoiceEntry] {
    var entries: [LitvinVoiceEntry] = [.presetsHeader]
    for preset in LitvinVoiceSettings.Preset.allCases {
        entries.append(.preset(preset, settings.preset == preset))
    }
    entries.append(.tuningHeader)
    entries.append(.pitch(settings.pitch))
    entries.append(.strength(settings.strength))
    entries.append(.volume(settings.volume))
    entries.append(.echo(settings.echo))
    entries.append(.reset)
    entries.append(.tuningInfo)
    entries.append(.scopeHeader)
    entries.append(.voiceMessages(settings.voiceMessages))
    entries.append(.calls(settings.calls))
    entries.append(.scopeInfo)
    return entries
}

public func litvinVoiceChangerController(context: AccountContext) -> ViewController {
    let statePromise = ValuePromise(LitvinVoiceSettings.current, ignoreRepeated: true)

    let arguments = LitvinVoiceArguments(update: { f in
        var settings = LitvinVoiceSettings.current
        f(&settings)
        settings.save()
        statePromise.set(settings)
    }, reset: {
        var settings = LitvinVoiceSettings.current
        settings.pitch = 0.0
        settings.strength = 1.0
        settings.volume = 1.0
        settings.echo = 0.0
        settings.save()
        statePromise.set(settings)
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Смена голоса"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: litvinVoiceEntries(settings), style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}

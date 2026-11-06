import Foundation
import Display
import TelegramCore
import AccountContext
import UndoUI
import LitvinSettings

// Opening a plugin file in a chat shows the "Запустить в Litvin" window
// instead of the regular document preview.
func litvinOpenPluginFileIfNeeded(_ params: OpenChatMessageParams) -> Bool {
    guard let file = params.message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile, let fileName = file.fileName, litvinIsPluginFileName(fileName) else {
        return false
    }
    guard let size = file.size, size < 512 * 1024 else {
        return false
    }
    guard let path = params.context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(file.resource.id)), let source = try? String(contentsOfFile: path, encoding: .utf8) else {
        return false
    }
    let context = params.context
    let present = params.present
    guard let controller = litvinPluginInstallController(context: context, source: source, fileName: fileName, installed: { info in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: "Плагин «\(info.name)» запущен", timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return true }), nil, .window(.root))
    }) else {
        return false
    }
    params.dismissInput()
    present(controller, nil, .window(.root))
    return true
}

import Foundation
import UIKit
import AVFoundation
import AccountContext
import TelegramCore
import SwiftSignalKit
import ConvertOpusToAAC
import LitvinCore

extension LitvinTools {
    public static func exportCleanMedia(context: AccountContext, message: EngineMessage) {
        if let photo = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage,
           let representation = photo.representations.max(by: { $0.dimensions.width * $0.dimensions.height < $1.dimensions.width * $1.dimensions.height }),
           let path = context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(representation.resource.id)) {
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let image = UIImage(contentsOfFile: path) else { throw LitvinProtectionError.invalidData }
                    let scale = min(1, 4096 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1
                    format.opaque = true
                    let clean = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                        UIColor.white.setFill()
                        renderer.fill(CGRect(origin: .zero, size: size))
                        image.draw(in: CGRect(origin: .zero, size: size))
                    }
                    guard let data = clean.jpegData(compressionQuality: 0.92) else { throw LitvinProtectionError.invalidData }
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Litvin-\(UUID().uuidString).jpg")
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    DispatchQueue.main.async { shareCleanFile(url, cleanup: [url]) }
                } catch { DispatchQueue.main.async { failure(error) } }
            }
            return
        }
        guard let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile,
              let path = context.engine.resources.completedResourcePath(id: EngineMediaResource.Id(file.resource.id)) else {
            info("Сначала загрузи медиа", "Полностью открой фото, видео или голосовое сообщение, затем повтори экспорт.")
            return
        }
        if file.isVoice {
            let alert = UIAlertController(title: "Изменить голос и экспортировать?", message: "Будет создан новый аудиофайл с изменённой высотой голоса и без исходных метаданных. Это не гарантирует неузнаваемость голоса.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
            alert.addAction(UIAlertAction(title: "Обработать", style: .default, handler: { _ in
                let converted = FileManager.default.temporaryDirectory.appendingPathComponent("Litvin-\(UUID().uuidString).m4a")
                let _ = convertOpusToAAC(sourcePath: path, allocateTempFile: { converted.path }).startStandalone(next: { result in
                    guard let result else { DispatchQueue.main.async { info("Не удалось преобразовать голосовое", "Исходный файл не изменён.") }; return }
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            let pcm = try distortVoice(URL(fileURLWithPath: result))
                            exportAsset(pcm, preset: AVAssetExportPresetAppleM4A, type: .m4a, extension: "m4a", cleanup: [converted, pcm])
                        } catch {
                            try? FileManager.default.removeItem(at: converted)
                            DispatchQueue.main.async { failure(error) }
                        }
                    }
                })
            }))
            present(alert)
        } else if file.isVideo {
            exportAsset(URL(fileURLWithPath: path), preset: AVAssetExportPresetMediumQuality, type: .mp4, extension: "mp4", cleanup: [])
        } else {
            info("Этот формат не поддерживается", "Очистка работает для фото, видео и голосовых сообщений. Документы нужно проверять отдельно.")
        }
    }

    private static func distortVoice(_ input: URL) throws -> URL {
        let source = try AVAudioFile(forReading: input)
        guard source.processingFormat.sampleRate > 0, Double(source.length) / source.processingFormat.sampleRate <= 600 else { throw LitvinArchiveError.tooLarge }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        pitch.pitch = -350
        pitch.rate = 1
        engine.attach(player)
        engine.attach(pitch)
        engine.connect(player, to: pitch, format: source.processingFormat)
        engine.connect(pitch, to: engine.mainMixerNode, format: source.processingFormat)
        try engine.enableManualRenderingMode(.offline, format: source.processingFormat, maximumFrameCount: 4096)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Litvin-\(UUID().uuidString).caf")
        do {
            let output = try AVAudioFile(forWriting: url, settings: engine.manualRenderingFormat.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else { throw LitvinProtectionError.invalidData }
            player.scheduleFile(source, at: nil)
            try engine.start()
            player.play()
            defer { player.stop(); engine.stop() }
            let deadline = Date().addingTimeInterval(60)
            while engine.manualRenderingSampleTime < source.length {
                guard Date() < deadline else { throw LitvinProtectionError.invalidData }
                let remaining = AVAudioFrameCount(source.length - engine.manualRenderingSampleTime)
                let status = try engine.renderOffline(min(buffer.frameCapacity, remaining), to: buffer)
                switch status {
                case .success: try output.write(from: buffer)
                case .cannotDoInCurrentContext, .insufficientDataFromInputNode: break
                case .error: throw LitvinProtectionError.invalidData
                @unknown default: throw LitvinProtectionError.invalidData
                }
            }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func exportAsset(_ input: URL, preset: String, type: AVFileType, extension suffix: String, cleanup: [URL]) {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Litvin-\(UUID().uuidString).\(suffix)")
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: input), presetName: preset) else {
            cleanup.forEach { try? FileManager.default.removeItem(at: $0) }
            DispatchQueue.main.async { info("Экспорт недоступен", "Этот медиафайл не удалось перекодировать.") }
            return
        }
        export.outputURL = output
        export.outputFileType = type
        export.metadata = []
        export.metadataItemFilter = AVMetadataItemFilter.forSharing()
        export.exportAsynchronously {
            DispatchQueue.main.async {
                if export.status == .completed { shareCleanFile(output, cleanup: cleanup + [output]) }
                else {
                    (cleanup + [output]).forEach { try? FileManager.default.removeItem(at: $0) }
                    info("Экспорт не завершён", "Исходное медиа не изменено.")
                }
            }
        }
    }
    private static func shareCleanFile(_ url: URL, cleanup: [URL]) {
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = topController()?.view
        share.popoverPresentationController?.sourceRect = topController()?.view.bounds ?? .zero
        share.completionWithItemsHandler = { _, _, _, _ in cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }
        present(share)
    }
}

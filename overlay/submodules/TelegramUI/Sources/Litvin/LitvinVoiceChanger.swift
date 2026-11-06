import Foundation
import LitvinVoiceKit

// Voice changer for recorded voice/video messages. The engine itself is shared
// with calls: features/LitvinVoiceKit (C++ phase vocoder).
final class LitvinVoiceChanger {
    private let processor: LitvinVoiceProcessor

    init(sampleRate: Double = 48000.0) {
        self.processor = LitvinVoiceProcessor(sampleRate: sampleRate)
    }

    func process(_ samples: UnsafeMutablePointer<Int16>, count: Int) {
        self.processor.processInt16Samples(samples, count: count)
    }
}

import Foundation
import TelegramCore

// Real-time voice changer for recorded voice/video messages.
// Mono Int16 PCM, processed in place. The same algorithm is implemented in C++
// for calls (tgcalls/utils/LitvinVoiceProcessing.cpp); keep them in sync.
final class LitvinVoiceChanger {
    private let sampleRate: Float
    private let settings: LitvinVoiceSettings
    private let enabled: Bool

    private let pitchRatio: Float
    private let strength: Float
    private let volume: Float
    private let echo: Float

    // Pitch shifter: circular buffer read by two cross-faded taps.
    private static let pitchBufferSize = 8192
    private var pitchBuffer = [Float](repeating: 0.0, count: LitvinVoiceChanger.pitchBufferSize)
    private var pitchWrite = 0
    private var pitchPhase: Float = 0.0
    private let pitchWindow: Float

    // Robot: ring modulator + short metallic comb.
    private var ringPhase: Float = 0.0
    private var combBuffer: [Float]
    private var combIndex = 0

    // Pixel: sample-and-hold + bit crusher.
    private var holdCounter = 0
    private var holdValue: Float = 0.0

    // Echo / vocal reverb: three feedback combs.
    private var reverbBuffers: [[Float]]
    private var reverbIndices: [Int]

    init(sampleRate: Double = 48000.0, settings: LitvinVoiceSettings = .current) {
        self.sampleRate = Float(sampleRate)
        self.settings = settings
        self.enabled = settings.isActive

        var ratio: Float
        switch settings.preset {
        case .angry: ratio = 0.78
        case .girl: ratio = 1.45
        case .child: ratio = 1.85
        case .pixel: ratio = 1.2
        case .off, .robot, .vocal: ratio = 1.0
        }
        ratio *= Float(pow(2.0, settings.pitch / 12.0))
        self.pitchRatio = ratio
        self.strength = Float(max(0.0, min(1.0, settings.strength)))
        self.volume = Float(max(0.0, min(2.0, settings.volume)))
        var echo = Float(max(0.0, min(1.0, settings.echo)))
        if settings.preset == .vocal {
            echo = max(echo, 0.45)
        }
        self.echo = echo

        self.pitchWindow = max(256.0, 0.04 * Float(sampleRate))
        self.combBuffer = [Float](repeating: 0.0, count: max(1, Int(0.006 * sampleRate)))
        let reverbLengths = [0.0297, 0.0371, 0.0411].map { max(1, Int($0 * sampleRate)) }
        self.reverbBuffers = reverbLengths.map { [Float](repeating: 0.0, count: $0) }
        self.reverbIndices = [0, 0, 0]
    }

    func process(_ samples: UnsafeMutablePointer<Int16>, count: Int) {
        if !self.enabled || count <= 0 {
            return
        }
        for i in 0 ..< count {
            let input = Float(samples[i]) / 32768.0
            let output = self.processSample(input)
            samples[i] = Int16(max(-32768.0, min(32767.0, output * 32767.0)))
        }
    }

    private func processSample(_ input: Float) -> Float {
        var wet = input

        if abs(self.pitchRatio - 1.0) > 0.001 {
            wet = self.pitchShift(wet)
        }

        switch self.settings.preset {
        case .angry:
            wet = tanhf(wet * 2.6) * 0.75
        case .robot:
            self.ringPhase += 2.0 * Float.pi * 52.0 / self.sampleRate
            if self.ringPhase > 2.0 * Float.pi {
                self.ringPhase -= 2.0 * Float.pi
            }
            let ring = wet * sinf(self.ringPhase) * 1.6
            let delayed = self.combBuffer[self.combIndex]
            let combined = ring + delayed * 0.55
            self.combBuffer[self.combIndex] = combined
            self.combIndex = (self.combIndex + 1) % self.combBuffer.count
            wet = combined * 0.7
        case .pixel:
            if self.holdCounter == 0 {
                let levels: Float = 24.0
                self.holdValue = (wet * levels).rounded() / levels
            }
            self.holdCounter = (self.holdCounter + 1) % 6
            wet = self.holdValue
        case .off, .girl, .child, .vocal:
            break
        }

        var mixed = input * (1.0 - self.strength) + wet * self.strength

        if self.echo > 0.001 {
            var reverb: Float = 0.0
            for k in 0 ..< self.reverbBuffers.count {
                let index = self.reverbIndices[k]
                let delayed = self.reverbBuffers[k][index]
                self.reverbBuffers[k][index] = mixed + delayed * (0.55 + 0.3 * self.echo)
                self.reverbIndices[k] = (index + 1) % self.reverbBuffers[k].count
                reverb += delayed
            }
            mixed = mixed + reverb * 0.33 * self.echo
        }

        return mixed * self.volume
    }

    private func pitchShift(_ input: Float) -> Float {
        let size = LitvinVoiceChanger.pitchBufferSize
        self.pitchBuffer[self.pitchWrite] = input

        self.pitchPhase += (1.0 - self.pitchRatio) / self.pitchWindow
        if self.pitchPhase >= 1.0 {
            self.pitchPhase -= 1.0
        } else if self.pitchPhase < 0.0 {
            self.pitchPhase += 1.0
        }
        var phase2 = self.pitchPhase + 0.5
        if phase2 >= 1.0 {
            phase2 -= 1.0
        }

        let tap1 = self.readDelayed(self.pitchPhase * self.pitchWindow)
        let tap2 = self.readDelayed(phase2 * self.pitchWindow)
        let gain1 = 1.0 - abs(2.0 * self.pitchPhase - 1.0)
        let gain2 = 1.0 - abs(2.0 * phase2 - 1.0)

        self.pitchWrite = (self.pitchWrite + 1) % size
        return (tap1 * gain1 + tap2 * gain2) * 1.45
    }

    private func readDelayed(_ delay: Float) -> Float {
        let size = LitvinVoiceChanger.pitchBufferSize
        let position = Float(self.pitchWrite) - delay - 1.0
        var base = Int(floorf(position))
        let fraction = position - Float(base)
        base = ((base % size) + size) % size
        let next = (base + 1) % size
        return self.pitchBuffer[base] * (1.0 - fraction) + self.pitchBuffer[next] * fraction
    }
}

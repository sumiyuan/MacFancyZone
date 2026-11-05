import AudioToolbox
import CoreAudio
import Foundation

/// Raw cells shared with the audio thread. The IO block touches only these pointers: no
/// allocation, locks or Swift concurrency on the real-time thread.
private final class SharedCells: @unchecked Sendable {
    let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    let heard = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)

    init(gain g: Float) {
        gain.initialize(to: g)
        heard.initialize(to: 0)
    }

    deinit {
        gain.deallocate()
        heard.deallocate()
    }
}

/// Captures one app's sound with a Core Audio process tap (muting the original) and replays
/// it, scaled by a gain, on the device the app was playing to. Call `stop()` to release it.
@available(macOS 14.2, *)
@MainActor
final class AppAudioCapture {
    let outputDeviceID: AudioObjectID
    private let cells: SharedCells
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var stopped = false
    private static let ioQueue = DispatchQueue(label: "MacPowertools.mixer.io", qos: .userInteractive)

    init?(processObjects: [AudioObjectID], gain: Float) {
        guard !processObjects.isEmpty else { return nil }
        cells = SharedCells(gain: gain)

        // Play where the app was playing; fall back to the system default output.
        let processDevice = processObjects.lazy
            .compactMap { caGetArray($0, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput).first }
            .first
        outputDeviceID = processDevice
            ?? caGet(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                     default: AudioObjectID(kAudioObjectUnknown))
        guard outputDeviceID != kAudioObjectUnknown,
              let outputUID = caGetString(outputDeviceID, kAudioDevicePropertyDeviceUID) else { return nil }

        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else {
            tapID = AudioObjectID(kAudioObjectUnknown)
            return nil
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MacPowertools Mixer",
            kAudioAggregateDeviceUIDKey: "com.sumiyuan.MacPowertools.mixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr else {
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            stop()
            return nil
        }

        let cells = self.cells
        let block: AudioDeviceIOBlock = { _, inData, _, outData, _ in
            Self.render(input: inData, output: outData, cells: cells)
        }
        guard AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, Self.ioQueue, block) == noErr,
              let ioProcID, AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            stop()
            return nil
        }
    }

    func setGain(_ g: Float) { cells.gain.pointee = g }

    /// True once the tap has delivered any non-silent sample.
    var heardSound: Bool { cells.heard.pointee != 0 }

    /// Tears everything down; the app's own sound comes back. Safe to call more than once.
    func stop() {
        guard !stopped else { return }
        stopped = true
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Copies the tap stream (always the last input buffer; earlier ones are the output
    /// device's own inputs, e.g. a microphone) to the output, scaled and clamped.
    private nonisolated static func render(input: UnsafePointer<AudioBufferList>,
                                           output: UnsafeMutablePointer<AudioBufferList>,
                                           cells: SharedCells) {
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outs = UnsafeMutableAudioBufferListPointer(output)
        let gain = cells.gain.pointee

        var src: UnsafeMutablePointer<Float>?
        var inChannels = 0
        var inFrames = 0
        if let tap = ins.last, let data = tap.mData, tap.mNumberChannels > 0 {
            src = data.assumingMemoryBound(to: Float.self)
            inChannels = Int(tap.mNumberChannels)
            inFrames = Int(tap.mDataByteSize) / 4 / inChannels
            var heard = false
            for i in 0..<(inFrames * inChannels) where abs(src![i]) > 1e-5 { heard = true; break }
            if heard { cells.heard.pointee = 1 }
        }

        let interleaved = outs.count == 1
        for (bufferIndex, buffer) in outs.enumerated() {
            guard let data = buffer.mData else { continue }
            let dst = data.assumingMemoryBound(to: Float.self)
            let outChannels = max(1, Int(buffer.mNumberChannels))
            let outFrames = Int(buffer.mDataByteSize) / 4 / outChannels
            for frame in 0..<outFrames {
                for c in 0..<outChannels {
                    // Interleaved: channel c; non-interleaved: buffer i carries channel i.
                    let channel = interleaved ? c : bufferIndex
                    var sample: Float = 0
                    if let src, frame < inFrames, channel < inChannels {
                        sample = max(-1, min(1, src[frame * inChannels + channel] * gain))
                    }
                    dst[frame * outChannels + c] = sample
                }
            }
        }
    }
}

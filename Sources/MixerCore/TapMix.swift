import CoreAudio

/// Writes an interleaved tap stream (`channels` × `frames` floats) into the output buffers,
/// scaled by `gain` and clamped to -1...1. Output channels are numbered across the buffers
/// (so a second stereo stream is channels 2–3) and any channel the tap lacks gets silence.
/// Real-time safe: no allocation, locks or Objective-C.
public func mixTap(source: UnsafePointer<Float>?, channels: Int, frames: Int,
                   into outputs: UnsafeMutableAudioBufferListPointer, gain: Float) {
    var channelOffset = 0
    for buffer in outputs {
        let outChannels = max(1, Int(buffer.mNumberChannels))
        defer { channelOffset += outChannels }
        guard let data = buffer.mData else { continue }
        let dst = data.assumingMemoryBound(to: Float.self)
        let outFrames = Int(buffer.mDataByteSize) / 4 / outChannels
        for frame in 0..<outFrames {
            for c in 0..<outChannels {
                let channel = channelOffset + c
                var sample: Float = 0
                if let source, frame < frames, channel < channels {
                    sample = max(-1, min(1, source[frame * channels + channel] * gain))
                }
                dst[frame * outChannels + c] = sample
            }
        }
    }
}

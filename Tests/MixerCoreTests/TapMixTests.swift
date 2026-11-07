import CoreAudio
import Testing
@testable import MixerCore

private func makeOutputs(_ channels: [Int], frames: Int) -> UnsafeMutableAudioBufferListPointer {
    let list = AudioBufferList.allocate(maximumBuffers: channels.count)
    for (i, ch) in channels.enumerated() {
        let data = UnsafeMutablePointer<Float>.allocate(capacity: ch * frames)
        data.initialize(repeating: 9, count: ch * frames)
        list[i] = AudioBuffer(mNumberChannels: UInt32(ch), mDataByteSize: UInt32(ch * frames * 4), mData: data)
    }
    return list
}

private func samples(_ list: UnsafeMutableAudioBufferListPointer, _ i: Int) -> [Float] {
    let b = list[i]
    let n = Int(b.mDataByteSize) / 4
    return Array(UnsafeBufferPointer(start: b.mData!.assumingMemoryBound(to: Float.self), count: n))
}

@Test func interleavedStereoScaledAndClamped() {
    var src: [Float] = [0.5, -0.5, 0.9, -0.9]   // 2 frames, L/R
    let out = makeOutputs([2], frames: 2)
    src.withUnsafeMutableBufferPointer { mixTap(source: $0.baseAddress, channels: 2, frames: 2, into: out, gain: 1.5) }
    #expect(samples(out, 0) == [0.75, -0.75, 1, -1])
}

@Test func twoStereoStreamsGetOnlyFirstPair() {
    var src: [Float] = [0.1, 0.2]               // 1 frame
    let out = makeOutputs([2, 2], frames: 1)
    src.withUnsafeMutableBufferPointer { mixTap(source: $0.baseAddress, channels: 2, frames: 1, into: out, gain: 1) }
    #expect(samples(out, 0) == [0.1, 0.2])
    #expect(samples(out, 1) == [0, 0])
}

@Test func monoBuffersGetOneChannelEach() {
    var src: [Float] = [0.1, 0.2]
    let out = makeOutputs([1, 1], frames: 1)
    src.withUnsafeMutableBufferPointer { mixTap(source: $0.baseAddress, channels: 2, frames: 1, into: out, gain: 1) }
    #expect(samples(out, 0) == [0.1])
    #expect(samples(out, 1) == [0.2])
}

@Test func missingSourceWritesSilence() {
    let out = makeOutputs([2], frames: 2)
    mixTap(source: nil, channels: 0, frames: 0, into: out, gain: 1)
    #expect(samples(out, 0) == [0, 0, 0, 0])
}

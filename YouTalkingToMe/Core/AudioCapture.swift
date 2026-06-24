import AVFoundation
import Foundation

final class AudioCapture {
    private let engine = AVAudioEngine()
    private var buffers: [AVAudioPCMBuffer] = []
    private var isRecording = false

    var onError: ((Error) -> Void)?

    func start() throws {
        guard !isRecording else { return }

        buffers.removeAll()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.buffers.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        isRecording = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        guard !buffers.isEmpty else { return nil }

        let format = buffers[0].format
        let frameCount = buffers.reduce(0) { $0 + Int($1.frameLength) }
        guard frameCount > 0 else { return nil }

        guard let combined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        var offset = 0
        for buffer in buffers {
            guard let src = buffer.floatChannelData?[0] else { continue }
            guard let dst = combined.floatChannelData?[0] else { continue }
            let count = Int(buffer.frameLength)
            dst.advanced(by: offset).update(from: src, count: count)
            offset += count
        }
        combined.frameLength = AVAudioFrameCount(frameCount)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("youtalkingtome-\(UUID().uuidString).wav")
        do {
            try writeWAV(buffer: combined, to: url)
            return url
        } catch {
            onError?(error)
            return nil
        }
    }

    private func writeWAV(buffer: AVAudioPCMBuffer, to url: URL) throws {
        let format = buffer.format
        let channels = Int(format.channelCount)
        let sampleRate = Int32(format.sampleRate)
        let frameCount = Int(buffer.frameLength)

        guard let channelData = buffer.floatChannelData else {
            throw DictationError.emptyAudio
        }

        var pcmData = Data()
        for frame in 0..<frameCount {
            for channel in 0..<channels {
                let sample = channelData[channel][frame]
                let clamped = max(-1.0, min(1.0, sample))
                let intSample = Int16(clamped * Float(Int16.max))
                pcmData.append(UInt8(truncatingIfNeeded: intSample & 0xFF))
                pcmData.append(UInt8(truncatingIfNeeded: (intSample >> 8) & 0xFF))
            }
        }

        let byteRate = sampleRate * Int32(channels) * 2
        let blockAlign = Int16(channels) * 2
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize

        var fileData = Data()
        fileData.append(contentsOf: "RIFF".utf8)
        fileData.append(littleEndian: fileSize)
        fileData.append(contentsOf: "WAVE".utf8)
        fileData.append(contentsOf: "fmt ".utf8)
        fileData.append(littleEndian: UInt32(16))
        fileData.append(littleEndian: UInt16(1))
        fileData.append(littleEndian: UInt16(channels))
        fileData.append(littleEndian: sampleRate)
        fileData.append(littleEndian: byteRate)
        fileData.append(littleEndian: blockAlign)
        fileData.append(littleEndian: UInt16(16))
        fileData.append(contentsOf: "data".utf8)
        fileData.append(littleEndian: dataSize)
        fileData.append(pcmData)

        try fileData.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    mutating func append(littleEndian value: UInt16) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    mutating func append(littleEndian value: Int32) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    mutating func append(littleEndian value: Int16) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }
}

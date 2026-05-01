import AVFoundation

@MainActor
final class AudioRecorder {
    private(set) var isRecording = false

    private var engine:  AVAudioEngine?
    private var samples: [Float] = []

    func start() async throws {
        samples = []
        let engine = AVAudioEngine()
        self.engine = engine

        let inputNode   = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        let targetRate: Double = 16_000

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate:   targetRate,
            channels:     1,
            interleaved:  false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.formatSetupFailed
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * targetRate / inputFormat.sampleRate)
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            var convError: NSError?
            converter.convert(to: converted, error: &convError) { _, status in
                status.pointee = .haveData
                return buffer
            }
            guard convError == nil, let channelData = converted.floatChannelData?[0] else { return }

            let frames = Array(UnsafeBufferPointer(start: channelData, count: Int(converted.frameLength)))
            Task { @MainActor [weak self] in
                self?.samples.append(contentsOf: frames)
            }
        }

        try engine.start()
        isRecording = true
    }

    func stop() -> [Float]? {
        guard isRecording else { return nil }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isRecording = false
        return samples
    }

    enum RecorderError: Error {
        case formatSetupFailed
    }
}

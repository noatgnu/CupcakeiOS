import AVFoundation
import Foundation

@MainActor
@Observable
public final class AudioRecorder: NSObject {
    public private(set) var isRecording = false
    public private(set) var recordedFileURL: URL?
    /// Normalized 0...1 input level, refreshed ~15x/sec while recording, for a live level meter.
    public private(set) var audioLevel: Float = 0

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?

    public override init() {
        super.init()
    }

    public func requestPermission() async -> Bool {
        #if os(iOS)
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        #else
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        #endif
    }

    #if os(iOS)
    /// Every mic currently offered by the system (built-in, wired/Bluetooth headset, etc.).
    public func availableInputs() -> [AVAudioSessionPortDescription] {
        AVAudioSession.sharedInstance().availableInputs ?? []
    }

    public func preferredInput() -> AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().preferredInput
    }

    /// Selects a mic for the next recording; pass `nil` to fall back to the system default.
    public func setPreferredInput(_ input: AVAudioSessionPortDescription?) {
        try? AVAudioSession.sharedInstance().setPreferredInput(input)
    }
    #endif

    public func startRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        #endif

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        let newRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
        newRecorder.delegate = self
        newRecorder.isMeteringEnabled = true
        newRecorder.record()
        recorder = newRecorder
        recordedFileURL = fileURL
        isRecording = true
        startMetering()
    }

    public func stopRecording() {
        recorder?.stop()
        isRecording = false
        meterTask?.cancel()
        meterTask = nil
        audioLevel = 0
    }

    private func startMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while let self, self.isRecording, !Task.isCancelled {
                self.recorder?.updateMeters()
                let decibels = self.recorder?.averagePower(forChannel: 0) ?? -160
                self.audioLevel = Self.normalizedLevel(decibels: decibels)
                try? await Task.sleep(for: .milliseconds(66))
            }
        }
    }

    /// Maps dBFS (roughly -60 quiet to 0 loud) onto a 0...1 range for a level-meter bar.
    nonisolated static func normalizedLevel(decibels: Float) -> Float {
        let minDecibels: Float = -60
        guard decibels.isFinite, decibels > minDecibels else { return 0 }
        return min(1, max(0, (decibels - minDecibels) / -minDecibels))
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}
}

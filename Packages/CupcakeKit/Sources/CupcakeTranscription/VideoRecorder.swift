import AVFoundation
import Foundation

@MainActor
@Observable
public final class VideoRecorder: NSObject {
    public private(set) var isRecording = false
    public private(set) var recordedFileURL: URL?

    public let session = AVCaptureSession()

    private var movieOutput: AVCaptureMovieFileOutput?
    private var isConfigured = false
    private var stopContinuation: CheckedContinuation<URL?, Never>?

    public override init() {
        super.init()
    }

    public func requestPermission() async -> Bool {
        let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
        let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
        return cameraGranted && micGranted
    }

    public func startSession() throws {
        if !isConfigured {
            session.beginConfiguration()
            session.sessionPreset = .medium

            guard let camera = AVCaptureDevice.default(for: .video) else {
                session.commitConfiguration()
                throw VideoRecorderError.cameraUnavailable
            }
            let videoInput = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            if let mic = AVCaptureDevice.default(for: .audio), let audioInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }

            let output = AVCaptureMovieFileOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            movieOutput = output

            session.commitConfiguration()
            isConfigured = true
        }

        session.startRunning()
    }

    public func stopSession() {
        session.stopRunning()
    }

    public func startRecording() {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mov")
        recordedFileURL = fileURL
        isRecording = true
        movieOutput?.startRecording(to: fileURL, recordingDelegate: self)
    }

    public func stopRecording() async -> URL? {
        guard let output = movieOutput, output.isRecording else { return recordedFileURL }
        return await withCheckedContinuation { continuation in
            self.stopContinuation = continuation
            output.stopRecording()
        }
    }
}

extension VideoRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.stopContinuation?.resume(returning: error == nil ? outputFileURL : nil)
            self.stopContinuation = nil
        }
    }
}

public enum VideoRecorderError: Error {
    case cameraUnavailable
}

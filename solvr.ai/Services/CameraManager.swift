import AVFoundation
import UIKit

@Observable
final class CameraManager: NSObject {
    let session = AVCaptureSession()
    var isRunning = false
    var torchOn = false
    var permissionGranted = false
    var permissionDenied = false

    var onFrameCaptured: ((CMSampleBuffer) -> Void)?

    private let sessionQueue = DispatchQueue(label: "ai.solvr.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?

    // MARK: - Permission

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionGranted = granted
                    self?.permissionDenied = !granted
                }
            }
        default:
            permissionDenied = true
        }
    }

    // MARK: - Setup

    func configure() {
        sessionQueue.async { [weak self] in
            self?.setupSession()
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Camera input
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            return
        }
        device = camera

        // Enable continuous autofocus
        do {
            try camera.lockForConfiguration()
            if camera.isFocusModeSupported(.continuousAutoFocus) {
                camera.focusMode = .continuousAutoFocus
            }
            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        } catch {}

        guard let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // Video data output for continuous frames
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "ai.solvr.camera.videooutput"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Set video orientation
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }

        session.commitConfiguration()
    }

    // MARK: - Start / Stop

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    // MARK: - Torch

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            torchOn.toggle()
            device.torchMode = torchOn ? .on : .off
            device.unlockForConfiguration()
        } catch {}
    }

    // MARK: - Capture Current Frame

    private var lastCapturedBuffer: CMSampleBuffer?

    func captureCurrentFrame() -> UIImage? {
        guard let buffer = lastCapturedBuffer else { return nil }
        return imageFromSampleBuffer(buffer)
    }

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lastCapturedBuffer = sampleBuffer
        onFrameCaptured?(sampleBuffer)
    }
}

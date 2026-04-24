//
//  HandTracker.swift
//  motion_capture_test
//
//  Tracks a single hand via the front camera using the Vision framework.
//  Emits normalized hand position, velocity, and a punch trigger on the main queue.
//

import AVFoundation
import Vision
import CoreGraphics
import QuartzCore

protocol HandTrackerDelegate: AnyObject {
    func handTrackerDidUpdate(position: CGPoint?, speed: CGFloat, didPunch: Bool)
    func handTrackerDidFail(reason: String)
}

final class HandTracker: NSObject {

    weak var delegate: HandTrackerDelegate?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "HandTracker.session")
    private let output = AVCaptureVideoDataOutput()

    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()

    private var lastPosition: CGPoint?
    private var lastTimestamp: CFTimeInterval = 0
    private var punchCooldownUntil: CFTimeInterval = 0

    private let punchSpeedThreshold: CGFloat = 2.8
    private let punchCooldown: CFTimeInterval = 0.35

    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndRun()
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.handTrackerDidFail(reason: "Camera access denied")
                    }
                }
            }
        default:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.handTrackerDidFail(reason: "Camera access denied. Enable it in System Settings > Privacy & Security > Camera.")
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureAndRun() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.inputs.isEmpty {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)

        guard let camera, let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.handTrackerDidFail(reason: "No usable camera found")
            }
            return
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
    }
}

extension HandTracker: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            process(observation: request.results?.first)
        } catch {
            // Drop bad frames silently — hand tracking is best-effort per frame.
        }
    }

    private func process(observation: VNHumanHandPoseObservation?) {
        guard let observation else {
            emit(position: nil, speed: 0, didPunch: false)
            return
        }

        // Prefer the middle MCP joint (knuckle) — it's stable and central to the palm.
        let point = (try? observation.recognizedPoint(.middleMCP))
            ?? (try? observation.recognizedPoint(.wrist))

        guard let point, point.confidence > 0.3 else {
            emit(position: nil, speed: 0, didPunch: false)
            return
        }

        // Vision uses a bottom-left origin in normalized [0,1]. Mirror X so the
        // on-screen indicator follows the user like a mirror.
        let position = CGPoint(x: 1.0 - point.location.x, y: point.location.y)
        let now = CACurrentMediaTime()

        var speed: CGFloat = 0
        var didPunch = false
        if let last = lastPosition, lastTimestamp > 0 {
            let dt = CGFloat(now - lastTimestamp)
            if dt > 0 {
                let dx = position.x - last.x
                let dy = position.y - last.y
                speed = sqrt(dx * dx + dy * dy) / dt
                if speed > punchSpeedThreshold && now > punchCooldownUntil {
                    didPunch = true
                    punchCooldownUntil = now + punchCooldown
                }
            }
        }

        lastPosition = position
        lastTimestamp = now
        emit(position: position, speed: speed, didPunch: didPunch)
    }

    private func emit(position: CGPoint?, speed: CGFloat, didPunch: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.handTrackerDidUpdate(position: position, speed: speed, didPunch: didPunch)
        }
    }
}

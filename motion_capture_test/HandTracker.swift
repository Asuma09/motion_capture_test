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

    private var lastTimestamp: CFTimeInterval = 0
    private var punchCooldownUntil: CFTimeInterval = 0

    // Ring buffer of (timestamp, palm size) used to compute palm-growth rate
    // over a stable time window. Growth represents forward motion toward the
    // camera — a real punch — and ignores lateral swipes.
    private var palmHistory: [(time: CFTimeInterval, size: CGFloat)] = []

    private let punchGrowthThreshold: CGFloat = 0.45 // normalized palm-size units / sec
    private let punchWindow: CFTimeInterval = 0.12   // measure growth over ~120 ms
    private let historyCutoff: CFTimeInterval = 0.5
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
            resetTracking()
            emit(position: nil, speed: 0, didPunch: false)
            return
        }

        // Need both wrist and middle MCP: middle MCP is the cursor anchor,
        // and the wrist→middleMCP distance is our 2D proxy for palm size.
        guard let middle = try? observation.recognizedPoint(.middleMCP),
              let wrist = try? observation.recognizedPoint(.wrist),
              middle.confidence > 0.3, wrist.confidence > 0.3 else {
            resetTracking()
            emit(position: nil, speed: 0, didPunch: false)
            return
        }

        // Vision uses a bottom-left origin in normalized [0,1]. Mirror X so the
        // on-screen indicator follows the user like a mirror.
        let position = CGPoint(x: 1.0 - middle.location.x, y: middle.location.y)

        // Palm size in normalized image coordinates. As the hand moves toward
        // the camera, this distance grows; lateral swipes leave it unchanged.
        let palmDx = middle.location.x - wrist.location.x
        let palmDy = middle.location.y - wrist.location.y
        let palmSize = sqrt(palmDx * palmDx + palmDy * palmDy)

        let now = CACurrentMediaTime()
        palmHistory.append((time: now, size: palmSize))
        let cutoff = now - historyCutoff
        palmHistory.removeAll { $0.time < cutoff }

        // Compare against the oldest sample at least `punchWindow` seconds in
        // the past — a fixed-window derivative is much less noisy than a
        // single-frame delta.
        var growthRate: CGFloat = 0
        var didPunch = false
        if let baseline = palmHistory.first(where: { now - $0.time >= punchWindow }) {
            let dt = CGFloat(now - baseline.time)
            if dt > 0 {
                growthRate = (palmSize - baseline.size) / dt
                if growthRate > punchGrowthThreshold && now > punchCooldownUntil {
                    didPunch = true
                    punchCooldownUntil = now + punchCooldown
                }
            }
        }

        lastTimestamp = now
        emit(position: position, speed: growthRate, didPunch: didPunch)
    }

    private func resetTracking() {
        palmHistory.removeAll(keepingCapacity: true)
        lastTimestamp = 0
    }

    private func emit(position: CGPoint?, speed: CGFloat, didPunch: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.handTrackerDidUpdate(position: position, speed: speed, didPunch: didPunch)
        }
    }
}

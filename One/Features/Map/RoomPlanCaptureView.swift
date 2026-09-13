import SwiftUI
import UIKit
import RoomPlan
import ARKit
import CoreImage
import CoreVideo

enum RoomPlanCaptureError: LocalizedError, Sendable, Equatable {
    case unsupportedDevice
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: "RoomPlan is not supported on this device."
        case let .captureFailed(message): message
        }
    }
}

struct RoomPlanCaptureResult {
    let room: CapturedRoom
    let cameraToWorld: simd_float4x4?
    let trackingState: String
    let visualSamples: [RoomPlanVisualSample]
}

struct RoomPlanVisualSample: Sendable {
    let jpegData: Data
    let width: Int
    let height: Int
    let depthData: Data
    let depthWidth: Int
    let depthHeight: Int
    let intrinsics: [[Double]]
    let cameraToWorld: [[Double]]
    let capturedAt: Date
}

struct RoomPlanCaptureView: UIViewRepresentable {
    @Binding var isCapturing: Bool
    var onComplete: @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.captureSession.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        guard isCapturing, !context.coordinator.hasStarted else { return }
        let configuration = RoomCaptureSession.Configuration()
        context.coordinator.hasStarted = true
        view.captureSession.run(configuration: configuration)
        context.coordinator.beginVisualSampling(session: view.captureSession)
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) {
        coordinator.stopVisualSampling()
        view.captureSession.stop()
    }

    final class Coordinator: NSObject, RoomCaptureSessionDelegate {
        let onComplete: @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void
        var hasStarted = false
        private var visualSamplingTimer: Timer?
        private var visualSamples: [RoomPlanVisualSample] = []
        private let imageContext = CIContext(options: [.cacheIntermediates: false])
        private let maxVisualSamples = 10
        init(onComplete: @escaping @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void) { self.onComplete = onComplete }

        func beginVisualSampling(session: RoomCaptureSession) {
            stopVisualSampling()
            visualSamplingTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self, weak session] _ in
                guard let self, let session else { return }
                self.captureVisualSample(from: session.arSession.currentFrame)
            }
            if let frame = session.arSession.currentFrame { captureVisualSample(from: frame) }
        }

        func stopVisualSampling() {
            visualSamplingTimer?.invalidate()
            visualSamplingTimer = nil
        }

        private func captureVisualSample(from frame: ARFrame?) {
            guard visualSamples.count < maxVisualSamples, let frame else { return }
            guard case .normal = frame.camera.trackingState else { return }
            guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
            let capturedImage = frame.capturedImage
            let sourceWidth = CVPixelBufferGetWidth(capturedImage)
            let sourceHeight = CVPixelBufferGetHeight(capturedImage)
            guard sourceWidth > 0, sourceHeight > 0 else { return }

            let maxDimension: CGFloat = 960
            let scale = min(1.0, maxDimension / CGFloat(max(sourceWidth, sourceHeight)))
            let outputWidth = max(1, Int((CGFloat(sourceWidth) * scale).rounded()))
            let outputHeight = max(1, Int((CGFloat(sourceHeight) * scale).rounded()))
            let image = CIImage(cvPixelBuffer: capturedImage).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return }
            guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.64) else { return }
            guard let depthData = Self.float32DepthData(sceneDepth.depthMap) else { return }

            let cameraIntrinsics = frame.camera.intrinsics
            let sx = Double(outputWidth) / Double(sourceWidth)
            let sy = Double(outputHeight) / Double(sourceHeight)
            let intrinsics = [
                [Double(cameraIntrinsics.columns.0.x) * sx, Double(cameraIntrinsics.columns.1.x) * sx, Double(cameraIntrinsics.columns.2.x) * sx],
                [Double(cameraIntrinsics.columns.0.y) * sy, Double(cameraIntrinsics.columns.1.y) * sy, Double(cameraIntrinsics.columns.2.y) * sy],
                [Double(cameraIntrinsics.columns.0.z), Double(cameraIntrinsics.columns.1.z), Double(cameraIntrinsics.columns.2.z)]
            ]
            guard let cameraToWorld = try? RoomPlanMatrix.rowMajor(frame.camera.transform) else { return }
            visualSamples.append(
                RoomPlanVisualSample(
                    jpegData: jpegData,
                    width: outputWidth,
                    height: outputHeight,
                    depthData: depthData,
                    depthWidth: CVPixelBufferGetWidth(sceneDepth.depthMap),
                    depthHeight: CVPixelBufferGetHeight(sceneDepth.depthMap),
                    intrinsics: intrinsics,
                    cameraToWorld: cameraToWorld,
                    capturedAt: frame.timestamp > 0 ? Date(timeIntervalSinceNow: 0) : Date()
                )
            )
        }

        private static func float32DepthData(_ pixelBuffer: CVPixelBuffer) -> Data? {
            guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32 else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let tightBytesPerRow = width * MemoryLayout<Float32>.size
            var result = Data(count: tightBytesPerRow * height)
            result.withUnsafeMutableBytes { destination in
                guard let destinationBase = destination.baseAddress else { return }
                for row in 0..<height {
                    memcpy(destinationBase.advanced(by: row * tightBytesPerRow), baseAddress.advanced(by: row * bytesPerRow), tightBytesPerRow)
                }
            }
            return result
        }

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            stopVisualSampling()
            let completion = onComplete
            let capturedData = data
            let frame = session.arSession.currentFrame
            if let frame { captureVisualSample(from: frame) }
            let cameraToWorld = frame?.camera.transform
            let completedVisualSamples = visualSamples
            let trackingState: String
            switch frame?.camera.trackingState {
            case .normal: trackingState = "normal"
            case .limited: trackingState = "limited"
            case .notAvailable, .none: trackingState = "unavailable"
            @unknown default: trackingState = "unavailable"
            }
            Task { @MainActor in
                if let error {
                    completion(.failure(.captureFailed(error.localizedDescription)))
                    return
                }
                do {
                    let room = try await RoomBuilder(options: []).capturedRoom(from: capturedData)
                    completion(.success(RoomPlanCaptureResult(room: room, cameraToWorld: cameraToWorld, trackingState: trackingState, visualSamples: completedVisualSamples)))
                } catch {
                    completion(.failure(.captureFailed(error.localizedDescription)))
                }
            }
        }
    }
}

enum RoomPlanCapability {
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        RoomCaptureSession.isSupported && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        #endif
    }
}

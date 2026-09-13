import SwiftUI
import RoomPlan
import ARKit

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
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) {
        view.captureSession.stop()
    }

    final class Coordinator: NSObject, RoomCaptureSessionDelegate {
        let onComplete: @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void
        var hasStarted = false
        init(onComplete: @escaping @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void) { self.onComplete = onComplete }

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            let completion = onComplete
            let capturedData = data
            let frame = session.arSession.currentFrame
            let cameraToWorld = frame?.camera.transform
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
                    completion(.success(RoomPlanCaptureResult(room: room, cameraToWorld: cameraToWorld, trackingState: trackingState)))
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

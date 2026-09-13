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

struct RoomPlanCaptureView: UIViewRepresentable {
    @Binding var isCapturing: Bool
    var onComplete: @MainActor @Sendable (Result<CapturedRoom, RoomPlanCaptureError>) -> Void

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
        let onComplete: @MainActor @Sendable (Result<CapturedRoom, RoomPlanCaptureError>) -> Void
        var hasStarted = false
        init(onComplete: @escaping @MainActor @Sendable (Result<CapturedRoom, RoomPlanCaptureError>) -> Void) { self.onComplete = onComplete }

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            let completion = onComplete
            let capturedData = data
            Task { @MainActor in
                if let error {
                    completion(.failure(.captureFailed(error.localizedDescription)))
                    return
                }
                do {
                    let room = try await RoomBuilder(options: []).capturedRoom(from: capturedData)
                    completion(.success(room))
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

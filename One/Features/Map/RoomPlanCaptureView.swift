import SwiftUI
import RoomPlan

struct RoomPlanCaptureView: UIViewRepresentable {
    @Binding var isCapturing: Bool
    var onComplete: @MainActor @Sendable (CapturedRoom?) -> Void

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
        let onComplete: @MainActor @Sendable (CapturedRoom?) -> Void
        var hasStarted = false
        init(onComplete: @escaping @MainActor @Sendable (CapturedRoom?) -> Void) { self.onComplete = onComplete }

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            let completion = onComplete
            let capturedData = data
            Task { @MainActor in
                guard error == nil else { completion(nil); return }
                completion(try? await RoomBuilder(options: []).capturedRoom(from: capturedData))
            }
        }
    }
}

enum RoomPlanCapability {
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        RoomCaptureSession.isSupported
        #endif
    }
}

import SwiftUI
import RealityKit
import simd

struct RoomPlanUSDZView: View {
    let url: URL

    var body: some View {
        RealityKitRoomView(url: url)
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.16, blue: 0.26), Color(red: 0.16, green: 0.34, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel("Native RoomPlan 3D model")
    }
}

private struct RealityKitRoomView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.environment.background = .color(.init(red: 0.09, green: 0.16, blue: 0.26, alpha: 1))

        do {
            let model = try ModelEntity.loadModel(contentsOf: url)
            model.generateCollisionShapes(recursive: true)
            let bounds = model.visualBounds(relativeTo: model)
            let center = bounds.center
            let extents = bounds.extents
            model.position = SIMD3<Float>(-center.x, -center.y, -center.z)

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(model)

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 46
            let halfSpan = max(max(extents.x, extents.z) * 0.5, 0.4)
            let halfFOV = Float.pi * 46 / 360
            let fitDistance = halfSpan / max(tanf(halfFOV), 0.1) * 1.2
            camera.position = SIMD3<Float>(0, max(extents.y * 0.5 + fitDistance, 1.2), 0)
            camera.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
            anchor.addChild(camera)

            view.scene.addAnchor(anchor)
            view.installGestures([.translation, .rotation, .scale], for: model)
        } catch {
            // AppStore validates/downloads the attachment before this view is
            // shown. A malformed local package simply leaves an empty viewer;
            // the surrounding retry state remains the source of truth.
        }
        return view
    }

    func updateUIView(_ view: ARView, context: Context) { }
}

struct RoomPlan3DSceneView: View {
    @Bindable var store: AppStore

    var body: some View {
        Group {
            if let url = store.roomPlanModelURL, store.scene.hasReadyUSDZ {
                RoomPlanUSDZView(url: url)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 44))
                        .foregroundStyle(OneTheme.accentCyan)
                    Text("3D scan ready")
                        .font(.title3.weight(.bold))
                    Text(store.roomPlanModelError ?? "The native RoomPlan geometry is ready while the USDZ attachment loads.")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await store.retryRoomPlanModel() }
                    } label: {
                        Label(store.isRoomPlanModelLoading ? "Loading…" : "Retry 3D asset", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isRoomPlanModelLoading)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(OneTheme.surface)
            }
        }
        .task(id: store.scene.version) {
            guard store.scene.isRenderable3D else { return }
            await store.retryRoomPlanModel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Native RoomPlan 3D scene")
    }
}

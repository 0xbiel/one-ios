import SwiftUI
import RealityKit
import simd
import UIKit

struct RoomPlanUSDZView: View {
    let url: URL
    let mapID: UUID?
    let cameraRegistration: CameraRegistrationDescriptor?
    let objects: [RoomObject]
    var calibrationTargets: [RoomPlanCalibrationTarget] = []

    var body: some View {
        RealityKitRoomView(
            url: url,
            mapID: mapID,
            cameraRegistration: cameraRegistration,
            objects: objects,
            calibrationTargets: calibrationTargets
        )
        .background(
            LinearGradient(
                colors: [Color(red: 0.09, green: 0.16, blue: 0.26), Color(red: 0.16, green: 0.34, blue: 0.42)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel("3D room model")
    }
}

private struct RealityKitRoomView: UIViewRepresentable {
    let url: URL
    let mapID: UUID?
    let cameraRegistration: CameraRegistrationDescriptor?
    let objects: [RoomObject]
    let calibrationTargets: [RoomPlanCalibrationTarget]

    final class Coordinator {
        var loadedURL: URL?
        var roomModel: ModelEntity?
        var overlayContainer: Entity?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.environment.background = .color(.init(red: 0.09, green: 0.16, blue: 0.26, alpha: 1))

        loadRoomIfNeeded(into: view, context: context)
        updateOverlays(context: context)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        loadRoomIfNeeded(into: view, context: context)
        updateOverlays(context: context)
    }

    private func loadRoomIfNeeded(into view: ARView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }

        for anchor in view.scene.anchors {
            view.scene.removeAnchor(anchor)
        }
        context.coordinator.loadedURL = nil
        context.coordinator.roomModel = nil
        context.coordinator.overlayContainer = nil

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
            context.coordinator.loadedURL = url
            context.coordinator.roomModel = model
        } catch {
            // AppStore validates/downloads the attachment before this view is
            // shown. A malformed local package simply leaves an empty viewer;
            // the surrounding retry state remains the source of truth.
        }
    }

    private func updateOverlays(context: Context) {
        guard let roomModel = context.coordinator.roomModel else { return }
        context.coordinator.overlayContainer?.removeFromParent()

        let overlay = Entity()
        overlay.name = "one-roomplan-overlays"
        addCameraOverlay(to: overlay)
        addLivePeople(to: overlay)
        addCalibrationTargets(to: overlay)
        roomModel.addChild(overlay)
        context.coordinator.overlayContainer = overlay
    }

    private func addCalibrationTargets(to overlay: Entity) {
        for target in calibrationTargets {
            let color: UIColor
            switch target.state {
            case "active": color = .systemOrange
            case "complete": color = .systemTeal
            default: color = .systemGray2
            }
            let radius: Float = target.state == "active" ? 0.20 : 0.15
            let floorPoint = SIMD3<Float>(Float(target.x), Float(target.y), Float(target.z))
            let disc = ModelEntity(
                mesh: .generateCylinder(height: 0.025, radius: radius),
                materials: [SimpleMaterial(color: color.withAlphaComponent(0.92), isMetallic: false)]
            )
            disc.position = floorPoint + SIMD3<Float>(0, 0.014, 0)
            disc.name = "one-calibration-target-\(target.index)"
            overlay.addChild(disc)

            let marker = ModelEntity(
                mesh: .generateSphere(radius: target.state == "active" ? 0.075 : 0.055),
                materials: [SimpleMaterial(color: color, isMetallic: false)]
            )
            marker.position = floorPoint + SIMD3<Float>(0, 0.16, 0)
            marker.name = "one-calibration-target-pin-\(target.index)"
            overlay.addChild(marker)
        }
    }

    private func addCameraOverlay(to overlay: Entity) {
        guard cameraRegistration?.status == .positioned,
              cameraRegistration?.mapID == mapID,
              let matrix = cameraRegistration?.cameraToWorld,
              matrix.count == 4,
              matrix.allSatisfy({ $0.count == 4 }) else { return }

        let cameraMaterial = SimpleMaterial(color: UIColor.systemBlue, isMetallic: false)
        let origin = transformRoomPoint(.zero, matrix: matrix)
        let body = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.18, 0.12, 0.10)), materials: [cameraMaterial])
        body.position = origin
        body.name = "one-camera-marker"
        overlay.addChild(body)

        let localCorners: [SIMD3<Float>] = [
            SIMD3(-0.34, 0.22, -0.62),
            SIMD3(0.34, 0.22, -0.62),
            SIMD3(0.34, -0.22, -0.62),
            SIMD3(-0.34, -0.22, -0.62),
        ]
        let corners = localCorners.map { transformRoomPoint($0, matrix: matrix) }
        for corner in corners {
            if let segment = segmentEntity(from: origin, to: corner, color: UIColor.systemBlue.withAlphaComponent(0.78)) {
                overlay.addChild(segment)
            }
        }
        for index in corners.indices {
            let next = corners[(index + 1) % corners.count]
            if let segment = segmentEntity(from: corners[index], to: next, color: UIColor.systemBlue.withAlphaComponent(0.58)) {
                overlay.addChild(segment)
            }
        }
    }

    private func addLivePeople(to overlay: Entity) {
        guard let mapID else { return }
        let now = Date()
        let people = objects.filter { object in
            let label = object.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["person", "people", "human"].contains(label),
                  object.mapID == mapID,
                  let observedAt = object.observedAt else { return false }
            return now.timeIntervalSince(observedAt) <= 12
        }
        let material = SimpleMaterial(color: UIColor.systemOrange, isMetallic: false)
        for person in people {
            let floorPoint = person.position
            let foot = ModelEntity(mesh: .generateCylinder(height: 0.035, radius: 0.18), materials: [material])
            foot.position = floorPoint + SIMD3<Float>(0, 0.018, 0)
            foot.name = "one-person-foot"
            overlay.addChild(foot)

            let marker = ModelEntity(mesh: .generateSphere(radius: 0.12), materials: [material])
            marker.position = floorPoint + SIMD3<Float>(0, 0.30, 0)
            marker.name = "one-person-marker"
            overlay.addChild(marker)
        }
    }

    private func transformRoomPoint(_ point: SIMD3<Float>, matrix: [[Double]]) -> SIMD3<Float> {
        let x = Float(matrix[0][0]) * point.x + Float(matrix[0][1]) * point.y + Float(matrix[0][2]) * point.z + Float(matrix[0][3])
        let y = Float(matrix[1][0]) * point.x + Float(matrix[1][1]) * point.y + Float(matrix[1][2]) * point.z + Float(matrix[1][3])
        let z = Float(matrix[2][0]) * point.x + Float(matrix[2][1]) * point.y + Float(matrix[2][2]) * point.z + Float(matrix[2][3])
        return SIMD3(x, y, z)
    }

    private func segmentEntity(from start: SIMD3<Float>, to end: SIMD3<Float>, color: UIColor) -> ModelEntity? {
        let delta = end - start
        let length = simd_length(delta)
        guard length > 0.001 else { return nil }
        let material = SimpleMaterial(color: color, isMetallic: false)
        let segment = ModelEntity(mesh: .generateBox(size: SIMD3<Float>(0.012, 0.012, length)), materials: [material])
        segment.position = (start + end) * 0.5
        segment.orientation = simd_quatf(from: SIMD3<Float>(0, 0, 1), to: simd_normalize(delta))
        segment.name = "one-camera-frustum"
        return segment
    }
}

struct RoomPlan3DSceneView: View {
    @Bindable var store: AppStore

    var body: some View {
        Group {
            if let url = store.roomPlanModelURL, store.scene.hasReadyUSDZ {
                RoomPlanUSDZView(
                    url: url,
                    mapID: store.scene.mapID,
                    cameraRegistration: store.scene.cameraRegistration,
                    objects: store.scan.objects
                )
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 44))
                        .foregroundStyle(OneTheme.accentCyan)
                    Text("3D scan ready")
                        .font(.title3.weight(.bold))
                    Text(store.roomPlanModelError ?? (store.scene.source == .arkitVideo3D ? "The ARKit room geometry is ready while the generated USDZ model loads." : "The native RoomPlan geometry is ready while the USDZ attachment loads."))
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
        .accessibilityLabel("3D room scene")
    }
}

import SwiftUI
import RealityKit
import Combine
import simd
import UIKit

@MainActor
enum RoomPlanModelCache {
    private static var models: [URL: ModelEntity] = [:]
    private static var cancellables: [URL: AnyCancellable] = [:]

    static func preload(url: URL) async {
        guard models[url] == nil else { return }

        let model: ModelEntity? = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ModelEntity, Error>) in
            var resolved = false
            let cancellable = ModelEntity.loadModelAsync(contentsOf: url)
                .sink(receiveCompletion: { completion in
                    Self.cancellables[url] = nil
                    if !resolved, case let .failure(error) = completion {
                        resolved = true
                        continuation.resume(throwing: error)
                    }
                }, receiveValue: { model in
                    guard !resolved else { return }
                    resolved = true
                    model.generateCollisionShapes(recursive: true)
                    continuation.resume(returning: model)
                })
            Self.cancellables[url] = cancellable
        }
        if let model {
            models[url] = model
        }
    }

    static func clone(for url: URL) -> ModelEntity? {
        models[url]?.clone(recursive: true) as? ModelEntity
    }
}

struct RoomPlanUSDZView: View {
    let url: URL
    let mapID: UUID?
    let cameraRegistration: CameraRegistrationDescriptor?
    var cameraRegistrations: [CameraRegistrationDescriptor] = []
    let objects: [RoomObject]
    var onPresenceSelected: ((RoomObject) -> Void)? = nil

    var body: some View {
        RealityKitRoomView(
            url: url,
            mapID: mapID,
            cameraRegistration: cameraRegistration,
            cameraRegistrations: cameraRegistrations,
            objects: objects,
            onPresenceSelected: onPresenceSelected
        )
        .background(Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.025, green: 0.03, blue: 0.04, alpha: 1)
                : .white
        }))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityLabel("3D room model")
    }
}

private struct RealityKitRoomView: UIViewRepresentable {
    let url: URL
    let mapID: UUID?
    let cameraRegistration: CameraRegistrationDescriptor?
    let cameraRegistrations: [CameraRegistrationDescriptor]
    let objects: [RoomObject]
    let onPresenceSelected: ((RoomObject) -> Void)?

    final class Coordinator: NSObject {
        var loadedURL: URL?
        var loadingURL: URL?
        var modelLoadCancellable: AnyCancellable?
        var roomModel: ModelEntity?
        var overlayContainer: Entity?
        var onPresenceSelected: ((RoomObject) -> Void)?
        var objects: [RoomObject] = []

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ARView,
                  let entity = view.entity(at: gesture.location(in: view)) else { return }
            guard let id = entity.name.split(separator: "-").last.flatMap({ UUID(uuidString: String($0)) }),
                  entity.name.contains("one-presence-orb"),
                  let object = objects.first(where: { $0.id == id }) else { return }
            onPresenceSelected?(object)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        context.coordinator.onPresenceSelected = onPresenceSelected
        context.coordinator.objects = objects
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:))))
        updatePalette(for: view, context: context)

        loadRoomIfNeeded(into: view, context: context)
        updateOverlays(context: context)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.onPresenceSelected = onPresenceSelected
        context.coordinator.objects = objects
        updatePalette(for: view, context: context)
        loadRoomIfNeeded(into: view, context: context)
        updateOverlays(context: context)
    }

    private func updatePalette(for view: ARView, context: Context) {
        let darkMode = view.traitCollection.userInterfaceStyle == .dark
        view.environment.background = .color(
            darkMode
                ? .init(red: 0.025, green: 0.03, blue: 0.04, alpha: 1)
                : .init(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        )
    }

    private func loadRoomIfNeeded(into view: ARView, context: Context) {
        guard context.coordinator.loadedURL != url,
              context.coordinator.loadingURL != url else { return }

        for anchor in view.scene.anchors {
            view.scene.removeAnchor(anchor)
        }
        context.coordinator.modelLoadCancellable?.cancel()
        context.coordinator.modelLoadCancellable = nil
        context.coordinator.loadedURL = nil
        context.coordinator.loadingURL = url
        context.coordinator.roomModel = nil
        context.coordinator.overlayContainer = nil

        if let model = RoomPlanModelCache.clone(for: url) {
            install(model, into: view, context: context)
            return
        }

        context.coordinator.modelLoadCancellable = ModelEntity.loadModelAsync(contentsOf: url)
            .sink(receiveCompletion: { [weak coordinator = context.coordinator] _ in
                guard let coordinator, coordinator.loadingURL == url else { return }
                coordinator.loadingURL = nil
                coordinator.modelLoadCancellable = nil
            }, receiveValue: { [weak coordinator = context.coordinator] model in
                guard let coordinator, coordinator.loadingURL == url else { return }
                install(model, into: view, context: context)
                coordinator.modelLoadCancellable = nil
            })
    }

    private func install(_ model: ModelEntity, into view: ARView, context: Context) {
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
        context.coordinator.loadedURL = url
        context.coordinator.loadingURL = nil
        context.coordinator.roomModel = model
        view.installGestures([.translation, .rotation, .scale], for: model)
        updateOverlays(context: context)
    }

    private func updateOverlays(context: Context) {
        guard let roomModel = context.coordinator.roomModel else { return }
        context.coordinator.overlayContainer?.removeFromParent()

        let overlay = Entity()
        overlay.name = "one-roomplan-overlays"
        addCameraOverlays(to: overlay)
        addLivePeople(to: overlay)
        roomModel.addChild(overlay)
        context.coordinator.overlayContainer = overlay
    }

    private func addCameraOverlays(to overlay: Entity) {
        let registrations = cameraRegistrations.isEmpty ? (cameraRegistration.map { [$0] } ?? []) : cameraRegistrations
        for (index, registration) in registrations.enumerated() {
            guard let matrix = registration.cameraToWorld,
                  matrix.count == 4,
                  matrix.allSatisfy({ $0.count == 4 }) else { continue }

            let origin = transformRoomPoint(.zero, matrix: matrix)
            let markerColor = registration.status == .positioned ? UIColor.systemBlue : UIColor.systemRed
            let cameraMaterial = SimpleMaterial(color: markerColor, isMetallic: false)
            let floorPoint = SIMD3<Float>(origin.x, 0, origin.z)
            let markerID = registration.cameraID?.uuidString ?? String(index)

            let foot = ModelEntity(mesh: .generateCylinder(height: 0.016, radius: 0.065), materials: [cameraMaterial])
            foot.position = floorPoint + SIMD3<Float>(0, 0.012, 0)
            foot.name = "one-camera-orb-\(markerID)"
            overlay.addChild(foot)

            let marker = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [cameraMaterial])
            marker.position = floorPoint + SIMD3<Float>(0, 0.105, 0)
            marker.name = "one-camera-orb-marker-\(markerID)"
            overlay.addChild(marker)

            guard let localCorners = calibratedFrustumCorners(registration) else { continue }
            let corners = localCorners.map { transformRoomPoint($0, matrix: matrix) }
            for corner in corners {
                if let segment = segmentEntity(from: origin, to: corner, color: markerColor.withAlphaComponent(0.78)) {
                    overlay.addChild(segment)
                }
            }
            for cornerIndex in corners.indices {
                let next = corners[(cornerIndex + 1) % corners.count]
                if let segment = segmentEntity(from: corners[cornerIndex], to: next, color: markerColor.withAlphaComponent(0.58)) {
                    overlay.addChild(segment)
                }
            }
        }
    }

    private func addLivePeople(to overlay: Entity) {
        guard let mapID else { return }
        let now = Date()
        var newestByID: [UUID: RoomObject] = [:]
        for object in objects {
            if let previous = newestByID[object.id],
               let previousDate = previous.observedAt,
               let currentDate = object.observedAt,
               previousDate > currentDate { continue }
            newestByID[object.id] = object
        }
        let people = newestByID.values.filter { object in
            let label = object.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["person", "people", "human"].contains(label),
                  object.mapID == mapID,
                  let observedAt = object.observedAt else { return false }
            if object.presenceState == .stale { return false }
            if object.presenceState == .current || object.presenceState == .recent { return true }
            return now.timeIntervalSince(observedAt) <= 120
        }
        for person in people {
            let age = person.observedAt.map { max(0, now.timeIntervalSince($0)) } ?? 121
            let isCurrent = person.presenceState == .current || (person.presenceState == nil && age <= 12)
            let alpha: CGFloat = isCurrent ? 0.96 : 0.45
            let material = SimpleMaterial(color: UIColor.systemOrange.withAlphaComponent(alpha), isMetallic: false)
            let floorPoint = person.position
            let foot = ModelEntity(mesh: .generateCylinder(height: 0.016, radius: isCurrent ? 0.07 : 0.05), materials: [material])
            foot.position = floorPoint + SIMD3<Float>(0, 0.012, 0)
            foot.name = "one-presence-orb-\(isCurrent ? "now" : "recent")-\(person.id.uuidString)"
            overlay.addChild(foot)

            let marker = ModelEntity(mesh: .generateSphere(radius: isCurrent ? 0.06 : 0.045), materials: [material])
            marker.position = floorPoint + SIMD3<Float>(0, isCurrent ? 0.12 : 0.08, 0)
            marker.name = "one-presence-orb-\(isCurrent ? "now" : "recent")-marker-\(person.id.uuidString)"
            overlay.addChild(marker)
        }
    }

    private func calibratedFrustumCorners(_ registration: CameraRegistrationDescriptor) -> [SIMD3<Float>]? {
        let distance: Double = 0.62
        let minimumFOV = 30.0
        let maximumFOV = 120.0
        var horizontalFOV = registration.intrinsics?.fovDegrees
        if horizontalFOV == nil,
           let matrix = registration.intrinsics?.matrix,
           matrix.count == 3,
           matrix.allSatisfy({ $0.count == 3 }),
           matrix[0][0] > 0,
           matrix[0][2] > 0 {
            horizontalFOV = 2 * atan(matrix[0][2] / matrix[0][0]) * 180 / .pi
        }
        guard let horizontalFOV,
              horizontalFOV >= minimumFOV,
              horizontalFOV <= maximumFOV else { return nil }
        let halfWidth = tan(horizontalFOV * .pi / 360) * distance
        var halfHeight: Double?
        if let matrix = registration.intrinsics?.matrix,
           matrix.count == 3,
           matrix.allSatisfy({ $0.count == 3 }),
           matrix[1][1] > 0,
           matrix[1][2] > 0 {
            halfHeight = distance * matrix[1][2] / matrix[1][1]
        }
        guard let halfHeight else {
            return [
                SIMD3(Float(-halfWidth), 0, Float(-distance)),
                SIMD3(Float(halfWidth), 0, Float(-distance)),
            ]
        }
        return [
            SIMD3(Float(-halfWidth), Float(halfHeight), Float(-distance)),
            SIMD3(Float(halfWidth), Float(halfHeight), Float(-distance)),
            SIMD3(Float(halfWidth), Float(-halfHeight), Float(-distance)),
            SIMD3(Float(-halfWidth), Float(-halfHeight), Float(-distance)),
        ]
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
    @State private var selectedPresence: RoomObject?

    var body: some View {
        Group {
            if let url = store.roomPlanModelURL, store.scene.hasReadyUSDZ {
                RoomPlanUSDZView(
                    url: url,
                    mapID: store.scene.mapID,
                    cameraRegistration: store.scene.cameraRegistration,
                    cameraRegistrations: store.scene.cameraRegistrations,
                    objects: store.scan.objects,
                    onPresenceSelected: { selectedPresence = $0 }
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
        .sheet(item: $selectedPresence) { presence in
            VStack(alignment: .leading, spacing: 14) {
                Text("Presence detected")
                    .font(.title2.weight(.bold))
                if let cameraID = presence.cameraID,
                   let data = store.cameraReferenceImages[cameraID],
                   let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                } else {
                    Text("No saved camera frame is available for this observation yet.")
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                Text("Detected at \(presence.observedAt?.formatted() ?? "unknown time")")
                    .font(.caption)
            }
            .padding(24)
            .presentationDetents([.medium])
        }
        .task(id: store.scene.version) {
            guard store.scene.isRenderable3D else { return }
            await store.retryRoomPlanModel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D room scene")
    }
}

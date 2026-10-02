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

// Keep geometry in its original metric frame; gestures move only the viewer.
struct HomeMapViewport {
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = .pi * 0.31
    private(set) var distance: Float = 10
    private(set) var fitDistance: Float = 10
    var target = SIMD3<Float>.zero

    mutating func fit(extents: SIMD3<Float>, aspect: Float, preservePose: Bool = false) {
        let previousYaw = yaw, previousPitch = pitch
        let previousDistanceRatio = distance / fitDistance
        let halfFOV = Float.pi * 46 / 360
        let horizontal = max(aspect, 0.25) * tanf(halfFOV)
        let fitPitch = Float.pi * 0.31
        let horizontalSpan = max(extents.x * 0.5, 0.4)
        let verticalSpan = max(extents.y * 0.5 * cosf(fitPitch) + extents.z * 0.5 * sinf(fitPitch), 0.4)
        // The nearest corners enlarge under perspective; include their camera-axis depth.
        let nearestDepth = extents.y * 0.5 * sinf(fitPitch) + extents.z * 0.5 * cosf(fitPitch)
        fitDistance = (max(horizontalSpan / horizontal, verticalSpan / tanf(halfFOV)) + nearestDepth) * 1.08
        if preservePose {
            yaw = previousYaw
            pitch = previousPitch
            distance = min(max(previousDistanceRatio * fitDistance, fitDistance * 0.35), fitDistance * 3)
        } else { reset() }
    }

    mutating func reset() {
        yaw = 0
        pitch = .pi * 0.31
        distance = fitDistance
        target = .zero
    }

    mutating func zoom(scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        distance = min(max(distance / scale, fitDistance * 0.35), fitDistance * 3)
    }

    mutating func orbit(dx: Float, dy: Float) {
        guard dx.isFinite, dy.isFinite else { return }
        yaw = (yaw - dx * 0.006).remainder(dividingBy: 2 * .pi)
        pitch = min(max(pitch + dy * 0.006, .pi / 9), .pi * 4 / 9)
    }

    var eye: SIMD3<Float> {
        target + SIMD3(distance * cosf(pitch) * sinf(yaw), distance * sinf(pitch), distance * cosf(pitch) * cosf(yaw))
    }
    var zoomPercent: Int { Int((fitDistance / distance * 100).rounded()) }
}

struct RoomPlanUSDZView: View {
    let url: URL
    let mapID: UUID?
    let cameraRegistration: CameraRegistrationDescriptor?
    var cameraRegistrations: [CameraRegistrationDescriptor] = []
    let objects: [RoomObject]
    var pairedCameras: [PairedCamera] = []
    var geometry: RoomPlanNormalizedScan? = nil
    var floorCoverage: [MapFloorCoverageModel] = []
    var onPresenceSelected: ((RoomObject) -> Void)? = nil
    var onCameraSelected: ((CameraRegistrationDescriptor) -> Void)? = nil

    var body: some View {
        RealityKitRoomView(
            url: url,
            mapID: mapID,
            cameraRegistration: cameraRegistration,
            cameraRegistrations: cameraRegistrations,
            objects: objects,
            pairedCameras: pairedCameras,
            geometry: geometry,
            floorCoverage: floorCoverage,
            onPresenceSelected: onPresenceSelected,
            onCameraSelected: onCameraSelected
        )
        .background(Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.025, green: 0.03, blue: 0.04, alpha: 1)
                : .white
        }))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D room model")
    }
}

private struct RealityKitRoomView: UIViewRepresentable {
    let url: URL
    let mapID: UUID?
    let cameraRegistration: CameraRegistrationDescriptor?
    let cameraRegistrations: [CameraRegistrationDescriptor]
    let objects: [RoomObject]
    let pairedCameras: [PairedCamera]
    let geometry: RoomPlanNormalizedScan?
    let floorCoverage: [MapFloorCoverageModel]
    let onPresenceSelected: ((RoomObject) -> Void)?
    let onCameraSelected: ((CameraRegistrationDescriptor) -> Void)?

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var loadedURL: URL?
        var loadingURL: URL?
        var modelLoadCancellable: AnyCancellable?
        var roomModel: ModelEntity?
        var overlayContainer: Entity?
        var onPresenceSelected: ((RoomObject) -> Void)?
        var onCameraSelected: ((CameraRegistrationDescriptor) -> Void)?
        var objects: [RoomObject] = []
        var projectionSubscription: (any Cancellable)?
        var markers: [(anchor: Entity, button: UIButton, title: String, size: CGSize)] = []
        weak var view: ARView?
        var camera: PerspectiveCamera?
        var modelExtents = SIMD3<Float>(1, 1, 1)
        var lastAspect: Float?

        func fitForViewIfNeeded() {
            guard let view, camera != nil, view.bounds.width > 1, view.bounds.height > 1 else { return }
            let aspect = Float(view.bounds.width / view.bounds.height)
            guard lastAspect == nil || abs(aspect - lastAspect!) > 0.01 else { return }
            viewport.fit(extents: modelExtents, aspect: aspect, preservePose: lastAspect != nil)
            lastAspect = aspect
            updateCamera()
        }
        var viewport = HomeMapViewport()
        var resetButton: UIButton?
        var navigationElement: UIAccessibilityElement?

        func updateCamera() {
            camera?.look(at: viewport.target, from: viewport.eye, relativeTo: nil)
            navigationElement?.accessibilityValue = "Zoom \(viewport.zoomPercent) percent"
        }

        func refreshAccessibility() {
            guard let view else { return }
            navigationElement?.accessibilityFrameInContainerSpace = view.bounds
            view.accessibilityElements = (navigationElement.map { [$0] as [Any] } ?? [])
                + (resetButton.map { [$0] as [Any] } ?? []) + markers.map { $0.button as Any }
        }

        @objc func resetView() {
            viewport.reset()
            updateCamera()
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            viewport.zoom(scale: Float(gesture.scale))
            gesture.scale = 1
            updateCamera()
        }

        @objc func handleOrbit(_ gesture: UIPanGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed, let view else { return }
            let delta = gesture.translation(in: view)
            viewport.orbit(dx: Float(delta.x), dy: Float(delta.y))
            gesture.setTranslation(.zero, in: view)
            updateCamera()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            (gestureRecognizer is UIPinchGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
                || (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UIPinchGestureRecognizer)
        }

        func clearMarkers() {
            markers.forEach { $0.button.removeFromSuperview() }
            markers.removeAll()
            refreshAccessibility()
        }

        func addMarker(anchor: Entity, style: MapMarkerStyle, title: String, accessibilityLabel: String, isRecent: Bool, symbol: String? = nil, action: @escaping () -> Void) {
            guard let view else { return }
            var configuration = UIButton.Configuration.tinted()
            configuration.title = nil
            configuration.image = UIImage(systemName: symbol ?? style.symbol)?.withTintColor(style.uiColor.withAlphaComponent(isRecent ? 0.38 : 1), renderingMode: .alwaysOriginal)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: min(UIFont.preferredFont(forTextStyle: .caption1).pointSize, 16))
            configuration.imagePadding = 5
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10)
            configuration.baseForegroundColor = .label
            configuration.background.backgroundColor = .secondarySystemBackground
            configuration.background.strokeColor = style.uiColor.withAlphaComponent(isRecent ? 0.25 : 0.65)
            configuration.background.strokeWidth = 0
            configuration.cornerStyle = .capsule
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = UIFont.systemFont(ofSize: min(UIFont.preferredFont(forTextStyle: .caption1).pointSize, 16))
                return attributes
            }
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
            button.isAccessibilityElement = true
            button.accessibilityLabel = accessibilityLabel
            button.accessibilityHint = "Shows marker details"
            button.accessibilityIdentifier = accessibilityLabel.hasPrefix("Camera") ? "map-camera-marker" : "map-person-marker"
            button.sizeToFit()
            button.bounds.size.height = max(44, button.bounds.height)
            view.addSubview(button)
            markers.append((anchor, button, title, button.bounds.size))
            refreshAccessibility()
        }

        func projectMarkers() {
            guard let view else { return }
            resetButton?.frame = CGRect(x: max(12, view.bounds.width - 60), y: view.safeAreaInsets.top + 12, width: 44, height: 44)
            refreshAccessibility()
            fitForViewIfNeeded()
            var occupied: [CGRect] = []
            for marker in markers {
                guard let point = view.project(marker.anchor.position(relativeTo: nil)),
                      view.bounds.contains(point) else {
                    marker.button.isHidden = true
                    continue
                }
                marker.button.isHidden = false
                let halfWidth = marker.size.width / 2
                let center = CGPoint(
                    x: min(max(point.x, halfWidth + 4), max(halfWidth + 4, view.bounds.width - halfWidth - 4)),
                    y: max(marker.size.height / 2 + 4, point.y - 24)
                )
                let fullFrame = CGRect(x: center.x - halfWidth, y: center.y - marker.size.height / 2, width: marker.size.width, height: marker.size.height)
                _ = occupied.contains { $0.intersects(fullFrame.insetBy(dx: -3, dy: -3)) }
                let title: String? = nil
                if marker.button.configuration?.title != title {
                    // Keep the location and touch target; collapse a crowded label to its state icon.
                    marker.button.configuration?.title = title
                    marker.button.sizeToFit()
                    marker.button.bounds.size.width = max(44, marker.button.bounds.width)
                    marker.button.bounds.size.height = max(44, marker.button.bounds.height)
                }
                marker.button.center = center
                occupied.append(marker.button.frame)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !(touch.view is UIControl) && !(touch.view?.superview is UIControl)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? ARView,
                  let entity = view.entity(at: gesture.location(in: view)),
                  entity.name.contains("one-presence-orb"),
                  let id = UUID(uuidString: String(entity.name.suffix(36))),
                  let object = objects.first(where: { $0.id == id }) else { return }
            onPresenceSelected?(object)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.cameraMode = .nonAR
        view.isAccessibilityElement = false
        context.coordinator.onPresenceSelected = onPresenceSelected
        context.coordinator.onCameraSelected = onCameraSelected
        context.coordinator.objects = objects
        context.coordinator.view = view
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleOrbit(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        tap.require(toFail: pan)
        let navigation = UIAccessibilityElement(accessibilityContainer: view)
        navigation.accessibilityLabel = "3D home map"
        navigation.accessibilityIdentifier = "home-3d-viewport"
        navigation.accessibilityTraits = [.allowsDirectInteraction]
        navigation.accessibilityHint = "Drag to orbit. Pinch to zoom."
        context.coordinator.navigationElement = navigation
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "arrow.counterclockwise")
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
        configuration.cornerStyle = .capsule
        let reset = UIButton(configuration: configuration, primaryAction: UIAction { [weak coordinator = context.coordinator] _ in coordinator?.resetView() })
        reset.accessibilityLabel = "Fit map to view"
        reset.accessibilityIdentifier = "map-reset-view"
        view.addSubview(reset)
        context.coordinator.resetButton = reset
        context.coordinator.refreshAccessibility()
        context.coordinator.projectionSubscription = view.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator = context.coordinator] _ in
            Task { @MainActor in coordinator?.projectMarkers() }
        }
        updatePalette(for: view, context: context)

        loadRoomIfNeeded(into: view, context: context)
        updateOverlays(context: context)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.onPresenceSelected = onPresenceSelected
        context.coordinator.onCameraSelected = onCameraSelected
        context.coordinator.objects = objects
        updatePalette(for: view, context: context)
        loadRoomIfNeeded(into: view, context: context)
        updateOverlays(context: context)
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        coordinator.projectionSubscription?.cancel()
        coordinator.modelLoadCancellable?.cancel()
        coordinator.clearMarkers()
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

#if DEBUG
        if url.scheme == "one-demo-map" {
            let floor = ModelEntity(mesh: .generateBox(width: 6, height: 0.06, depth: 8), materials: [SimpleMaterial(color: .systemGray5, isMetallic: false)])
            for x: Float in [-2.95, 2.95] {
                let wall = ModelEntity(mesh: .generateBox(width: 0.10, height: 0.35, depth: 8), materials: [SimpleMaterial(color: .systemGray3, isMetallic: false)])
                wall.position = SIMD3(x, 0.15, 0)
                floor.addChild(wall)
            }
            for z: Float in [-3.95, 0, 3.95] {
                let wall = ModelEntity(mesh: .generateBox(width: 6, height: 0.35, depth: 0.10), materials: [SimpleMaterial(color: .systemGray3, isMetallic: false)])
                wall.position = SIMD3(0, 0.15, z)
                floor.addChild(wall)
            }
            floor.generateCollisionShapes(recursive: true)
            install(floor, into: view, context: context)
            return
        }
#endif

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
        let aspect = max(Float(view.bounds.width / max(view.bounds.height, 1)), 0.25)
        context.coordinator.modelExtents = extents
        context.coordinator.lastAspect = nil
        context.coordinator.viewport.fit(extents: extents, aspect: aspect)
        context.coordinator.camera = camera
        context.coordinator.updateCamera()
        anchor.addChild(camera)

        view.scene.addAnchor(anchor)
        context.coordinator.loadedURL = url
        context.coordinator.loadingURL = nil
        context.coordinator.roomModel = model
        // World geometry and camera registrations remain fixed during navigation.
        updateOverlays(context: context)
    }

    private func updateOverlays(context: Context) {
        guard let roomModel = context.coordinator.roomModel else { return }
        context.coordinator.overlayContainer?.removeFromParent()
        context.coordinator.clearMarkers()

        let overlay = Entity()
        overlay.name = "one-roomplan-overlays"
        addFloorCoverage(to: overlay)
        addCameraOverlays(to: overlay, coordinator: context.coordinator)
        addLivePeople(to: overlay, coordinator: context.coordinator)
        roomModel.addChild(overlay)
        context.coordinator.overlayContainer = overlay
    }

    private func addFloorCoverage(to overlay: Entity) {
        for floor in geometry?.floors ?? [] {
            // Canonical polygons are world-space. A convex check avoids filling
            // concave/invalid geometry beyond its actual floor footprint.
            let vertices = floor.vertices
            guard vertices.count >= 3, vertices.count <= 64 else { continue }
            let signs = vertices.indices.map { index -> Double in
                let a = vertices[index], b = vertices[(index + 1) % vertices.count], c = vertices[(index + 2) % vertices.count]
                return (b.x - a.x) * (c.z - b.z) - (b.z - a.z) * (c.x - b.x)
            }.filter { abs($0) > 0.000001 }
            guard !signs.isEmpty, signs.allSatisfy({ $0 > 0 }) || signs.allSatisfy({ $0 < 0 }) else { continue }
            let coverage = floorCoverage.first { $0.floorID == floor.id }
            let state = coverage?.currentState() ?? .unknown
            let color: UIColor
            switch state {
            case .covered: color = .systemBlue
            case .uncovered: color = .systemRed
            case .unknown: color = .systemGray3
            }
            var descriptor = MeshDescriptor(name: "floor-coverage")
            let topY = Float(floor.center.y + floor.dimensions.y / 2 + 0.012)
            descriptor.positions = MeshBuffers.Positions(vertices.map { SIMD3<Float>(Float($0.x), topY, Float($0.z)) })
            var indices: [UInt32] = []
            for index in 1..<(vertices.count - 1) {
                indices += [0, UInt32(index), UInt32(index + 1), 0, UInt32(index + 1), UInt32(index)]
            }
            descriptor.primitives = .triangles(indices)
            guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
            let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
            entity.name = "one-floor-coverage-\(floor.id)"
            overlay.addChild(entity)
        }
    }

    private func addCameraOverlays(to overlay: Entity, coordinator: Coordinator) {
        let registrations = cameraRegistrations.isEmpty ? (cameraRegistration.map { [$0] } ?? []) : cameraRegistrations
        for (index, registration) in registrations.enumerated() {
            guard let matrix = registration.cameraToWorld,
                  matrix.count == 4,
                  matrix.allSatisfy({ $0.count == 4 }) else { continue }

            let origin = transformRoomPoint(.zero, matrix: matrix)
            let markerState = MapMarkerStyle.camera(registration, objects: objects, cameras: pairedCameras)
            let markerColor = markerState.uiColor.withAlphaComponent(markerState == .unknownRecent ? 0.38 : 0.96)
            let cameraMaterial = SimpleMaterial(color: markerColor, isMetallic: false)
            let floorPoint = SIMD3<Float>(origin.x, 0, origin.z)
            let markerID = registration.cameraID?.uuidString ?? String(index)

            let foot = ModelEntity(mesh: .generateCylinder(height: 0.018, radius: 0.105), materials: [cameraMaterial])
            foot.position = floorPoint + SIMD3<Float>(0, 0.012, 0)
            foot.name = "one-camera-orb-\(markerID)"
            overlay.addChild(foot)

            coordinator.addMarker(
                anchor: foot,
                style: markerState,
                title: markerState == .cameraOffline ? "Offline" : "Camera",
                accessibilityLabel: "Camera, \(registration.cameraName ?? "Room camera"), \(markerState.title)",
                isRecent: markerState == .unknownRecent,
                symbol: markerState == .cameraOffline ? "video.slash.fill" : "camera.fill"
            ) { [weak coordinator] in coordinator?.onCameraSelected?(registration) }


        }
    }

    private func addLivePeople(to overlay: Entity, coordinator: Coordinator) {
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
        let people = newestByID.values.filter { $0.mapID == mapID && MapPresenceAppearance.presence($0, now: now) != nil }
        for person in people {
            guard let appearance = MapPresenceAppearance.presence(person, now: now) else { continue }
            let isCurrent = !appearance.isRecent
            let material = SimpleMaterial(color: appearance.style.uiColor.withAlphaComponent(appearance.opacity), isMetallic: false)
            let floorPoint = person.position
            let foot = ModelEntity(mesh: .generateCylinder(height: 0.018, radius: isCurrent ? 0.11 : 0.085), materials: [material])
            foot.position = floorPoint + SIMD3<Float>(0, 0.012, 0)
            foot.name = "one-presence-orb-\(isCurrent ? "now" : "recent")-\(person.id.uuidString)"
            overlay.addChild(foot)

            foot.generateCollisionShapes(recursive: false)
            coordinator.addMarker(
                anchor: foot,
                style: appearance.style,
                title: person.identityStatus == "simulated" ? (person.identityName ?? "Unknown") : appearance.style == .recognized ? (person.identityName ?? "Person") : (appearance.isRecent ? "Recent" : "Unknown"),
                accessibilityLabel: "\(appearance.style.title), \((appearance.style == .recognized || person.identityStatus == "simulated") ? (person.identityName ?? "Person") : "Anonymous person")\(appearance.isRecent ? ", seen recently" : "")",
                isRecent: appearance.isRecent
            ) { [weak coordinator] in coordinator?.onPresenceSelected?(person) }

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
    var onPresenceSelected: ((RoomObject) -> Void)? = nil
    var onCameraSelected: ((CameraRegistrationDescriptor) -> Void)? = nil

    var body: some View {
        Group {
            if let url = store.roomPlanModelURL, store.scene.hasReadyUSDZ {
                RoomPlanUSDZView(
                    url: url,
                    mapID: store.scene.mapID,
                    cameraRegistration: store.scene.cameraRegistration,
                    cameraRegistrations: store.scene.cameraRegistrations,
                    objects: store.scan.objects,
                    pairedCameras: store.pairedCameras,
                    geometry: store.scene.canonicalGeometry ?? store.scene.geometry,
                    onPresenceSelected: onPresenceSelected,
                    onCameraSelected: onCameraSelected
                )
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 44))
                        .foregroundStyle(OneTheme.accentCyan)
                    Text("3D scan ready")
                        .font(.title3.weight(.bold))
                    Text(store.roomPlanModelError ?? "Preparing your 3D model…")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await store.retryRoomPlanModel() }
                    } label: {
                        Label(store.isRoomPlanModelLoading ? "Loading…" : "Retry", systemImage: "arrow.clockwise")
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

struct MapPresenceDetails: View {
    let presence: RoomObject
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text((presence.identityStatus == "matched" || presence.identityStatus == "simulated") ? (presence.identityName ?? "Unknown person") : "Unknown person")
                .font(.system(.title3, design: .rounded).weight(.bold))
            if let appearance = MapPresenceAppearance.presence(presence) {
                OneStatusBadge(title: appearance.style.title, symbol: appearance.style.symbol, tint: appearance.style.color, faded: appearance.isRecent)
            }
            Text("\(presence.identityStatus == "simulated" ? "Scripted at" : "Last seen") \(presence.observedAt?.formatted(date: .abbreviated, time: .shortened) ?? "an unknown time")")
                .font(.subheadline)
                .foregroundStyle(OneTheme.secondaryInk)
            if let camera = store.pairedCameras.first(where: { $0.id == presence.cameraID }) {
                Label(camera.name, systemImage: "camera.fill").font(.subheadline)
            }
            if let cameraID = presence.cameraID,
               let data = store.cameraReferenceImages[cameraID],
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MapCameraDetails: View {
    let camera: CameraRegistrationDescriptor
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(camera.cameraName ?? "Room camera")
                .font(.system(.title3, design: .rounded).weight(.bold))
            MapLegendBadge(style: MapMarkerStyle.camera(camera, objects: store.scan.objects, cameras: store.pairedCameras))
            if let room = store.cameraRooms.first(where: { $0.id == camera.roomID }) {
                Label(room.name, systemImage: "door.left.hand.open").font(.subheadline)
            }
            DisclosureGroup("Placement details") {
                Text(camera.status == .positioned ? "Position saved" : "Position pending")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

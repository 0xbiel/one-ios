import SwiftUI
import UIKit
import RoomPlan
import ARKit
import SceneKit
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
    let visualDiagnostics: RoomPlanVisualCaptureDiagnostics
}

struct RoomPlanVisualCaptureDiagnostics: Sendable, Equatable {
    let samplingAttempts: Int
    let missingFrameCount: Int
    let imageEncodingFailureCount: Int
    let invalidMatrixCount: Int
    let capturedSampleCount: Int
    let depthSampleCount: Int
    let lastTrackingState: String
    let estimatedAreaSquareMeters: Double?
    let recommendedVisualSampleCount: Int
}

struct RoomPlanVisualSample: Sendable {
    let jpegData: Data
    let width: Int
    let height: Int
    let depthData: Data?
    let depthWidth: Int?
    let depthHeight: Int?
    let intrinsics: [[Double]]
    let cameraToWorld: [[Double]]
    let capturedAt: Date
}

struct RoomPlanCaptureView: UIViewRepresentable {
    @Binding var isCapturing: Bool
    let arSession: ARSession
    var onComplete: @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero, arSession: arSession)
        view.captureSession.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: RoomCaptureView, context: Context) {
        if isCapturing {
            guard !context.coordinator.hasStarted else { return }
            let configuration = RoomCaptureSession.Configuration()
            context.coordinator.hasStarted = true
            context.coordinator.hasStopped = false
            view.captureSession.run(configuration: configuration)
            context.coordinator.beginVisualSampling(session: view.captureSession)
            return
        }

        guard context.coordinator.hasStarted, !context.coordinator.hasStopped else { return }
        context.coordinator.hasStopped = true
        context.coordinator.stopVisualSampling()
        view.captureSession.stop(pauseARSession: false)
    }

    static func dismantleUIView(_ view: RoomCaptureView, coordinator: Coordinator) {
        coordinator.stopVisualSampling()
        view.captureSession.stop(pauseARSession: false)
    }

    final class Coordinator: NSObject, RoomCaptureSessionDelegate {
        let onComplete: @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void
        var hasStarted = false
        var hasStopped = false
        private var visualSamples: [RoomPlanVisualSample] = []
        private var lastVisualSampleTimestamp: TimeInterval?
        private var visualSamplingSession: RoomCaptureSession?
        private var visualSamplingTimer: DispatchSourceTimer?
        private let imageContext = CIContext(options: [.cacheIntermediates: false])
        // Keep a large temporal reservoir, then choose the final number of
        // viewpoints from the measured RoomPlan footprint when the scan ends.
        // This lets a large room contribute more landmarks without retaining
        // an unbounded stream of RGB + LiDAR buffers on the phone.
        private let maxBufferedVisualSamples = 192
        private let visualSampleInterval: TimeInterval = 0.5
        private var samplingAttempts = 0
        private var missingFrameCount = 0
        private var imageEncodingFailureCount = 0
        private var invalidMatrixCount = 0
        private var lastTrackingState = "unavailable"
        init(onComplete: @escaping @MainActor @Sendable (Result<RoomPlanCaptureResult, RoomPlanCaptureError>) -> Void) { self.onComplete = onComplete }

        func beginVisualSampling(session: RoomCaptureSession) {
            stopVisualSampling()
            visualSamples.removeAll(keepingCapacity: true)
            lastVisualSampleTimestamp = nil
            samplingAttempts = 0
            missingFrameCount = 0
            imageEncodingFailureCount = 0
            invalidMatrixCount = 0
            lastTrackingState = "unavailable"
            visualSamplingSession = session
            if let frame = session.arSession.currentFrame { captureVisualSample(from: frame) }
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now(), repeating: visualSampleInterval, leeway: .milliseconds(80))
            timer.setEventHandler { [weak self] in
                self?.captureScheduledVisualSample()
            }
            visualSamplingTimer = timer
            timer.resume()
        }

        func stopVisualSampling() {
            visualSamplingTimer?.setEventHandler {}
            visualSamplingTimer?.cancel()
            visualSamplingTimer = nil
            visualSamplingSession = nil
            lastVisualSampleTimestamp = nil
        }

        private func captureScheduledVisualSample() {
            captureVisualSample(from: visualSamplingSession?.arSession.currentFrame)
        }

        private func captureVisualSample(from frame: ARFrame?, force: Bool = false) {
            samplingAttempts += 1
            guard let frame else {
                missingFrameCount += 1
                return
            }
            switch frame.camera.trackingState {
            case .normal: lastTrackingState = "normal"
            case .limited: lastTrackingState = "limited"
            case .notAvailable:
                lastTrackingState = "unavailable"
            @unknown default:
                lastTrackingState = "unavailable"
            }
            if !force, let lastVisualSampleTimestamp,
               frame.timestamp - lastVisualSampleTimestamp < visualSampleInterval {
                return
            }
            let capturedImage = frame.capturedImage
            let sourceWidth = CVPixelBufferGetWidth(capturedImage)
            let sourceHeight = CVPixelBufferGetHeight(capturedImage)
            guard sourceWidth > 0, sourceHeight > 0 else { return }

            let image = CIImage(cvPixelBuffer: capturedImage)
            // Keep enough high-frequency texture for the local SIFT descriptor
            // index. The bytes remain transient and the backend still applies
            // its bounded frame-size contract before decoding them.
            guard let cgImage = imageContext.createCGImage(image, from: image.extent),
                  let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82) else {
                imageEncodingFailureCount += 1
                return
            }
            let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth
            let depthData = sceneDepth.flatMap { Self.float32DepthData($0.depthMap) }

            let cameraIntrinsics = frame.camera.intrinsics
            let intrinsics = [
                [Double(cameraIntrinsics.columns.0.x), Double(cameraIntrinsics.columns.1.x), Double(cameraIntrinsics.columns.2.x)],
                [Double(cameraIntrinsics.columns.0.y), Double(cameraIntrinsics.columns.1.y), Double(cameraIntrinsics.columns.2.y)],
                [Double(cameraIntrinsics.columns.0.z), Double(cameraIntrinsics.columns.1.z), Double(cameraIntrinsics.columns.2.z)]
            ]
            guard let cameraToWorld = try? RoomPlanMatrix.rowMajor(frame.camera.transform) else {
                invalidMatrixCount += 1
                return
            }
            visualSamples.append(
                RoomPlanVisualSample(
                    jpegData: jpegData,
                    width: sourceWidth,
                    height: sourceHeight,
                    depthData: depthData,
                    depthWidth: sceneDepth.map { CVPixelBufferGetWidth($0.depthMap) },
                    depthHeight: sceneDepth.map { CVPixelBufferGetHeight($0.depthMap) },
                    intrinsics: intrinsics,
                    cameraToWorld: cameraToWorld,
                    capturedAt: frame.timestamp > 0 ? Date(timeIntervalSinceNow: 0) : Date()
                )
            )
            // Keep viewpoints from the whole scan instead of filling the
            // buffer during its first few seconds. When the bounded buffer is
            // full, halve its temporal density and continue sampling.
            if visualSamples.count > maxBufferedVisualSamples {
                visualSamples = visualSamples.enumerated().compactMap { index, sample in
                    index.isMultiple(of: 2) ? sample : nil
                }
            }
            lastVisualSampleTimestamp = frame.timestamp
        }

        private static func evenlySpacedSamples(_ samples: [RoomPlanVisualSample], limit: Int) -> [RoomPlanVisualSample] {
            guard limit > 0, samples.count > limit else { return samples }
            return (0..<limit).map { index in
                let position = Double(index) * Double(samples.count - 1) / Double(limit - 1)
                return samples[Int(position.rounded())]
            }
        }

        private struct VisualSamplePlan {
            let targetCount: Int
            let estimatedAreaSquareMeters: Double?
        }

        private static func visualSamplePlan(for room: CapturedRoom) -> VisualSamplePlan {
            let minimumSamples = 32
            let maximumSamples = 120
            guard let normalized = try? RoomPlanNormalizer.normalize(room) else {
                return VisualSamplePlan(targetCount: minimumSamples, estimatedAreaSquareMeters: nil)
            }

            let surfaces = normalized.walls + normalized.floors + normalized.openings + normalized.doors + normalized.windows
            let points = surfaces.flatMap(\.vertices)
            let xValues = points.map(\.x)
            let zValues = points.map(\.z)
            let boundsArea: Double
            if let minX = xValues.min(), let maxX = xValues.max(), let minZ = zValues.min(), let maxZ = zValues.max() {
                boundsArea = max(0, (maxX - minX) * (maxZ - minZ))
            } else {
                boundsArea = 0
            }

            func polygonArea(_ polygon: [RoomPlanPoint3D]) -> Double {
                guard polygon.count >= 3 else { return 0 }
                var area = 0.0
                for index in polygon.indices {
                    let next = polygon[(index + 1) % polygon.count]
                    area += polygon[index].x * next.z - next.x * polygon[index].z
                }
                return abs(area) * 0.5
            }

            let floorArea = normalized.floors.reduce(0.0) { partial, floor in
                partial + polygonArea(floor.vertices)
            }
            let area = max(floorArea, boundsArea)
            let wallLength = normalized.walls.reduce(0.0) { partial, wall in
                let wallX = wall.vertices.map(\.x)
                let wallZ = wall.vertices.map(\.z)
                guard let minX = wallX.min(), let maxX = wallX.max(), let minZ = wallZ.min(), let maxZ = wallZ.max() else {
                    return partial
                }
                return partial + max(maxX - minX, maxZ - minZ)
            }
            let complexity = Double(max(0, normalized.walls.count - 4)) * 2.0
                + Double(max(0, normalized.objects.count - 8)) * 0.75
            let target = min(
                maximumSamples,
                max(minimumSamples, Int(ceil(24.0 + area * 1.25 + wallLength * 0.35 + complexity)))
            )
            return VisualSamplePlan(targetCount: target, estimatedAreaSquareMeters: area > 0 ? area : nil)
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
            let completion = onComplete
            let capturedData = data
            let frame = session.arSession.currentFrame
            if let frame { captureVisualSample(from: frame, force: true) }
            stopVisualSampling()
            let cameraToWorld = frame?.camera.transform
            let bufferedVisualSamples = visualSamples
            let sampleAttempts = samplingAttempts
            let sampleMissingFrameCount = missingFrameCount
            let sampleImageEncodingFailureCount = imageEncodingFailureCount
            let sampleInvalidMatrixCount = invalidMatrixCount
            let sampleLastTrackingState = lastTrackingState
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
                    let plan = Self.visualSamplePlan(for: room)
                    let completedVisualSamples = Self.evenlySpacedSamples(bufferedVisualSamples, limit: plan.targetCount)
                    let diagnostics = RoomPlanVisualCaptureDiagnostics(
                        samplingAttempts: sampleAttempts,
                        missingFrameCount: sampleMissingFrameCount,
                        imageEncodingFailureCount: sampleImageEncodingFailureCount,
                        invalidMatrixCount: sampleInvalidMatrixCount,
                        capturedSampleCount: completedVisualSamples.count,
                        depthSampleCount: completedVisualSamples.filter { $0.depthData != nil }.count,
                        lastTrackingState: sampleLastTrackingState,
                        estimatedAreaSquareMeters: plan.estimatedAreaSquareMeters,
                        recommendedVisualSampleCount: plan.targetCount
                    )
                    completion(.success(RoomPlanCaptureResult(room: room, cameraToWorld: cameraToWorld, trackingState: trackingState, visualSamples: completedVisualSamples, visualDiagnostics: diagnostics)))
                } catch {
                    completion(.failure(.captureFailed(error.localizedDescription)))
                }
            }
        }

        func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
            captureVisualSample(from: session.arSession.currentFrame)
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

struct ARVideoRoomCaptureResult: Sendable {
    let scan: ARVideoRoomScan
}

struct ARVideoRoomCaptureView: UIViewRepresentable {
    @Binding var isCapturing: Bool
    var onComplete: @MainActor @Sendable (Result<ARVideoRoomCaptureResult, RoomPlanCaptureError>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session.delegate = context.coordinator
        view.automaticallyUpdatesLighting = true
        view.debugOptions = [.showFeaturePoints]
        return view
    }

    func updateUIView(_ view: ARSCNView, context: Context) {
        if isCapturing {
            guard !context.coordinator.hasStarted else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.worldAlignment = .gravity
            configuration.planeDetection = [.horizontal, .vertical]
            configuration.environmentTexturing = .automatic
            context.coordinator.hasStarted = true
            context.coordinator.hasStopped = false
            view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            return
        }

        guard context.coordinator.hasStarted, !context.coordinator.hasStopped else { return }
        context.coordinator.hasStopped = true
        context.coordinator.finish(session: view.session)
    }

    static func dismantleUIView(_ view: ARSCNView, coordinator: Coordinator) {
        view.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let onComplete: @MainActor @Sendable (Result<ARVideoRoomCaptureResult, RoomPlanCaptureError>) -> Void
        var hasStarted = false
        var hasStopped = false
        private var frameSampleCount = 0
        private var normalTrackingSamples = 0
        private var lastSampleTimestamp: TimeInterval?
        private var lastTrackingState = "unavailable"
        private let sampleInterval: TimeInterval = 0.7

        init(onComplete: @escaping @MainActor @Sendable (Result<ARVideoRoomCaptureResult, RoomPlanCaptureError>) -> Void) {
            self.onComplete = onComplete
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            switch frame.camera.trackingState {
            case .normal: lastTrackingState = "normal"
            case .limited: lastTrackingState = "limited"
            case .notAvailable: lastTrackingState = "unavailable"
            @unknown default: lastTrackingState = "unavailable"
            }
            if let lastSampleTimestamp, frame.timestamp - lastSampleTimestamp < sampleInterval { return }
            frameSampleCount += 1
            if case .normal = frame.camera.trackingState { normalTrackingSamples += 1 }
            lastSampleTimestamp = frame.timestamp
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            guard !hasStopped else { return }
            hasStopped = true
            session.pause()
            let completion = onComplete
            Task { @MainActor in completion(.failure(.captureFailed(error.localizedDescription))) }
        }

        func finish(session: ARSession) {
            let frame = session.currentFrame
            let candidates = (frame?.anchors ?? []).compactMap { anchor -> PlaneCandidate? in
                guard let plane = anchor as? ARPlaneAnchor else { return nil }
                return Self.candidate(from: plane)
            }
            session.pause()

            let horizontal = candidates.filter { $0.alignment == .horizontal }
            let vertical = candidates.filter { $0.alignment == .vertical }.sorted { $0.area > $1.area }
            guard let floor = horizontal.min(by: { $0.averageY < $1.averageY }) else {
                completeFailure("No stable floor was detected. Keep the phone aimed at the floor and lower walls, then continue scanning.")
                return
            }
            guard vertical.count >= 2 else {
                completeFailure("Not enough wall structure was detected. Walk around the room until at least two walls have been tracked, then finish again.")
                return
            }
            guard normalTrackingSamples >= 6, lastTrackingState == "normal" else {
                completeFailure("ARKit tracking is not stable enough yet. Move slowly through the room for a few more seconds before finishing.")
                return
            }

            do {
                var surfaces = [try ARVideoSurface(id: floor.id, kind: "floor", alignment: "horizontal", vertices: floor.vertices, confidence: 0.82)]
                surfaces.append(contentsOf: try vertical.prefix(24).map {
                    try ARVideoSurface(id: $0.id, kind: "wall", alignment: "vertical", vertices: $0.vertices, confidence: 0.74)
                })
                let diagnostics = ARVideoCaptureDiagnostics(
                    frameSampleCount: frameSampleCount,
                    normalTrackingSamples: normalTrackingSamples,
                    planeCount: candidates.count,
                    trackingState: lastTrackingState
                )
                let scan = try ARVideoRoomScan(surfaces: surfaces, diagnostics: diagnostics)
                let completion = onComplete
                Task { @MainActor in completion(.success(ARVideoRoomCaptureResult(scan: scan))) }
            } catch {
                completeFailure("The tracked room surfaces could not be converted into a 3D map. Continue scanning the floor and walls and try again.")
            }
        }

        private func completeFailure(_ message: String) {
            let completion = onComplete
            Task { @MainActor in completion(.failure(.captureFailed(message))) }
        }

        private struct PlaneCandidate {
            let id: UUID
            let alignment: ARPlaneAnchor.Alignment
            let vertices: [SIMD3<Float>]
            let area: Float
            let averageY: Float
        }

        private static func candidate(from anchor: ARPlaneAnchor) -> PlaneCandidate? {
            let boundary = anchor.geometry.boundaryVertices
            guard boundary.count >= 3 else { return nil }
            let vertices = boundary.map { vertex -> SIMD3<Float> in
                let world = simd_mul(anchor.transform, SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1))
                return SIMD3<Float>(world.x, world.y, world.z)
            }
            guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return nil }
            let area = polygonArea(vertices)
            guard area >= 0.18 else { return nil }
            let averageY = vertices.reduce(Float.zero) { $0 + $1.y } / Float(vertices.count)
            return PlaneCandidate(id: anchor.identifier, alignment: anchor.alignment, vertices: vertices, area: area, averageY: averageY)
        }

        private static func polygonArea(_ vertices: [SIMD3<Float>]) -> Float {
            guard vertices.count >= 3 else { return 0 }
            let origin = vertices[0]
            var doubledArea: Float = 0
            for index in 1..<(vertices.count - 1) {
                doubledArea += simd_length(simd_cross(vertices[index] - origin, vertices[index + 1] - origin))
            }
            return doubledArea * 0.5
        }
    }
}

enum ARVideoRoomCaptureCapability {
    static var isSupported: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        ARWorldTrackingConfiguration.isSupported
        #endif
    }
}

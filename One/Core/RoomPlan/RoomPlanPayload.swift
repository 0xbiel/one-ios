import Foundation
import RoomPlan
import simd
import Darwin

let roomPlanSchemaVersion = "roomplan-normalized.v1"
let arVideoRoomSchemaVersion = "arkit-video-room.v1"

enum RoomPlanMatrix {
    static func rowMajor(_ value: simd_float4x4) throws -> [[Double]] {
        let columns = value.columns
        let result = [
            [Double(columns.0.x), Double(columns.1.x), Double(columns.2.x), Double(columns.3.x)],
            [Double(columns.0.y), Double(columns.1.y), Double(columns.2.y), Double(columns.3.y)],
            [Double(columns.0.z), Double(columns.1.z), Double(columns.2.z), Double(columns.3.z)],
            [Double(columns.0.w), Double(columns.1.w), Double(columns.2.w), Double(columns.3.w)]
        ]
        guard result.flatMap({ $0 }).allSatisfy(\.isFinite) else { throw RoomPlanNormalizationError.nonFiniteGeometry }
        return result
    }
}

struct RoomPlanPoint3D: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let z: Double

    init(_ value: SIMD3<Float>) throws {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
            throw RoomPlanNormalizationError.nonFiniteGeometry
        }
        self.x = Double(value.x)
        self.y = Double(value.y)
        self.z = Double(value.z)
    }

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

struct RoomPlanDimensions3D: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let z: Double

    init(_ value: SIMD3<Float>) throws {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite,
              value.x > 0, value.y > 0, value.z > 0 else {
            throw RoomPlanNormalizationError.invalidDimensions
        }
        self.x = Double(value.x)
        self.y = Double(value.y)
        self.z = Double(value.z)
    }

    init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

struct RoomPlanElement: Codable, Sendable, Equatable {
    let id: String
    let category: String
    let confidence: String
    let center: RoomPlanPoint3D
    let dimensions: RoomPlanDimensions3D
    let transform: [[Double]]
    let vertices: [RoomPlanPoint3D]
    let attributes: [String]

    init(id: String, category: String, confidence: String, center: RoomPlanPoint3D, dimensions: RoomPlanDimensions3D, transform: [[Double]], vertices: [RoomPlanPoint3D] = [], attributes: [String] = []) throws {
        guard !id.isEmpty, !category.isEmpty,
              transform.count == 4, transform.allSatisfy({ $0.count == 4 }),
              transform.flatMap({ $0 }).allSatisfy(\.isFinite),
              attributes.allSatisfy({ !$0.isEmpty && $0.count <= 80 }) else {
            throw RoomPlanNormalizationError.invalidGeometry
        }
        self.id = id
        self.category = category
        self.confidence = confidence
        self.center = center
        self.dimensions = dimensions
        self.transform = transform
        self.vertices = vertices
        self.attributes = attributes
    }
}

struct RoomPlanSection: Codable, Sendable, Equatable {
    let id: String
    let label: String
    let center: RoomPlanPoint3D
    let story: Int
}

struct RoomPlanNormalizedScan: Codable, Sendable, Equatable {
    let schemaVersion: String
    let producer: String
    let framework: String
    let units: String
    let upAxis: String
    let coordinateFrame: String
    let geometryType: String
    let capturedAt: String?
    let roomID: String?
    let walls: [RoomPlanElement]
    let floors: [RoomPlanElement]
    let openings: [RoomPlanElement]
    let doors: [RoomPlanElement]
    let windows: [RoomPlanElement]
    let objects: [RoomPlanElement]
    let sections: [RoomPlanSection]

    init(roomID: UUID?, capturedAt: Date?, walls: [RoomPlanElement], floors: [RoomPlanElement], openings: [RoomPlanElement], doors: [RoomPlanElement], windows: [RoomPlanElement], objects: [RoomPlanElement], sections: [RoomPlanSection]) throws {
        guard !walls.isEmpty || !floors.isEmpty || !openings.isEmpty || !doors.isEmpty || !windows.isEmpty || !objects.isEmpty else {
            throw RoomPlanNormalizationError.emptyCapture
        }
        self.schemaVersion = roomPlanSchemaVersion
        self.producer = "native-ios"
        self.framework = "RoomPlan"
        self.units = "m"
        self.upAxis = "Y"
        self.coordinateFrame = "roomplan-local"
        self.geometryType = "3d"
        self.capturedAt = capturedAt.map(Self.iso8601String)
        self.roomID = roomID?.uuidString
        self.walls = walls
        self.floors = floors
        self.openings = openings
        self.doors = doors
        self.windows = windows
        self.objects = objects
        self.sections = sections
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

struct RoomPlanScanMetadata: Codable, Sendable, Equatable {
    let provenance: String
    let deviceModel: String
    let lidar: Bool
    let roomplanVersion: String
    let units: String
    let upAxis: String
    let geometryType: String
    var visualSamplingAttempts: Int? = nil
    var visualMissingFrameCount: Int? = nil
    var visualImageEncodingFailureCount: Int? = nil
    var visualInvalidMatrixCount: Int? = nil
    var visualSampleCount: Int? = nil
    var visualDepthSampleCount: Int? = nil
    var visualLastTrackingState: String? = nil
    var visualRecommendedSampleCount: Int? = nil
    var visualEstimatedAreaSquareMeters: Double? = nil
}

struct RoomPlanVisualLandmarkUploadProgress: Sendable, Equatable {
    var mapID: UUID?
    var phase: String
    var completedFrameCount: Int
    let totalFrameCount: Int
    var failedFrameCount: Int
    var currentBatch: Int
    var batchCount: Int
    var retryAttempt: Int
    var lastError: String?

    var percent: Int {
        guard totalFrameCount > 0 else { return 0 }
        return min(100, max(0, Int((Double(completedFrameCount) / Double(totalFrameCount) * 100.0).rounded())))
    }
}

struct RoomPlanSaveProgress: Sendable, Equatable {
    var phase: String
    var percent: Int
    var detail: String
}

struct ARVideoPoint3D: Codable, Sendable, Equatable {
    let x: Double
    let y: Double
    let z: Double

    init(_ value: SIMD3<Float>) throws {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
            throw RoomPlanNormalizationError.nonFiniteGeometry
        }
        x = Double(value.x)
        y = Double(value.y)
        z = Double(value.z)
    }
}

struct ARVideoSurface: Codable, Sendable, Equatable {
    let id: String
    let kind: String
    let alignment: String
    let vertices: [ARVideoPoint3D]
    let confidence: Double

    init(id: UUID, kind: String, alignment: String, vertices: [SIMD3<Float>], confidence: Double) throws {
        guard ["floor", "wall"].contains(kind),
              ["horizontal", "vertical"].contains(alignment),
              vertices.count >= 3,
              confidence.isFinite,
              (0...1).contains(confidence) else {
            throw RoomPlanNormalizationError.invalidGeometry
        }
        self.id = id.uuidString
        self.kind = kind
        self.alignment = alignment
        self.vertices = try vertices.map(ARVideoPoint3D.init)
        self.confidence = confidence
    }
}

struct ARVideoCaptureDiagnostics: Codable, Sendable, Equatable {
    let frameSampleCount: Int
    let normalTrackingSamples: Int
    let planeCount: Int
    let trackingState: String
}

struct ARVideoRoomScan: Encodable, Sendable, Equatable {
    let schemaVersion = arVideoRoomSchemaVersion
    let producer = "native-ios"
    let framework = "ARKit"
    let units = "m"
    let upAxis = "Y"
    let coordinateFrame = "arkit-world"
    let geometryType = "3d"
    let lidar = false
    let capturedAt: String
    let roomID: String? = nil
    let surfaces: [ARVideoSurface]
    let diagnostics: ARVideoCaptureDiagnostics

    init(surfaces: [ARVideoSurface], diagnostics: ARVideoCaptureDiagnostics, capturedAt: Date = Date()) throws {
        guard surfaces.contains(where: { $0.kind == "floor" }),
              surfaces.filter({ $0.kind == "wall" }).count >= 2,
              diagnostics.trackingState == "normal",
              diagnostics.normalTrackingSamples >= 6 else {
            throw RoomPlanNormalizationError.invalidGeometry
        }
        self.surfaces = surfaces
        self.diagnostics = diagnostics
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.capturedAt = formatter.string(from: capturedAt)
    }
}

struct RoomPlanCaptureFixture: Sendable {
    var roomID: UUID?
    var capturedAt: Date?
    var walls: [RoomPlanElementInput]
    var floors: [RoomPlanElementInput]
    var openings: [RoomPlanElementInput]
    var doors: [RoomPlanElementInput]
    var windows: [RoomPlanElementInput]
    var objects: [RoomPlanElementInput]
    var sections: [RoomPlanSectionInput]

    init(roomID: UUID? = nil, capturedAt: Date? = nil, walls: [RoomPlanElementInput] = [], floors: [RoomPlanElementInput] = [], openings: [RoomPlanElementInput] = [], doors: [RoomPlanElementInput] = [], windows: [RoomPlanElementInput] = [], objects: [RoomPlanElementInput] = [], sections: [RoomPlanSectionInput] = []) {
        self.roomID = roomID
        self.capturedAt = capturedAt
        self.walls = walls
        self.floors = floors
        self.openings = openings
        self.doors = doors
        self.windows = windows
        self.objects = objects
        self.sections = sections
    }
}

struct RoomPlanElementInput: Sendable {
    let id: UUID
    let category: String
    let confidence: String
    let center: SIMD3<Float>
    let dimensions: SIMD3<Float>
    let transform: simd_float4x4
    let vertices: [SIMD3<Float>]
    let attributes: [String]

    init(id: UUID = UUID(), category: String, confidence: String = "high", center: SIMD3<Float>, dimensions: SIMD3<Float>, transform: simd_float4x4 = matrix_identity_float4x4, vertices: [SIMD3<Float>] = [], attributes: [String] = []) {
        self.id = id
        self.category = category
        self.confidence = confidence
        self.center = center
        self.dimensions = dimensions
        self.transform = transform
        self.vertices = vertices
        self.attributes = attributes
    }
}

struct RoomPlanSectionInput: Sendable {
    let id: UUID
    let label: String
    let center: SIMD3<Float>
    let story: Int

    init(id: UUID = UUID(), label: String, center: SIMD3<Float>, story: Int = 0) {
        self.id = id
        self.label = label
        self.center = center
        self.story = story
    }
}

enum RoomPlanNormalizationError: LocalizedError, Equatable, Sendable {
    case emptyCapture
    case invalidGeometry
    case invalidDimensions
    case nonFiniteGeometry
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .emptyCapture: "The RoomPlan scan did not contain a surface or object."
        case .invalidGeometry: "The RoomPlan scan contained invalid 3D geometry."
        case .invalidDimensions: "The RoomPlan scan contained non-positive dimensions."
        case .nonFiniteGeometry: "The RoomPlan scan contained non-finite coordinates."
        case .exportFailed: "The RoomPlan USDZ export could not be read."
        }
    }
}

enum RoomPlanNormalizer {
    private static let minimumNativeDimension: Float = 0.001
    private static let nativeDimensionTolerance: Float = 0.001

    /// RoomPlan can report an exactly-zero (or tiny negative from floating point
    /// noise) thickness for planar surfaces such as walls and floors. The ONE
    /// wire contract requires positive 3D extents, so give those native planar
    /// elements a 1 mm thickness while still rejecting materially invalid data.
    static func sanitizedNativeDimensions(_ value: SIMD3<Float>) throws -> SIMD3<Float> {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
            throw RoomPlanNormalizationError.nonFiniteGeometry
        }

        func sanitize(_ component: Float) throws -> Float {
            guard component >= -nativeDimensionTolerance else {
                throw RoomPlanNormalizationError.invalidDimensions
            }
            return max(component, minimumNativeDimension)
        }

        return SIMD3<Float>(try sanitize(value.x), try sanitize(value.y), try sanitize(value.z))
    }

    static func normalize(_ fixture: RoomPlanCaptureFixture) throws -> RoomPlanNormalizedScan {
        try RoomPlanNormalizedScan(
            roomID: fixture.roomID,
            capturedAt: fixture.capturedAt,
            walls: try fixture.walls.map(normalizeElement),
            floors: try fixture.floors.map(normalizeElement),
            openings: try fixture.openings.map(normalizeElement),
            doors: try fixture.doors.map(normalizeElement),
            windows: try fixture.windows.map(normalizeElement),
            objects: try fixture.objects.map(normalizeElement),
            sections: try fixture.sections.map(normalizeSection)
        )
    }

    static func normalize(_ room: CapturedRoom, capturedAt: Date = Date()) throws -> RoomPlanNormalizedScan {
        let fixture = RoomPlanCaptureFixture(
            roomID: room.identifier,
            capturedAt: capturedAt,
            walls: try room.walls.map { try input(from: $0) },
            floors: try room.floors.map { try input(from: $0) },
            openings: try room.openings.map { try input(from: $0) },
            doors: try room.doors.map { try input(from: $0) },
            windows: try room.windows.map { try input(from: $0) },
            objects: try room.objects.map { try input(from: $0) },
            sections: room.sections.map { RoomPlanSectionInput(label: $0.label.rawValue, center: $0.center, story: $0.story) }
        )
        return try normalize(fixture)
    }

    static func normalize(
        _ structure: CapturedStructure,
        capturedAt: Date = Date(),
        roomSections: [RoomPlanSectionInput]? = nil
    ) throws -> RoomPlanNormalizedScan {
        let fixture = RoomPlanCaptureFixture(
            roomID: nil,
            capturedAt: capturedAt,
            walls: try structure.walls.map { try input(from: $0) },
            floors: try structure.floors.map { try input(from: $0) },
            openings: try structure.openings.map { try input(from: $0) },
            doors: try structure.doors.map { try input(from: $0) },
            windows: try structure.windows.map { try input(from: $0) },
            objects: try structure.objects.map { try input(from: $0) },
            sections: roomSections ?? structure.sections.map { RoomPlanSectionInput(label: $0.label.rawValue, center: $0.center, story: $0.story) }
        )
        return try normalize(fixture)
    }

    static func metadata(for room: CapturedRoom) -> RoomPlanScanMetadata {
        RoomPlanScanMetadata(
            provenance: "native-roomplan",
            deviceModel: deviceModel,
            lidar: true,
            roomplanVersion: String(room.version),
            units: "m",
            upAxis: "Y",
            geometryType: "3d"
        )
    }

    static func metadata(for structure: CapturedStructure) -> RoomPlanScanMetadata {
        RoomPlanScanMetadata(
            provenance: "native-roomplan-structure",
            deviceModel: deviceModel,
            lidar: true,
            roomplanVersion: String(structure.version),
            units: "m",
            upAxis: "Y",
            geometryType: "3d"
        )
    }

    private static func normalizeElement(_ input: RoomPlanElementInput) throws -> RoomPlanElement {
        let center = try RoomPlanPoint3D(input.center)
        let dimensions = try RoomPlanDimensions3D(input.dimensions)
        let vertices = try input.vertices.map(RoomPlanPoint3D.init)
        let transform = try RoomPlanMatrix.rowMajor(input.transform)
        return try RoomPlanElement(id: input.id.uuidString, category: input.category, confidence: input.confidence, center: center, dimensions: dimensions, transform: transform, vertices: vertices, attributes: input.attributes)
    }

    private static func normalizeSection(_ input: RoomPlanSectionInput) throws -> RoomPlanSection {
        guard input.story >= 0 else { throw RoomPlanNormalizationError.invalidGeometry }
        return RoomPlanSection(id: input.id.uuidString, label: input.label, center: try RoomPlanPoint3D(input.center), story: input.story)
    }

    private static func input(from surface: CapturedRoom.Surface) throws -> RoomPlanElementInput {
        let category: String
        var attributes: [String] = []
        switch surface.category {
        case .wall: category = "wall"
        case .opening: category = "opening"
        case .window: category = "window"
        case .door(let isOpen):
            category = "door"
            attributes.append(isOpen ? "is_open=true" : "is_open=false")
        case .floor: category = "floor"
        @unknown default: throw RoomPlanNormalizationError.invalidGeometry
        }
        let vertices = surface.polygonCorners.map { corner in
            let transformed = simd_mul(surface.transform, SIMD4<Float>(corner.x, corner.y, corner.z, 1))
            return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
        }
        return RoomPlanElementInput(id: surface.identifier, category: category, confidence: confidence(surface.confidence), center: SIMD3<Float>(surface.transform.columns.3.x, surface.transform.columns.3.y, surface.transform.columns.3.z), dimensions: try sanitizedNativeDimensions(surface.dimensions), transform: surface.transform, vertices: vertices, attributes: attributes)
    }

    private static func input(from object: CapturedRoom.Object) throws -> RoomPlanElementInput {
        RoomPlanElementInput(id: object.identifier, category: objectCategory(object.category), confidence: confidence(object.confidence), center: SIMD3<Float>(object.transform.columns.3.x, object.transform.columns.3.y, object.transform.columns.3.z), dimensions: try sanitizedNativeDimensions(object.dimensions), transform: object.transform, attributes: object.attributes.map(\.shortIdentifier))
    }

    private static func confidence(_ value: CapturedRoom.Confidence) -> String {
        switch value {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        @unknown default: "low"
        }
    }

    private static func objectCategory(_ value: CapturedRoom.Object.Category) -> String {
        switch value {
        case .storage: "storage"
        case .refrigerator: "refrigerator"
        case .stove: "stove"
        case .bed: "bed"
        case .sink: "sink"
        case .washerDryer: "washer_dryer"
        case .toilet: "toilet"
        case .bathtub: "bathtub"
        case .oven: "oven"
        case .dishwasher: "dishwasher"
        case .table: "table"
        case .sofa: "sofa"
        case .chair: "chair"
        case .fireplace: "fireplace"
        case .television: "television"
        case .stairs: "stairs"
        @unknown default: "object"
        }
    }

    private static var deviceModel: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(decoding: machine.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

struct NativeRoomPlanArtifact: Sendable {
    let scan: RoomPlanNormalizedScan
    let metadata: RoomPlanScanMetadata
    let usdzData: Data
}

enum RoomPlanArtifactBuilder {
    static func build(
        from structure: CapturedStructure,
        roomSections: [RoomPlanSectionInput]? = nil,
        capturedAt: Date = Date()
    ) throws -> NativeRoomPlanArtifact {
        let scan = try RoomPlanNormalizer.normalize(structure, capturedAt: capturedAt, roomSections: roomSections)
        let metadata = RoomPlanNormalizer.metadata(for: structure)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("one-roomplan-structure-\(structure.identifier.uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try structure.export(to: url, exportOptions: .model)
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw RoomPlanNormalizationError.exportFailed }
            return NativeRoomPlanArtifact(scan: scan, metadata: metadata, usdzData: data)
        } catch let error as RoomPlanNormalizationError {
            throw error
        } catch {
            throw RoomPlanNormalizationError.exportFailed
        }
    }

    static func build(from room: CapturedRoom, capturedAt: Date = Date()) throws -> NativeRoomPlanArtifact {
        let scan = try RoomPlanNormalizer.normalize(room, capturedAt: capturedAt)
        let metadata = RoomPlanNormalizer.metadata(for: room)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("one-roomplan-\(room.identifier.uuidString).usdz")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            try room.export(to: url, exportOptions: .model)
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { throw RoomPlanNormalizationError.exportFailed }
            return NativeRoomPlanArtifact(scan: scan, metadata: metadata, usdzData: data)
        } catch let error as RoomPlanNormalizationError {
            throw error
        } catch {
            throw RoomPlanNormalizationError.exportFailed
        }
    }
}

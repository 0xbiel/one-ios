import Foundation
import CoreGraphics

enum UserRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case resident, caregiver
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CareSpaceMembershipRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case admin, caregiver, resident

    var id: String { rawValue }

    var title: String {
        switch self {
        case .admin: "Owner"
        case .caregiver: "Caregiver"
        case .resident: "Resident"
        }
    }

    var userRole: UserRole {
        self == .resident ? .resident : .caregiver
    }
}

enum CareSetting: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, residence

    var id: String { rawValue }
    var title: String { self == .home ? "Home" : "Residence" }
    var connectedTitle: String { self == .home ? "Connected household" : "Connected residence" }
    var symbol: String { self == .home ? "house.fill" : "building.2.fill" }
}

enum SupportFocus: String, Codable, CaseIterable, Identifiable, Sendable {
    case general, mci

    var id: String { rawValue }
    var title: String { self == .general ? "Everyday support" : "Memory-focused support" }
    var detail: String {
        self == .general
            ? "A calm overview of routines, check-ins, and the home."
            : "Extra attention to changes from the person's own familiar routine."
    }
}

struct CareSpaceSummary: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    var residentName: String
    let careSetting: CareSetting
    let supportFocus: SupportFocus
    let role: CareSpaceMembershipRole
    var active: Bool
    var recipientNames: [String]?
    var recipientCount: Int?

    init(
        id: UUID,
        name: String,
        residentName: String,
        careSetting: CareSetting,
        supportFocus: SupportFocus,
        role: CareSpaceMembershipRole,
        active: Bool,
        recipientNames: [String]? = nil,
        recipientCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.residentName = residentName
        self.careSetting = careSetting
        self.supportFocus = supportFocus
        self.role = role
        self.active = active
        self.recipientNames = recipientNames
        self.recipientCount = recipientCount
    }

    var peopleSummary: String {
        let names = (recipientNames ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let count = recipientCount ?? names.count
        if count == 1, let first = names.first { return first }
        if count == 2, names.count >= 2 { return "\(names[0]) & \(names[1])" }
        if count > 2 { return "\(count) people" }
        if residentName != "Resident" { return residentName }
        return "No people added yet"
    }

    static let demoSpaces: [CareSpaceSummary] = [
        CareSpaceSummary(id: UUID(uuidString: "5f93f34b-b1f9-4daa-9503-33a0fe4c90d1")!, name: "The García home", residentName: "María", careSetting: .home, supportFocus: .general, role: .admin, active: true, recipientNames: ["María", "José"], recipientCount: 2),
        CareSpaceSummary(id: UUID(uuidString: "c41ca810-45c0-4f97-99e0-a6ea62de0d9e")!, name: "La Marina residence", residentName: "Resident", careSetting: .residence, supportFocus: .mci, role: .caregiver, active: false)
    ]
}

struct CareRecipient: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var displayName: String
    var relationship: String?
    var roomLabel: String?
    let createdAt: Date

    var name: String { displayName }

    init(id: UUID, displayName: String, relationship: String? = nil, roomLabel: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.relationship = relationship
        self.roomLabel = roomLabel
        self.createdAt = createdAt
    }
}

enum CaregiverAccessRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case owner, primaryCaregiver, supporter, viewer

    var id: String { rawValue }
    var title: String {
        switch self {
        case .owner: "Owner"
        case .primaryCaregiver: "Primary caregiver"
        case .supporter: "Supporter"
        case .viewer: "View only"
        }
    }

    /// The backend currently exposes only resident/caregiver membership roles.
    /// Keep unsupported demo-only roles out of live mutations rather than
    /// mapping them to a broader permission set.
    var backendRole: UserRole? {
        switch self {
        case .primaryCaregiver: .caregiver
        case .viewer: .resident
        case .owner, .supporter: nil
        }
    }
}

struct CaregiverAccount: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let relationship: String
    let role: CaregiverAccessRole
    let permissions: [String]
    var isCurrentUser: Bool
}

enum MedicationDoseStatus: String, Codable, CaseIterable, Sendable {
    case scheduled, acknowledged, missed, needsConfirmation

    var title: String {
        switch self {
        case .scheduled: "Scheduled"
        case .acknowledged: "Acknowledged"
        case .missed: "Missed"
        case .needsConfirmation: "Needs confirmation"
        }
    }

    var symbol: String {
        switch self {
        case .scheduled: "clock"
        case .acknowledged: "checkmark.circle.fill"
        case .missed: "exclamationmark.circle.fill"
        case .needsConfirmation: "questionmark.circle.fill"
        }
    }
}

struct MedicationDose: Codable, Identifiable, Sendable {
    let id: UUID
    var medicationName: String
    var instructions: String
    var scheduledAt: Date
    var status: MedicationDoseStatus
    var assignedCaregiverName: String?
    var scheduleRule: String = ""
    var subjectUserID: UUID? = nil
    var planID: UUID? = nil
}

enum ObservationConfidence: String, Codable, CaseIterable {
    case high, medium, low
    var title: String { rawValue.capitalized }
}

enum PinSource: String, Codable { case roomObject, zoneFallback, manual }

struct ConsentRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let purpose: String
    var enabled: Bool
    let policyVersion: String
    let updatedAt: Date
}

struct RoomObject: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let category: String
    let position: SIMD3<Float>
    let dimensions: SIMD3<Float>
    let confidence: ObservationConfidence
    let zoneID: UUID
    let mapID: UUID?
    let cameraID: UUID?
    let observedAt: Date?

    init(
        id: UUID,
        name: String,
        category: String,
        position: SIMD3<Float>,
        dimensions: SIMD3<Float>,
        confidence: ObservationConfidence,
        zoneID: UUID,
        mapID: UUID? = nil,
        cameraID: UUID? = nil,
        observedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.position = position
        self.dimensions = dimensions
        self.confidence = confidence
        self.zoneID = zoneID
        self.mapID = mapID
        self.cameraID = cameraID
        self.observedAt = observedAt
    }
}

struct Zone: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let center: SIMD3<Float>
    let areaSquareMeters: Double
}

struct RoomScan: Codable, Identifiable, Sendable {
    let id: UUID
    let schemaVersion: Int
    let capturedAt: Date
    let units: String
    let upAxis: String
    let objects: [RoomObject]
    let zones: [Zone]
    let artifactHash: String
    var exportedUSDZName: String?
}

extension RoomScan {
    static var empty: RoomScan {
        RoomScan(id: UUID(), schemaVersion: 1, capturedAt: Date(), units: "m", upAxis: "Y", objects: [], zones: [], artifactHash: "", exportedUSDZName: nil)
    }
}

enum MapSource: String, Codable, Sendable {
    case cameraCV2D = "camera-cv-2d"
    case roomplanLidar3D = "roomplan-lidar-3d"
    case arkitVideo3D = "arkit-video-3d"
    case legacy2D = "legacy-2d"
}

enum MapDimension: String, Codable, Sendable {
    case twoD = "2d"
    case threeD = "3d"
}

struct USDZAsset: Codable, Sendable, Equatable {
    let available: Bool
    let sha256: String?
    let bytes: Int?
    let contentType: String?
    let downloadPath: String?
}

struct PairedCamera: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let name: String
    let roomID: UUID?
    let status: String
}

enum CameraRegistrationState: String, Codable, Sendable, Equatable {
    case positioned
    case needsRescan = "needs_rescan"
    case unavailable
}

struct CameraRegistrationDescriptor: Codable, Sendable, Equatable {
    let status: CameraRegistrationState
    let cameraID: UUID?
    let mapID: UUID?
    let coordinateFrame: String
    let cameraToWorld: [[Double]]?
    let confidence: Double?
    let trackingState: String?
    let source: String
}

struct SceneDescriptor: Decodable, Sendable, Equatable {
    let sceneID: UUID?
    let mapID: UUID?
    let version: Int
    let dimension: MapDimension
    let source: MapSource
    let provenance: String
    let approximate: Bool
    let metricScaleKnown: Bool
    let geometryStatus: String
    let rescanRequired: Bool
    let coordinateFrame: String?
    let cameraRegistration: CameraRegistrationDescriptor?
    let canonicalGeometry: RoomPlanNormalizedScan?
    let geometry: RoomPlanNormalizedScan?
    let usdz: USDZAsset?

    var isRenderable3D: Bool {
        guard dimension == .threeD, geometryStatus == "ready" else { return false }
        switch source {
        case .roomplanLidar3D:
            return canonicalGeometry != nil
        case .arkitVideo3D:
            return usdz?.available == true
        case .cameraCV2D, .legacy2D:
            return false
        }
    }

    var hasReadyUSDZ: Bool { isRenderable3D && usdz?.available == true }

    static var empty: SceneDescriptor {
        SceneDescriptor(sceneID: nil, mapID: nil, version: 0, dimension: .twoD, source: .legacy2D, provenance: "legacy-2d", approximate: true, metricScaleKnown: false, geometryStatus: "empty", rescanRequired: true, coordinateFrame: nil, geometry: nil, usdz: nil)
    }

    init(sceneID: UUID?, mapID: UUID?, version: Int, dimension: MapDimension, source: MapSource, provenance: String, approximate: Bool, metricScaleKnown: Bool, geometryStatus: String, rescanRequired: Bool, coordinateFrame: String?, cameraRegistration: CameraRegistrationDescriptor? = nil, geometry: RoomPlanNormalizedScan?, usdz: USDZAsset?) {
        self.sceneID = sceneID
        self.mapID = mapID
        self.version = version
        self.dimension = dimension
        self.source = source
        self.provenance = provenance
        self.approximate = approximate
        self.metricScaleKnown = metricScaleKnown
        self.geometryStatus = geometryStatus
        self.rescanRequired = rescanRequired
        self.coordinateFrame = coordinateFrame
        self.cameraRegistration = cameraRegistration
        self.canonicalGeometry = geometry
        self.geometry = geometry
        self.usdz = usdz
    }

    private enum CodingKeys: String, CodingKey {
        case sceneID = "sceneId"
        case mapID = "mapId"
        case version, dimension, source, provenance, approximate
        case metricScaleKnown, geometryStatus, rescanRequired
        case coordinateFrame, cameraRegistration, canonicalGeometry, geometry, usdz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sceneID = try container.decodeIfPresent(UUID.self, forKey: .sceneID)
        mapID = try container.decodeIfPresent(UUID.self, forKey: .mapID)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0
        dimension = (try? container.decode(MapDimension.self, forKey: .dimension)) ?? .twoD
        source = (try? container.decode(MapSource.self, forKey: .source)) ?? .legacy2D
        provenance = try container.decodeIfPresent(String.self, forKey: .provenance) ?? source.rawValue
        approximate = try container.decodeIfPresent(Bool.self, forKey: .approximate) ?? true
        metricScaleKnown = try container.decodeIfPresent(Bool.self, forKey: .metricScaleKnown) ?? false
        geometryStatus = try container.decodeIfPresent(String.self, forKey: .geometryStatus) ?? "empty"
        rescanRequired = try container.decodeIfPresent(Bool.self, forKey: .rescanRequired) ?? false
        coordinateFrame = try container.decodeIfPresent(String.self, forKey: .coordinateFrame)
        cameraRegistration = try? container.decode(CameraRegistrationDescriptor.self, forKey: .cameraRegistration)
        canonicalGeometry = try? container.decode(RoomPlanNormalizedScan.self, forKey: .canonicalGeometry)
        geometry = canonicalGeometry ?? (try? container.decode(RoomPlanNormalizedScan.self, forKey: .geometry))
        usdz = try container.decodeIfPresent(USDZAsset.self, forKey: .usdz)
    }
}

struct MapPin: Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let position: CGPoint
    let radius: CGFloat
    let confidence: ObservationConfidence
    let source: PinSource
}

enum EventKind: String, CaseIterable, Identifiable, Codable {
    case checkIn, movement, noResponse, assistant
    var id: String { rawValue }
    var title: String {
        switch self { case .checkIn: "Daily check-in"; case .movement: "Movement observed"; case .noResponse: "No response"; case .assistant: "Assistant request" }
    }
    var symbol: String {
        switch self { case .checkIn: "checkmark.seal.fill"; case .movement: "figure.walk.motion"; case .noResponse: "clock.badge.exclamationmark"; case .assistant: "waveform" }
    }
}

struct ObservedEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let kind: EventKind
    let timestamp: Date
    let location: String
    let confidence: ObservationConfidence
    let explanation: String
    var reviewed: Bool
    var hasClip: Bool
}

struct CameraCalibration: Codable, Sendable {
    let cameraID: UUID
    let mapVersion: Int
    let reprojectionErrorPixels: Double
    let calibratedAt: Date
    let quality: ObservationConfidence
}

struct AssistantMessage: Identifiable, Sendable {
    let id = UUID()
    let isUser: Bool
    let text: String
    let date = Date()
}

struct DataRequest: Identifiable, Sendable {
    let id = UUID()
    let kind: Kind
    let createdAt = Date()
    enum Kind: String, Sendable { case export, delete }
}

import Foundation
import CoreGraphics

enum UserRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case resident, caregiver
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
struct CareRecipient: Identifiable, Codable, Sendable, Equatable { let id: UUID; let name: String; let relationship: String }

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

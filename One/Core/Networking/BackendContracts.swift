import Foundation
import CryptoKit

struct APIProblem: Codable, Sendable, Error {
    let type: String?
    let title: String?
    let status: Int?
    let detail: String?
    let error: CanonicalAPIError?
    let requestID: String?
    let apiVersion: String?

    var message: String { error?.message ?? detail ?? title ?? "The ONE API request failed." }
}

struct CanonicalAPIError: Codable, Sendable {
    let code: String
    let message: String
    let details: [String: String]?
    let retryable: Bool
}

struct PairingChallengeRequest: Codable, Sendable { let code: String }
struct EmailAuthRequest: Codable, Sendable {
    let email: String
    let purpose: String
    let displayName: String?
    let homeName: String
    let careSetting: String
    let supportFocus: String
    let role: UserRole

    init(email: String, purpose: String, displayName: String?, homeName: String, careSetting: String = "home", supportFocus: String = "general", role: UserRole) {
        self.email = email
        self.purpose = purpose
        self.displayName = displayName
        self.homeName = homeName
        self.careSetting = careSetting
        self.supportFocus = supportFocus
        self.role = role
    }
}
struct EmailAuthVerifyRequest: Codable, Sendable { let email: String; let code: String }
struct EmailAuthChallenge: Codable, Sendable {
    let verificationID: UUID
    let expiresInSeconds: Int
    let delivery: String
    let devCode: String?
    let email: String
    let purpose: String
    let homeID: UUID
    let userID: UUID
    let role: String

    private enum CodingKeys: String, CodingKey {
        case verificationID = "verificationId"
        case expiresInSeconds
        case delivery
        case devCode = "devCode"
        case email, purpose
        case homeID = "homeId"
        case userID = "userId"
        case role
    }
}
struct PairingChallengeResponse: Codable, Sendable {
    let pairingID: UUID
    let expiresAt: Date
    let accessToken: String?
    let homeID: UUID?
    let userID: UUID?
    let role: String?
    let pairingCode: String?

    init(pairingID: UUID, expiresAt: Date, accessToken: String? = nil, homeID: UUID? = nil, userID: UUID? = nil, role: String? = nil, pairingCode: String? = nil) {
        self.pairingID = pairingID; self.expiresAt = expiresAt; self.accessToken = accessToken; self.homeID = homeID; self.userID = userID; self.role = role; self.pairingCode = pairingCode
    }
}
struct AuthSession: Codable, Sendable, Equatable {
    let accessToken: String
    let homeID: UUID
    let userID: UUID
    let role: UserRole
    let expiresAt: Date?
}
struct CareSpaceCreateRequest: Codable, Sendable, Equatable {
    let name: String
    let careSetting: CareSetting
    let supportFocus: SupportFocus
}
struct CareRecipientCreateRequest: Codable, Sendable, Equatable {
    let displayName: String
    let relationship: String?
    let roomLabel: String?
}
struct CareRecipientUpdateRequest: Codable, Sendable, Equatable {
    let displayName: String?
    let relationship: String?
    let roomLabel: String?

    private enum CodingKeys: String, CodingKey {
        case displayName, relationship, roomLabel
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        if let relationship { try container.encode(relationship, forKey: .relationship) }
        else { try container.encodeNil(forKey: .relationship) }
        if let roomLabel { try container.encode(roomLabel, forKey: .roomLabel) }
        else { try container.encodeNil(forKey: .roomLabel) }
    }
}

struct FaceEnrollmentFrameRequest: Codable, Sendable, Equatable {
    let frameBase64: String
    let width: Int
    let height: Int
    let cameraPosition: String
}

struct FaceEnrollmentRequest: Codable, Sendable, Equatable {
    let frames: [FaceEnrollmentFrameRequest]
}

struct FaceProfile: Codable, Sendable, Equatable {
    let careRecipientID: UUID
    let status: FaceRecognitionStatus
    let modelVersion: String?
    let sampleCount: Int
    let updatedAt: Date?
}

struct BootstrapAccountRequest: Codable, Sendable {
    let displayName: String
    let email: String?
    let homeName: String
    let careSetting: String
    let supportFocus: String
    let role: UserRole

    init(displayName: String, email: String?, homeName: String, careSetting: String = "home", supportFocus: String = "general", role: UserRole) {
        self.displayName = displayName
        self.email = email
        self.homeName = homeName
        self.careSetting = careSetting
        self.supportFocus = supportFocus
        self.role = role
    }
}

struct CameraPairingChallenge: Codable, Sendable, Equatable {
    let pairingID: UUID
    let pairingCode: String
    let expiresInSeconds: Int

    private enum CodingKeys: String, CodingKey {
        case pairingID = "pairingId"
        case pairingCode
        case expiresInSeconds
    }
}

struct CameraPairingStatus: Codable, Sendable, Equatable {
    struct Device: Codable, Sendable, Equatable {
        let id: UUID
        let label: String
        let role: String
    }

    let pairingID: UUID
    let status: String
    let expiresAt: String
    let connectedAt: String?
    let device: Device

    private enum CodingKeys: String, CodingKey {
        case pairingID = "pairingId"
        case status
        case expiresAt
        case connectedAt
        case device
    }
}

struct CameraUpdateRequest: Encodable, Sendable, Equatable {
    let name: String
    let roomID: UUID?

    private enum CodingKeys: String, CodingKey {
        case name, roomID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        if let roomID { try container.encode(roomID, forKey: .roomID) }
        else { try container.encodeNil(forKey: .roomID) }
    }
}

struct FamilyInviteAcceptRequest: Codable, Sendable { let code: String; let displayName: String?; let email: String? }
struct FamilyInviteRequest: Codable, Sendable { let displayName: String; let email: String?; let role: UserRole; let expiresInSeconds: Int }
struct FamilyMemberUpdateRequest: Codable, Sendable, Equatable { let role: UserRole }
struct FamilyMemberMutationResult: Sendable, Equatable {
    let member: CaregiverAccount
    let invalidatedSessions: Int
}
struct ConsentRequest: Encodable, Sendable {
    let purpose: String
    let policyVersion: String
    let granted: Bool
    var subjectUserID: UUID? = nil
    var careRecipientID: UUID? = nil

    private enum CodingKeys: String, CodingKey {
        case purpose, policyVersion, granted, subjectUserID, careRecipientID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(policyVersion, forKey: .policyVersion)
        try container.encode(granted, forKey: .granted)
        if let subjectUserID {
            try container.encode(subjectUserID.uuidString.lowercased(), forKey: .subjectUserID)
        }
        if let careRecipientID {
            try container.encode(careRecipientID.uuidString.lowercased(), forKey: .careRecipientID)
        }
    }
}
struct MedicationPlan: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let subjectUserID: UUID
    let careRecipientID: UUID?
    var name: String
    var dose: String
    var schedule: String
    var instructions: String
    var active: Bool
    var version: Int
    var assignedCaregiverID: UUID?
}
struct MedicationPlanRequest: Codable, Sendable {
    let subjectUserID: UUID?
    let careRecipientID: UUID?
    let name: String
    let dose: String
    let schedule: String
    let instructions: String
    let active: Bool
    let assignedCaregiverID: UUID?

    private enum CodingKeys: String, CodingKey {
        case subjectUserID, careRecipientID, name, dose, schedule, instructions, active, assignedCaregiverID
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let subjectUserID {
            try container.encode(subjectUserID.uuidString.lowercased(), forKey: .subjectUserID)
        }
        if let careRecipientID {
            try container.encode(careRecipientID.uuidString.lowercased(), forKey: .careRecipientID)
        }
        try container.encode(name, forKey: .name)
        try container.encode(dose, forKey: .dose)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(instructions, forKey: .instructions)
        try container.encode(active, forKey: .active)
        if let assignedCaregiverID {
            try container.encode(assignedCaregiverID.uuidString.lowercased(), forKey: .assignedCaregiverID)
        }
    }
}
struct MedicationCheckInRequest: Codable, Sendable {
    let scheduledFor: Date
    let status: String
    var note: String = ""
}
struct FamilyAssistantRequest: Codable, Sendable {
    let message: String
    let careRecipientID: UUID?
    var windowDays: Int = 14
    var timezoneName: String = TimeZone.current.identifier

    private enum CodingKeys: String, CodingKey { case message, careRecipientID, windowDays, timezoneName }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(message, forKey: .message)
        try container.encode(windowDays, forKey: .windowDays)
        try container.encode(timezoneName, forKey: .timezoneName)
        if let careRecipientID {
            try container.encode(careRecipientID.uuidString.lowercased(), forKey: .careRecipientID)
        }
    }
}
struct FamilyAssistantResult: Codable, Sendable, Equatable {
    let summary: String
    let nextAction: String
    let limitations: String
}
struct DailyCheckInRequest: Encodable, Sendable, Equatable {
    let transcript: String
    let subjectUserID: UUID?
    let careRecipientID: UUID?

    private enum CodingKeys: String, CodingKey { case transcript, subjectUserID, careRecipientID }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transcript, forKey: .transcript)
        if let subjectUserID { try container.encode(subjectUserID.uuidString.lowercased(), forKey: .subjectUserID) }
        if let careRecipientID { try container.encode(careRecipientID.uuidString.lowercased(), forKey: .careRecipientID) }
    }
}
struct DailyCheckInResult: Codable, Sendable, Equatable {
    let id: UUID
    let eventID: UUID?
    let careRecipientID: UUID?
    let status: String
    let trend: String
    let explanation: String
    let evidenceIDs: [String]?
    let limitations: String
    let degraded: Bool?
    let inferenceStatus: String?
    let modelVersion: String?
}
struct MedicationPlanUpdateRequest: Codable, Sendable {
    let name: String?
    let dose: String?
    let schedule: String?
    let instructions: String?
    let active: Bool?
    let assignedCaregiverID: UUID?
    let version: Int?

    private enum CodingKeys: String, CodingKey { case name, dose, schedule, instructions, active, assignedCaregiverID, version }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(dose, forKey: .dose)
        try container.encodeIfPresent(schedule, forKey: .schedule)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(active, forKey: .active)
        if let assignedCaregiverID {
            try container.encode(assignedCaregiverID.uuidString.lowercased(), forKey: .assignedCaregiverID)
        }
        try container.encodeIfPresent(version, forKey: .version)
    }
}
struct LiveKitTokenResponse: Codable, Sendable { let websocketURL: URL; let token: String; let roomName: String; let expiresAt: Date }
struct ArtifactUploadResponse: Codable, Sendable { let artifactID: UUID; let sha256: String; let expiresAt: Date? }
struct RoomPlanUploadRequest: Codable, Sendable {
    let roomID: UUID?
    let normalizedScan: RoomPlanNormalizedScan
    let scanMetadata: RoomPlanScanMetadata
}
struct RoomPlanMapUploadResponse: Decodable, Sendable, Equatable {
    let mapID: UUID
    let revision: Int
    let source: MapSource
    let dimension: MapDimension
    let coordinateFrame: String?
    let usdz: USDZAsset?

    private enum CodingKeys: String, CodingKey {
        case id, mapID = "map_id", revision, source, dimension
        case coordinateFrame = "coordinate_frame", usdz
    }

    init(mapID: UUID, revision: Int = 0, source: MapSource = .roomplanLidar3D, dimension: MapDimension = .threeD, coordinateFrame: String? = "roomplan-local", usdz: USDZAsset? = nil) {
        self.mapID = mapID; self.revision = revision; self.source = source; self.dimension = dimension; self.coordinateFrame = coordinateFrame; self.usdz = usdz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? container.decode(UUID.self, forKey: .mapID)
        mapID = id
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        source = (try? container.decode(MapSource.self, forKey: .source)) ?? .legacy2D
        dimension = (try? container.decode(MapDimension.self, forKey: .dimension)) ?? .twoD
        coordinateFrame = try container.decodeIfPresent(String.self, forKey: .coordinateFrame)
        usdz = try container.decodeIfPresent(USDZAsset.self, forKey: .usdz)
    }
}
struct USDZUploadResponse: Decodable, Sendable, Equatable {
    let mapID: UUID
    let source: MapSource
    let dimension: MapDimension
    let usdz: USDZAsset?

    private enum CodingKeys: String, CodingKey { case mapID = "map_id", source, dimension, usdz }

    init(mapID: UUID, source: MapSource = .roomplanLidar3D, dimension: MapDimension = .threeD, usdz: USDZAsset? = nil) {
        self.mapID = mapID; self.source = source; self.dimension = dimension; self.usdz = usdz
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mapID = try container.decode(UUID.self, forKey: .mapID)
        source = (try? container.decode(MapSource.self, forKey: .source)) ?? .legacy2D
        dimension = (try? container.decode(MapDimension.self, forKey: .dimension)) ?? .twoD
        usdz = try container.decodeIfPresent(USDZAsset.self, forKey: .usdz)
    }
}
struct RoomPlanCameraRegistrationRequest: Codable, Sendable, Equatable {
    var roomID: UUID? = nil
    let cameraID: UUID
    let mapID: UUID
    let cameraToWorld: [[Double]]
    let confidence: Double?
    let trackingState: String
}
struct RoomPlanCameraRegistrationResponse: Codable, Sendable, Equatable {
    let id: UUID
    let status: CameraRegistrationState
    let cameraID: UUID
    let mapID: UUID
    let coordinateFrame: String
    let cameraToWorld: [[Double]]?
    let confidence: Double?
    let trackingState: String
    let source: String
    private enum CodingKeys: String, CodingKey {
        case id, status, coordinateFrame, cameraToWorld, confidence, trackingState, source
        case cameraID = "cameraId"
        case mapID = "mapId"
    }
}
struct Matrix3x3Request: Codable, Sendable, Equatable {
    let values: [[Double]]
}
struct RoomPlanVisualLandmarkFrameRequest: Codable, Sendable, Equatable {
    let frameBase64: String
    let width: Int
    let height: Int
    let depthBase64: String?
    let depthWidth: Int?
    let depthHeight: Int?
    let intrinsics: Matrix3x3Request
    let cameraToWorld: [[Double]]
    let capturedAt: String
}
struct RoomPlanVisualLandmarksRequest: Codable, Sendable, Equatable {
    let frames: [RoomPlanVisualLandmarkFrameRequest]
}
struct RoomPlanVisualLandmarksResponse: Codable, Sendable, Equatable {
    let mapID: UUID
    let status: String
    let landmarkCount: Int
    let detector: String

    private enum CodingKeys: String, CodingKey {
        // JSONDecoder.one converts `map_id` to `mapId` before matching CodingKeys.
        // Keep this key in its post-conversion form so a successful landmark
        // build is not reported to the app as a decoding failure.
        case mapID = "mapId"
        case status
        case landmarkCount
        case detector
    }
}
struct DataRequestResponse: Codable, Sendable { let requestID: UUID; let status: String }
struct BackendHealthResponse: Codable, Sendable { let status: String; let database: String?; let localInferenceModel: String? }

enum BackendConnectionState: String, Sendable {
    case demo, checking, connected, unavailable

    var label: String {
        switch self { case .demo: "Demo data"; case .checking: "Connecting…"; case .connected: "Backend connected"; case .unavailable: "Backend unavailable" }
    }
}

enum OneAPIError: LocalizedError, Sendable {
    case missingSession
    case invalidResponse
    case familyMemberNotFound
    case cannotChangeOwnAccess
    case cannotChangeOwnerAccess
    case unsupportedFamilyAccessRole(CaregiverAccessRole)
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingSession: "A home session is required for this ONE API operation."
        case .invalidResponse: "The ONE API returned an invalid response."
        case .familyMemberNotFound: "That person is no longer available in this household."
        case .cannotChangeOwnAccess: "You cannot change or remove your own household access."
        case .cannotChangeOwnerAccess: "Owner access requires a separate administrator workflow."
        case let .unsupportedFamilyAccessRole(role): "The live household API does not support the \(role.title) access level yet."
        case let .server(status, message): "ONE API error (\(status)): \(message)"
        }
    }
}

protocol OneAPIClient: Sendable {
    func health() async throws -> BackendHealthResponse
    func createPairingChallenge(_ request: PairingChallengeRequest) async throws -> PairingChallengeResponse
    func completePairing(code: String) async throws -> AuthSession
    func requestEmailCode(_ request: EmailAuthRequest) async throws -> EmailAuthChallenge
    func verifyEmailCode(_ request: EmailAuthVerifyRequest) async throws -> AuthSession
    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String?) async throws -> PairingChallengeResponse
    func acceptFamilyInvite(_ request: FamilyInviteAcceptRequest) async throws -> AuthSession
    func careSpaces() async throws -> [CareSpaceSummary]
    func createCareSpace(_ request: CareSpaceCreateRequest) async throws -> AuthSession
    func activateCareSpace(id: UUID) async throws -> AuthSession
    func authenticated(accessToken: String, homeID: UUID) -> any OneAPIClient
    func events(homeID: UUID) async throws -> [ObservedEvent]
    func recordDailyCheckIn(homeID: UUID, request: DailyCheckInRequest) async throws -> DailyCheckInResult
    func eventSnapshot(homeID: UUID, eventID: UUID) async throws -> Data
    func roomObjects(homeID: UUID) async throws -> [RoomObject]
    func pairedCameras(homeID: UUID) async throws -> [PairedCamera]
    func cameraRooms(homeID: UUID) async throws -> [CameraRoom]
    func createRoom(homeID: UUID, id: UUID?, name: String) async throws -> CameraRoom
    func updateRoom(homeID: UUID, roomID: UUID, name: String) async throws -> CameraRoom
    func deleteRoom(homeID: UUID, roomID: UUID) async throws
    func cameraCount(homeID: UUID) async throws -> Int
    func startCameraPairing(homeID: UUID, label: String) async throws -> CameraPairingChallenge
    func cameraPairingStatus(homeID: UUID, pairingID: UUID) async throws -> CameraPairingStatus
    func updateCamera(homeID: UUID, cameraID: UUID, request: CameraUpdateRequest) async throws
    func deleteCamera(homeID: UUID, cameraID: UUID) async throws
    func startRoomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws -> RoomPlanCalibrationSession
    func roomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws -> RoomPlanCalibrationSession
    func requestRoomPlanCalibrationCapture(homeID: UUID, cameraID: UUID, targetIndex: Int) async throws -> RoomPlanCalibrationSession
    func commitRoomPlanCalibrationReference(homeID: UUID, cameraID: UUID) async throws
    func requestCameraReferenceCapture(homeID: UUID, cameraID: UUID) async throws
    func downloadCameraReferenceSnapshot(homeID: UUID, cameraID: UUID) async throws -> Data
    func cancelRoomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws
    func careRecipients(homeID: UUID) async throws -> [CareRecipient]
    func createCareRecipient(homeID: UUID, request: CareRecipientCreateRequest) async throws -> CareRecipient
    func updateCareRecipient(homeID: UUID, recipientID: UUID, request: CareRecipientUpdateRequest) async throws -> CareRecipient
    func deleteCareRecipient(homeID: UUID, recipientID: UUID) async throws
    func faceProfile(homeID: UUID, recipientID: UUID) async throws -> FaceProfile
    func enrollFaceProfile(homeID: UUID, recipientID: UUID, request: FaceEnrollmentRequest) async throws -> FaceProfile
    func deleteFaceProfile(homeID: UUID, recipientID: UUID) async throws
    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount]
    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String
    func updateFamilyMember(homeID: UUID, userID: UUID, request: FamilyMemberUpdateRequest) async throws -> FamilyMemberMutationResult
    func removeFamilyMember(homeID: UUID, userID: UUID) async throws -> FamilyMemberMutationResult
    func medicationPlans(homeID: UUID, careRecipientID: UUID?, activeOnly: Bool) async throws -> [MedicationPlan]
    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan
    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan
    func medicationReminders(homeID: UUID, careRecipientID: UUID?, day: Date) async throws -> [MedicationDose]
    func recordMedicationCheckIn(homeID: UUID, planID: UUID, request: MedicationCheckInRequest) async throws
    func familyAssistant(homeID: UUID, request: FamilyAssistantRequest) async throws -> FamilyAssistantResult
    func assistantCapability(homeID: UUID, recipientID: UUID?) async throws -> AssistantCapability
    func assistantChat(homeID: UUID, request: AssistantChatRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>
    func assistantAnswers(homeID: UUID, conversationID: UUID, request: AssistantAnswersRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>
    func assistantConversation(homeID: UUID, conversationID: UUID) async throws -> AssistantConversation
    func cancelAssistantConversation(homeID: UUID, conversationID: UUID, requestID: UUID, revision: Int) async throws -> AssistantConversation
    func recordConsent(homeID: UUID, request: ConsentRequest) async throws
    func consents(homeID: UUID) async throws -> [ConsentRecord]
    func logout() async throws
    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse
    func uploadRoomPlan(roomID: UUID?, scan: RoomPlanNormalizedScan, metadata: RoomPlanScanMetadata) async throws -> RoomPlanMapUploadResponse
    func importGeometry(data: Data) async throws -> RoomPlanMapUploadResponse
    func uploadARVideoRoom(scan: ARVideoRoomScan) async throws -> RoomPlanMapUploadResponse
    func uploadRoomPlanUSDZ(mapID: UUID, data: Data) async throws -> USDZUploadResponse
    func uploadRoomPlanVisualLandmarks(mapID: UUID, frames: [RoomPlanVisualLandmarkFrameRequest]) async throws -> RoomPlanVisualLandmarksResponse
    func registerRoomPlanCamera(homeID: UUID, request: RoomPlanCameraRegistrationRequest) async throws -> RoomPlanCameraRegistrationResponse
    func downloadRoomPlanUSDZ(mapID: UUID) async throws -> Data
    func refreshScene(homeID: UUID) async throws -> SceneDescriptor
    func liveKitToken(cameraID: UUID) async throws -> LiveKitTokenResponse
    func dayStory(homeID: UUID, recipientID: UUID, timezone: String) async throws -> DataReviewJSON
    func analyticsReview(homeID: UUID, recipientID: UUID?, timezone: String) async throws -> DataReviewJSON
    func collectionReview(homeID: UUID) async throws -> DataReviewJSON
    func assistantContextReview(homeID: UUID, recipientID: UUID?, timezone: String, message: String) async throws -> DataReviewJSON
    func exportHouseholdData(homeID: UUID) async throws -> Data
    func deleteHouseholdData(homeID: UUID, confirmationHomeID: UUID) async throws
    func requestExport() async throws -> DataRequestResponse
    func requestDeletion() async throws -> DataRequestResponse
}

private final class MockCareSpaceState: @unchecked Sendable {
    private let lock = NSLock()
    private var spaces: [CareSpaceSummary]

    init(spaces: [CareSpaceSummary]) {
        self.spaces = spaces
    }

    func all() -> [CareSpaceSummary] {
        lock.lock()
        defer { lock.unlock() }
        return spaces
    }

    func create(_ request: CareSpaceCreateRequest) -> CareSpaceSummary {
        lock.lock()
        defer { lock.unlock() }
        spaces = spaces.map { item in
            var updated = item
            updated.active = false
            return updated
        }
        let created = CareSpaceSummary(id: UUID(), name: request.name, residentName: "Resident", careSetting: request.careSetting, supportFocus: request.supportFocus, role: .admin, active: true)
        spaces.append(created)
        return created
    }

    func activate(id: UUID) -> CareSpaceSummary? {
        lock.lock()
        defer { lock.unlock() }
        guard let selected = spaces.first(where: { $0.id == id }) else { return nil }
        spaces = spaces.map { item in
            var updated = item
            updated.active = item.id == id
            return updated
        }
        return selected
    }
}

private final class MockCareRecipientState: @unchecked Sendable {
    private let lock = NSLock()
    private var recipientsByHome: [UUID: [CareRecipient]]

    init(recipientsByHome: [UUID: [CareRecipient]]) {
        self.recipientsByHome = recipientsByHome
    }

    func all(homeID: UUID) -> [CareRecipient] {
        lock.lock()
        defer { lock.unlock() }
        return recipientsByHome[homeID] ?? []
    }

    func create(homeID: UUID, request: CareRecipientCreateRequest) -> CareRecipient {
        lock.lock()
        defer { lock.unlock() }
        let recipient = CareRecipient(id: UUID(), displayName: request.displayName, relationship: request.relationship, roomLabel: request.roomLabel)
        recipientsByHome[homeID, default: []].append(recipient)
        return recipient
    }

    func update(homeID: UUID, recipientID: UUID, request: CareRecipientUpdateRequest) -> CareRecipient? {
        lock.lock()
        defer { lock.unlock() }
        guard var recipients = recipientsByHome[homeID], let index = recipients.firstIndex(where: { $0.id == recipientID }) else { return nil }
        var recipient = recipients[index]
        if let displayName = request.displayName { recipient.displayName = displayName }
        recipient.relationship = request.relationship
        recipient.roomLabel = request.roomLabel
        recipients[index] = recipient
        recipientsByHome[homeID] = recipients
        return recipient
    }

    func delete(homeID: UUID, recipientID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var recipients = recipientsByHome[homeID], recipients.contains(where: { $0.id == recipientID }) else { return false }
        recipients.removeAll { $0.id == recipientID }
        recipientsByHome[homeID] = recipients
        return true
    }
}

struct MockOneAPIClient: OneAPIClient {
    private let careSpaceState: MockCareSpaceState
    private let careRecipientState: MockCareRecipientState
    let mockUserID: UUID
    let careSpaceError: OneAPIError?

    init(mockCareSpaces: [CareSpaceSummary] = CareSpaceSummary.demoSpaces, mockCareRecipients: [UUID: [CareRecipient]] = [:], mockUserID: UUID = UUID(), careSpaceError: OneAPIError? = nil) {
        self.careSpaceState = MockCareSpaceState(spaces: mockCareSpaces)
        self.careRecipientState = MockCareRecipientState(recipientsByHome: mockCareRecipients)
        self.mockUserID = mockUserID
        self.careSpaceError = careSpaceError
    }

    func health() async throws -> BackendHealthResponse { BackendHealthResponse(status: "ok", database: "demo", localInferenceModel: "qwen3.6-35b-a3b") }
    func createPairingChallenge(_ request: PairingChallengeRequest) async throws -> PairingChallengeResponse { PairingChallengeResponse(pairingID: UUID(), expiresAt: Date().addingTimeInterval(300)) }
    func completePairing(code: String) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func requestEmailCode(_ request: EmailAuthRequest) async throws -> EmailAuthChallenge { EmailAuthChallenge(verificationID: UUID(), expiresInSeconds: 600, delivery: "development_outbox", devCode: "482701", email: request.email, purpose: request.purpose, homeID: UUID(), userID: UUID(), role: request.role.rawValue) }
    func verifyEmailCode(_ request: EmailAuthVerifyRequest) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String?) async throws -> PairingChallengeResponse { PairingChallengeResponse(pairingID: UUID(), expiresAt: Date().addingTimeInterval(600), accessToken: "demo", homeID: UUID(), userID: UUID(), role: request.role.rawValue) }
    func acceptFamilyInvite(_ request: FamilyInviteAcceptRequest) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func careSpaces() async throws -> [CareSpaceSummary] {
        if let careSpaceError { throw careSpaceError }
        return careSpaceState.all()
    }
    func createCareSpace(_ request: CareSpaceCreateRequest) async throws -> AuthSession {
        if let careSpaceError { throw careSpaceError }
        let created = careSpaceState.create(request)
        return AuthSession(accessToken: "demo-created", homeID: created.id, userID: mockUserID, role: .caregiver, expiresAt: Date().addingTimeInterval(3600))
    }
    func activateCareSpace(id: UUID) async throws -> AuthSession {
        if let careSpaceError { throw careSpaceError }
        guard let space = careSpaceState.activate(id: id) else { throw OneAPIError.server(status: 404, message: "Care space membership not found") }
        return AuthSession(accessToken: "demo-switched", homeID: id, userID: mockUserID, role: space.role.userRole, expiresAt: Date().addingTimeInterval(3600))
    }
    func authenticated(accessToken: String, homeID: UUID) -> any OneAPIClient { self }
    func events(homeID: UUID) async throws -> [ObservedEvent] { [] }
    func recordDailyCheckIn(homeID: UUID, request: DailyCheckInRequest) async throws -> DailyCheckInResult {
        DailyCheckInResult(id: UUID(), eventID: UUID(), careRecipientID: request.careRecipientID, status: "stable", trend: "stable", explanation: "A familiar check-in was recorded in demo mode.", evidenceIDs: [], limitations: "Demo response; observations are not a diagnosis.", degraded: true, inferenceStatus: "demo", modelVersion: "demo-check-in-v1")
    }
    func eventSnapshot(homeID: UUID, eventID: UUID) async throws -> Data { Data() }
    func roomObjects(homeID: UUID) async throws -> [RoomObject] { [] }
    func pairedCameras(homeID: UUID) async throws -> [PairedCamera] { [] }
    func cameraRooms(homeID: UUID) async throws -> [CameraRoom] { [] }
    func createRoom(homeID: UUID, id: UUID?, name: String) async throws -> CameraRoom { CameraRoom(id: id ?? UUID(), name: name) }
    func updateRoom(homeID: UUID, roomID: UUID, name: String) async throws -> CameraRoom { CameraRoom(id: roomID, name: name) }
    func deleteRoom(homeID: UUID, roomID: UUID) async throws { }
    func cameraCount(homeID: UUID) async throws -> Int { 0 }
    func startCameraPairing(homeID: UUID, label: String) async throws -> CameraPairingChallenge { CameraPairingChallenge(pairingID: UUID(), pairingCode: "482701", expiresInSeconds: 600) }
    func cameraPairingStatus(homeID: UUID, pairingID: UUID) async throws -> CameraPairingStatus { CameraPairingStatus(pairingID: pairingID, status: "connected", expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)), connectedAt: ISO8601DateFormatter().string(from: Date()), device: .init(id: pairingID, label: "Demo camera", role: "publisher")) }
    func updateCamera(homeID: UUID, cameraID: UUID, request: CameraUpdateRequest) async throws { }
    func deleteCamera(homeID: UUID, cameraID: UUID) async throws { }
    func startRoomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws -> RoomPlanCalibrationSession {
        let mapID = UUID()
        return RoomPlanCalibrationSession(
            sessionID: UUID(), cameraID: cameraID, mapID: mapID, mode: "scene_reference", status: .waitingForScene,
            currentTargetIndex: 0, capturedTargetCount: 0, captureRoundCount: 3,
            proposal: nil, error: nil,
            solveProgress: nil, solveStage: nil, solveProgressUpdatedAt: nil,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)),
            rawFramesPersisted: false,
            referenceSnapshotPending: false,
            referenceSnapshotAvailable: false
        )
    }
    func roomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws -> RoomPlanCalibrationSession { try await startRoomPlanCalibrationSession(homeID: homeID, cameraID: cameraID) }
    func requestRoomPlanCalibrationCapture(homeID: UUID, cameraID: UUID, targetIndex: Int) async throws -> RoomPlanCalibrationSession { try await startRoomPlanCalibrationSession(homeID: homeID, cameraID: cameraID) }
    func commitRoomPlanCalibrationReference(homeID: UUID, cameraID: UUID) async throws { }
    func requestCameraReferenceCapture(homeID: UUID, cameraID: UUID) async throws { }
    func downloadCameraReferenceSnapshot(homeID: UUID, cameraID: UUID) async throws -> Data { Data() }
    func cancelRoomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws { }
    func careRecipients(homeID: UUID) async throws -> [CareRecipient] { careRecipientState.all(homeID: homeID) }
    func createCareRecipient(homeID: UUID, request: CareRecipientCreateRequest) async throws -> CareRecipient { careRecipientState.create(homeID: homeID, request: request) }
    func updateCareRecipient(homeID: UUID, recipientID: UUID, request: CareRecipientUpdateRequest) async throws -> CareRecipient {
        guard let recipient = careRecipientState.update(homeID: homeID, recipientID: recipientID, request: request) else { throw OneAPIError.server(status: 404, message: "Care recipient not found") }
        return recipient
    }
    func deleteCareRecipient(homeID: UUID, recipientID: UUID) async throws {
        guard careRecipientState.delete(homeID: homeID, recipientID: recipientID) else { throw OneAPIError.server(status: 404, message: "Care recipient not found") }
    }
    func faceProfile(homeID: UUID, recipientID: UUID) async throws -> FaceProfile {
        FaceProfile(careRecipientID: recipientID, status: .notEnrolled, modelVersion: nil, sampleCount: 0, updatedAt: nil)
    }
    func enrollFaceProfile(homeID: UUID, recipientID: UUID, request: FaceEnrollmentRequest) async throws -> FaceProfile {
        guard request.frames.count >= 3 else { throw OneAPIError.server(status: 422, message: "At least three face samples are required") }
        return FaceProfile(careRecipientID: recipientID, status: .ready, modelVersion: "demo-local-face", sampleCount: request.frames.count, updatedAt: Date())
    }
    func deleteFaceProfile(homeID: UUID, recipientID: UUID) async throws { }
    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount] { [] }
    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String { "123456" }
    func updateFamilyMember(homeID: UUID, userID: UUID, request: FamilyMemberUpdateRequest) async throws -> FamilyMemberMutationResult {
        let role: CaregiverAccessRole = request.role == .caregiver ? .primaryCaregiver : .viewer
        return FamilyMemberMutationResult(member: CaregiverAccount(id: userID, name: "Household member", relationship: "Household member", role: role, permissions: role == .viewer ? ["View today"] : ["Review events"], isCurrentUser: false), invalidatedSessions: 0)
    }
    func removeFamilyMember(homeID: UUID, userID: UUID) async throws -> FamilyMemberMutationResult {
        FamilyMemberMutationResult(member: CaregiverAccount(id: userID, name: "Household member", relationship: "Household member", role: .viewer, permissions: ["View today"], isCurrentUser: false), invalidatedSessions: 0)
    }
    func medicationPlans(homeID: UUID, careRecipientID: UUID?, activeOnly: Bool) async throws -> [MedicationPlan] { [] }
    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan { MedicationPlan(id: UUID(), subjectUserID: request.subjectUserID ?? UUID(), careRecipientID: request.careRecipientID, name: request.name, dose: request.dose, schedule: request.schedule, instructions: request.instructions, active: request.active, version: 1, assignedCaregiverID: request.assignedCaregiverID) }
    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan { MedicationPlan(id: planID, subjectUserID: UUID(), careRecipientID: nil, name: request.name ?? "Reminder", dose: request.dose ?? "", schedule: request.schedule ?? "", instructions: request.instructions ?? "", active: request.active ?? true, version: (request.version ?? 1) + 1, assignedCaregiverID: request.assignedCaregiverID) }
    func medicationReminders(homeID: UUID, careRecipientID: UUID?, day: Date) async throws -> [MedicationDose] { [] }
    func recordMedicationCheckIn(homeID: UUID, planID: UUID, request: MedicationCheckInRequest) async throws { }
    func familyAssistant(homeID: UUID, request: FamilyAssistantRequest) async throws -> FamilyAssistantResult { FamilyAssistantResult(summary: "No live assistant data in demo mode.", nextAction: "Review today's plan.", limitations: "Demo response") }
    func recordConsent(homeID: UUID, request: ConsentRequest) async throws { }
    func consents(homeID: UUID) async throws -> [ConsentRecord] { [] }
    func logout() async throws { }
    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse { ArtifactUploadResponse(artifactID: UUID(), sha256: "local-demo", expiresAt: nil) }
    func uploadRoomPlan(roomID: UUID?, scan: RoomPlanNormalizedScan, metadata: RoomPlanScanMetadata) async throws -> RoomPlanMapUploadResponse { RoomPlanMapUploadResponse(mapID: UUID()) }
    func importGeometry(data: Data) async throws -> RoomPlanMapUploadResponse { throw OneAPIError.invalidResponse }
    func uploadARVideoRoom(scan: ARVideoRoomScan) async throws -> RoomPlanMapUploadResponse { RoomPlanMapUploadResponse(mapID: UUID(), source: .arkitVideo3D, coordinateFrame: "arkit-world", usdz: USDZAsset(available: true, sha256: "local-demo", bytes: 1, contentType: "model/vnd.usdz+zip", downloadPath: nil)) }
    func uploadRoomPlanUSDZ(mapID: UUID, data: Data) async throws -> USDZUploadResponse { USDZUploadResponse(mapID: mapID, usdz: USDZAsset(available: true, sha256: "local-demo", bytes: data.count, contentType: "model/vnd.usdz+zip", downloadPath: nil)) }
    func uploadRoomPlanVisualLandmarks(mapID: UUID, frames: [RoomPlanVisualLandmarkFrameRequest]) async throws -> RoomPlanVisualLandmarksResponse { RoomPlanVisualLandmarksResponse(mapID: mapID, status: "ready", landmarkCount: 128, detector: "opencv-orb") }
    func registerRoomPlanCamera(homeID: UUID, request: RoomPlanCameraRegistrationRequest) async throws -> RoomPlanCameraRegistrationResponse { RoomPlanCameraRegistrationResponse(id: UUID(), status: .positioned, cameraID: request.cameraID, mapID: request.mapID, coordinateFrame: "roomplan-local", cameraToWorld: request.cameraToWorld, confidence: request.confidence, trackingState: request.trackingState, source: "auto-roomplan-registration") }
    func downloadRoomPlanUSDZ(mapID: UUID) async throws -> Data { Data() }
    func refreshScene(homeID: UUID) async throws -> SceneDescriptor { .empty }
    func liveKitToken(cameraID: UUID) async throws -> LiveKitTokenResponse { LiveKitTokenResponse(websocketURL: URL(string: "wss://lan.invalid")!, token: "demo-token", roomName: "one-demo", expiresAt: Date().addingTimeInterval(300)) }
    func requestExport() async throws -> DataRequestResponse { DataRequestResponse(requestID: UUID(), status: "queued") }
    func requestDeletion() async throws -> DataRequestResponse { DataRequestResponse(requestID: UUID(), status: "queued") }
}

/// Minimal URLSession adapter for the versioned FastAPI contract. It is used
/// whenever `ONE_API_BASE_URL` is configured. The checked-in loopback URL is
/// intended for a local API on the simulator; previews can omit the setting
/// to use deterministic demo data.
struct HTTPOneAPIClient: OneAPIClient {
    let baseURL: URL
    let accessToken: String?
    let homeID: UUID?
    private let session: URLSession

    init(configuration: RuntimeConfiguration, accessToken: String? = nil, homeID: UUID? = nil, session: URLSession = .shared) {
        self.baseURL = configuration.apiBaseURL; self.accessToken = accessToken; self.homeID = homeID; self.session = session
    }

    private init(baseURL: URL, accessToken: String, homeID: UUID, session: URLSession) {
        self.baseURL = baseURL; self.accessToken = accessToken; self.homeID = homeID; self.session = session
    }

    func health() async throws -> BackendHealthResponse {
        try await send(path: "/health", method: "GET", body: nil, requiresSession: false)
    }

    func createPairingChallenge(_ request: PairingChallengeRequest) async throws -> PairingChallengeResponse {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendPairingResponse = try await send(path: "/pairing/complete", method: "POST", body: body, requiresSession: false)
        let userID = UUID(uuidString: response.userID)
        let homeID = UUID(uuidString: response.homeID)
        return PairingChallengeResponse(pairingID: userID ?? UUID(), expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)), accessToken: response.accessToken, homeID: homeID, userID: userID, role: response.role)
    }

    func completePairing(code: String) async throws -> AuthSession {
        let body = try JSONEncoder.one.encode(PairingChallengeRequest(code: code))
        let response: BackendPairingResponse = try await send(path: "/pairing/complete", method: "POST", body: body, requiresSession: false)
        guard let homeID = UUID(uuidString: response.homeID), let userID = UUID(uuidString: response.userID) else { throw OneAPIError.invalidResponse }
        let role: UserRole
        if let responseRole = response.role, let parsed = UserRole(rawValue: responseRole) { role = parsed }
        else {
            let authenticated = HTTPOneAPIClient(baseURL: baseURL, accessToken: response.accessToken, homeID: homeID, session: session)
            role = (try? await authenticated.currentRole()) ?? .caregiver
        }
        return AuthSession(accessToken: response.accessToken, homeID: homeID, userID: userID, role: role, expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    func requestEmailCode(_ request: EmailAuthRequest) async throws -> EmailAuthChallenge {
        let body = try JSONEncoder.one.encode(request)
        return try await send(path: "/auth/email/request", method: "POST", body: body, requiresSession: false)
    }

    func verifyEmailCode(_ request: EmailAuthVerifyRequest) async throws -> AuthSession {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendPairingResponse = try await send(path: "/auth/email/verify", method: "POST", body: body, requiresSession: false)
        guard let homeID = UUID(uuidString: response.homeID), let userID = UUID(uuidString: response.userID) else { throw OneAPIError.invalidResponse }
        let role = UserRole(rawValue: response.role ?? "caregiver") ?? .caregiver
        return AuthSession(accessToken: response.accessToken, homeID: homeID, userID: userID, role: role, expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String? = nil) async throws -> PairingChallengeResponse {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendBootstrapResponse = try await send(path: "/pairing/start", method: "POST", body: body, requiresSession: false, headers: bootstrapSecret.map { ["X-Bootstrap-Secret": $0] } ?? [:])
        return PairingChallengeResponse(pairingID: UUID(uuidString: response.userID) ?? UUID(), expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresInSeconds)), homeID: UUID(uuidString: response.homeID), userID: UUID(uuidString: response.userID), role: response.role ?? request.role.rawValue, pairingCode: response.pairingCode)
    }

    func acceptFamilyInvite(_ request: FamilyInviteAcceptRequest) async throws -> AuthSession {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendPairingResponse = try await send(path: "/family/invites/accept", method: "POST", body: body, requiresSession: false)
        guard let homeID = UUID(uuidString: response.homeID), let userID = UUID(uuidString: response.userID) else { throw OneAPIError.invalidResponse }
        return AuthSession(accessToken: response.accessToken, homeID: homeID, userID: userID, role: response.role == "resident" ? .resident : .caregiver, expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    func careSpaces() async throws -> [CareSpaceSummary] {
        let response: BackendCareSpacesResponse = try await send(path: "/account/homes", method: "GET", body: nil, requiresSession: true)
        return response.data
    }

    func createCareSpace(_ request: CareSpaceCreateRequest) async throws -> AuthSession {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendPairingResponse = try await send(path: "/account/homes", method: "POST", body: body, requiresSession: true)
        return try response.authSession
    }

    func activateCareSpace(id: UUID) async throws -> AuthSession {
        let response: BackendPairingResponse = try await send(path: "/account/homes/\(id.oneAPIPath)/activate", method: "POST", body: nil, requiresSession: true)
        return try response.authSession
    }

    func authenticated(accessToken: String, homeID: UUID) -> any OneAPIClient {
        HTTPOneAPIClient(baseURL: baseURL, accessToken: accessToken, homeID: homeID, session: session)
    }

    func events(homeID: UUID) async throws -> [ObservedEvent] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")]
        let response: BackendEventsResponse = try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap(\.event)
    }

    func recordDailyCheckIn(homeID: UUID, request: DailyCheckInRequest) async throws -> DailyCheckInResult {
        let body = try JSONEncoder.one.encode(request)
        return try await send(path: "/homes/\(homeID.oneAPIPath)/check-ins", method: "POST", body: body, requiresSession: true)
    }

    func eventSnapshot(homeID: UUID, eventID: UUID) async throws -> Data {
        try await sendRaw(path: "/homes/\(homeID.oneAPIPath)/events/\(eventID.oneAPIPath)/snapshot", method: "GET", body: nil, requiresSession: true, headers: [:])
    }

    func roomObjects(homeID: UUID) async throws -> [RoomObject] {
        let response: BackendObjectsResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/objects/last-seen", method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap(\.object)
    }

    func pairedCameras(homeID: UUID) async throws -> [PairedCamera] {
        let response: BackendCamerasResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/cameras", method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap(\.camera)
    }

    func cameraRooms(homeID: UUID) async throws -> [CameraRoom] {
        let response: BackendRoomsResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/rooms", method: "GET", body: nil, requiresSession: true)
        return response.data
    }

    func createRoom(homeID: UUID, id: UUID?, name: String) async throws -> CameraRoom {
        var payload: [String: Any] = ["name": name]
        if let id { payload["id"] = id.uuidString }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await send(path: "/homes/\(homeID.oneAPIPath)/rooms", method: "POST", body: body, requiresSession: true)
    }

    func updateRoom(homeID: UUID, roomID: UUID, name: String) async throws -> CameraRoom {
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        return try await send(path: "/homes/\(homeID.oneAPIPath)/rooms/\(roomID.oneAPIPath)", method: "PATCH", body: body, requiresSession: true)
    }

    func deleteRoom(homeID: UUID, roomID: UUID) async throws {
        let _: RoomDeleteResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/rooms/\(roomID.oneAPIPath)", method: "DELETE", body: nil, requiresSession: true)
    }

    func cameraCount(homeID: UUID) async throws -> Int {
        try await pairedCameras(homeID: homeID).count
    }

    func startCameraPairing(homeID: UUID, label: String) async throws -> CameraPairingChallenge {
        let body = try JSONSerialization.data(withJSONObject: ["label": label, "expires_in_seconds": 600])
        return try await send(path: "/homes/\(homeID.oneAPIPath)/pairing/start", method: "POST", body: body, requiresSession: true)
    }

    func cameraPairingStatus(homeID: UUID, pairingID: UUID) async throws -> CameraPairingStatus {
        try await send(path: "/homes/\(homeID.oneAPIPath)/pairing/\(pairingID.oneAPIPath)/status", method: "GET", body: nil, requiresSession: true)
    }

    func updateCamera(homeID: UUID, cameraID: UUID, request: CameraUpdateRequest) async throws {
        let body = try JSONEncoder.one.encode(request)
        let _: CameraMutationResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)", method: "PATCH", body: body, requiresSession: true)
    }

    func deleteCamera(homeID: UUID, cameraID: UUID) async throws {
        let _: CameraDeleteResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)", method: "DELETE", body: nil, requiresSession: true)
    }

    func startRoomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws -> RoomPlanCalibrationSession {
        try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)/roomplan-calibration-session", method: "POST", body: nil, requiresSession: true)
    }

    func roomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws -> RoomPlanCalibrationSession {
        try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)/roomplan-calibration-session", method: "GET", body: nil, requiresSession: true)
    }

    func requestRoomPlanCalibrationCapture(homeID: UUID, cameraID: UUID, targetIndex: Int) async throws -> RoomPlanCalibrationSession {
        let body = try JSONSerialization.data(withJSONObject: ["target_index": targetIndex])
        return try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)/roomplan-calibration-session/request-capture", method: "POST", body: body, requiresSession: true)
    }

    func commitRoomPlanCalibrationReference(homeID: UUID, cameraID: UUID) async throws {
        let _: CameraReferenceSnapshotMutationResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)/roomplan-calibration-session/commit-reference", method: "POST", body: nil, requiresSession: true)
    }

    func requestCameraReferenceCapture(homeID: UUID, cameraID: UUID) async throws {
        let _: CameraReferenceCaptureRequestResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)/reference-snapshot/request-capture", method: "POST", body: nil, requiresSession: true)
    }

    func downloadCameraReferenceSnapshot(homeID: UUID, cameraID: UUID) async throws -> Data {
        try await sendRaw(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)/reference-snapshot", method: "GET", body: nil, requiresSession: true, headers: [:])
    }

    func cancelRoomPlanCalibrationSession(homeID: UUID, cameraID: UUID) async throws {
        let _: CameraCalibrationCancelResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/cameras/\(cameraID.oneAPIPath)/roomplan-calibration-session", method: "DELETE", body: nil, requiresSession: true)
    }

    func careRecipients(homeID: UUID) async throws -> [CareRecipient] {
        let response: BackendCareRecipientsResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/care-recipients", method: "GET", body: nil, requiresSession: true)
        return response.data
    }

    func createCareRecipient(homeID: UUID, request: CareRecipientCreateRequest) async throws -> CareRecipient {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendCareRecipientMutationResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/care-recipients", method: "POST", body: body, requiresSession: true)
        return response.data
    }

    func updateCareRecipient(homeID: UUID, recipientID: UUID, request: CareRecipientUpdateRequest) async throws -> CareRecipient {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendCareRecipientMutationResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/care-recipients/\(recipientID.oneAPIPath)", method: "PATCH", body: body, requiresSession: true)
        return response.data
    }

    func deleteCareRecipient(homeID: UUID, recipientID: UUID) async throws {
        _ = try await sendRaw(path: "/homes/\(homeID.oneAPIPath)/care-recipients/\(recipientID.oneAPIPath)", method: "DELETE", body: nil, requiresSession: true, headers: [:])
    }

    func faceProfile(homeID: UUID, recipientID: UUID) async throws -> FaceProfile {
        let response: BackendFaceProfileResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/care-recipients/\(recipientID.oneAPIPath)/face-profile", method: "GET", body: nil, requiresSession: true)
        return response.profile
    }

    func enrollFaceProfile(homeID: UUID, recipientID: UUID, request: FaceEnrollmentRequest) async throws -> FaceProfile {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendFaceProfileResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/care-recipients/\(recipientID.oneAPIPath)/face-profile/enroll", method: "POST", body: body, requiresSession: true)
        return response.profile
    }

    func deleteFaceProfile(homeID: UUID, recipientID: UUID) async throws {
        _ = try await sendRaw(path: "/homes/\(homeID.oneAPIPath)/care-recipients/\(recipientID.oneAPIPath)/face-profile", method: "DELETE", body: nil, requiresSession: true, headers: [:])
    }

    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount] {
        let response: BackendFamilyMembersResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/family/members", method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap { $0.account }
    }

    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendFamilyInviteResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/family/invites", method: "POST", body: body, requiresSession: true)
        return response.code
    }

    func updateFamilyMember(homeID: UUID, userID: UUID, request: FamilyMemberUpdateRequest) async throws -> FamilyMemberMutationResult {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendFamilyMemberMutationResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/family/members/\(userID.oneAPIPath)", method: "PATCH", body: body, requiresSession: true)
        guard let member = response.data.account else { throw OneAPIError.invalidResponse }
        return FamilyMemberMutationResult(member: member, invalidatedSessions: response.invalidatedSessions)
    }

    func removeFamilyMember(homeID: UUID, userID: UUID) async throws -> FamilyMemberMutationResult {
        let response: BackendFamilyMemberMutationResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/family/members/\(userID.oneAPIPath)", method: "DELETE", body: nil, requiresSession: true)
        guard let member = response.data.account else { throw OneAPIError.invalidResponse }
        return FamilyMemberMutationResult(member: member, invalidatedSessions: response.invalidatedSessions)
    }

    func medicationPlans(homeID: UUID, careRecipientID: UUID?, activeOnly: Bool = true) async throws -> [MedicationPlan] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/medication-plans"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "active_only", value: activeOnly ? "true" : "false")]
        if let careRecipientID { query.append(URLQueryItem(name: "care_recipient_id", value: careRecipientID.oneAPIPath)) }
        components.queryItems = query
        let response: BackendMedicationPlansResponse = try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap { $0.plan }
    }

    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendMedicationPlan = try await send(path: "/homes/\(homeID.oneAPIPath)/medication-plans", method: "POST", body: body, requiresSession: true)
        guard let plan = response.plan else { throw OneAPIError.invalidResponse }
        return plan
    }

    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendMedicationPlan = try await send(path: "/homes/\(homeID.oneAPIPath)/medication-plans/\(planID.oneAPIPath)", method: "PATCH", body: body, requiresSession: true)
        guard let plan = response.plan else { throw OneAPIError.invalidResponse }
        return plan
    }

    func medicationReminders(homeID: UUID, careRecipientID: UUID?, day: Date) async throws -> [MedicationDose] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/medication-reminders"), resolvingAgainstBaseURL: false)!
        // The picker represents a local calendar day. Format its components
        // in the user's calendar so midnight does not become the previous UTC
        // day before it reaches the API.
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = .current
        var query = [URLQueryItem(name: "day", value: formatter.string(from: day))]
        if let careRecipientID { query.append(URLQueryItem(name: "care_recipient_id", value: careRecipientID.oneAPIPath)) }
        components.queryItems = query
        let response: BackendMedicationRemindersResponse = try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap { $0.dose }
    }

    func recordMedicationCheckIn(homeID: UUID, planID: UUID, request: MedicationCheckInRequest) async throws {
        let encoder = JSONEncoder.one
        encoder.dateEncodingStrategy = .iso8601
        let body = try encoder.encode(request)
        let _: BackendMedicationCheckInResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/medication-plans/\(planID.oneAPIPath)/check-ins", method: "POST", body: body, requiresSession: true)
    }

    func familyAssistant(homeID: UUID, request: FamilyAssistantRequest) async throws -> FamilyAssistantResult {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendFamilyAssistantResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/family-assistant", method: "POST", body: body, requiresSession: true)
        return response.data
    }

    func recordConsent(homeID: UUID, request: ConsentRequest) async throws {
        let body = try JSONEncoder.one.encode(request)
        let _: BackendConsentResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/consents", method: "POST", body: body, requiresSession: true)
    }

    func consents(homeID: UUID) async throws -> [ConsentRecord] {
        let response: BackendConsentsResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/consents", method: "GET", body: nil, requiresSession: true)
        var latestByScope: [String: BackendConsentRecord] = [:]
        for record in response.data.sorted(by: { $0.grantedAt > $1.grantedAt }) {
            let scope = "\(record.subjectUserId)|\(record.careRecipientId ?? "")|\(record.purpose)"
            if latestByScope[scope] == nil {
                latestByScope[scope] = record
            }
        }
        return latestByScope.values.compactMap { record in
            guard let id = UUID(uuidString: record.id),
                  let subjectUserID = UUID(uuidString: record.subjectUserId) else { return nil }
            return ConsentRecord(
                id: id,
                purpose: record.purpose,
                enabled: record.revokedAt == nil,
                policyVersion: record.policyVersion,
                updatedAt: record.grantedAt,
                subjectUserID: subjectUserID,
                careRecipientID: record.careRecipientId.flatMap(UUID.init(uuidString:))
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func logout() async throws { try await sendEmpty(path: "/sessions/current", method: "DELETE") }

    private func currentRole() async throws -> UserRole {
        let response: BackendMeResponse = try await send(path: "/me", method: "GET", body: nil, requiresSession: true)
        return response.actor.role == "resident" ? .resident : .caregiver // backend admin/caregiver accounts use the caregiver shell
    }

    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        guard JSONSerialization.isValidJSONObject(try JSONSerialization.jsonObject(with: normalizedJSON)) else { throw OneAPIError.invalidResponse }
        let mapData = try JSONSerialization.jsonObject(with: normalizedJSON)
        let payload: [String: Any] = ["room_id": roomID.oneAPIPath, "coordinate_frame": "roomplan-local", "map_data": mapData]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let response: BackendMapUploadResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/maps", method: "POST", body: body, requiresSession: true)
        let digest = SHA256.hash(data: normalizedJSON).map { String(format: "%02x", $0) }.joined()
        return ArtifactUploadResponse(artifactID: UUID(uuidString: response.id) ?? UUID(), sha256: digest, expiresAt: nil)
    }

    func uploadRoomPlan(roomID: UUID?, scan: RoomPlanNormalizedScan, metadata: RoomPlanScanMetadata) async throws -> RoomPlanMapUploadResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let body = try JSONEncoder.one.encode(RoomPlanUploadRequest(roomID: roomID, normalizedScan: scan, scanMetadata: metadata))
        return try await send(path: "/homes/\(homeID.oneAPIPath)/maps/roomplan", method: "POST", body: body, requiresSession: true, headers: ["X-ONE-Client": "native-ios-roomplan"])
    }

    func importGeometry(data: Data) async throws -> RoomPlanMapUploadResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        return try await send(path: "/homes/\(homeID.oneAPIPath)/maps/imported-3d", method: "POST", body: data, requiresSession: true)
    }

    func uploadARVideoRoom(scan: ARVideoRoomScan) async throws -> RoomPlanMapUploadResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let body = try JSONEncoder.one.encode(scan)
        return try await send(path: "/homes/\(homeID.oneAPIPath)/maps/arkit-video", method: "POST", body: body, requiresSession: true, headers: ["X-ONE-Client": "native-ios-arkit-video"])
    }

    func uploadRoomPlanUSDZ(mapID: UUID, data: Data) async throws -> USDZUploadResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let response: BackendUSDZUploadResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/maps/\(mapID.oneAPIPath)/usdz", method: "PUT", body: data, requiresSession: true, headers: ["Content-Type": "model/vnd.usdz+zip", "X-ONE-Client": "native-ios-roomplan", "X-ONE-Idempotency-Key": mapID.oneAPIPath])
        guard let responseMapID = UUID(uuidString: response.mapId) else { throw OneAPIError.invalidResponse }
        return USDZUploadResponse(mapID: responseMapID, source: MapSource(rawValue: response.source) ?? .legacy2D, dimension: MapDimension(rawValue: response.dimension) ?? .twoD, usdz: response.usdz)
    }

    func uploadRoomPlanVisualLandmarks(mapID: UUID, frames: [RoomPlanVisualLandmarkFrameRequest]) async throws -> RoomPlanVisualLandmarksResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let request = RoomPlanVisualLandmarksRequest(frames: frames)
        let body = try await Task.detached(priority: .userInitiated) {
            try JSONEncoder.one.encode(request)
        }.value
        return try await send(path: "/homes/\(homeID.oneAPIPath)/maps/\(mapID.oneAPIPath)/visual-landmarks", method: "POST", body: body, requiresSession: true, headers: ["X-ONE-Client": "native-ios-roomplan"], timeoutInterval: 180)
    }

    func registerRoomPlanCamera(homeID: UUID, request: RoomPlanCameraRegistrationRequest) async throws -> RoomPlanCameraRegistrationResponse {
        if let roomID = request.roomID {
            let body = try JSONSerialization.data(withJSONObject: ["camera_id": request.cameraID.oneAPIPath, "map_id": request.mapID.oneAPIPath, "room_id": roomID.oneAPIPath, "camera_to_world": request.cameraToWorld, "confirmed": true])
            return try await send(path: "/homes/\(homeID.oneAPIPath)/camera-registrations/manual", method: "POST", body: body, requiresSession: true)
        }
        let body = try JSONEncoder.one.encode(request)
        return try await send(path: "/homes/\(homeID.oneAPIPath)/camera-registrations/roomplan", method: "POST", body: body, requiresSession: true, headers: ["X-ONE-Client": "native-ios-roomplan"])
    }

    func downloadRoomPlanUSDZ(mapID: UUID) async throws -> Data {
        guard let homeID else { throw OneAPIError.missingSession }
        return try await sendRaw(path: "/homes/\(homeID.oneAPIPath)/maps/\(mapID.oneAPIPath)/usdz", method: "GET", body: nil, requiresSession: true, headers: [:])
    }

    func refreshScene(homeID: UUID) async throws -> SceneDescriptor {
        try await send(path: "/homes/\(homeID.oneAPIPath)/scene", method: "GET", body: nil, requiresSession: true)
    }

    func liveKitToken(cameraID: UUID) async throws -> LiveKitTokenResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let body = try JSONSerialization.data(withJSONObject: ["mode": "subscribe"])
        let response: BackendLiveKitResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/livekit/token", method: "POST", body: body, requiresSession: true)
        guard let url = URL(string: response.url) else { throw OneAPIError.invalidResponse }
        return LiveKitTokenResponse(websocketURL: url, token: response.token, roomName: "one-\(homeID.oneAPIPath)", expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    private func dataReviewURL(homeID: UUID, endpoint: String, recipientID: UUID?, timezone: String) throws -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/\(endpoint)"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "window_days", value: "14"), URLQueryItem(name: "timezone_name", value: timezone)]
        if let recipientID { items.append(URLQueryItem(name: "care_recipient_id", value: recipientID.oneAPIPath)) }
        components?.queryItems = items
        guard let url = components?.url else { throw OneAPIError.invalidResponse }
        return url
    }
    func dayStory(homeID: UUID, recipientID: UUID, timezone: String) async throws -> DataReviewJSON {
        try await send(url: dataReviewURL(homeID: homeID, endpoint: "day-story", recipientID: recipientID, timezone: timezone), method: "GET", body: nil, requiresSession: true)
    }
    func analyticsReview(homeID: UUID, recipientID: UUID?, timezone: String) async throws -> DataReviewJSON {
        try await send(url: dataReviewURL(homeID: homeID, endpoint: "analytics", recipientID: recipientID, timezone: timezone), method: "GET", body: nil, requiresSession: true)
    }
    func collectionReview(homeID: UUID) async throws -> DataReviewJSON {
        try await send(path: "/homes/\(homeID.oneAPIPath)/collection-readiness", method: "GET", body: nil, requiresSession: true)
    }
    func assistantContextReview(homeID: UUID, recipientID: UUID?, timezone: String, message: String) async throws -> DataReviewJSON {
        var components = URLComponents(url: try dataReviewURL(homeID: homeID, endpoint: "assistant-context", recipientID: recipientID, timezone: timezone), resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "message", value: message)]
        return try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
    }
    func exportHouseholdData(homeID: UUID) async throws -> Data {
        try await sendRaw(path: "/homes/\(homeID.oneAPIPath)/privacy/export", method: "POST", body: nil, requiresSession: true, headers: ["Accept": "application/json"])
    }
    func deleteHouseholdData(homeID: UUID, confirmationHomeID: UUID) async throws {
        guard confirmationHomeID == homeID else { throw OneAPIError.server(status: 422, message: "Confirmation does not match this household.") }
        let body = try JSONSerialization.data(withJSONObject: ["confirmed": true, "confirmation_home_id": confirmationHomeID.oneAPIPath])
        let _: BackendDeletionResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/privacy/delete", method: "POST", body: body, requiresSession: true)
    }

    func requestExport() async throws -> DataRequestResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        _ = try await send(path: "/homes/\(homeID.oneAPIPath)/privacy/export", method: "POST", body: nil, requiresSession: true) as BackendExportResponse
        return DataRequestResponse(requestID: UUID(), status: "complete")
    }

    func requestDeletion() async throws -> DataRequestResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        throw OneAPIError.server(status: 422, message: "Explicit household confirmation is required before deletion.")
    }

    private func send<T: Decodable>(path: String, method: String, body: Data?, requiresSession: Bool, headers: [String: String] = [:], timeoutInterval: TimeInterval? = nil) async throws -> T {
        if requiresSession && (accessToken == nil || homeID == nil) { throw OneAPIError.missingSession }
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.httpBody = body
        if let timeoutInterval { request.timeoutInterval = timeoutInterval }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OneAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder.one.decode(APIProblem.self, from: data).message) ?? "The ONE API request failed."
            throw OneAPIError.server(status: http.statusCode, message: message)
        }
        guard let decoded = try? JSONDecoder.one.decode(T.self, from: data) else { throw OneAPIError.invalidResponse }
        return decoded
    }

    private func send<T: Decodable>(url: URL, method: String, body: Data?, requiresSession: Bool) async throws -> T {
        try await sendRequest(url: url, method: method, body: body, requiresSession: requiresSession, headers: [:])
    }

    private func sendRaw(path: String, method: String, body: Data?, requiresSession: Bool, headers: [String: String]) async throws -> Data {
        if requiresSession && (accessToken == nil || homeID == nil) { throw OneAPIError.missingSession }
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.httpBody = body
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OneAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder.one.decode(APIProblem.self, from: data).message) ?? "The ONE API request failed."
            throw OneAPIError.server(status: http.statusCode, message: message)
        }
        return data
    }

    private func sendRequest<T: Decodable>(url: URL, method: String, body: Data?, requiresSession: Bool, headers: [String: String]) async throws -> T {
        if requiresSession && (accessToken == nil || homeID == nil) { throw OneAPIError.missingSession }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request); guard let http = response as? HTTPURLResponse else { throw OneAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { let message = (try? JSONDecoder.one.decode(APIProblem.self, from: data).message) ?? "The ONE API request failed."; throw OneAPIError.server(status: http.statusCode, message: message) }
        guard let decoded = try? JSONDecoder.one.decode(T.self, from: data) else { throw OneAPIError.invalidResponse }; return decoded
    }

    private func sendEmpty(path: String, method: String) async throws {
        guard accessToken != nil else { throw OneAPIError.missingSession }
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.setValue("Bearer \(accessToken!)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OneAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { let message = (try? JSONDecoder.one.decode(APIProblem.self, from: data).message) ?? "The ONE API request failed."; throw OneAPIError.server(status: http.statusCode, message: message) }
    }
}

private struct BackendPairingResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let homeID: String
    let userID: String
    let role: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken
        case expiresIn
        case homeID = "homeId"
        case userID = "userId"
        case role
    }

    var authSession: AuthSession {
        get throws {
            guard let homeID = UUID(uuidString: homeID), let userID = UUID(uuidString: userID) else { throw OneAPIError.invalidResponse }
            let membership = role.flatMap(CareSpaceMembershipRole.init(rawValue:))
            return AuthSession(
                accessToken: accessToken,
                homeID: homeID,
                userID: userID,
                role: membership?.userRole ?? .caregiver,
                expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
            )
        }
    }
}

private struct BackendBootstrapResponse: Decodable {
    let pairingCode: String
    let expiresInSeconds: Int
    let homeID: String
    let userID: String
    let role: String?

    private enum CodingKeys: String, CodingKey {
        case pairingCode = "pairingCode"
        case expiresInSeconds
        case homeID = "homeId"
        case userID = "userId"
        case role
    }
}
private struct BackendMeResponse: Decodable { let actor: BackendActor }
private struct BackendCareSpacesResponse: Decodable { let data: [CareSpaceSummary] }
private struct BackendCareRecipientsResponse: Decodable { let data: [CareRecipient] }
private struct BackendCareRecipientMutationResponse: Decodable { let data: CareRecipient }
private struct BackendFaceProfileResponse: Decodable {
    let careRecipientID: String
    let status: FaceRecognitionStatus
    let modelVersion: String?
    let sampleCount: Int
    let updatedAt: Date?

    var profile: FaceProfile {
        FaceProfile(
            careRecipientID: UUID(uuidString: careRecipientID) ?? UUID(),
            status: status,
            modelVersion: modelVersion,
            sampleCount: sampleCount,
            updatedAt: updatedAt
        )
    }
}
private struct BackendActor: Decodable { let role: String }
private struct BackendConsentResponse: Decodable { let id: String? }
private struct BackendConsentsResponse: Decodable { let data: [BackendConsentRecord] }
private struct BackendConsentRecord: Decodable {
    let id: String
    let subjectUserId: String
    let purpose: String
    let policyVersion: String
    let grantedAt: Date
    let revokedAt: Date?
    let careRecipientId: String?
}
private struct BackendIDResponse: Decodable { let id: String }
private struct BackendMapUploadResponse: Decodable { let id: String; let revision: Int? }
private struct BackendUSDZUploadResponse: Decodable { let mapId: String; let source: String; let dimension: String; let usdz: USDZAsset? }
private struct BackendLiveKitResponse: Decodable { let url: String; let token: String; let expiresIn: Int }
private struct BackendExportResponse: Decodable { let homeID: String }
private struct BackendDeletionResponse: Decodable { let requestID: String; let status: String }
private struct BackendFamilyInviteResponse: Decodable { let code: String }
private struct BackendEventsResponse: Decodable { let data: [BackendEvent] }
private struct BackendEvent: Decodable {
    let id: String
    let eventType: String
    let status: String?
    let explanation: String?
    let confidence: Double?
    let firstSeenAt: Date?
    let lastSeenAt: Date?
    let snapshotPath: String?
    let snapshotContentType: String?

    var event: ObservedEvent? {
        guard let id = UUID(uuidString: id), let timestamp = lastSeenAt ?? firstSeenAt else { return nil }
        let kind: EventKind
        switch eventType {
        case "check_in", "checkin", "daily_check_in": kind = .checkIn
        case "no_response": kind = .noResponse
        case "assistant_request": kind = .assistant
        case "fall_suspected": kind = .fallSuspected
        default: kind = .movement
        }
        let confidenceLevel: ObservationConfidence
        switch confidence ?? 0 {
        case 0.8...: confidenceLevel = .high
        case 0.5..<0.8: confidenceLevel = .medium
        default: confidenceLevel = .low
        }
        return ObservedEvent(id: id, kind: kind, timestamp: timestamp, location: "Home · approximate", confidence: confidenceLevel, explanation: explanation ?? "An observation is available for review.", reviewed: status == "reviewed", hasClip: false, snapshotPath: snapshotPath, snapshotContentType: snapshotContentType)
    }
}
private struct BackendObjectsResponse: Decodable { let data: [BackendObject] }
private struct BackendObjectIdentity: Decodable {
    let status: String?
    let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case displayName
    }
}
private struct BackendObject: Decodable {
    let id: String
    let label: String
    let objectType: String?
    let lastSeenAt: Date?
    let point: BackendPoint?
    let worldPoint: BackendPoint?
    let mapId: String?
    let cameraId: String?
    let confidence: Double?
    let presenceState: PersonPresenceState?
    let identity: BackendObjectIdentity?

    var object: RoomObject? {
        guard let id = UUID(uuidString: id) else { return nil }
        let mappedPoint = worldPoint ?? point ?? BackendPoint(x: nil, y: nil, z: nil)
        let confidenceLevel: ObservationConfidence
        switch confidence ?? 0 {
        case 0.8...: confidenceLevel = .high
        case 0.5..<0.8: confidenceLevel = .medium
        default: confidenceLevel = .low
        }
        return RoomObject(
            id: id,
            name: objectType == "person" ? "person" : label,
            category: (objectType ?? label).lowercased(),
            position: SIMD3(Float(mappedPoint.x ?? 0), Float(mappedPoint.y ?? 0), Float(mappedPoint.z ?? 0)),
            dimensions: SIMD3(repeating: 0),
            confidence: confidenceLevel,
            zoneID: id,
            mapID: mapId.flatMap(UUID.init(uuidString:)),
            cameraID: cameraId.flatMap(UUID.init(uuidString:)),
            observedAt: lastSeenAt,
            presenceState: presenceState,
            identityStatus: identity?.status,
            identityName: identity?.displayName
        )
    }
}
private struct BackendPoint: Decodable { let x: Double?; let y: Double?; let z: Double? }
private struct CameraReferenceSnapshotMutationResponse: Decodable {
    let cameraID: String

    private enum CodingKeys: String, CodingKey {
        case cameraID = "cameraId"
    }
}
private struct CameraReferenceCaptureRequestResponse: Decodable {
    let requestID: String
    let cameraID: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case requestID = "requestId"
        case cameraID = "cameraId"
        case status
    }
}
private struct BackendCamerasResponse: Decodable { let data: [BackendCamera] }
private struct BackendRoomsResponse: Decodable { let data: [CameraRoom] }
private struct BackendCamera: Decodable {
    let id: String
    let name: String
    let roomID: String?
    struct Simulation: Decodable { let status: String? }
    let simulation: Simulation?
    let status: String
    let calibrationNeeded: Bool?
    let roomplanRegistrationStatus: String?
    let roomplanMapID: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, simulation, status, calibrationNeeded, roomplanRegistrationStatus
        case roomID = "roomId"
        case roomplanMapID = "roomplanMapId"
    }

    var camera: PairedCamera? {
        guard let id = UUID(uuidString: id) else { return nil }
        return PairedCamera(
            id: id,
            name: name,
            roomID: roomID.flatMap(UUID.init(uuidString:)),
            status: status,
            simulationStatus: simulation?.status,
            calibrationNeeded: calibrationNeeded ?? false,
            roomplanRegistrationStatus: roomplanRegistrationStatus ?? "map_required",
            roomplanMapID: roomplanMapID.flatMap(UUID.init(uuidString:))
        )
    }
}
private struct CameraMutationResponse: Decodable { let id: UUID }
private struct CameraDeleteResponse: Decodable { let id: UUID; let status: String }
private struct RoomDeleteResponse: Decodable { let id: UUID; let status: String }
private struct CameraCalibrationCancelResponse: Decodable {
    let cameraID: UUID
    let status: String

    private enum CodingKeys: String, CodingKey {
        case cameraID = "cameraId"
        case status
    }
}
private struct BackendFamilyMembersResponse: Decodable { let data: [BackendFamilyMember] }
private struct BackendFamilyMemberMutationResponse: Decodable { let data: BackendFamilyMember; let invalidatedSessions: Int }
private struct BackendFamilyMember: Decodable {
    let id: String; let displayName: String; let email: String?; let role: String
    var account: CaregiverAccount? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let accessRole: CaregiverAccessRole = role == "admin" ? .owner : (role == "caregiver" ? .primaryCaregiver : (CaregiverAccessRole(rawValue: role) ?? .viewer))
        return CaregiverAccount(id: uuid, name: displayName, relationship: email ?? "Household member", role: accessRole, permissions: accessRole == .viewer ? ["View today"] : ["Review events"], isCurrentUser: false)
    }
}
private struct BackendMedicationRemindersResponse: Decodable { let data: [BackendMedicationReminder] }
private struct BackendMedicationPlansResponse: Decodable { let data: [BackendMedicationPlan] }
private struct BackendMedicationCheckInResponse: Decodable { let data: BackendMedicationCheckIn }
private struct BackendMedicationCheckIn: Decodable { let status: String; let markedByName: String?; let updatedAt: Date }
private struct BackendFamilyAssistantResponse: Decodable { let data: FamilyAssistantResult }
private struct BackendMedicationPlan: Decodable {
    let id: String
    let subjectUserID: String
    let careRecipientID: String?
    let name: String
    let dose: String
    let schedule: String
    let instructions: String
    let active: Bool
    let version: Int
    let assignedCaregiverID: String?

    private enum CodingKeys: String, CodingKey {
        // JSONDecoder.one converts snake-case keys before matching custom
        // keys, so the post-conversion spelling keeps the ID suffix intact.
        case id
        case subjectUserID = "subjectUserId"
        case careRecipientID = "careRecipientId"
        case name, dose, schedule, instructions, active, version
        case assignedCaregiverID = "assignedCaregiverId"
    }

    var plan: MedicationPlan? {
        guard let id = UUID(uuidString: id), let subjectUserID = UUID(uuidString: subjectUserID) else { return nil }
        return MedicationPlan(id: id, subjectUserID: subjectUserID, careRecipientID: careRecipientID.flatMap(UUID.init(uuidString:)), name: name, dose: dose, schedule: schedule, instructions: instructions, active: active, version: version, assignedCaregiverID: assignedCaregiverID.flatMap(UUID.init(uuidString:)))
    }
}
private struct BackendMedicationReminder: Decodable {
    let planID: String; let careRecipientID: String?; let name: String; let medicationDose: String; let instructions: String; let scheduleRule: String; let scheduledFor: Date; let status: String; let assignedCaregiverName: String?; let markedByName: String?; let updatedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case planID = "planId"
        case careRecipientID = "careRecipientId"
        case name
        case medicationDose = "dose"
        case instructions
        case scheduleRule = "scheduleRule"
        case scheduledFor
        case status
        case assignedCaregiverName
        case markedByName
        case updatedAt
    }

    var dose: MedicationDose? {
        guard let planID = UUID(uuidString: planID) else { return nil }
        let status = status == "taken" ? MedicationDoseStatus.acknowledged : status == "missed" ? .missed : status == "skipped" ? .needsConfirmation : .scheduled
        return MedicationDose(id: UUID(), medicationName: "\(name) · \(medicationDose)", instructions: instructions, scheduledAt: scheduledFor, status: status, assignedCaregiverName: assignedCaregiverName, scheduleRule: scheduleRule, careRecipientID: careRecipientID.flatMap(UUID.init(uuidString:)), planID: planID, markedByName: markedByName, markedAt: updatedAt)
    }
}

// Shared by the API adapter and AppStore when serializing RoomPlan payloads.
private extension UUID {
    /// The API stores UUID identifiers as lowercase text and compares route
    /// parameters as strings. Keep every iOS route/query identifier in that
    /// canonical form instead of using UUID.uuidString directly.
    var oneAPIPath: String { uuidString.lowercased() }
}

extension JSONEncoder {
    static var one: JSONEncoder { let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; return encoder }
}

private extension JSONDecoder {
    static var one: JSONDecoder { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date") }
        return date
    }; return decoder }
}

protocol LiveKitViewingSession: Sendable {
    func joinSubscribeOnly(using token: LiveKitTokenResponse) async throws
    func leave() async
}

// Normal assistant transport deliberately decodes only public presentation events.
struct AssistantCapability: Codable, Sendable, Equatable {
    enum State: String, Codable, Sendable { case unconfigured, configured, unavailable }
    let state: State
    let mode: String
    let provider: String?
    let external: Bool
    let reason: String?
    let requiresConsent: Bool
    let toolsSupported: Bool
    enum CodingKeys: String, CodingKey {
        case state, mode, provider, external, reason
        case requiresConsent = "requires_consent", toolsSupported = "tools_supported"
    }
    static let debug = Self(state: .unconfigured, mode: "debug", provider: nil, external: false, reason: nil, requiresConsent: false, toolsSupported: true)
}

struct AssistantQuestionOption: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let label: String
    let description: String
}
struct AssistantQuestion: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let header: String
    let question: String
    let options: [AssistantQuestionOption]
}
struct AssistantQuestionBatch: Codable, Sendable, Equatable {
    let toolCallID: String
    let questions: [AssistantQuestion]
    enum CodingKeys: String, CodingKey { case toolCallID = "tool_call_id", questions }
    func validate() throws {
        guard !toolCallID.isEmpty, (1...3).contains(questions.count), Set(questions.map(\.id)).count == questions.count else { throw OneAPIError.invalidResponse }
        for question in questions {
            guard !question.id.isEmpty, !question.question.isEmpty, (2...3).contains(question.options.count),
                  Set(question.options.map(\.id)).count == question.options.count,
                  question.options.allSatisfy({ !$0.id.isEmpty && !$0.label.isEmpty }) else { throw OneAPIError.invalidResponse }
        }
    }
}
struct AssistantQuestionAnswer: Codable, Sendable, Equatable {
    let questionID: String
    var optionID: String?
    var customText: String?
    enum CodingKeys: String, CodingKey { case questionID = "question_id", optionID = "option_id", customText = "custom_text" }
}
struct AssistantChatRequest: Codable, Sendable {
    let requestID: UUID
    let message: String
    let careRecipientID: UUID?
    let conversationID: UUID?
    let expectedRevision: Int?
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", message, careRecipientID = "care_recipient_id", conversationID = "conversation_id", expectedRevision = "expected_revision"
    }
}
struct AssistantAnswersRequest: Codable, Sendable {
    let requestID: UUID
    let expectedRevision: Int
    let toolCallID: String
    let answers: [AssistantQuestionAnswer]
    enum CodingKeys: String, CodingKey {
        case requestID = "request_id", expectedRevision = "expected_revision", toolCallID = "tool_call_id", answers
    }
}
struct AssistantConversation: Codable, Sendable {
    struct Message: Codable, Sendable { let role: String; let content: String }
    let conversationID: UUID
    let revision: Int
    let status: String
    let pending: AssistantQuestionBatch?
    let messages: [Message]
    enum CodingKeys: String, CodingKey { case conversationID = "conversation_id", revision, status, pending, messages }
}
struct AssistantStreamEvent: Sendable {
    enum Payload: Sendable {
        case started, delta(String), questions(AssistantQuestionBatch), completed(String)
        case error(code: String, message: String, retryable: Bool), done(String)
    }
    let conversationID: UUID
    let requestID: UUID
    let revision: Int
    let payload: Payload
}

/// Buffers bytes before UTF-8 decoding, so split Unicode and split JSON are safe.
struct AssistantSSEParser {
    private var line = Data()
    private var eventName = ""
    private var dataLines: [String] = []
    private var frameBytes = 0
    mutating func feed(_ bytes: Data) throws -> [AssistantStreamEvent] {
        var events: [AssistantStreamEvent] = []
        for byte in bytes {
            frameBytes += 1
            guard frameBytes <= 262_144 else { throw OneAPIError.invalidResponse }
            if byte == 10 {
                if line.last == 13 { line.removeLast() }
                guard let text = String(data: line, encoding: .utf8) else { throw OneAPIError.invalidResponse }
                line.removeAll(keepingCapacity: true)
                if text.isEmpty {
                    if let event = try dispatch() { events.append(event) }
                    eventName = ""; dataLines = []; frameBytes = 0
                } else if text.hasPrefix("event:") { eventName = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
                else if text.hasPrefix("data:") {
                    var value = String(text.dropFirst(5)); if value.first == " " { value.removeFirst() }; dataLines.append(value)
                }
            } else { line.append(byte) }
        }
        return events
    }
    private func dispatch() throws -> AssistantStreamEvent? {
        let known = ["conversation.started", "assistant.delta", "questions.required", "assistant.completed", "stream.error", "stream.done"]
        guard known.contains(eventName) else { return nil }
        struct Envelope: Decodable {
            let conversation_id: UUID; let request_id: UUID; let revision: Int
            let text: String?; let tool_call_id: String?; let questions: [AssistantQuestion]?
            let code: String?; let message: String?; let retryable: Bool?; let status: String?
        }
        let decoded = try JSONDecoder().decode(Envelope.self, from: Data(dataLines.joined(separator: "\n").utf8))
        guard decoded.revision >= 0 else { throw OneAPIError.invalidResponse }
        let payload: AssistantStreamEvent.Payload
        switch eventName {
        case "conversation.started": payload = .started
        case "assistant.delta", "assistant.completed":
            guard let text = decoded.text, !text.contains("<|"), !text.contains("[start]") else { throw OneAPIError.invalidResponse }
            payload = eventName == "assistant.delta" ? .delta(text) : .completed(text)
        case "questions.required":
            guard let id = decoded.tool_call_id, let questions = decoded.questions else { throw OneAPIError.invalidResponse }
            let batch = AssistantQuestionBatch(toolCallID: id, questions: questions); try batch.validate(); payload = .questions(batch)
        case "stream.error": payload = .error(code: decoded.code ?? "unavailable", message: decoded.message ?? "The assistant is unavailable. Please try again.", retryable: decoded.retryable ?? false)
        default:
            guard let status = decoded.status, ["completed", "awaiting_answers", "failed", "cancelled"].contains(status) else { throw OneAPIError.invalidResponse }
            payload = .done(status)
        }
        return AssistantStreamEvent(conversationID: decoded.conversation_id, requestID: decoded.request_id, revision: decoded.revision, payload: payload)
    }
}

extension OneAPIClient {
    func assistantCapability(homeID: UUID, recipientID: UUID?) async throws -> AssistantCapability { throw OneAPIError.invalidResponse }
    func assistantChat(homeID: UUID, request: AssistantChatRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> { AsyncThrowingStream { $0.finish(throwing: OneAPIError.invalidResponse) } }
    func assistantAnswers(homeID: UUID, conversationID: UUID, request: AssistantAnswersRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> { AsyncThrowingStream { $0.finish(throwing: OneAPIError.invalidResponse) } }
    func assistantConversation(homeID: UUID, conversationID: UUID) async throws -> AssistantConversation { throw OneAPIError.invalidResponse }
    func cancelAssistantConversation(homeID: UUID, conversationID: UUID, requestID: UUID, revision: Int) async throws -> AssistantConversation { throw OneAPIError.invalidResponse }
}

extension HTTPOneAPIClient {
    func assistantCapability(homeID: UUID, recipientID: UUID?) async throws -> AssistantCapability {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/chat/capability"), resolvingAgainstBaseURL: false)!
        if let recipientID { components.queryItems = [URLQueryItem(name: "care_recipient_id", value: recipientID.oneAPIPath)] }
        let data = try await chatData(url: components.url!, method: "GET", body: nil)
        return try JSONDecoder().decode(AssistantCapability.self, from: data)
    }
    func assistantChat(homeID: UUID, request: AssistantChatRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        chatStream(path: "homes/\(homeID.oneAPIPath)/chat/stream", body: try? JSONEncoder().encode(request))
    }
    func assistantAnswers(homeID: UUID, conversationID: UUID, request: AssistantAnswersRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        chatStream(path: "homes/\(homeID.oneAPIPath)/chat/conversations/\(conversationID.oneAPIPath)/answers/stream", body: try? JSONEncoder().encode(request))
    }
    func assistantConversation(homeID: UUID, conversationID: UUID) async throws -> AssistantConversation {
        let data = try await chatData(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/chat/conversations/\(conversationID.oneAPIPath)"), method: "GET", body: nil)
        return try JSONDecoder().decode(AssistantConversation.self, from: data)
    }
    func cancelAssistantConversation(homeID: UUID, conversationID: UUID, requestID: UUID, revision: Int) async throws -> AssistantConversation {
        let body = try JSONSerialization.data(withJSONObject: ["request_id": requestID.oneAPIPath, "expected_revision": revision])
        let data = try await chatData(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/chat/conversations/\(conversationID.oneAPIPath)/cancel"), method: "POST", body: body)
        return try JSONDecoder().decode(AssistantConversation.self, from: data)
    }
    private func chatRequest(url: URL, method: String, body: Data?) throws -> URLRequest {
        guard let accessToken, self.homeID != nil else { throw OneAPIError.missingSession }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 90
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    private func chatData(url: URL, method: String, body: Data?) async throws -> Data {
        let request = try chatRequest(url: url, method: method, body: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OneAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw OneAPIError.server(status: http.statusCode, message: "The assistant request could not be completed. Please try again.") }
        return data
    }
    private func chatStream(path: String, body: Data?) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard body != nil else { throw OneAPIError.invalidResponse }
                    var request = try chatRequest(url: baseURL.appendingPathComponent(path), method: "POST", body: body)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw OneAPIError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else { throw OneAPIError.server(status: http.statusCode, message: "The assistant is unavailable. Please try again.") }
                    guard http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("text/event-stream") == true else { throw OneAPIError.invalidResponse }
                    var parser = AssistantSSEParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for event in try parser.feed(Data([byte])) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

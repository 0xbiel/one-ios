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
}
struct FamilyInviteAcceptRequest: Codable, Sendable { let code: String; let displayName: String?; let email: String? }
struct FamilyInviteRequest: Codable, Sendable { let displayName: String; let email: String?; let role: UserRole; let expiresInSeconds: Int }
struct FamilyMemberUpdateRequest: Codable, Sendable, Equatable { let role: UserRole }
struct FamilyMemberMutationResult: Sendable, Equatable {
    let member: CaregiverAccount
    let invalidatedSessions: Int
}
struct ConsentRequest: Codable, Sendable { let purpose: String; let policyVersion: String; let granted: Bool }
struct MedicationPlan: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let subjectUserID: UUID
    var name: String
    var dose: String
    var schedule: String
    var instructions: String
    var active: Bool
    var version: Int
    var assignedCaregiverID: UUID?
}
struct MedicationPlanRequest: Codable, Sendable {
    let subjectUserID: UUID
    let name: String
    let dose: String
    let schedule: String
    let instructions: String
    let active: Bool
    let assignedCaregiverID: UUID?
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
        try container.encodeIfPresent(assignedCaregiverID, forKey: .assignedCaregiverID)
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
}
struct Matrix3x3Request: Codable, Sendable, Equatable {
    let values: [[Double]]
}
struct RoomPlanVisualLandmarkFrameRequest: Codable, Sendable, Equatable {
    let frameBase64: String
    let width: Int
    let height: Int
    let depthBase64: String
    let depthWidth: Int
    let depthHeight: Int
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
        case mapID = "map_id"
        case status
        case landmarkCount = "landmark_count"
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
    func events(homeID: UUID) async throws -> [ObservedEvent]
    func roomObjects(homeID: UUID) async throws -> [RoomObject]
    func pairedCameras(homeID: UUID) async throws -> [PairedCamera]
    func cameraCount(homeID: UUID) async throws -> Int
    func startCameraPairing(homeID: UUID, label: String) async throws -> CameraPairingChallenge
    func cameraPairingStatus(homeID: UUID, pairingID: UUID) async throws -> CameraPairingStatus
    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount]
    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String
    func updateFamilyMember(homeID: UUID, userID: UUID, request: FamilyMemberUpdateRequest) async throws -> FamilyMemberMutationResult
    func removeFamilyMember(homeID: UUID, userID: UUID) async throws -> FamilyMemberMutationResult
    func medicationPlans(homeID: UUID, subjectUserID: UUID?, activeOnly: Bool) async throws -> [MedicationPlan]
    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan
    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan
    func medicationReminders(homeID: UUID, subjectUserID: UUID?, day: Date) async throws -> [MedicationDose]
    func recordConsent(homeID: UUID, request: ConsentRequest) async throws
    func logout() async throws
    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse
    func uploadRoomPlan(roomID: UUID?, scan: RoomPlanNormalizedScan, metadata: RoomPlanScanMetadata) async throws -> RoomPlanMapUploadResponse
    func uploadRoomPlanUSDZ(mapID: UUID, data: Data) async throws -> USDZUploadResponse
    func uploadRoomPlanVisualLandmarks(mapID: UUID, frames: [RoomPlanVisualLandmarkFrameRequest]) async throws -> RoomPlanVisualLandmarksResponse
    func registerRoomPlanCamera(homeID: UUID, request: RoomPlanCameraRegistrationRequest) async throws -> RoomPlanCameraRegistrationResponse
    func downloadRoomPlanUSDZ(mapID: UUID) async throws -> Data
    func refreshScene(homeID: UUID) async throws -> SceneDescriptor
    func liveKitToken(cameraID: UUID) async throws -> LiveKitTokenResponse
    func requestExport() async throws -> DataRequestResponse
    func requestDeletion() async throws -> DataRequestResponse
}

struct MockOneAPIClient: OneAPIClient {
    func health() async throws -> BackendHealthResponse { BackendHealthResponse(status: "ok", database: "demo", localInferenceModel: "qwen3.6-35b-a3b") }
    func createPairingChallenge(_ request: PairingChallengeRequest) async throws -> PairingChallengeResponse { PairingChallengeResponse(pairingID: UUID(), expiresAt: Date().addingTimeInterval(300)) }
    func completePairing(code: String) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func requestEmailCode(_ request: EmailAuthRequest) async throws -> EmailAuthChallenge { EmailAuthChallenge(verificationID: UUID(), expiresInSeconds: 600, delivery: "development_outbox", devCode: "482701", email: request.email, purpose: request.purpose, homeID: UUID(), userID: UUID(), role: request.role.rawValue) }
    func verifyEmailCode(_ request: EmailAuthVerifyRequest) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String?) async throws -> PairingChallengeResponse { PairingChallengeResponse(pairingID: UUID(), expiresAt: Date().addingTimeInterval(600), accessToken: "demo", homeID: UUID(), userID: UUID(), role: request.role.rawValue) }
    func acceptFamilyInvite(_ request: FamilyInviteAcceptRequest) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func events(homeID: UUID) async throws -> [ObservedEvent] { [] }
    func roomObjects(homeID: UUID) async throws -> [RoomObject] { [] }
    func pairedCameras(homeID: UUID) async throws -> [PairedCamera] { [] }
    func cameraCount(homeID: UUID) async throws -> Int { 0 }
    func startCameraPairing(homeID: UUID, label: String) async throws -> CameraPairingChallenge { CameraPairingChallenge(pairingID: UUID(), pairingCode: "482701", expiresInSeconds: 600) }
    func cameraPairingStatus(homeID: UUID, pairingID: UUID) async throws -> CameraPairingStatus { CameraPairingStatus(pairingID: pairingID, status: "connected", expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)), connectedAt: ISO8601DateFormatter().string(from: Date()), device: .init(id: pairingID, label: "Demo camera", role: "publisher")) }
    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount] { [] }
    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String { "123456" }
    func updateFamilyMember(homeID: UUID, userID: UUID, request: FamilyMemberUpdateRequest) async throws -> FamilyMemberMutationResult {
        let role: CaregiverAccessRole = request.role == .caregiver ? .primaryCaregiver : .viewer
        return FamilyMemberMutationResult(member: CaregiverAccount(id: userID, name: "Household member", relationship: "Household member", role: role, permissions: role == .viewer ? ["View today"] : ["Review events"], isCurrentUser: false), invalidatedSessions: 0)
    }
    func removeFamilyMember(homeID: UUID, userID: UUID) async throws -> FamilyMemberMutationResult {
        FamilyMemberMutationResult(member: CaregiverAccount(id: userID, name: "Household member", relationship: "Household member", role: .viewer, permissions: ["View today"], isCurrentUser: false), invalidatedSessions: 0)
    }
    func medicationPlans(homeID: UUID, subjectUserID: UUID?, activeOnly: Bool) async throws -> [MedicationPlan] { [] }
    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan { MedicationPlan(id: UUID(), subjectUserID: request.subjectUserID, name: request.name, dose: request.dose, schedule: request.schedule, instructions: request.instructions, active: request.active, version: 1, assignedCaregiverID: request.assignedCaregiverID) }
    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan { MedicationPlan(id: planID, subjectUserID: UUID(), name: request.name ?? "Reminder", dose: request.dose ?? "", schedule: request.schedule ?? "", instructions: request.instructions ?? "", active: request.active ?? true, version: (request.version ?? 1) + 1, assignedCaregiverID: request.assignedCaregiverID) }
    func medicationReminders(homeID: UUID, subjectUserID: UUID?, day: Date) async throws -> [MedicationDose] { [] }
    func recordConsent(homeID: UUID, request: ConsentRequest) async throws { }
    func logout() async throws { }
    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse { ArtifactUploadResponse(artifactID: UUID(), sha256: "local-demo", expiresAt: nil) }
    func uploadRoomPlan(roomID: UUID?, scan: RoomPlanNormalizedScan, metadata: RoomPlanScanMetadata) async throws -> RoomPlanMapUploadResponse { RoomPlanMapUploadResponse(mapID: UUID()) }
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

    func events(homeID: UUID) async throws -> [ObservedEvent] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/events"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")]
        let response: BackendEventsResponse = try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap(\.event)
    }

    func roomObjects(homeID: UUID) async throws -> [RoomObject] {
        let response: BackendObjectsResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/objects/last-seen", method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap(\.object)
    }

    func pairedCameras(homeID: UUID) async throws -> [PairedCamera] {
        let response: BackendCamerasResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/cameras", method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap(\.camera)
    }

    func cameraCount(homeID: UUID) async throws -> Int {
        try await pairedCameras(homeID: homeID).count
    }

    func startCameraPairing(homeID: UUID, label: String) async throws -> CameraPairingChallenge {
        struct Response: Decodable { let pairingID: UUID; let pairingCode: String; let expiresInSeconds: Int }
        let body = try JSONSerialization.data(withJSONObject: ["label": label, "expires_in_seconds": 600])
        let response: Response = try await send(path: "/homes/\(homeID.oneAPIPath)/pairing/start", method: "POST", body: body, requiresSession: true)
        return CameraPairingChallenge(pairingID: response.pairingID, pairingCode: response.pairingCode, expiresInSeconds: response.expiresInSeconds)
    }

    func cameraPairingStatus(homeID: UUID, pairingID: UUID) async throws -> CameraPairingStatus {
        try await send(path: "/homes/\(homeID.oneAPIPath)/pairing/\(pairingID.oneAPIPath)/status", method: "GET", body: nil, requiresSession: true)
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

    func medicationPlans(homeID: UUID, subjectUserID: UUID?, activeOnly: Bool = true) async throws -> [MedicationPlan] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/medication-plans"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "active_only", value: activeOnly ? "true" : "false")]
        if let subjectUserID { query.append(URLQueryItem(name: "subject_user_id", value: subjectUserID.oneAPIPath)) }
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

    func medicationReminders(homeID: UUID, subjectUserID: UUID?, day: Date) async throws -> [MedicationDose] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.oneAPIPath)/medication-reminders"), resolvingAgainstBaseURL: false)!
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var query = [URLQueryItem(name: "day", value: formatter.string(from: day))]
        if let subjectUserID { query.append(URLQueryItem(name: "subject_user_id", value: subjectUserID.oneAPIPath)) }
        components.queryItems = query
        let response: BackendMedicationRemindersResponse = try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap { $0.dose }
    }

    func recordConsent(homeID: UUID, request: ConsentRequest) async throws {
        let body = try JSONEncoder.one.encode(request)
        let _: BackendConsentResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/consents", method: "POST", body: body, requiresSession: true)
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

    func uploadRoomPlanUSDZ(mapID: UUID, data: Data) async throws -> USDZUploadResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let response: BackendUSDZUploadResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/maps/\(mapID.oneAPIPath)/usdz", method: "PUT", body: data, requiresSession: true, headers: ["Content-Type": "model/vnd.usdz+zip", "X-ONE-Client": "native-ios-roomplan", "X-ONE-Idempotency-Key": mapID.oneAPIPath])
        guard let responseMapID = UUID(uuidString: response.mapId) else { throw OneAPIError.invalidResponse }
        return USDZUploadResponse(mapID: responseMapID, source: MapSource(rawValue: response.source) ?? .legacy2D, dimension: MapDimension(rawValue: response.dimension) ?? .twoD, usdz: response.usdz)
    }

    func uploadRoomPlanVisualLandmarks(mapID: UUID, frames: [RoomPlanVisualLandmarkFrameRequest]) async throws -> RoomPlanVisualLandmarksResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let body = try JSONEncoder.one.encode(RoomPlanVisualLandmarksRequest(frames: frames))
        return try await send(path: "/homes/\(homeID.oneAPIPath)/maps/\(mapID.oneAPIPath)/visual-landmarks", method: "POST", body: body, requiresSession: true, headers: ["X-ONE-Client": "native-ios-roomplan"])
    }

    func registerRoomPlanCamera(homeID: UUID, request: RoomPlanCameraRegistrationRequest) async throws -> RoomPlanCameraRegistrationResponse {
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

    func requestExport() async throws -> DataRequestResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        _ = try await send(path: "/homes/\(homeID.oneAPIPath)/privacy/export", method: "POST", body: nil, requiresSession: true) as BackendExportResponse
        return DataRequestResponse(requestID: UUID(), status: "complete")
    }

    func requestDeletion() async throws -> DataRequestResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let response: BackendDeletionResponse = try await send(path: "/homes/\(homeID.oneAPIPath)/privacy/delete", method: "POST", body: nil, requiresSession: true)
        return DataRequestResponse(requestID: UUID(uuidString: response.requestID) ?? UUID(), status: response.status)
    }

    private func send<T: Decodable>(path: String, method: String, body: Data?, requiresSession: Bool, headers: [String: String] = [:]) async throws -> T {
        if requiresSession && (accessToken == nil || homeID == nil) { throw OneAPIError.missingSession }
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.httpBody = body
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
private struct BackendActor: Decodable { let role: String }
private struct BackendConsentResponse: Decodable { let id: String? }
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

    var event: ObservedEvent? {
        guard let id = UUID(uuidString: id), let timestamp = lastSeenAt ?? firstSeenAt else { return nil }
        let kind: EventKind
        switch eventType {
        case "check_in", "checkin": kind = .checkIn
        case "no_response": kind = .noResponse
        case "assistant_request": kind = .assistant
        default: kind = .movement
        }
        let confidenceLevel: ObservationConfidence
        switch confidence ?? 0 {
        case 0.8...: confidenceLevel = .high
        case 0.5..<0.8: confidenceLevel = .medium
        default: confidenceLevel = .low
        }
        return ObservedEvent(id: id, kind: kind, timestamp: timestamp, location: "Home · approximate", confidence: confidenceLevel, explanation: explanation ?? "An observation is available for review.", reviewed: status == "reviewed", hasClip: false)
    }
}
private struct BackendObjectsResponse: Decodable { let data: [BackendObject] }
private struct BackendObject: Decodable {
    let id: String
    let label: String
    let lastSeenAt: Date?
    let point: BackendPoint?
    let confidence: Double?

    var object: RoomObject? {
        guard let id = UUID(uuidString: id) else { return nil }
        let point = point ?? BackendPoint(x: nil, y: nil)
        let confidenceLevel: ObservationConfidence
        switch confidence ?? 0 {
        case 0.8...: confidenceLevel = .high
        case 0.5..<0.8: confidenceLevel = .medium
        default: confidenceLevel = .low
        }
        return RoomObject(id: id, name: label, category: "object", position: SIMD3(Float(point.x ?? 0), Float(point.y ?? 0), 0), dimensions: SIMD3(repeating: 0), confidence: confidenceLevel, zoneID: id)
    }
}
private struct BackendPoint: Decodable { let x: Double?; let y: Double? }
private struct BackendCamerasResponse: Decodable { let data: [BackendCamera] }
private struct BackendCamera: Decodable {
    let id: String
    let name: String
    let roomID: String?
    let status: String

    var camera: PairedCamera? {
        guard let id = UUID(uuidString: id) else { return nil }
        return PairedCamera(id: id, name: name, roomID: roomID.flatMap(UUID.init(uuidString:)), status: status)
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
private struct BackendMedicationPlan: Decodable {
    let id: String
    let subjectUserID: String
    let name: String
    let dose: String
    let schedule: String
    let instructions: String
    let active: Bool
    let version: Int
    let assignedCaregiverID: String?

    var plan: MedicationPlan? {
        guard let id = UUID(uuidString: id), let subjectUserID = UUID(uuidString: subjectUserID) else { return nil }
        return MedicationPlan(id: id, subjectUserID: subjectUserID, name: name, dose: dose, schedule: schedule, instructions: instructions, active: active, version: version, assignedCaregiverID: assignedCaregiverID.flatMap(UUID.init(uuidString:)))
    }
}
private struct BackendMedicationReminder: Decodable {
    let planID: String; let name: String; let medicationDose: String; let instructions: String; let scheduleRule: String; let scheduledFor: Date; let status: String; let assignedCaregiverName: String?
    var dose: MedicationDose? {
        guard let planID = UUID(uuidString: planID) else { return nil }
        let status = status == "taken" ? MedicationDoseStatus.acknowledged : status == "missed" ? .missed : status == "skipped" ? .needsConfirmation : .scheduled
        return MedicationDose(id: UUID(), medicationName: "\(name) · \(medicationDose)", instructions: instructions, scheduledAt: scheduledFor, status: status, assignedCaregiverName: assignedCaregiverName, scheduleRule: scheduleRule, planID: planID)
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

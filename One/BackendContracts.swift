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
struct BootstrapAccountRequest: Codable, Sendable { let displayName: String; let email: String?; let homeName: String; let role: UserRole }
struct FamilyInviteAcceptRequest: Codable, Sendable { let code: String; let displayName: String? }
struct FamilyInviteRequest: Codable, Sendable { let displayName: String; let email: String?; let role: UserRole; let expiresInSeconds: Int }
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
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingSession: "A home session is required for this ONE API operation."
        case .invalidResponse: "The ONE API returned an invalid response."
        case let .server(status, message): "ONE API error (\(status)): \(message)"
        }
    }
}

protocol OneAPIClient: Sendable {
    func health() async throws -> BackendHealthResponse
    func createPairingChallenge(_ request: PairingChallengeRequest) async throws -> PairingChallengeResponse
    func completePairing(code: String) async throws -> AuthSession
    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String?) async throws -> PairingChallengeResponse
    func acceptFamilyInvite(_ request: FamilyInviteAcceptRequest) async throws -> AuthSession
    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount]
    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String
    func medicationPlans(homeID: UUID, subjectUserID: UUID?, activeOnly: Bool) async throws -> [MedicationPlan]
    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan
    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan
    func medicationReminders(homeID: UUID, subjectUserID: UUID?, day: Date) async throws -> [MedicationDose]
    func recordConsent(homeID: UUID, request: ConsentRequest) async throws
    func logout() async throws
    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse
    func liveKitToken(cameraID: UUID) async throws -> LiveKitTokenResponse
    func requestExport() async throws -> DataRequestResponse
    func requestDeletion() async throws -> DataRequestResponse
}

struct MockOneAPIClient: OneAPIClient {
    func health() async throws -> BackendHealthResponse { BackendHealthResponse(status: "ok", database: "demo", localInferenceModel: "qwen3.6-35b-a3b") }
    func createPairingChallenge(_ request: PairingChallengeRequest) async throws -> PairingChallengeResponse { PairingChallengeResponse(pairingID: UUID(), expiresAt: Date().addingTimeInterval(300)) }
    func completePairing(code: String) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String?) async throws -> PairingChallengeResponse { PairingChallengeResponse(pairingID: UUID(), expiresAt: Date().addingTimeInterval(600), accessToken: "demo", homeID: UUID(), userID: UUID(), role: request.role.rawValue) }
    func acceptFamilyInvite(_ request: FamilyInviteAcceptRequest) async throws -> AuthSession { AuthSession(accessToken: "demo", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600)) }
    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount] { [] }
    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String { "123456" }
    func medicationPlans(homeID: UUID, subjectUserID: UUID?, activeOnly: Bool) async throws -> [MedicationPlan] { [] }
    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan { MedicationPlan(id: UUID(), subjectUserID: request.subjectUserID, name: request.name, dose: request.dose, schedule: request.schedule, instructions: request.instructions, active: request.active, version: 1, assignedCaregiverID: request.assignedCaregiverID) }
    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan { MedicationPlan(id: planID, subjectUserID: UUID(), name: request.name ?? "Reminder", dose: request.dose ?? "", schedule: request.schedule ?? "", instructions: request.instructions ?? "", active: request.active ?? true, version: (request.version ?? 1) + 1, assignedCaregiverID: request.assignedCaregiverID) }
    func medicationReminders(homeID: UUID, subjectUserID: UUID?, day: Date) async throws -> [MedicationDose] { [] }
    func recordConsent(homeID: UUID, request: ConsentRequest) async throws { }
    func logout() async throws { }
    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse { ArtifactUploadResponse(artifactID: UUID(), sha256: "local-demo", expiresAt: nil) }
    func liveKitToken(cameraID: UUID) async throws -> LiveKitTokenResponse { LiveKitTokenResponse(websocketURL: URL(string: "wss://lan.invalid")!, token: "demo-token", roomName: "one-demo", expiresAt: Date().addingTimeInterval(300)) }
    func requestExport() async throws -> DataRequestResponse { DataRequestResponse(requestID: UUID(), status: "queued") }
    func requestDeletion() async throws -> DataRequestResponse { DataRequestResponse(requestID: UUID(), status: "queued") }
}

/// Minimal URLSession adapter for the versioned FastAPI contract. It is used
/// only when `ONE_API_BASE_URL` points to a real LAN/Tailscale HTTPS host;
/// loopback remains the deterministic simulator/demo mode.
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

    func familyMembers(homeID: UUID) async throws -> [CaregiverAccount] {
        let response: BackendFamilyMembersResponse = try await send(path: "/homes/\(homeID.uuidString)/family/members", method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap { $0.account }
    }

    func createFamilyInvite(homeID: UUID, request: FamilyInviteRequest) async throws -> String {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendFamilyInviteResponse = try await send(path: "/homes/\(homeID.uuidString)/family/invites", method: "POST", body: body, requiresSession: true)
        return response.code
    }

    func medicationPlans(homeID: UUID, subjectUserID: UUID?, activeOnly: Bool = true) async throws -> [MedicationPlan] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.uuidString)/medication-plans"), resolvingAgainstBaseURL: false)!
        var query = [URLQueryItem(name: "active_only", value: activeOnly ? "true" : "false")]
        if let subjectUserID { query.append(URLQueryItem(name: "subject_user_id", value: subjectUserID.uuidString)) }
        components.queryItems = query
        let response: BackendMedicationPlansResponse = try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap { $0.plan }
    }

    func createMedicationPlan(homeID: UUID, request: MedicationPlanRequest) async throws -> MedicationPlan {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendMedicationPlan = try await send(path: "/homes/\(homeID.uuidString)/medication-plans", method: "POST", body: body, requiresSession: true)
        guard let plan = response.plan else { throw OneAPIError.invalidResponse }
        return plan
    }

    func updateMedicationPlan(homeID: UUID, planID: UUID, request: MedicationPlanUpdateRequest) async throws -> MedicationPlan {
        let body = try JSONEncoder.one.encode(request)
        let response: BackendMedicationPlan = try await send(path: "/homes/\(homeID.uuidString)/medication-plans/\(planID.uuidString)", method: "PATCH", body: body, requiresSession: true)
        guard let plan = response.plan else { throw OneAPIError.invalidResponse }
        return plan
    }

    func medicationReminders(homeID: UUID, subjectUserID: UUID?, day: Date) async throws -> [MedicationDose] {
        var components = URLComponents(url: baseURL.appendingPathComponent("homes/\(homeID.uuidString)/medication-reminders"), resolvingAgainstBaseURL: false)!
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        var query = [URLQueryItem(name: "day", value: formatter.string(from: day))]
        if let subjectUserID { query.append(URLQueryItem(name: "subject_user_id", value: subjectUserID.uuidString)) }
        components.queryItems = query
        let response: BackendMedicationRemindersResponse = try await send(url: components.url!, method: "GET", body: nil, requiresSession: true)
        return response.data.compactMap { $0.dose }
    }

    func recordConsent(homeID: UUID, request: ConsentRequest) async throws {
        let body = try JSONEncoder.one.encode(request)
        let _: BackendConsentResponse = try await send(path: "/homes/\(homeID.uuidString)/consents", method: "POST", body: body, requiresSession: true)
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
        let payload: [String: Any] = ["room_id": roomID.uuidString, "coordinate_frame": "roomplan-local", "map_data": mapData]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let response: BackendMapUploadResponse = try await send(path: "/homes/\(homeID.uuidString)/maps", method: "POST", body: body, requiresSession: true)
        let digest = SHA256.hash(data: normalizedJSON).map { String(format: "%02x", $0) }.joined()
        return ArtifactUploadResponse(artifactID: UUID(uuidString: response.id) ?? UUID(), sha256: digest, expiresAt: nil)
    }

    func liveKitToken(cameraID: UUID) async throws -> LiveKitTokenResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let body = try JSONSerialization.data(withJSONObject: ["mode": "subscribe"])
        let response: BackendLiveKitResponse = try await send(path: "/homes/\(homeID.uuidString)/livekit/token", method: "POST", body: body, requiresSession: true)
        guard let url = URL(string: response.url) else { throw OneAPIError.invalidResponse }
        return LiveKitTokenResponse(websocketURL: url, token: response.token, roomName: "one-\(homeID.uuidString)", expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)))
    }

    func requestExport() async throws -> DataRequestResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        _ = try await send(path: "/homes/\(homeID.uuidString)/privacy/export", method: "POST", body: nil, requiresSession: true) as BackendExportResponse
        return DataRequestResponse(requestID: UUID(), status: "complete")
    }

    func requestDeletion() async throws -> DataRequestResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        let response: BackendDeletionResponse = try await send(path: "/homes/\(homeID.uuidString)/privacy/delete", method: "POST", body: nil, requiresSession: true)
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

private struct BackendPairingResponse: Decodable { let accessToken: String; let expiresIn: Int; let homeID: String; let userID: String; let role: String? }
private struct BackendBootstrapResponse: Decodable { let pairingCode: String; let expiresInSeconds: Int; let homeID: String; let userID: String; let role: String? }
private struct BackendMeResponse: Decodable { let actor: BackendActor }
private struct BackendActor: Decodable { let role: String }
private struct BackendConsentResponse: Decodable { let id: String? }
private struct BackendIDResponse: Decodable { let id: String }
private struct BackendMapUploadResponse: Decodable { let id: String; let revision: Int? }
private struct BackendLiveKitResponse: Decodable { let url: String; let token: String; let expiresIn: Int }
private struct BackendExportResponse: Decodable { let homeID: String }
private struct BackendDeletionResponse: Decodable { let requestID: String; let status: String }
private struct BackendFamilyInviteResponse: Decodable { let code: String }
private struct BackendFamilyMembersResponse: Decodable { let data: [BackendFamilyMember] }
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

private extension JSONEncoder {
    static var one: JSONEncoder { let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; return encoder }
}

private extension JSONDecoder {
    static var one: JSONDecoder { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; decoder.dateDecodingStrategy = .custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else { throw DecodingError.dataCorruptedError(in: decoder.singleValueContainer(), debugDescription: "Invalid ISO-8601 date") }
        return date
    }; return decoder }
}

protocol LiveKitViewingSession: Sendable {
    func joinSubscribeOnly(using token: LiveKitTokenResponse) async throws
    func leave() async
}

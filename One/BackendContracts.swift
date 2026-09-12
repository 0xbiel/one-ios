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

    init(pairingID: UUID, expiresAt: Date, accessToken: String? = nil, homeID: UUID? = nil, userID: UUID? = nil, role: String? = nil) {
        self.pairingID = pairingID; self.expiresAt = expiresAt; self.accessToken = accessToken; self.homeID = homeID; self.userID = userID; self.role = role
    }
}
struct AuthSession: Codable, Sendable, Equatable {
    let accessToken: String
    let homeID: UUID
    let userID: UUID
    let role: UserRole
    let expiresAt: Date?
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

    func logout() async throws { try await sendEmpty(path: "/sessions/current", method: "DELETE") }

    private func currentRole() async throws -> UserRole {
        let response: BackendMeResponse = try await send(path: "/me", method: "GET", body: nil, requiresSession: true)
        return UserRole(rawValue: response.actor.role) ?? .caregiver
    }

    func uploadRoomScan(roomID: UUID, normalizedJSON: Data, usdz: Data?) async throws -> ArtifactUploadResponse {
        guard let homeID else { throw OneAPIError.missingSession }
        guard JSONSerialization.isValidJSONObject(try JSONSerialization.jsonObject(with: normalizedJSON)) else { throw OneAPIError.invalidResponse }
        let mapData = try JSONSerialization.jsonObject(with: normalizedJSON)
        let payload: [String: Any] = ["room_id": roomID.uuidString, "coordinate_frame": "roomplan-local", "map_data": mapData]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let response: BackendIDResponse = try await send(path: "/homes/\(homeID.uuidString)/maps", method: "POST", body: body, requiresSession: true)
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

    private func send<T: Decodable>(path: String, method: String, body: Data?, requiresSession: Bool) async throws -> T {
        if requiresSession && (accessToken == nil || homeID == nil) { throw OneAPIError.missingSession }
        var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
private struct BackendMeResponse: Decodable { let actor: BackendActor }
private struct BackendActor: Decodable { let role: String }
private struct BackendIDResponse: Decodable { let id: String }
private struct BackendLiveKitResponse: Decodable { let url: String; let token: String; let expiresIn: Int }
private struct BackendExportResponse: Decodable { let homeID: String }
private struct BackendDeletionResponse: Decodable { let requestID: String; let status: String }

private extension JSONEncoder {
    static var one: JSONEncoder { let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; return encoder }
}

private extension JSONDecoder {
    static var one: JSONDecoder { let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder }
}

protocol LiveKitViewingSession: Sendable {
    func joinSubscribeOnly(using token: LiveKitTokenResponse) async throws
    func leave() async
}

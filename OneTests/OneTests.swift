import XCTest
import Foundation
@testable import One

@MainActor
final class OneTests: XCTestCase {
    func testDemoDataHasUncertaintyAndConsent() {
        let store = AppStore.demo
        XCTAssertFalse(store.scan.objects.isEmpty)
        XCTAssertTrue(store.scan.objects.allSatisfy { $0.dimensions.x > 0 })
        XCTAssertEqual(store.consents.count, 3)
    }

    func testConfidenceIsCodable() throws {
        let data = try JSONEncoder().encode(ObservationConfidence.medium)
        XCTAssertEqual(try JSONDecoder().decode(ObservationConfidence.self, from: data), .medium)
    }

    func testDemoCareCircleUsesLeastPrivilegeAndMedicationStatuses() {
        let store = AppStore.demo
        XCTAssertGreaterThanOrEqual(store.caregivers.count, 3)
        XCTAssertTrue(store.caregivers.contains { $0.role == .viewer && $0.permissions == ["View today"] })
        XCTAssertTrue(store.medicationDoses.contains { $0.status == .needsConfirmation })
        let doseID = try! XCTUnwrap(store.medicationDoses.first?.id)
        store.updateMedicationDose(doseID, status: .acknowledged)
        XCTAssertEqual(store.medicationDoses.first(where: { $0.id == doseID })?.status, .acknowledged)
    }

    func testRuntimeConfigurationDefaultsToLocalAPI() {
        let configuration = RuntimeConfiguration(info: [:])
        XCTAssertEqual(configuration.apiBaseURL.absoluteString, "http://127.0.0.1:8000/api/v1")
        XCTAssertTrue(configuration.isDemoMode)

        let local = RuntimeConfiguration(info: ["ONE_API_BASE_URL": RuntimeConfiguration.localSimulatorURL.absoluteString])
        XCTAssertFalse(local.isDemoMode)

        let tailscale = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example.ts.net/api/v1"])
        XCTAssertEqual(tailscale.apiBaseURL.host, "one-api.example.ts.net")
        XCTAssertFalse(tailscale.isDemoMode)
    }

    func testSessionCodableAndLogoutClearsState() async throws {
        let session = AuthSession(accessToken: "token", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date(timeIntervalSince1970: 1_000))
        let decoded = try JSONDecoder().decode(AuthSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded, session)
        let store = AppStore.demo
        store.session = session
        await store.logout()
        XCTAssertNil(store.session)
    }

    func testMockPairingLoginCreatesAuthenticatedSession() async {
        let store = AppStore.demo
        await store.login(pairingCode: "DEMO")
        XCTAssertEqual(store.session?.accessToken, "demo")
        XCTAssertEqual(store.role, .caregiver)
        XCTAssertNil(store.authError)
    }

    func testMockOnboardingEntryPointsReturnSessionData() async throws {
        let client = MockOneAPIClient()
        let account = try await client.bootstrapAccount(BootstrapAccountRequest(displayName: "Test", email: nil, homeName: "Home", role: .caregiver), bootstrapSecret: nil)
        XCTAssertEqual(account.role, "caregiver")
        let joined = try await client.acceptFamilyInvite(FamilyInviteAcceptRequest(code: "123456", displayName: "Test", email: nil))
        XCTAssertEqual(joined.role, .caregiver)
    }

    func testDemoModeSkipsPostAuthOnboarding() {
        XCTAssertFalse(AppStore.demo.requiresOnboarding)
    }

    func testConsentRequestUsesBackendPurposeNames() async throws {
        let client = MockOneAPIClient()
        try await client.recordConsent(homeID: UUID(), request: ConsentRequest(purpose: "family_mode", policyVersion: "2026-09", granted: false))
    }

    func testDemoFamilyMemberCanBeEditedAndRemovedLocally() async throws {
        let store = AppStore.demo
        let member = try XCTUnwrap(store.caregivers.first(where: { !$0.isCurrentUser && $0.role == .supporter }))

        let didUpdate = await store.updateFamilyMember(member.id, accessRole: .viewer)
        XCTAssertTrue(didUpdate)
        XCTAssertEqual(store.caregivers.first(where: { $0.id == member.id })?.role, .viewer)
        XCTAssertEqual(store.caregivers.first(where: { $0.id == member.id })?.permissions, ["View today"])

        let didRemove = await store.removeFamilyMember(member.id)
        XCTAssertTrue(didRemove)
        XCTAssertNil(store.caregivers.first(where: { $0.id == member.id }))
        XCTAssertNil(store.careRecipients.first(where: { $0.id == member.id }))
    }

    func testDemoFamilyMemberMutationsProtectSelfAndOwner() async throws {
        let store = AppStore.demo
        let owner = try XCTUnwrap(store.caregivers.first(where: { $0.role == .owner }))
        let before = store.caregivers

        let removedOwner = await store.removeFamilyMember(owner.id)
        XCTAssertFalse(removedOwner)
        XCTAssertEqual(store.authError, OneAPIError.cannotChangeOwnAccess.localizedDescription)
        XCTAssertEqual(store.caregivers, before)

        let otherOwner = CaregiverAccount(id: UUID(), name: "Other owner", relationship: "Owner", role: .owner, permissions: ["Manage people"], isCurrentUser: false)
        store.caregivers.append(otherOwner)
        let updatedOwner = await store.updateFamilyMember(otherOwner.id, accessRole: .viewer)
        XCTAssertFalse(updatedOwner)
        XCTAssertEqual(store.authError, OneAPIError.cannotChangeOwnerAccess.localizedDescription)
        XCTAssertTrue(store.caregivers.contains(otherOwner))

        let member = try XCTUnwrap(store.caregivers.first(where: { !$0.isCurrentUser && $0.role != .owner }))
        let grantedOwner = await store.updateFamilyMember(member.id, accessRole: .owner)
        XCTAssertFalse(grantedOwner)
        XCTAssertEqual(store.authError, OneAPIError.cannotChangeOwnerAccess.localizedDescription)
        XCTAssertNotEqual(store.caregivers.first(where: { $0.id == member.id })?.role, .owner)
    }

    func testLiveFamilyMemberUpdateUsesContractPatchAndLeastPrivilegeRole() async throws {
        let homeID = UUID()
        let userID = UUID()
        var capturedRequest: URLRequest?
        OneURLProtocolStub.handler = { request in
            capturedRequest = request
            let body = """
            {"data":{"id":"\(userID.uuidString)","display_name":"Resident","email":null,"role":"resident","created_at":"2026-09-12T10:00:00Z","representation_status":"not_recorded","synthetic_demo":true},"invalidated_sessions":1}
            """.data(using: .utf8)!
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let session = URLSession(configuration: .oneTest)
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: session)
        let result = try await client.updateFamilyMember(homeID: homeID, userID: userID, request: FamilyMemberUpdateRequest(role: .resident))

        XCTAssertEqual(capturedRequest?.httpMethod, "PATCH")
        XCTAssertEqual(capturedRequest?.url?.path, "/api/v1/homes/\(homeID.uuidString)/family/members/\(userID.uuidString)")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        let requestBody = try XCTUnwrap(capturedRequest.flatMap(requestBody))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
        XCTAssertEqual(payload["role"], "resident")
        XCTAssertEqual(result.member.id, userID)
        XCTAssertEqual(result.member.role, .viewer)
        XCTAssertEqual(result.invalidatedSessions, 1)
        XCTAssertNil(CaregiverAccessRole.supporter.backendRole)
    }

    func testLiveFamilyMemberRemovalUsesContractDelete() async throws {
        let homeID = UUID()
        let userID = UUID()
        var capturedRequest: URLRequest?
        OneURLProtocolStub.handler = { request in
            capturedRequest = request
            let body = """
            {"data":{"id":"\(userID.uuidString)","display_name":"Caregiver","email":"caregiver@example.invalid","role":"caregiver","created_at":"2026-09-12T10:00:00Z","representation_status":"not_recorded","synthetic_demo":true},"invalidated_sessions":2}
            """.data(using: .utf8)!
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))
        let result = try await client.removeFamilyMember(homeID: homeID, userID: userID)

        XCTAssertEqual(capturedRequest?.httpMethod, "DELETE")
        XCTAssertEqual(capturedRequest?.url?.path, "/api/v1/homes/\(homeID.uuidString)/family/members/\(userID.uuidString)")
        XCTAssertEqual(result.member.role, .primaryCaregiver)
        XCTAssertEqual(result.invalidatedSessions, 2)
    }
}

private final class OneURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw OneAPIError.invalidResponse }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

private extension URLSessionConfiguration {
    static var oneTest: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OneURLProtocolStub.self]
        return configuration
    }
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(buffer, count: count)
    }
    return data.isEmpty ? nil : data
}

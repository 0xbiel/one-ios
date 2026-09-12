import XCTest
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
}

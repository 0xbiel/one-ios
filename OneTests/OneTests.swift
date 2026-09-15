import XCTest
import Foundation
import simd
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

    func testDemoMedicationSubjectSelectionFiltersReminders() throws {
        let store = AppStore.demo
        let first = try XCTUnwrap(store.careRecipients.first)
        let second = try XCTUnwrap(store.careRecipients.dropFirst().first)

        XCTAssertTrue(store.medicationDosesForSelectedSubject.allSatisfy { $0.careRecipientID == first.id })

        store.selectedSubjectID = second.id

        XCTAssertEqual(store.medicationDosesForSelectedSubject.map(\.medicationName), ["Evening reminder"])
    }

    func testDemoMedicationDateSelectionStartsNewDayAsPending() async throws {
        let store = AppStore.demo
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
        let morningID = try XCTUnwrap(store.medicationPlans.first?.id)

        XCTAssertEqual(store.medicationDoses.first(where: { $0.planID == morningID })?.status, .scheduled)
        store.selectedMedicationDate = tomorrow
        await store.refreshMedicationReminders()

        let tomorrowDoses = store.medicationDosesForSelectedSubject
        XCTAssertFalse(tomorrowDoses.isEmpty)
        XCTAssertTrue(tomorrowDoses.allSatisfy { $0.status == .scheduled })
        XCTAssertTrue(tomorrowDoses.allSatisfy { calendar.isDate($0.scheduledAt, inSameDayAs: tomorrow) })

        let tomorrowDose = try XCTUnwrap(tomorrowDoses.first)
        let markedDone = await store.markMedicationDose(tomorrowDose, status: .acknowledged)
        XCTAssertTrue(markedDone)
        XCTAssertEqual(store.medicationDoses.first(where: { $0.id == tomorrowDose.id })?.status, .acknowledged)
    }

    func testUpdatingSelectedCareRecipientKeepsMedicationSubjectNameInSync() async throws {
        let store = AppStore.demo
        let recipient = try XCTUnwrap(store.careRecipients.first)

        let updated = await store.updateCareRecipient(recipient, name: "Biel Oliver Mas", relationship: "Family", roomLabel: "Room 1")

        XCTAssertTrue(updated)
        XCTAssertEqual(store.selectedSubjectName, "Biel Oliver Mas")
    }

    func testDemoMedicationPlanEditArchiveAndDoneActionsPersist() async throws {
        let store = AppStore.demo
        let plan = try XCTUnwrap(store.medicationPlans.first)
        let dose = try XCTUnwrap(store.medicationDoses.first(where: { $0.planID == plan.id }))

        let updated = await store.updateMedicationPlan(
            plan,
            name: "Updated reminder",
            dose: "2 tablets",
            instructions: "After breakfast",
            schedule: "Daily @ 09:00",
            active: true,
            assignedCaregiverID: nil
        )

        XCTAssertTrue(updated)
        XCTAssertEqual(store.medicationPlans.first(where: { $0.id == plan.id })?.name, "Updated reminder")
        XCTAssertEqual(store.medicationDoses.first(where: { $0.id == dose.id })?.medicationName, "Updated reminder")

        let markedDone = await store.markMedicationDose(dose, status: .acknowledged)
        XCTAssertTrue(markedDone)
        XCTAssertEqual(store.medicationDoses.first(where: { $0.id == dose.id })?.status, .acknowledged)
        XCTAssertNotNil(store.medicationDoses.first(where: { $0.id == dose.id })?.markedByName)
        XCTAssertNotNil(store.medicationDoses.first(where: { $0.id == dose.id })?.markedAt)

        let archived = await store.archiveMedicationPlan(plan)
        XCTAssertTrue(archived)
        XCTAssertFalse(store.medicationPlans.contains(where: { $0.id == plan.id }))
        XCTAssertFalse(store.medicationDoses.contains(where: { $0.planID == plan.id }))
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

    func testKeychainSessionStoreOverwritesExistingSessionValue() throws {
        let store = KeychainSessionStore()
        let key = "one.tests.session.\(UUID().uuidString)"
        defer { try? store.delete(key) }

        try store.save(Data("first".utf8), for: key)
        try store.save(Data("second".utf8), for: key)

        XCTAssertEqual(try store.load(key), Data("second".utf8))
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

    func testAuthClientDecodesSnakeCaseIdentityFields() async throws {
        let homeID = UUID()
        let userID = UUID()
        let verificationID = UUID()
        OneURLProtocolStub.handler = { request in
            let body: Data
            switch request.url?.path {
            case "/api/v1/auth/email/request":
                body = Data("""
                {"verification_id":"\(verificationID.uuidString)","expires_in_seconds":600,"delivery":"development_outbox","dev_code":"482701","email":"caregiver@example.com","purpose":"login","home_id":"\(homeID.uuidString)","user_id":"\(userID.uuidString)","role":"caregiver"}
                """.utf8)
            case "/api/v1/auth/email/verify":
                body = Data("""
                {"access_token":"email-token","token_type":"bearer","expires_in":3600,"home_id":"\(homeID.uuidString)","user_id":"\(userID.uuidString)","role":"caregiver"}
                """.utf8)
            case "/api/v1/pairing/complete":
                body = Data("""
                {"access_token":"pairing-token","token_type":"bearer","expires_in":3600,"home_id":"\(homeID.uuidString)","user_id":"\(userID.uuidString)"}
                """.utf8)
            case "/api/v1/me":
                body = Data("""
                {"actor":{"role":"admin"}}
                """.utf8)
            default:
                throw OneAPIError.invalidResponse
            }
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, session: URLSession(configuration: .oneTest))
        let challenge = try await client.requestEmailCode(EmailAuthRequest(email: "caregiver@example.com", purpose: "login", displayName: nil, homeName: "ONE Home", role: .caregiver))
        XCTAssertEqual(challenge.verificationID, verificationID)
        XCTAssertEqual(challenge.homeID, homeID)
        XCTAssertEqual(challenge.userID, userID)
        XCTAssertEqual(challenge.devCode, "482701")

        let emailSession = try await client.verifyEmailCode(EmailAuthVerifyRequest(email: "caregiver@example.com", code: "482701"))
        XCTAssertEqual(emailSession.accessToken, "email-token")
        XCTAssertEqual(emailSession.homeID, homeID)
        XCTAssertEqual(emailSession.userID, userID)
        XCTAssertEqual(emailSession.role, .caregiver)

        let pairingSession = try await client.completePairing(code: "123456")
        XCTAssertEqual(pairingSession.accessToken, "pairing-token")
        XCTAssertEqual(pairingSession.homeID, homeID)
        XCTAssertEqual(pairingSession.userID, userID)
        XCTAssertEqual(pairingSession.role, .caregiver)
    }

    func testCameraPairingClientDecodesDocumentedSnakeCaseContract() async throws {
        let homeID = UUID()
        let pairingID = UUID()
        var requests: [URLRequest] = []

        OneURLProtocolStub.handler = { request in
            requests.append(request)
            let body: Data
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/homes/\(homeID.uuidString.lowercased())/pairing/start"):
                body = Data("""
                {"pairing_id":"\(pairingID.uuidString)","pairing_code":"482701","code":"482701","expires_in_seconds":600,"home_id":"\(homeID.uuidString)","user_id":"\(pairingID.uuidString)"}
                """.utf8)
            case ("GET", "/api/v1/homes/\(homeID.uuidString.lowercased())/pairing/\(pairingID.uuidString.lowercased())/status"):
                body = Data("""
                {"pairing_id":"\(pairingID.uuidString)","home_id":"\(homeID.uuidString)","status":"pending","expires_at":"2026-09-14T12:00:00Z","connected_at":null,"device":{"id":"\(pairingID.uuidString)","label":"Living room camera","role":"publisher"}}
                """.utf8)
            default:
                throw OneAPIError.invalidResponse
            }
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "caregiver-token", homeID: homeID, session: URLSession(configuration: .oneTest))

        let challenge = try await client.startCameraPairing(homeID: homeID, label: "Living room camera")
        XCTAssertEqual(challenge.pairingID, pairingID)
        XCTAssertEqual(challenge.pairingCode, "482701")
        XCTAssertEqual(challenge.expiresInSeconds, 600)

        let status = try await client.cameraPairingStatus(homeID: homeID, pairingID: pairingID)
        XCTAssertEqual(status.pairingID, pairingID)
        XCTAssertEqual(status.status, "pending")
        XCTAssertEqual(status.device.id, pairingID)
        XCTAssertEqual(status.device.label, "Living room camera")
        XCTAssertEqual(status.device.role, "publisher")

        XCTAssertEqual(requests.count, 2)
        let startBody = try XCTUnwrap(requestBody(requests[0]))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: startBody) as? [String: Any])
        XCTAssertEqual(payload["label"] as? String, "Living room camera")
        XCTAssertEqual(payload["expires_in_seconds"] as? Int, 600)
    }

    func testCameraManagementClientListsRoomsUpdatesAndDeletesWithExactContract() async throws {
        let homeID = UUID()
        let roomID = UUID()
        let cameraID = UUID()
        var requests: [URLRequest] = []

        OneURLProtocolStub.handler = { request in
            requests.append(request)
            let body: Data
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/homes/\(homeID.uuidString.lowercased())/rooms"):
                body = Data("""
                {"data":[{"id":"\(roomID.uuidString)","home_id":"\(homeID.uuidString)","name":"Kitchen","created_at":"2026-09-15T08:00:00Z"}]}
                """.utf8)
            case ("PATCH", "/api/v1/homes/\(homeID.uuidString.lowercased())/cameras/\(cameraID.uuidString.lowercased())"):
                body = Data("""
                {"id":"\(cameraID.uuidString)","name":"Kitchen camera","room_id":"\(roomID.uuidString)","resolution_width":null,"resolution_height":null,"metadata":{},"calibrations_invalidated":true}
                """.utf8)
            case ("DELETE", "/api/v1/homes/\(homeID.uuidString.lowercased())/cameras/\(cameraID.uuidString.lowercased())"):
                body = Data("""
                {"id":"\(cameraID.uuidString)","status":"deleted","revoked_sessions":1}
                """.utf8)
            default:
                throw OneAPIError.invalidResponse
            }
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "caregiver-token", homeID: homeID, session: URLSession(configuration: .oneTest))

        let rooms = try await client.cameraRooms(homeID: homeID)
        XCTAssertEqual(rooms, [CameraRoom(id: roomID, name: "Kitchen")])

        try await client.updateCamera(
            homeID: homeID,
            cameraID: cameraID,
            request: CameraUpdateRequest(name: "Kitchen camera", roomID: roomID)
        )
        try await client.deleteCamera(homeID: homeID, cameraID: cameraID)

        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "PATCH", "DELETE"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer caregiver-token" })

        let updateBody = try XCTUnwrap(requestBody(requests[1]))
        let updatePayload = try XCTUnwrap(JSONSerialization.jsonObject(with: updateBody) as? [String: Any])
        XCTAssertEqual(updatePayload["name"] as? String, "Kitchen camera")
        XCTAssertEqual(updatePayload["room_id"] as? String, roomID.uuidString)
    }

    func testCareSpaceClientListsCreatesAndActivatesWithExactContract() async throws {
        let currentHomeID = UUID()
        let residenceID = UUID()
        let userID = UUID()
        var requests: [URLRequest] = []
        OneURLProtocolStub.handler = { request in
            requests.append(request)
            let body: Data
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/account/homes"):
                body = Data("""
                {"data":[
                  {"id":"\(currentHomeID.uuidString)","name":"Family Home","residentName":"María","recipientNames":["María","José"],"recipientCount":2,"careSetting":"home","supportFocus":"general","role":"admin","active":true},
                  {"id":"\(residenceID.uuidString)","name":"La Marina","residentName":"Resident","recipientNames":[],"recipientCount":0,"careSetting":"residence","supportFocus":"mci","role":"resident","active":false}
                ]}
                """.utf8)
            case ("POST", "/api/v1/account/homes"):
                body = Data("""
                {"access_token":"created-token","token_type":"bearer","expires_in":3600,"home_id":"\(residenceID.uuidString)","user_id":"\(userID.uuidString)","role":"admin"}
                """.utf8)
            case ("POST", "/api/v1/account/homes/\(residenceID.uuidString.lowercased())/activate"):
                body = Data("""
                {"access_token":"switched-token","token_type":"bearer","expires_in":3600,"home_id":"\(residenceID.uuidString)","user_id":"\(userID.uuidString)","role":"resident"}
                """.utf8)
            default:
                throw OneAPIError.invalidResponse
            }
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "old-token", homeID: currentHomeID, session: URLSession(configuration: .oneTest))

        let spaces = try await client.careSpaces()
        XCTAssertEqual(spaces.count, 2)
        XCTAssertEqual(spaces[0].role, .admin)
        XCTAssertEqual(spaces[0].peopleSummary, "María & José")
        XCTAssertEqual(spaces[1].careSetting, .residence)
        XCTAssertEqual(spaces[1].supportFocus, .mci)
        XCTAssertEqual(spaces[1].peopleSummary, "No people added yet")

        let created = try await client.createCareSpace(CareSpaceCreateRequest(name: "La Marina", careSetting: .residence, supportFocus: .mci))
        XCTAssertEqual(created.homeID, residenceID)
        XCTAssertEqual(created.role, .caregiver)
        let createBody = try XCTUnwrap(requestBody(requests[1]))
        let createPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: createBody) as? [String: String])
        XCTAssertEqual(createPayload["name"], "La Marina")
        XCTAssertEqual(createPayload["care_setting"], "residence")
        XCTAssertEqual(createPayload["support_focus"], "mci")

        let activated = try await client.activateCareSpace(id: residenceID)
        XCTAssertEqual(activated.role, .resident)
        XCTAssertEqual(requests[2].url?.path, "/api/v1/account/homes/\(residenceID.uuidString.lowercased())/activate")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer old-token")
    }

    func testCareRecipientClientUsesDedicatedCRUDContract() async throws {
        let homeID = UUID()
        let recipientID = UUID()
        var requests: [URLRequest] = []
        OneURLProtocolStub.handler = { request in
            requests.append(request)
            let body: Data
            let status: Int
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/api/v1/homes/\(homeID.uuidString.lowercased())/care-recipients"):
                status = 200
                body = Data("""
                {"data":[{"id":"\(recipientID.uuidString)","display_name":"María","relationship":"Partner","room_label":"Room 12","created_at":"2026-09-14T07:00:00Z"}]}
                """.utf8)
            case ("POST", "/api/v1/homes/\(homeID.uuidString.lowercased())/care-recipients"):
                status = 201
                body = Data("""
                {"data":{"id":"\(recipientID.uuidString)","display_name":"María","relationship":"Partner","room_label":"Room 12","created_at":"2026-09-14T07:00:00Z"}}
                """.utf8)
            case ("PATCH", "/api/v1/homes/\(homeID.uuidString.lowercased())/care-recipients/\(recipientID.uuidString.lowercased())"):
                status = 200
                body = Data("""
                {"data":{"id":"\(recipientID.uuidString)","display_name":"Maria","relationship":null,"room_label":null,"created_at":"2026-09-14T07:00:00Z"}}
                """.utf8)
            case ("DELETE", "/api/v1/homes/\(homeID.uuidString.lowercased())/care-recipients/\(recipientID.uuidString.lowercased())"):
                status = 204
                body = Data()
            default:
                throw OneAPIError.invalidResponse
            }
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))

        let listed = try await client.careRecipients(homeID: homeID)
        XCTAssertEqual(listed.first?.displayName, "María")
        XCTAssertEqual(listed.first?.roomLabel, "Room 12")

        let created = try await client.createCareRecipient(homeID: homeID, request: CareRecipientCreateRequest(displayName: "María", relationship: "Partner", roomLabel: "Room 12"))
        XCTAssertEqual(created.id, recipientID)
        let createPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requestBody(requests[1]))) as? [String: Any])
        XCTAssertEqual(createPayload["display_name"] as? String, "María")
        XCTAssertEqual(createPayload["relationship"] as? String, "Partner")
        XCTAssertEqual(createPayload["room_label"] as? String, "Room 12")

        let updated = try await client.updateCareRecipient(homeID: homeID, recipientID: recipientID, request: CareRecipientUpdateRequest(displayName: "Maria", relationship: nil, roomLabel: nil))
        XCTAssertEqual(updated.displayName, "Maria")
        XCTAssertNil(updated.relationship)
        XCTAssertNil(updated.roomLabel)
        let updatePayload = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(requestBody(requests[2]))) as? [String: Any])
        XCTAssertEqual(updatePayload["display_name"] as? String, "Maria")
        XCTAssertTrue(updatePayload["relationship"] is NSNull)
        XCTAssertTrue(updatePayload["room_label"] is NSNull)

        try await client.deleteCareRecipient(homeID: homeID, recipientID: recipientID)
        XCTAssertEqual(requests.map(\.httpMethod), ["GET", "POST", "PATCH", "DELETE"])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer token" })
    }

    func testDemoCareRecipientsMutateWithoutChangingHouseholdAccess() async throws {
        let store = AppStore.demo
        let accessBefore = store.caregivers
        let initialCount = store.careRecipients.count

        let created = await store.createCareRecipient(name: "  Elena  ", relationship: "Grandmother", roomLabel: "Room 4")
        XCTAssertTrue(created)
        XCTAssertEqual(store.careRecipients.count, initialCount + 1)
        XCTAssertEqual(store.caregivers, accessBefore)
        XCTAssertEqual(store.activeCareSpace?.peopleSummary, "3 people")

        let recipient = try XCTUnwrap(store.careRecipients.last)
        let updated = await store.updateCareRecipient(recipient, name: "Elena Soler", relationship: nil, roomLabel: nil)
        XCTAssertTrue(updated)
        XCTAssertEqual(store.careRecipients.last?.displayName, "Elena Soler")
        XCTAssertNil(store.careRecipients.last?.relationship)
        XCTAssertNil(store.careRecipients.last?.roomLabel)

        let removed = await store.removeCareRecipient(recipient.id)
        XCTAssertTrue(removed)
        XCTAssertEqual(store.careRecipients.count, initialCount)
        XCTAssertEqual(store.caregivers, accessBefore)
        XCTAssertEqual(store.activeCareSpace?.peopleSummary, "María & José")
    }

    func testCareSpaceSwitchPersistsSessionClearsScopedStateAndRestoresOnboarding() async throws {
        let first = CareSpaceSummary(id: UUID(), name: "Family Home", residentName: "María", careSetting: .home, supportFocus: .general, role: .admin, active: true)
        let second = CareSpaceSummary(id: UUID(), name: "La Marina", residentName: "Resident", careSetting: .residence, supportFocus: .mci, role: .resident, active: false)
        let userID = UUID()
        let oldSession = AuthSession(accessToken: "old", homeID: first.id, userID: userID, role: .caregiver, expiresAt: Date().addingTimeInterval(3_600))
        let sessionStore = OneTestSessionStore()
        try sessionStore.save(Data("complete".utf8), for: AppStore.onboardingKey(homeID: second.id, userID: userID))
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let event = ObservedEvent(id: UUID(), kind: .movement, timestamp: Date(), location: "Kitchen", confidence: .high, explanation: "Test event", reviewed: false, hasClip: false)
        let client = MockOneAPIClient(mockCareSpaces: [first, second], mockUserID: userID)
        let store = AppStore(events: [event], scan: .empty, consents: AppStore.demo.consents, careSpaces: [first, second], apiClient: client, backendState: .connected, session: oldSession, sessionStore: sessionStore, runtimeConfiguration: configuration)
        store.selectedTab = "family"

        let switched = await store.activateCareSpace(second)

        XCTAssertTrue(switched)
        XCTAssertEqual(store.session?.homeID, second.id)
        XCTAssertEqual(store.role, .resident)
        XCTAssertEqual(store.selectedTab, "overview")
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(store.consents.isEmpty)
        XCTAssertEqual(store.activeCareSpace?.id, second.id)
        XCTAssertFalse(store.requiresOnboarding)
        let persistedData = try XCTUnwrap(sessionStore.load(AppStore.sessionKey))
        XCTAssertEqual(try JSONDecoder().decode(AuthSession.self, from: persistedData).homeID, second.id)
    }

    func testCreatingCareSpaceActivatesItAndRequiresPerHomeOnboarding() async throws {
        let first = CareSpaceSummary(id: UUID(), name: "Family Home", residentName: "María", careSetting: .home, supportFocus: .general, role: .admin, active: true)
        let userID = UUID()
        let oldSession = AuthSession(accessToken: "old", homeID: first.id, userID: userID, role: .caregiver, expiresAt: Date().addingTimeInterval(3_600))
        let sessionStore = OneTestSessionStore()
        try sessionStore.save(Data("complete".utf8), for: AppStore.onboardingKey(homeID: first.id, userID: userID))
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = MockOneAPIClient(mockCareSpaces: [first], mockUserID: userID)
        let store = AppStore(events: [], scan: .empty, consents: [], careSpaces: [first], apiClient: client, backendState: .connected, session: oldSession, sessionStore: sessionStore, runtimeConfiguration: configuration)

        let created = await store.createCareSpace(name: "  Grandparents Residence  ", careSetting: .residence, supportFocus: .mci)

        XCTAssertTrue(created)
        XCTAssertNotEqual(store.session?.homeID, first.id)
        XCTAssertEqual(store.activeCareSpace?.name, "Grandparents Residence")
        XCTAssertEqual(store.activeCareSpace?.careSetting, .residence)
        XCTAssertTrue(store.requiresOnboarding)
        XCTAssertEqual(store.selectedTab, "overview")
    }

    func testFailedCareSpaceSwitchKeepsCurrentSessionAndData() async throws {
        let first = CareSpaceSummary(id: UUID(), name: "Family Home", residentName: "María", careSetting: .home, supportFocus: .general, role: .admin, active: true)
        let second = CareSpaceSummary(id: UUID(), name: "La Marina", residentName: "Resident", careSetting: .residence, supportFocus: .mci, role: .caregiver, active: false)
        let oldSession = AuthSession(accessToken: "old", homeID: first.id, userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3_600))
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let event = ObservedEvent(id: UUID(), kind: .movement, timestamp: Date(), location: "Kitchen", confidence: .high, explanation: "Keep me", reviewed: false, hasClip: false)
        let client = MockOneAPIClient(mockCareSpaces: [first, second], careSpaceError: .server(status: 503, message: "Temporarily unavailable"))
        let store = AppStore(events: [event], scan: .empty, consents: [], careSpaces: [first, second], apiClient: client, backendState: .connected, session: oldSession, sessionStore: OneTestSessionStore(), runtimeConfiguration: configuration)

        let switched = await store.activateCareSpace(second)

        XCTAssertFalse(switched)
        XCTAssertEqual(store.session, oldSession)
        XCTAssertEqual(store.events.map(\.id), [event.id])
        XCTAssertEqual(store.activeCareSpace?.id, first.id)
        XCTAssertNotNil(store.careSpaceError)
    }

    func testOnboardingConsentUpdatesLocalAccountStateAfterSaving() async {
        let session = AuthSession(accessToken: "token", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3600))
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let store = AppStore(events: [], scan: .empty, consents: [], apiClient: MockOneAPIClient(), backendState: .connected, session: session, runtimeConfiguration: configuration)

        let saved = await store.recordOnboardingConsent(for: "Family sharing", granted: true)

        XCTAssertTrue(saved)
        XCTAssertEqual(store.onboardingConsents["Family sharing"], true)
        XCTAssertEqual(store.consents.first?.purpose, "Family sharing")
        XCTAssertEqual(store.consents.first?.enabled, true)
    }

    func testDemoModeSkipsPostAuthOnboarding() {
        XCTAssertFalse(AppStore.demo.requiresOnboarding)
    }

    func testCompletingOnboardingImmediatelyUnlocksTheApp() throws {
        let session = AuthSession(accessToken: "token", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3_600))
        let sessionStore = OneTestSessionStore()
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let store = AppStore(events: [], scan: .empty, consents: [], apiClient: MockOneAPIClient(), backendState: .connected, session: session, sessionStore: sessionStore, runtimeConfiguration: configuration)

        XCTAssertTrue(store.requiresOnboarding)
        XCTAssertTrue(store.completeOnboarding())
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertFalse(store.requiresOnboarding)
        XCTAssertNotNil(try sessionStore.load(AppStore.onboardingKey(homeID: session.homeID, userID: session.userID)))
    }

    func testConsentRequestUsesBackendPurposeNames() async throws {
        let client = MockOneAPIClient()
        try await client.recordConsent(homeID: UUID(), request: ConsentRequest(purpose: "family_mode", policyVersion: "2026-09", granted: false))
    }

    func testLiveConsentRouteUsesLowercaseUUIDsExpectedByBackend() async throws {
        let homeID = UUID()
        let subjectUserID = UUID()
        let careRecipientID = UUID()
        var capturedRequest: URLRequest?
        OneURLProtocolStub.handler = { request in
            capturedRequest = request
            let response = try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Data("{}".utf8))
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))
        try await client.recordConsent(
            homeID: homeID,
            request: ConsentRequest(
                purpose: "medication_management",
                policyVersion: "2026-09",
                granted: true,
                careRecipientID: careRecipientID
            )
        )

        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(request.url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/consents")
        XCTAssertFalse(request.url?.path.contains(homeID.uuidString) ?? true)
        let body = try XCTUnwrap(requestBody(request))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["care_recipient_id"] as? String, careRecipientID.uuidString.lowercased())

        let representedSubjectBody = try JSONEncoder.one.encode(
            ConsentRequest(purpose: "family_mode", policyVersion: "2026-09", granted: true, subjectUserID: subjectUserID)
        )
        let representedSubjectPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: representedSubjectBody) as? [String: Any])
        XCTAssertEqual(representedSubjectPayload["subject_user_id"] as? String, subjectUserID.uuidString.lowercased())
    }

    func testLiveConsentListAggregatesLatestGlobalAndCareRecipientChoices() async throws {
        let homeID = UUID()
        let userID = UUID()
        let recipientID = UUID()
        let oldConsentID = UUID()
        let latestConsentID = UUID()
        var capturedRequest: URLRequest?
        OneURLProtocolStub.handler = { request in
            capturedRequest = request
            let body = Data("""
            {"data":[
              {"id":"\(oldConsentID.uuidString)","home_id":"\(homeID.uuidString)","subject_user_id":"\(userID.uuidString)","purpose":"video_capture","policy_version":"2026-09","granted_at":"2026-09-14T08:00:00Z","revoked_at":null,"care_recipient_id":null},
              {"id":"\(latestConsentID.uuidString)","home_id":"\(homeID.uuidString)","subject_user_id":"\(userID.uuidString)","purpose":"video_capture","policy_version":"2026-09","granted_at":"2026-09-14T09:00:00Z","revoked_at":"2026-09-14T09:01:00Z","care_recipient_id":null},
              {"id":"\(UUID().uuidString)","home_id":"\(homeID.uuidString)","subject_user_id":"\(userID.uuidString)","purpose":"medication_management","policy_version":"2026-09","granted_at":"2026-09-14T10:00:00Z","revoked_at":null,"care_recipient_id":"\(recipientID.uuidString)"}
            ]}
            """.utf8)
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))
        let records = try await client.consents(homeID: homeID)

        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/consents")
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first(where: { $0.purpose == "video_capture" })?.id, latestConsentID)
        XCTAssertEqual(records.first(where: { $0.purpose == "video_capture" })?.enabled, false)
        XCTAssertEqual(records.first(where: { $0.purpose == "video_capture" })?.subjectUserID, userID)
        XCTAssertEqual(records.first(where: { $0.purpose == "medication_management" })?.careRecipientID, recipientID)
    }

    func testLiveMedicationReminderQueryUsesPickerCalendarDay() async throws {
        let homeID = UUID()
        var capturedURL: URL?
        OneURLProtocolStub.handler = { request in
            capturedURL = request.url
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), Data("{\"data\":[]}".utf8))
        }
        defer { OneURLProtocolStub.handler = nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let selectedDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))
        _ = try await client.medicationReminders(homeID: homeID, careRecipientID: nil, day: selectedDate)

        let day = URLComponents(url: try XCTUnwrap(capturedURL), resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "day" })?.value
        XCTAssertEqual(day, "2026-09-15")
    }

    func testPrivacyConsentChoicesRemainVisibleWhenLiveHomeHasNoSavedRows() {
        let session = AuthSession(accessToken: "token", homeID: UUID(), userID: UUID(), role: .caregiver, expiresAt: Date().addingTimeInterval(3_600))
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let legacyGlobalMedicationConsent = ConsentRecord(id: UUID(), purpose: "medication_management", enabled: true, policyVersion: "2026-09", updatedAt: Date(), subjectUserID: session.userID)
        let store = AppStore(events: [], scan: .empty, consents: [legacyGlobalMedicationConsent], apiClient: MockOneAPIClient(), backendState: .connected, session: session, runtimeConfiguration: configuration)

        XCTAssertEqual(store.privacyConsents.map(\.purpose), ["Room and camera data", "Daily check-in support", "Family sharing"])
        XCTAssertTrue(store.privacyConsents.allSatisfy { !$0.enabled })
    }

    func testMedicationReminderConsentIsScopedToCareRecipient() async throws {
        let store = AppStore.demo
        let person = try XCTUnwrap(store.careRecipients.first(where: { $0.medicationRemindersEnabled == false }))

        XCTAssertFalse(store.privacyConsents.contains(where: { $0.purpose == "Medication reminders" }))
        let enabled = await store.setMedicationRemindersEnabled(for: person, enabled: true)
        XCTAssertTrue(enabled)
        XCTAssertEqual(store.careRecipients.first(where: { $0.id == person.id })?.medicationRemindersEnabled, true)
        XCTAssertFalse(store.privacyConsents.contains(where: { $0.purpose == "Medication reminders" }))
    }

    func testDemoFamilyMemberCanBeEditedAndRemovedLocally() async throws {
        let store = AppStore.demo
        let member = try XCTUnwrap(store.caregivers.first(where: { !$0.isCurrentUser && $0.role == .supporter }))
        let recipientsBefore = store.careRecipients

        let didUpdate = await store.updateFamilyMember(member.id, accessRole: .viewer)
        XCTAssertTrue(didUpdate)
        XCTAssertEqual(store.caregivers.first(where: { $0.id == member.id })?.role, .viewer)
        XCTAssertEqual(store.caregivers.first(where: { $0.id == member.id })?.permissions, ["View today"])

        let didRemove = await store.removeFamilyMember(member.id)
        XCTAssertTrue(didRemove)
        XCTAssertNil(store.caregivers.first(where: { $0.id == member.id }))
        XCTAssertEqual(store.careRecipients, recipientsBefore)
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
        XCTAssertEqual(capturedRequest?.url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/family/members/\(userID.uuidString.lowercased())")
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
        XCTAssertEqual(capturedRequest?.url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/family/members/\(userID.uuidString.lowercased())")
        XCTAssertEqual(result.member.role, .primaryCaregiver)
        XCTAssertEqual(result.invalidatedSessions, 2)
    }

    func testRoomPlanNormalizerCoversEveryElementTypeAndPreservesMetricTransform() throws {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(1.25, 2.5, -0.75, 1)
        func element(_ category: String) -> RoomPlanElementInput {
            RoomPlanElementInput(category: category, center: SIMD3(1.25, 2.5, -0.75), dimensions: SIMD3(2, 2.5, 3), transform: transform, vertices: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)], attributes: category == "door" ? ["is_open=true"] : [])
        }

        let scan = try RoomPlanNormalizer.normalize(RoomPlanCaptureFixture(
            roomID: UUID(), capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            walls: [element("wall")], floors: [element("floor")], openings: [element("opening")],
            doors: [element("door")], windows: [element("window")], objects: [element("chair")],
            sections: [RoomPlanSectionInput(label: "livingRoom", center: SIMD3(0, 0, 0), story: 0)]
        ))

        XCTAssertEqual(scan.schemaVersion, "roomplan-normalized.v1")
        XCTAssertEqual(scan.producer, "native-ios")
        XCTAssertEqual(scan.units, "m")
        XCTAssertEqual(scan.upAxis, "Y")
        XCTAssertEqual(scan.coordinateFrame, "roomplan-local")
        XCTAssertEqual(scan.geometryType, "3d")
        XCTAssertEqual(scan.walls.count, 1)
        XCTAssertEqual(scan.floors.count, 1)
        XCTAssertEqual(scan.openings.count, 1)
        XCTAssertEqual(scan.doors.count, 1)
        XCTAssertEqual(scan.windows.count, 1)
        XCTAssertEqual(scan.objects.count, 1)
        XCTAssertEqual(scan.sections.count, 1)
        XCTAssertEqual(scan.walls[0].center, RoomPlanPoint3D(x: 1.25, y: 2.5, z: -0.75))
        XCTAssertEqual(scan.walls[0].transform[0][3], 1.25)
        XCTAssertEqual(scan.walls[0].dimensions, RoomPlanDimensions3D(x: 2, y: 2.5, z: 3))

        let encoded = try JSONEncoder.one.encode(scan)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(json["schema_version"] as? String, "roomplan-normalized.v1")
        XCTAssertEqual(json["geometry_type"] as? String, "3d")
    }

    func testRoomPlanNormalizerRejectsEmptyNonFiniteAndNonPositiveGeometry() {
        XCTAssertThrowsError(try RoomPlanNormalizer.normalize(RoomPlanCaptureFixture())) { error in
            XCTAssertEqual(error as? RoomPlanNormalizationError, .emptyCapture)
        }

        XCTAssertThrowsError(try RoomPlanNormalizer.normalize(RoomPlanCaptureFixture(objects: [RoomPlanElementInput(category: "chair", center: SIMD3(Float.nan, 0, 0), dimensions: SIMD3(repeating: 1))]))) { error in
            XCTAssertEqual(error as? RoomPlanNormalizationError, .nonFiniteGeometry)
        }

        XCTAssertThrowsError(try RoomPlanNormalizer.normalize(RoomPlanCaptureFixture(walls: [RoomPlanElementInput(category: "wall", center: SIMD3(repeating: 0), dimensions: SIMD3(1, 0, 1))]))) { error in
            XCTAssertEqual(error as? RoomPlanNormalizationError, .invalidDimensions)
        }

        var invalidTransform = matrix_identity_float4x4
        invalidTransform.columns.0.x = .infinity
        XCTAssertThrowsError(try RoomPlanNormalizer.normalize(RoomPlanCaptureFixture(floors: [RoomPlanElementInput(category: "floor", center: SIMD3(repeating: 0), dimensions: SIMD3(repeating: 1), transform: invalidTransform)]))) { error in
            XCTAssertEqual(error as? RoomPlanNormalizationError, .nonFiniteGeometry)
        }
    }

    func testRoomPlanNativeDimensionsGivePlanarSurfacesMinimalThickness() throws {
        let sanitized = try RoomPlanNormalizer.sanitizedNativeDimensions(SIMD3<Float>(2.4, 0, -0.0005))
        XCTAssertEqual(sanitized.x, 2.4)
        XCTAssertEqual(sanitized.y, 0.001)
        XCTAssertEqual(sanitized.z, 0.001)

        XCTAssertThrowsError(try RoomPlanNormalizer.sanitizedNativeDimensions(SIMD3<Float>(1, -0.01, 1))) { error in
            XCTAssertEqual(error as? RoomPlanNormalizationError, .invalidDimensions)
        }
        XCTAssertThrowsError(try RoomPlanNormalizer.sanitizedNativeDimensions(SIMD3<Float>(1, .nan, 1))) { error in
            XCTAssertEqual(error as? RoomPlanNormalizationError, .nonFiniteGeometry)
        }
    }

    func testRoomPlanMetadataAndCaptureErrorsStayNative() throws {
        let metadata = RoomPlanScanMetadata(provenance: "native-roomplan", deviceModel: "iPhone17,1", lidar: true, roomplanVersion: "17", units: "m", upAxis: "Y", geometryType: "3d")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.one.encode(metadata)) as? [String: Any])
        XCTAssertEqual(json["provenance"] as? String, "native-roomplan")
        XCTAssertEqual(json["lidar"] as? Bool, true)
        XCTAssertEqual(json["units"] as? String, "m")
        XCTAssertEqual(json["up_axis"] as? String, "Y")
        XCTAssertEqual(RoomPlanCaptureError.unsupportedDevice.localizedDescription, "RoomPlan is not supported on this device.")
    }

    func testARVideoRoomScanEncodesExplicitNonLidarProvenance() throws {
        let floor = try ARVideoSurface(
            id: UUID(), kind: "floor", alignment: "horizontal",
            vertices: [SIMD3(-2, 0, -2), SIMD3(2, 0, -2), SIMD3(2, 0, 2), SIMD3(-2, 0, 2)],
            confidence: 0.82
        )
        let wallA = try ARVideoSurface(
            id: UUID(), kind: "wall", alignment: "vertical",
            vertices: [SIMD3(-2, 0, -2), SIMD3(2, 0, -2), SIMD3(2, 2.4, -2), SIMD3(-2, 2.4, -2)],
            confidence: 0.74
        )
        let wallB = try ARVideoSurface(
            id: UUID(), kind: "wall", alignment: "vertical",
            vertices: [SIMD3(2, 0, -2), SIMD3(2, 0, 2), SIMD3(2, 2.4, 2), SIMD3(2, 2.4, -2)],
            confidence: 0.74
        )
        let diagnostics = ARVideoCaptureDiagnostics(frameSampleCount: 8, normalTrackingSamples: 8, planeCount: 3, trackingState: "normal")
        let scan = try ARVideoRoomScan(surfaces: [floor, wallA, wallB], diagnostics: diagnostics, capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.one.encode(scan)) as? [String: Any])

        XCTAssertEqual(json["schema_version"] as? String, "arkit-video-room.v1")
        XCTAssertEqual(json["framework"] as? String, "ARKit")
        XCTAssertEqual(json["coordinate_frame"] as? String, "arkit-world")
        XCTAssertEqual(json["lidar"] as? Bool, false)
        XCTAssertEqual((json["surfaces"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual((json["diagnostics"] as? [String: Any])?["normal_tracking_samples"] as? Int, 8)
    }

    func testARVideoSceneRendersGeneratedUSDZWithoutRoomPlanGeometry() throws {
        let payload: [String: Any] = [
            "sceneId": UUID().uuidString,
            "mapId": UUID().uuidString,
            "version": 1,
            "source": "arkit-video-3d",
            "dimension": "3d",
            "provenance": "arkit-video-3d",
            "approximate": true,
            "metricScaleKnown": true,
            "geometryStatus": "ready",
            "rescanRequired": false,
            "coordinateFrame": "arkit-world",
            "geometry": [
                "coordinate_space": "arkit-world",
                "polygons": [], "walls": [], "surfaces": []
            ],
            "usdz": [
                "available": true,
                "sha256": "abc",
                "bytes": 1024,
                "content_type": "model/vnd.usdz+zip",
                "download_path": "/api/v1/homes/home/maps/map/usdz"
            ]
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(SceneDescriptor.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.source, .arkitVideo3D)
        XCTAssertTrue(decoded.approximate)
        XCTAssertTrue(decoded.isRenderable3D)
        XCTAssertTrue(decoded.hasReadyUSDZ)
        XCTAssertNil(decoded.canonicalGeometry)
    }

    func testRoomPlanSceneRequiresExactValidated3DSource() throws {
        let element = try RoomPlanElement(id: UUID().uuidString, category: "wall", confidence: "high", center: RoomPlanPoint3D(x: 0, y: 1, z: 0), dimensions: RoomPlanDimensions3D(x: 1, y: 2, z: 0.1), transform: [[1, 0, 0, 0], [0, 1, 0, 1], [0, 0, 1, 0], [0, 0, 0, 1]])
        let geometry = try RoomPlanNormalizedScan(roomID: UUID(), capturedAt: Date(), walls: [element], floors: [], openings: [], doors: [], windows: [], objects: [], sections: [])
        let valid = SceneDescriptor(sceneID: UUID(), mapID: UUID(), version: 1, dimension: .threeD, source: .roomplanLidar3D, provenance: "roomplan-lidar-3d", approximate: false, metricScaleKnown: true, geometryStatus: "ready", rescanRequired: false, coordinateFrame: "roomplan-local", geometry: geometry, usdz: nil)
        let generic = SceneDescriptor(sceneID: valid.sceneID, mapID: valid.mapID, version: 1, dimension: .threeD, source: .legacy2D, provenance: "legacy-2d", approximate: true, metricScaleKnown: false, geometryStatus: "ready", rescanRequired: false, coordinateFrame: nil, geometry: geometry, usdz: nil)
        XCTAssertTrue(valid.isRenderable3D)
        XCTAssertFalse(generic.isRenderable3D)
    }

    func testRoomPlanSceneDecodesNativeBackendGeometryAndAttachment() throws {
        let element = try RoomPlanElement(id: UUID().uuidString, category: "floor", confidence: "high", center: RoomPlanPoint3D(x: 0, y: 0, z: 0), dimensions: RoomPlanDimensions3D(x: 2, y: 0.1, z: 2), transform: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
        let geometry = try RoomPlanNormalizedScan(roomID: UUID(), capturedAt: Date(), walls: [], floors: [element], openings: [], doors: [], windows: [], objects: [], sections: [])
        let geometryJSON = try JSONSerialization.jsonObject(with: JSONEncoder.one.encode(geometry))
        let payload: [String: Any] = [
            "sceneId": UUID().uuidString,
            "mapId": UUID().uuidString,
            "version": 4,
            "source": "roomplan-lidar-3d",
            "dimension": "3d",
            "provenance": "roomplan-lidar-3d",
            "approximate": false,
            "metricScaleKnown": true,
            "geometryStatus": "ready",
            "rescanRequired": false,
            "coordinateFrame": "roomplan-local",
            "canonicalGeometry": geometryJSON,
            "geometry": geometryJSON,
            "usdz": [
                "available": true,
                "sha256": "abc",
                "bytes": 4,
                "content_type": "model/vnd.usdz+zip",
                "download_path": "/api/v1/homes/home/maps/map/usdz"
            ]
        ]
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(SceneDescriptor.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertTrue(decoded.isRenderable3D)
        XCTAssertTrue(decoded.hasReadyUSDZ)
        XCTAssertEqual(decoded.geometry?.floors.first?.dimensions.x, 2)
        XCTAssertEqual(decoded.usdz?.contentType, "model/vnd.usdz+zip")
    }

    func testRoomPlanClientUsesExactNativeRoutesAndMetadata() async throws {
        let homeID = UUID()
        let mapID = UUID()
        let roomID = UUID()
        let element = try RoomPlanElement(id: UUID().uuidString, category: "floor", confidence: "high", center: RoomPlanPoint3D(x: 0, y: 0, z: 0), dimensions: RoomPlanDimensions3D(x: 2, y: 0.1, z: 2), transform: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
        let scan = try RoomPlanNormalizedScan(roomID: roomID, capturedAt: Date(), walls: [], floors: [element], openings: [], doors: [], windows: [], objects: [], sections: [])
        let metadata = RoomPlanScanMetadata(provenance: "native-roomplan", deviceModel: "iPhone17,1", lidar: true, roomplanVersion: "17", units: "m", upAxis: "Y", geometryType: "3d")
        var requests: [URLRequest] = []
        OneURLProtocolStub.handler = { request in
            requests.append(request)
            if request.httpMethod == "POST" {
                let body = "{\"id\":\"\(mapID.uuidString)\",\"revision\":2,\"coordinate_frame\":\"roomplan-local\",\"source\":\"roomplan-lidar-3d\",\"dimension\":\"3d\",\"usdz\":null}".data(using: .utf8)!
                return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
            }
            if request.httpMethod == "PUT" {
                let body = "{\"map_id\":\"\(mapID.uuidString)\",\"source\":\"roomplan-lidar-3d\",\"dimension\":\"3d\",\"usdz\":{\"available\":true,\"sha256\":\"abc\",\"bytes\":4,\"content_type\":\"model/vnd.usdz+zip\",\"download_path\":\"/api/v1/...\"}}".data(using: .utf8)!
                return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
            }
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), Data([0x50, 0x4B]))
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))
        let uploaded = try await client.uploadRoomPlan(roomID: roomID, scan: scan, metadata: metadata)
        XCTAssertEqual(uploaded.mapID, mapID)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/maps/roomplan")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-ONE-Client"), "native-ios-roomplan")
        let body = try XCTUnwrap(requestBody(requests[0]))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual((payload["scan_metadata"] as? [String: Any])?["provenance"] as? String, "native-roomplan")
        XCTAssertEqual((payload["scan_metadata"] as? [String: Any])?["lidar"] as? Bool, true)

        let attachment = try await client.uploadRoomPlanUSDZ(mapID: mapID, data: Data([1, 2, 3, 4]))
        XCTAssertEqual(attachment.mapID, mapID)
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertEqual(requests[1].url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/maps/\(mapID.uuidString.lowercased())/usdz")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Content-Type"), "model/vnd.usdz+zip")
        XCTAssertEqual(requestBody(requests[1]), Data([1, 2, 3, 4]))
        let downloaded = try await client.downloadRoomPlanUSDZ(mapID: mapID)
        XCTAssertEqual(downloaded, Data([0x50, 0x4B]))
        XCTAssertEqual(requests[2].httpMethod, "GET")
        XCTAssertEqual(requests[2].url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/maps/\(mapID.uuidString.lowercased())/usdz")
    }

    func testARVideoClientUsesDedicatedNativeRoute() async throws {
        let homeID = UUID()
        let mapID = UUID()
        let floor = try ARVideoSurface(id: UUID(), kind: "floor", alignment: "horizontal", vertices: [SIMD3(-1, 0, -1), SIMD3(1, 0, -1), SIMD3(1, 0, 1), SIMD3(-1, 0, 1)], confidence: 0.8)
        let wallA = try ARVideoSurface(id: UUID(), kind: "wall", alignment: "vertical", vertices: [SIMD3(-1, 0, -1), SIMD3(1, 0, -1), SIMD3(1, 2, -1), SIMD3(-1, 2, -1)], confidence: 0.7)
        let wallB = try ARVideoSurface(id: UUID(), kind: "wall", alignment: "vertical", vertices: [SIMD3(1, 0, -1), SIMD3(1, 0, 1), SIMD3(1, 2, 1), SIMD3(1, 2, -1)], confidence: 0.7)
        let scan = try ARVideoRoomScan(surfaces: [floor, wallA, wallB], diagnostics: ARVideoCaptureDiagnostics(frameSampleCount: 8, normalTrackingSamples: 8, planeCount: 3, trackingState: "normal"))
        var capturedRequest: URLRequest?
        OneURLProtocolStub.handler = { request in
            capturedRequest = request
            let body = "{\"id\":\"\(mapID.uuidString)\",\"revision\":3,\"coordinate_frame\":\"arkit-world\",\"source\":\"arkit-video-3d\",\"dimension\":\"3d\",\"usdz\":{\"available\":true,\"sha256\":\"abc\",\"bytes\":1024,\"content_type\":\"model/vnd.usdz+zip\",\"download_path\":\"/api/v1/...\"}}".data(using: .utf8)!
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))
        let uploaded = try await client.uploadARVideoRoom(scan: scan)
        XCTAssertEqual(uploaded.mapID, mapID)
        XCTAssertEqual(uploaded.source, .arkitVideo3D)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.url?.path, "/api/v1/homes/\(homeID.uuidString.lowercased())/maps/arkit-video")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "X-ONE-Client"), "native-ios-arkit-video")
        let body = try XCTUnwrap(requestBody(try XCTUnwrap(capturedRequest)))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["lidar"] as? Bool, false)
        XCTAssertEqual(json["coordinate_frame"] as? String, "arkit-world")
    }

    func testRoomPlanVisualLandmarkResponseDecodesSnakeCase() async throws {
        let homeID = UUID()
        let mapID = UUID()
        OneURLProtocolStub.handler = { request in
            let body = "{\"map_id\":\"\(mapID.uuidString)\",\"status\":\"ready\",\"landmark_count\":128,\"detector\":\"opencv-orb\",\"diagnostics\":{}}".data(using: .utf8)!
            return (try XCTUnwrap(HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)), body)
        }
        defer { OneURLProtocolStub.handler = nil }

        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": "https://one-api.example/api/v1"])
        let client = HTTPOneAPIClient(configuration: configuration, accessToken: "token", homeID: homeID, session: URLSession(configuration: .oneTest))
        let frame = RoomPlanVisualLandmarkFrameRequest(
            frameBase64: "AA==",
            width: 1,
            height: 1,
            depthBase64: nil,
            depthWidth: nil,
            depthHeight: nil,
            intrinsics: Matrix3x3Request(values: [[1, 0, 0], [0, 1, 0], [0, 0, 1]]),
            cameraToWorld: [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
            capturedAt: "2026-09-14T10:00:00.000Z"
        )
        let response = try await client.uploadRoomPlanVisualLandmarks(mapID: mapID, frames: [frame])
        XCTAssertEqual(response.mapID, mapID)
        XCTAssertEqual(response.status, "ready")
        XCTAssertEqual(response.landmarkCount, 128)
    }

    #if targetEnvironment(simulator)
    func testRoomPlanCapabilityIsDisabledOnSimulator() {
        XCTAssertFalse(RoomPlanCapability.isSupported)
        XCTAssertFalse(ARVideoRoomCaptureCapability.isSupported)
    }
    #endif
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

private final class OneTestSessionStore: SessionKeyStore, @unchecked Sendable {
    private var values: [String: Data] = [:]

    func save(_ value: Data, for key: String) throws {
        values[key] = value
    }

    func load(_ key: String) throws -> Data? {
        values[key]
    }

    func delete(_ key: String) throws {
        values.removeValue(forKey: key)
    }
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

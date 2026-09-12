import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    static let sessionKey = "one.auth.session"
    static func onboardingKey(homeID: UUID, userID: UUID) -> String { "one.auth.onboarding.\(homeID.uuidString).\(userID.uuidString)" }
    var role: UserRole = .caregiver
    var selectedTab = "overview"
    var events: [ObservedEvent]
    var scan: RoomScan
    var assistantMessages: [AssistantMessage] = [
        AssistantMessage(isUser: false, text: "Hi, I’m here for a calm daily check-in. Press and hold when you’d like to talk.")
    ]
    var isListening = false
    var consents: [ConsentRecord]
    var lastDataRequest: DataRequest?
    var caregivers: [CaregiverAccount]
    var medicationDoses: [MedicationDose]
    var medicationPlans: [MedicationPlan] = []
    var isMedicationLoading = false
    var isMedicationMutating = false
    var backendState: BackendConnectionState
    var apiClient: any OneAPIClient
    var session: AuthSession?
    var authError: String?
    var onboardingStep = 0
    var onboardingConsents: [String: Bool] = ["Daily check-in support": false, "Room and camera data": false, "Medication reminders": false, "Family sharing": false]
    var selectedSubjectName = "Everyone"
    var selectedSubjectID: UUID?
    var selectedMedicationDate = Date()
    var inviteCode: String?
    var mapUploadResult: ArtifactUploadResponse?
    var careRecipients: [CareRecipient] = []
    private let sessionStore: any SessionKeyStore
    let runtimeConfiguration = RuntimeConfiguration()

    init(events: [ObservedEvent], scan: RoomScan, consents: [ConsentRecord], caregivers: [CaregiverAccount] = [], medicationDoses: [MedicationDose] = [], medicationPlans: [MedicationPlan] = [], apiClient: any OneAPIClient = MockOneAPIClient(), backendState: BackendConnectionState = .demo, session: AuthSession? = nil, sessionStore: any SessionKeyStore = KeychainSessionStore()) {
        self.events = events; self.scan = scan; self.consents = consents
        self.caregivers = caregivers; self.medicationDoses = medicationDoses; self.medicationPlans = medicationPlans; self.apiClient = apiClient; self.backendState = backendState; self.session = session; self.sessionStore = sessionStore
        self.careRecipients = caregivers.map { CareRecipient(id: $0.id, name: $0.name, relationship: $0.relationship) }
    }

    static func configured() -> AppStore {
        let store = AppStore.demo
        guard !store.runtimeConfiguration.isDemoMode else { return store }
        do {
            if let data = try store.sessionStore.load(Self.sessionKey), let saved = try? JSONDecoder().decode(AuthSession.self, from: data), saved.expiresAt.map({ $0 > Date() }) ?? true { store.session = saved }
        } catch { /* A missing or unreadable credential starts signed out. */ }
        store.apiClient = HTTPOneAPIClient(configuration: store.runtimeConfiguration, accessToken: store.session?.accessToken, homeID: store.session?.homeID)
        if let role = store.session?.role { store.role = role }
        store.backendState = .checking
        return store
    }

    static var demo: AppStore {
        let kitchen = Zone(id: UUID(), name: "Kitchen", center: SIMD3(1, 0, 1), areaSquareMeters: 12)
        let lounge = Zone(id: UUID(), name: "Living room", center: SIMD3(-1, 0, -1), areaSquareMeters: 18)
        let mug = RoomObject(id: UUID(), name: "Blue mug", category: "cup", position: SIMD3(0.3, 0.8, 0.6), dimensions: SIMD3(0.1, 0.12, 0.1), confidence: .high, zoneID: kitchen.id)
        let scan = RoomScan(id: UUID(), schemaVersion: 1, capturedAt: Date().addingTimeInterval(-86400 * 3), units: "m", upAxis: "Y", objects: [mug], zones: [kitchen, lounge], artifactHash: "demo-room-v1", exportedUSDZName: "room-demo.usdz")
        let now = Date()
        let events = [
            ObservedEvent(id: UUID(), kind: .checkIn, timestamp: now.addingTimeInterval(-3600), location: "Living room", confidence: .high, explanation: "A familiar morning check-in was completed.", reviewed: false, hasClip: false),
            ObservedEvent(id: UUID(), kind: .movement, timestamp: now.addingTimeInterval(-86400), location: "Kitchen · approximate", confidence: .medium, explanation: "Movement was observed near the calibrated kitchen zone.", reviewed: true, hasClip: true),
            ObservedEvent(id: UUID(), kind: .assistant, timestamp: now.addingTimeInterval(-86400 * 2), location: "Home", confidence: .high, explanation: "The resident used push-to-talk to ask for the day’s reminder.", reviewed: true, hasClip: false)
        ]
        let consents = [
            ConsentRecord(id: UUID(), purpose: "Room scan and map", enabled: true, policyVersion: "2026-09", updatedAt: now),
            ConsentRecord(id: UUID(), purpose: "Microphone for push-to-talk", enabled: true, policyVersion: "2026-09", updatedAt: now),
            ConsentRecord(id: UUID(), purpose: "Caregiver event clips", enabled: false, policyVersion: "2026-09", updatedAt: now)
        ]
        let caregivers = [
            CaregiverAccount(id: UUID(), name: "Biel Martínez", relationship: "You", role: .owner, permissions: ["Manage people", "Manage plans", "Review events"], isCurrentUser: true),
            CaregiverAccount(id: UUID(), name: "Marta Martínez", relationship: "Daughter", role: .primaryCaregiver, permissions: ["Manage plans", "Review events"], isCurrentUser: false),
            CaregiverAccount(id: UUID(), name: "Joan Soler", relationship: "Neighbour", role: .supporter, permissions: ["Check in", "View today"], isCurrentUser: false),
            CaregiverAccount(id: UUID(), name: "Clara Martínez", relationship: "Family member", role: .viewer, permissions: ["View today"], isCurrentUser: false)
        ]
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: now) ?? now
        let midday = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now) ?? now
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        let medicationDoses = [
            MedicationDose(id: UUID(), medicationName: "Morning reminder", instructions: "With breakfast", scheduledAt: morning, status: .acknowledged, assignedCaregiverName: "Marta Martínez"),
            MedicationDose(id: UUID(), medicationName: "Midday reminder", instructions: "After lunch", scheduledAt: midday, status: .needsConfirmation, assignedCaregiverName: "Joan Soler"),
            MedicationDose(id: UUID(), medicationName: "Evening reminder", instructions: "With dinner", scheduledAt: evening, status: .scheduled, assignedCaregiverName: nil)
        ]
        return AppStore(events: events, scan: scan, consents: consents, caregivers: caregivers, medicationDoses: medicationDoses)
    }

    func toggleConsent(_ consent: ConsentRecord) {
        guard let index = consents.firstIndex(where: { $0.id == consent.id }) else { return }
        consents[index].enabled.toggle()
    }

    func sendAssistantMessage() {
        assistantMessages.append(AssistantMessage(isUser: true, text: "I’m ready for today’s check-in."))
        assistantMessages.append(AssistantMessage(isUser: false, text: "Thanks. I’ve noted that you’re ready. Your caregiver can see the check-in status."))
    }

    func updateMedicationDose(_ doseID: UUID, status: MedicationDoseStatus) {
        guard let index = medicationDoses.firstIndex(where: { $0.id == doseID }) else { return }
        medicationDoses[index].status = status
    }

    func addReminder() {
        medicationDoses.append(MedicationDose(id: UUID(), medicationName: "New reminder", instructions: "Add instructions", scheduledAt: Date().addingTimeInterval(3600), status: .scheduled, assignedCaregiverName: nil))
    }

    func refreshMedicationPlans() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        isMedicationLoading = true
        defer { isMedicationLoading = false }
        do {
            medicationPlans = try await apiClient.medicationPlans(homeID: session.homeID, subjectUserID: selectedSubjectID, activeOnly: true)
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not load medication plans."
        }
    }

    func createMedicationPlan(name: String, dose: String, instructions: String, schedule: String, assignedCaregiverID: UUID?, subjectUserID: UUID?) async -> Bool {
        guard !runtimeConfiguration.isDemoMode, let session else {
            addReminder()
            return true
        }
        let subjectID = subjectUserID ?? selectedSubjectID ?? session.userID
        isMedicationMutating = true
        defer { isMedicationMutating = false }
        do {
            let plan = try await apiClient.createMedicationPlan(homeID: session.homeID, request: MedicationPlanRequest(subjectUserID: subjectID, name: name, dose: dose, schedule: schedule, instructions: instructions, active: true, assignedCaregiverID: assignedCaregiverID))
            medicationPlans.append(plan)
            await refreshMedicationReminders()
            return true
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not save the medication plan."
            return false
        }
    }

    func updateMedicationPlan(_ plan: MedicationPlan, name: String, dose: String, instructions: String, schedule: String, active: Bool, assignedCaregiverID: UUID?) async -> Bool {
        guard !runtimeConfiguration.isDemoMode, let session else { return false }
        isMedicationMutating = true
        defer { isMedicationMutating = false }
        do {
            let updated = try await apiClient.updateMedicationPlan(homeID: session.homeID, planID: plan.id, request: MedicationPlanUpdateRequest(name: name, dose: dose, schedule: schedule, instructions: instructions, active: active, assignedCaregiverID: assignedCaregiverID, version: plan.version))
            if let index = medicationPlans.firstIndex(where: { $0.id == updated.id }) { medicationPlans[index] = updated }
            await refreshMedicationReminders()
            return true
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not update the medication plan."
            return false
        }
    }

    func archiveMedicationPlan(_ plan: MedicationPlan) async -> Bool {
        guard !runtimeConfiguration.isDemoMode, let session else { return false }
        isMedicationMutating = true
        defer { isMedicationMutating = false }
        do {
            _ = try await apiClient.updateMedicationPlan(homeID: session.homeID, planID: plan.id, request: MedicationPlanUpdateRequest(name: nil, dose: nil, schedule: nil, instructions: nil, active: false, assignedCaregiverID: nil, version: plan.version))
            medicationPlans.removeAll { $0.id == plan.id }
            await refreshMedicationReminders()
            return true
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not archive the medication plan."
            return false
        }
    }

    func checkBackend() async {
        guard !runtimeConfiguration.isDemoMode, session != nil else { backendState = runtimeConfiguration.isDemoMode ? .demo : .unavailable; return }
        backendState = .checking
        do {
            let response = try await apiClient.health()
            backendState = response.status == "ok" ? .connected : .unavailable
        } catch {
            backendState = .unavailable
        }
    }

    var isAuthenticated: Bool { runtimeConfiguration.isDemoMode || session != nil }
    var requiresOnboarding: Bool { guard !runtimeConfiguration.isDemoMode, let session else { return false }; return (try? sessionStore.load(Self.onboardingKey(homeID: session.homeID, userID: session.userID))) == nil }

    func login(pairingCode: String) async {
        authError = nil
        do {
            let authenticated = try await apiClient.completePairing(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            try sessionStore.save(JSONEncoder().encode(authenticated), for: Self.sessionKey)
            applySession(authenticated)
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not sign in." }
    }

    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String? = nil) async -> String? {
        authError = nil
        do {
            let response = try await apiClient.bootstrapAccount(request, bootstrapSecret: bootstrapSecret)
            if let token = response.accessToken, let homeID = response.homeID, let userID = response.userID {
                applySession(AuthSession(accessToken: token, homeID: homeID, userID: userID, role: request.role, expiresAt: response.expiresAt))
            }
            return response.pairingCode
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not create the household."; return nil }
    }

    func acceptFamilyInvite(code: String, displayName: String?) async {
        authError = nil
        do { applySession(try await apiClient.acceptFamilyInvite(FamilyInviteAcceptRequest(code: code, displayName: displayName))) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not join the household." }
    }

    func refreshFamilyData() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do {
            caregivers = try await apiClient.familyMembers(homeID: session.homeID).map { account in
                CaregiverAccount(id: account.id, name: account.name, relationship: account.id == session.userID ? "You" : account.relationship, role: account.role, permissions: account.permissions, isCurrentUser: account.id == session.userID)
            }
            careRecipients = caregivers.filter { !$0.isCurrentUser }.map { CareRecipient(id: $0.id, name: $0.name, relationship: $0.relationship) }
            if selectedSubjectID == nil { selectedSubjectID = careRecipients.first?.id; selectedSubjectName = careRecipients.first?.name ?? "Everyone" }
            medicationPlans = try await apiClient.medicationPlans(homeID: session.homeID, subjectUserID: selectedSubjectID, activeOnly: true)
            medicationDoses = try await apiClient.medicationReminders(homeID: session.homeID, subjectUserID: selectedSubjectID, day: selectedMedicationDate)
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not load family data." }
    }

    func createFamilyInvite(name: String, email: String?) async {
        guard !runtimeConfiguration.isDemoMode, let session else { inviteCode = "Demo invites require a live household session."; return }
        do { inviteCode = try await apiClient.createFamilyInvite(homeID: session.homeID, request: FamilyInviteRequest(displayName: name, email: email, role: .caregiver, expiresInSeconds: 86_400)) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not create the invitation." }
    }

    func refreshMedicationReminders() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do { medicationDoses = try await apiClient.medicationReminders(homeID: session.homeID, subjectUserID: selectedSubjectID, day: selectedMedicationDate) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not load medication reminders." }
    }

    func uploadCurrentMap() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do { mapUploadResult = try await apiClient.uploadRoomScan(roomID: scan.id, normalizedJSON: JSONEncoder.one.encode(scan), usdz: nil) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not upload the room map." }
    }

    private func applySession(_ authenticated: AuthSession) {
        try? sessionStore.save(JSONEncoder().encode(authenticated), for: Self.sessionKey)
        session = authenticated; role = authenticated.role
        onboardingStep = 0
        apiClient = HTTPOneAPIClient(configuration: runtimeConfiguration, accessToken: authenticated.accessToken, homeID: authenticated.homeID)
        backendState = .connected
    }

    func completeOnboarding() { guard let session else { return }; try? sessionStore.save(Data("complete".utf8), for: Self.onboardingKey(homeID: session.homeID, userID: session.userID)); onboardingStep = 3 }

    func recordOnboardingConsents() async -> Bool {
        guard !runtimeConfiguration.isDemoMode, let session else { return true }
        authError = nil
        let mapping = ["Daily check-in support": "audio_capture", "Room and camera data": "video_capture", "Medication reminders": "medication_management", "Family sharing": "family_mode"]
        for (label, purpose) in mapping {
            do { try await apiClient.recordConsent(homeID: session.homeID, request: ConsentRequest(purpose: purpose, policyVersion: "2026-09", granted: onboardingConsents[label] ?? false)) }
            catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not save consent choices."; return false }
        }
        return true
    }

    func logout() async {
        let onboardingCredential = session.map { Self.onboardingKey(homeID: $0.homeID, userID: $0.userID) }
        defer { try? sessionStore.delete(Self.sessionKey); if let onboardingCredential { try? sessionStore.delete(onboardingCredential) }; session = nil; authError = nil; apiClient = HTTPOneAPIClient(configuration: runtimeConfiguration); backendState = runtimeConfiguration.isDemoMode ? .demo : .unavailable }
        guard session != nil else { return }
        do { try await apiClient.logout() } catch { /* Local credentials are cleared even if the network is unavailable. */ }
    }
}

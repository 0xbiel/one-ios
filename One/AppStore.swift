import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    static let sessionKey = "one.auth.session"
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
    var backendState: BackendConnectionState
    var apiClient: any OneAPIClient
    var session: AuthSession?
    var authError: String?
    private let sessionStore: any SessionKeyStore
    let runtimeConfiguration = RuntimeConfiguration()

    init(events: [ObservedEvent], scan: RoomScan, consents: [ConsentRecord], caregivers: [CaregiverAccount] = [], medicationDoses: [MedicationDose] = [], apiClient: any OneAPIClient = MockOneAPIClient(), backendState: BackendConnectionState = .demo, session: AuthSession? = nil, sessionStore: any SessionKeyStore = KeychainSessionStore()) {
        self.events = events; self.scan = scan; self.consents = consents
        self.caregivers = caregivers; self.medicationDoses = medicationDoses; self.apiClient = apiClient; self.backendState = backendState; self.session = session; self.sessionStore = sessionStore
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

    func login(pairingCode: String) async {
        authError = nil
        do {
            let authenticated = try await apiClient.completePairing(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            try sessionStore.save(JSONEncoder().encode(authenticated), for: Self.sessionKey)
            session = authenticated; role = authenticated.role
            apiClient = HTTPOneAPIClient(configuration: runtimeConfiguration, accessToken: authenticated.accessToken, homeID: authenticated.homeID)
            backendState = .connected
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not sign in." }
    }

    func logout() async {
        defer { try? sessionStore.delete(Self.sessionKey); session = nil; authError = nil; apiClient = HTTPOneAPIClient(configuration: runtimeConfiguration); backendState = runtimeConfiguration.isDemoMode ? .demo : .unavailable }
        guard session != nil else { return }
        do { try await apiClient.logout() } catch { /* Local credentials are cleared even if the network is unavailable. */ }
    }
}

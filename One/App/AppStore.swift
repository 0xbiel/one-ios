import Foundation
import Observation
import RoomPlan

@MainActor
@Observable
final class AppStore {
    static let sessionKey = "one.auth.session"
    static func onboardingKey(homeID: UUID, userID: UUID) -> String { "one.auth.onboarding.\(homeID.uuidString).\(userID.uuidString)" }
    private static let onboardingConsentMapping: [(label: String, purpose: String)] = [
        ("Room and camera data", "video_capture"),
        ("Daily check-in support", "audio_capture"),
        ("Family sharing", "family_mode")
    ]
    private static let onboardingConsentDefaults = [
        "Daily check-in support": false,
        "Room and camera data": false,
        "Family sharing": false
    ]
    private static let privacyConsentFallbackIDs: [String: UUID] = [
        "video_capture": UUID(uuidString: "9a8f7c6b-5d4e-4f3a-8b2c-1d0e9f8a7b6c")!,
        "audio_capture": UUID(uuidString: "8b7a6c5d-4e3f-4a2b-9c1d-0e8f7a6b5c4d")!,
        "family_mode": UUID(uuidString: "7c6b5a4e-3f2d-4b1a-8e0f-9a7b6c5d4e3f")!
    ]
    var role: UserRole = .caregiver
    var selectedTab = "overview"
    var events: [ObservedEvent]
    var scan: RoomScan
    var assistantMessages: [AssistantMessage] = [
        AssistantMessage(isUser: false, text: "Hi, I’m here for a calm daily check-in. Press and hold when you’d like to talk.")
    ]
    var familyAssistantMessages: [AssistantMessage] = [
        AssistantMessage(isUser: false, text: "I can summarize medication plans and check-ins for the person you select. I do not make care or medication decisions.")
    ]
    var isListening = false
    var consents: [ConsentRecord]
    var lastDataRequest: DataRequest?
    var caregivers: [CaregiverAccount]
    var medicationDoses: [MedicationDose]
    var medicationPlans: [MedicationPlan] = []
    var isMedicationLoading = false
    var isMedicationMutating = false
    var careSpaces: [CareSpaceSummary] = []
    var isCareSpacesLoading = false
    var isCareSpaceMutating = false
    var switchingCareSpaceID: UUID?
    var careSpaceError: String?
    var backendState: BackendConnectionState
    var apiClient: any OneAPIClient
    var session: AuthSession?
    var authError: String?
    var isConsentsLoading = false
    var isConsentMutating = false
    var consentError: String?
    var emailChallenge: EmailAuthChallenge?
    var onboardingStep = 0
    var onboardingConsents = AppStore.onboardingConsentDefaults
    var hasCompletedOnboarding = false
    var selectedSubjectName = "Everyone"
    var selectedSubjectID: UUID?
    var selectedMedicationDate = Date()
    var inviteCode: String?
    var mapUploadResult: ArtifactUploadResponse?
    var scene: SceneDescriptor = .empty
    var roomPlanModelURL: URL?
    var isRoomPlanUploading = false
    var roomPlanVisualUploadProgress: RoomPlanVisualLandmarkUploadProgress?
    var roomPlanSaveProgress: RoomPlanSaveProgress?
    var isRoomPlanModelLoading = false
    var roomPlanModelError: String?
    var careRecipients: [CareRecipient] = []
    var isCareRecipientsLoading = false
    var isCareRecipientMutating = false
    var careRecipientError: String?
    var pairedCameras: [PairedCamera] = []
    var cameraRooms: [CameraRoom] = []
    var isRoomMutating = false
    var roomError: String?
    var cameraCount = 0
    var cameraPairingChallenge: CameraPairingChallenge?
    var cameraPairingStatus: CameraPairingStatus?
    var isCameraPairingBusy = false
    var isCameraMutating = false
    var cameraPairingError: String?
    var cameraCalibrationError: String?
    var cameraReferenceCaptureError: String?
    var cameraReferenceImages: [UUID: Data] = [:]
    private var pendingCameraRoomID: UUID?
    private var pendingRoomPlanMapID: UUID?
    private var pendingRoomPlanUSDZData: Data?
    private struct PendingRoomPlanVisualUpload {
        let mapID: UUID
        let samples: [RoomPlanVisualSample]
    }
    private var pendingRoomPlanVisualUpload: PendingRoomPlanVisualUpload?
    private var roomPlanModelMapID: UUID?
    private var cameraReferenceCaptureKeys: [UUID: String] = [:]
    private let sessionStore: any SessionKeyStore
    let runtimeConfiguration: RuntimeConfiguration

    var canRetryRoomPlanVisualLandmarks: Bool {
        pendingRoomPlanVisualUpload != nil && !isRoomPlanUploading
    }

    init(events: [ObservedEvent], scan: RoomScan, consents: [ConsentRecord], caregivers: [CaregiverAccount] = [], careRecipients: [CareRecipient] = [], medicationDoses: [MedicationDose] = [], medicationPlans: [MedicationPlan] = [], careSpaces: [CareSpaceSummary] = [], apiClient: any OneAPIClient = MockOneAPIClient(), backendState: BackendConnectionState = .demo, session: AuthSession? = nil, sessionStore: any SessionKeyStore = KeychainSessionStore(), runtimeConfiguration: RuntimeConfiguration = RuntimeConfiguration()) {
        self.events = events; self.scan = scan; self.consents = consents
        self.caregivers = caregivers; self.medicationDoses = medicationDoses; self.medicationPlans = medicationPlans; self.careSpaces = careSpaces; self.apiClient = apiClient; self.backendState = backendState; self.session = session; self.sessionStore = sessionStore; self.runtimeConfiguration = runtimeConfiguration
        self.careRecipients = careRecipients
    }

    var medicationSubjects: [CareRecipient] { careRecipients }
    var medicationDosesForSelectedSubject: [MedicationDose] {
        let subjectDoses: [MedicationDose]
        if let selectedSubjectID {
            let matching = medicationDoses.filter { $0.careRecipientID == selectedSubjectID }

            // Keep older demo/test fixtures useful when they predate recipient IDs.
            subjectDoses = matching.isEmpty && medicationDoses.allSatisfy({ $0.careRecipientID == nil })
                ? medicationDoses
                : matching
        } else {
            subjectDoses = medicationDoses
        }

        // The live API already returns reminders for the requested day. Demo
        // data is kept locally, so it needs the same day boundary here.
        guard runtimeConfiguration.isDemoMode else { return subjectDoses }
        return subjectDoses.filter { Calendar.current.isDate($0.scheduledAt, inSameDayAs: selectedMedicationDate) }
    }
    var medicationPlansForSelectedSubject: [MedicationPlan] {
        guard let selectedSubjectID else { return medicationPlans.filter(\.active) }
        let matching = medicationPlans.filter { $0.active && $0.careRecipientID == selectedSubjectID }

        // Keep older fixtures useful when they predate recipient IDs.
        if matching.isEmpty && medicationPlans.allSatisfy({ $0.careRecipientID == nil }) {
            return medicationPlans.filter(\.active)
        }
        return matching
    }
    var currentUserName: String? { caregivers.first(where: \.isCurrentUser)?.name }

    var privacyConsents: [ConsentRecord] {
        let currentUserID = session?.userID
        let relevant = consents.filter { consent in
            consent.careRecipientID == nil
                && consent.purpose != "medication_management"
                && consent.purpose != "Medication reminders"
                && (consent.subjectUserID == nil || consent.subjectUserID == currentUserID)
        }

        let known = Self.onboardingConsentMapping.map { mapping in
            let existing = relevant
                .filter { $0.purpose == mapping.label || $0.purpose == mapping.purpose }
                .max { $0.updatedAt < $1.updatedAt }
            return existing.map {
                ConsentRecord(
                    id: $0.id,
                    purpose: mapping.label,
                    enabled: $0.enabled,
                    policyVersion: $0.policyVersion,
                    updatedAt: $0.updatedAt,
                    subjectUserID: $0.subjectUserID,
                    careRecipientID: nil
                )
            } ?? ConsentRecord(
                id: Self.privacyConsentFallbackIDs[mapping.purpose]!,
                purpose: mapping.label,
                enabled: false,
                policyVersion: "2026-09",
                updatedAt: .distantPast,
                subjectUserID: currentUserID,
                careRecipientID: nil
            )
        }

        let knownPurposes = Set(Self.onboardingConsentMapping.flatMap { [$0.label, $0.purpose] })
        let additional = relevant.filter { !knownPurposes.contains($0.purpose) }
        return known + additional
    }

    var canManageCareRecipients: Bool { role != .resident }

    static func configured() -> AppStore {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-one-show-family")
            || ProcessInfo.processInfo.arguments.contains("-one-show-care-spaces")
            || ProcessInfo.processInfo.arguments.contains("-one-show-care-space-create")
            || ProcessInfo.processInfo.arguments.contains("-one-show-settings") {
            let store = AppStore.demo
            if ProcessInfo.processInfo.arguments.contains("-one-show-family") {
                store.selectedTab = "family"
            }
            if ProcessInfo.processInfo.arguments.contains("-one-show-settings") {
                store.selectedTab = "settings"
            }
            return store
        }
        if ProcessInfo.processInfo.arguments.contains("-one-show-login") {
            return AppStore.live
        }
        if ProcessInfo.processInfo.arguments.contains("-one-show-onboarding") {
            let store = AppStore.live
            let session = AuthSession(
                accessToken: "debug-onboarding",
                homeID: UUID(),
                userID: UUID(),
                role: .caregiver,
                expiresAt: Date().addingTimeInterval(3_600)
            )
            store.session = session
            store.role = session.role
            store.hasCompletedOnboarding = false
            return store
        }
#endif
        let configuration = RuntimeConfiguration()
        let store = AppStore(events: [], scan: .empty, consents: [], caregivers: [], medicationDoses: [], backendState: .checking, runtimeConfiguration: configuration)
        guard !configuration.isDemoMode else { return AppStore.demo }
        do {
            if let data = try store.sessionStore.load(Self.sessionKey), let saved = try? JSONDecoder().decode(AuthSession.self, from: data), saved.expiresAt.map({ $0 > Date() }) ?? true {
                store.session = saved
                store.hasCompletedOnboarding = (try? store.sessionStore.load(Self.onboardingKey(homeID: saved.homeID, userID: saved.userID))) != nil
            }
        } catch { /* A missing or unreadable credential starts signed out. */ }
        store.apiClient = HTTPOneAPIClient(configuration: store.runtimeConfiguration, accessToken: store.session?.accessToken, homeID: store.session?.homeID)
        if let role = store.session?.role { store.role = role }
        store.backendState = .checking
        return store
    }

    static var live: AppStore {
        let configuration = RuntimeConfiguration(info: ["ONE_API_BASE_URL": RuntimeConfiguration.localSimulatorURL.absoluteString])
        let store = AppStore(events: [], scan: .empty, consents: [], caregivers: [], medicationDoses: [], backendState: .checking, runtimeConfiguration: configuration)
        store.assistantMessages = []
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
            ConsentRecord(id: UUID(), purpose: "Room and camera data", enabled: true, policyVersion: "2026-09", updatedAt: now),
            ConsentRecord(id: UUID(), purpose: "Daily check-in support", enabled: true, policyVersion: "2026-09", updatedAt: now),
            ConsentRecord(id: UUID(), purpose: "Family sharing", enabled: false, policyVersion: "2026-09", updatedAt: now)
        ]
        let caregivers = [
            CaregiverAccount(id: UUID(), name: "Biel Martínez", relationship: "You", role: .owner, permissions: ["Manage people", "Manage plans", "Review events"], isCurrentUser: true),
            CaregiverAccount(id: UUID(), name: "Marta Martínez", relationship: "Daughter", role: .primaryCaregiver, permissions: ["Manage plans", "Review events"], isCurrentUser: false),
            CaregiverAccount(id: UUID(), name: "Joan Soler", relationship: "Neighbour", role: .supporter, permissions: ["Check in", "View today"], isCurrentUser: false),
            CaregiverAccount(id: UUID(), name: "Clara Martínez", relationship: "Family member", role: .viewer, permissions: ["View today"], isCurrentUser: false)
        ]
        let careRecipients = [
            CareRecipient(id: UUID(), displayName: "María", relationship: "Mother", medicationRemindersEnabled: true),
            CareRecipient(id: UUID(), displayName: "José", relationship: "Father", medicationRemindersEnabled: false)
        ]
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 8, minute: 30, second: 0, of: now) ?? now
        let midday = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now) ?? now
        let evening = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        let morningPlanID = UUID()
        let middayPlanID = UUID()
        let eveningPlanID = UUID()
        let medicationPlans = [
            MedicationPlan(id: morningPlanID, subjectUserID: caregivers[0].id, careRecipientID: careRecipients[0].id, name: "Morning reminder", dose: "1 tablet", schedule: "Daily @ 08:30", instructions: "With breakfast", active: true, version: 1, assignedCaregiverID: caregivers[1].id),
            MedicationPlan(id: middayPlanID, subjectUserID: caregivers[0].id, careRecipientID: careRecipients[0].id, name: "Midday reminder", dose: "1 tablet", schedule: "Daily @ 13:00", instructions: "After lunch", active: true, version: 1, assignedCaregiverID: caregivers[2].id),
            MedicationPlan(id: eveningPlanID, subjectUserID: caregivers[0].id, careRecipientID: careRecipients[1].id, name: "Evening reminder", dose: "1 tablet", schedule: "Daily @ 20:00", instructions: "With dinner", active: true, version: 1, assignedCaregiverID: nil)
        ]
        let medicationDoses = [
            MedicationDose(id: UUID(), medicationName: "Morning reminder", instructions: "With breakfast", scheduledAt: morning, status: .scheduled, assignedCaregiverName: "Marta Martínez", careRecipientID: careRecipients[0].id, planID: morningPlanID),
            MedicationDose(id: UUID(), medicationName: "Midday reminder", instructions: "After lunch", scheduledAt: midday, status: .needsConfirmation, assignedCaregiverName: "Joan Soler", careRecipientID: careRecipients[0].id, planID: middayPlanID),
            MedicationDose(id: UUID(), medicationName: "Evening reminder", instructions: "With dinner", scheduledAt: evening, status: .scheduled, assignedCaregiverName: nil, careRecipientID: careRecipients[1].id, planID: eveningPlanID)
        ]
        let store = AppStore(events: events, scan: scan, consents: consents, caregivers: caregivers, careRecipients: careRecipients, medicationDoses: medicationDoses, medicationPlans: medicationPlans, careSpaces: CareSpaceSummary.demoSpaces, runtimeConfiguration: RuntimeConfiguration(info: [:]))
        store.selectedSubjectID = careRecipients[0].id
        store.selectedSubjectName = careRecipients[0].displayName
        store.cameraRooms = scan.zones.map { CameraRoom(id: $0.id, name: $0.name) }
        store.pairedCameras = [PairedCamera(id: UUID(), name: "Living room camera", roomID: lounge.id, status: "online")]
        store.cameraCount = store.pairedCameras.count
        return store
    }

    func toggleConsent(_ consent: ConsentRecord) {
        guard let index = consents.firstIndex(where: { $0.id == consent.id }) else { return }
        consents[index].enabled.toggle()
    }

    @discardableResult
    func refreshConsents() async -> Bool {
        guard !runtimeConfiguration.isDemoMode, let session else { return true }
        isConsentsLoading = true
        defer { isConsentsLoading = false }
        do {
            consents = try await apiClient.consents(homeID: session.homeID)
            consentError = nil
            return true
        } catch {
            consentError = (error as? LocalizedError)?.errorDescription ?? "Could not load privacy and consent settings."
            return false
        }
    }

    @discardableResult
    func setConsent(_ consent: ConsentRecord, enabled: Bool) async -> Bool {
        guard let mapping = Self.onboardingConsentMapping.first(where: { $0.label == consent.purpose || $0.purpose == consent.purpose }) else {
            consentError = "That consent choice is not available."
            return false
        }

        let previousConsents = consents
        onboardingConsents[mapping.label] = enabled
        upsertOnboardingConsent(label: mapping.label, granted: enabled)

        if runtimeConfiguration.isDemoMode {
            consentError = nil
            return true
        }

        guard let session else {
            consents = previousConsents
            onboardingConsents[mapping.label] = consent.enabled
            consentError = OneAPIError.missingSession.localizedDescription
            return false
        }

        isConsentMutating = true
        consentError = nil
        defer { isConsentMutating = false }
        do {
            try await apiClient.recordConsent(
                homeID: session.homeID,
                request: ConsentRequest(
                    purpose: mapping.purpose,
                    policyVersion: "2026-09",
                    granted: enabled,
                    subjectUserID: session.userID
                )
            )
            _ = await refreshConsents()
            authError = nil
            return true
        } catch {
            consents = previousConsents
            onboardingConsents[mapping.label] = consent.enabled
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not save this consent choice."
            consentError = message
            authError = message
            return false
        }
    }

    func sendAssistantMessage() {
        guard runtimeConfiguration.isDemoMode else {
            authError = "The live organizer assistant is not connected yet."
            return
        }
        assistantMessages.append(AssistantMessage(isUser: true, text: "I’m ready for today’s check-in."))
        assistantMessages.append(AssistantMessage(isUser: false, text: "Thanks. I’ve noted that you’re ready. Your caregiver can see the check-in status."))
    }

    func updateMedicationDose(_ doseID: UUID, status: MedicationDoseStatus) {
        guard let index = medicationDoses.firstIndex(where: { $0.id == doseID }) else { return }
        medicationDoses[index].status = status
    }

    @discardableResult
    func markMedicationDose(_ dose: MedicationDose, status: MedicationDoseStatus) async -> Bool {
        if runtimeConfiguration.isDemoMode {
            updateMedicationDose(dose.id, status: status)
            if let index = medicationDoses.firstIndex(where: { $0.id == dose.id }), status != .scheduled {
                medicationDoses[index].markedByName = currentUserName ?? "You"
                medicationDoses[index].markedAt = Date()
            }
            return true
        }
        guard let session, let planID = dose.planID else {
            authError = OneAPIError.missingSession.localizedDescription
            return false
        }
        let backendStatus: String
        switch status {
        case .acknowledged: backendStatus = "taken"
        case .missed: backendStatus = "missed"
        case .needsConfirmation: backendStatus = "skipped"
        case .scheduled: backendStatus = "pending"
        }
        isMedicationMutating = true
        defer { isMedicationMutating = false }
        do {
            try await apiClient.recordMedicationCheckIn(homeID: session.homeID, planID: planID, request: MedicationCheckInRequest(scheduledFor: dose.scheduledAt, status: backendStatus))
            await refreshMedicationReminders()
            return true
        } catch {
            authError = medicationErrorMessage(error, careRecipientID: dose.careRecipientID, fallback: "Could not update this reminder.")
            return false
        }
    }

    func addReminder() {
        medicationDoses.append(MedicationDose(id: UUID(), medicationName: "New reminder", instructions: "Add instructions", scheduledAt: Date().addingTimeInterval(3600), status: .scheduled, assignedCaregiverName: nil, careRecipientID: selectedSubjectID))
    }

    func refreshMedicationPlans() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        guard let selectedSubjectID else {
            medicationPlans = []
            return
        }
        if let recipient = careRecipients.first(where: { $0.id == selectedSubjectID }), recipient.medicationRemindersEnabled == false {
            medicationPlans = []
            medicationDoses = []
            return
        }
        isMedicationLoading = true
        defer { isMedicationLoading = false }
        do {
            medicationPlans = try await apiClient.medicationPlans(homeID: session.homeID, careRecipientID: selectedSubjectID, activeOnly: true)
        } catch {
            authError = medicationErrorMessage(error, careRecipientID: selectedSubjectID, fallback: "Could not load medication plans.")
        }
    }

    func createMedicationPlan(name: String, dose: String, instructions: String, schedule: String, assignedCaregiverID: UUID?, careRecipientID: UUID?) async -> Bool {
        if runtimeConfiguration.isDemoMode {
            guard let recipientID = careRecipientID ?? selectedSubjectID else {
                authError = "Choose who this medication plan is for."
                return false
            }
            let planID = UUID()
            let plan = MedicationPlan(
                id: planID,
                subjectUserID: session?.userID ?? caregivers.first?.id ?? UUID(),
                careRecipientID: recipientID,
                name: name,
                dose: dose,
                schedule: schedule,
                instructions: instructions,
                active: true,
                version: 1,
                assignedCaregiverID: assignedCaregiverID
            )
            medicationPlans.append(plan)
            medicationDoses.append(MedicationDose(
                id: UUID(),
                medicationName: name,
                instructions: instructions,
                scheduledAt: Date().addingTimeInterval(3600),
                status: .scheduled,
                assignedCaregiverName: assignedCaregiverID.flatMap { id in caregivers.first(where: { $0.id == id })?.name },
                careRecipientID: recipientID,
                planID: planID
            ))
            selectedSubjectID = recipientID
            selectedSubjectName = careRecipients.first(where: { $0.id == recipientID })?.displayName ?? selectedSubjectName
            return true
        }
        guard let session else {
            authError = OneAPIError.missingSession.localizedDescription
            return false
        }
        guard let recipientID = careRecipientID ?? selectedSubjectID else {
            authError = "Choose who this medication plan is for."
            return false
        }
        if let recipient = careRecipients.first(where: { $0.id == recipientID }), recipient.medicationRemindersEnabled == false {
            authError = "Medication reminders are off for \(recipient.displayName). Open their profile and turn on Medication reminders first."
            return false
        }
        isMedicationMutating = true
        defer { isMedicationMutating = false }
        do {
            let plan = try await apiClient.createMedicationPlan(homeID: session.homeID, request: MedicationPlanRequest(subjectUserID: nil, careRecipientID: recipientID, name: name, dose: dose, schedule: schedule, instructions: instructions, active: true, assignedCaregiverID: assignedCaregiverID))
            medicationPlans.append(plan)
            await refreshMedicationReminders()
            return true
        } catch {
            authError = medicationErrorMessage(error, careRecipientID: recipientID, fallback: "Could not save the medication plan.")
            return false
        }
    }

    func updateMedicationPlan(_ plan: MedicationPlan, name: String, dose: String, instructions: String, schedule: String, active: Bool, assignedCaregiverID: UUID?) async -> Bool {
        if runtimeConfiguration.isDemoMode {
            guard let index = medicationPlans.firstIndex(where: { $0.id == plan.id }) else {
                authError = "This medication plan is no longer available."
                return false
            }
            medicationPlans[index].name = name
            medicationPlans[index].dose = dose
            medicationPlans[index].instructions = instructions
            medicationPlans[index].schedule = schedule
            medicationPlans[index].active = active
            medicationPlans[index].version += 1
            medicationPlans[index].assignedCaregiverID = assignedCaregiverID
            for doseIndex in medicationDoses.indices where medicationDoses[doseIndex].planID == plan.id {
                medicationDoses[doseIndex].medicationName = name
                medicationDoses[doseIndex].instructions = instructions
                medicationDoses[doseIndex].assignedCaregiverName = assignedCaregiverID.flatMap { id in caregivers.first(where: { $0.id == id })?.name }
            }
            if !active {
                medicationDoses.removeAll { $0.planID == plan.id }
            }
            return true
        }
        guard let session else {
            authError = OneAPIError.missingSession.localizedDescription
            return false
        }
        if let recipientID = plan.careRecipientID,
           let recipient = careRecipients.first(where: { $0.id == recipientID }),
           recipient.medicationRemindersEnabled == false {
            authError = "Medication reminders are off for \(recipient.displayName). Open their profile and turn on Medication reminders first."
            return false
        }
        isMedicationMutating = true
        defer { isMedicationMutating = false }
        do {
            let updated = try await apiClient.updateMedicationPlan(homeID: session.homeID, planID: plan.id, request: MedicationPlanUpdateRequest(name: name, dose: dose, schedule: schedule, instructions: instructions, active: active, assignedCaregiverID: assignedCaregiverID, version: plan.version))
            if let index = medicationPlans.firstIndex(where: { $0.id == updated.id }) { medicationPlans[index] = updated }
            await refreshMedicationReminders()
            return true
        } catch {
            authError = medicationErrorMessage(error, careRecipientID: plan.careRecipientID, fallback: "Could not update the medication plan.")
            return false
        }
    }

    func archiveMedicationPlan(_ plan: MedicationPlan) async -> Bool {
        if runtimeConfiguration.isDemoMode {
            medicationPlans.removeAll { $0.id == plan.id }
            medicationDoses.removeAll { $0.planID == plan.id }
            return true
        }
        guard let session else {
            authError = OneAPIError.missingSession.localizedDescription
            return false
        }
        isMedicationMutating = true
        defer { isMedicationMutating = false }
        do {
            _ = try await apiClient.updateMedicationPlan(homeID: session.homeID, planID: plan.id, request: MedicationPlanUpdateRequest(name: nil, dose: nil, schedule: nil, instructions: nil, active: false, assignedCaregiverID: nil, version: plan.version))
            medicationPlans.removeAll { $0.id == plan.id }
            await refreshMedicationReminders()
            return true
        } catch {
            authError = medicationErrorMessage(error, careRecipientID: plan.careRecipientID, fallback: "Could not archive the medication plan.")
            return false
        }
    }

    func checkBackend() async {
        guard !runtimeConfiguration.isDemoMode else { backendState = .demo; return }
        backendState = .checking
        do {
            let response = try await apiClient.health()
            backendState = response.status == "ok" ? .connected : .unavailable
        } catch {
            backendState = .unavailable
        }
    }

    var isAuthenticated: Bool { runtimeConfiguration.isDemoMode || session != nil }
    var activeCareSpace: CareSpaceSummary? {
        if let homeID = session?.homeID, let matching = careSpaces.first(where: { $0.id == homeID }) { return matching }
        return careSpaces.first(where: \.active) ?? careSpaces.first
    }
    var requiresOnboarding: Bool {
        !runtimeConfiguration.isDemoMode && session != nil && !hasCompletedOnboarding
    }

    func login(pairingCode: String) async {
        authError = nil
        do {
            let authenticated = try await apiClient.completePairing(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            try applySession(authenticated)
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not sign in." }
    }

    func requestEmailCode(email: String, purpose: String, displayName: String? = nil, homeName: String = "ONE Home", careSetting: String = "home", supportFocus: String = "general") async -> String? {
        authError = nil
        emailChallenge = nil
        do {
            emailChallenge = try await apiClient.requestEmailCode(EmailAuthRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines), purpose: purpose, displayName: displayName, homeName: homeName, careSetting: careSetting, supportFocus: supportFocus, role: .caregiver))
            return emailChallenge?.devCode ?? "requested"
        } catch {
            if let apiError = error as? OneAPIError, case let .server(status: 404, message) = apiError {
                authError = "\(message) Choose Create household if this is your first ONE account."
            } else {
                authError = (error as? LocalizedError)?.errorDescription ?? "Could not send the email code."
            }
            return nil
        }
    }

    func login(email: String, code: String) async {
        authError = nil
        do {
            let authenticated = try await apiClient.verifyEmailCode(EmailAuthVerifyRequest(email: email, code: code))
            try applySession(authenticated)
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not sign in." }
    }

    func bootstrapAccount(_ request: BootstrapAccountRequest, bootstrapSecret: String? = nil) async -> String? {
        authError = nil
        do {
            let response = try await apiClient.bootstrapAccount(request, bootstrapSecret: bootstrapSecret)
            if let token = response.accessToken, let homeID = response.homeID, let userID = response.userID {
                try applySession(AuthSession(accessToken: token, homeID: homeID, userID: userID, role: request.role, expiresAt: response.expiresAt))
            }
            return response.pairingCode
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not create the household."; return nil }
    }

    func acceptFamilyInvite(code: String, displayName: String?, email: String? = nil) async {
        authError = nil
        do { try applySession(try await apiClient.acceptFamilyInvite(FamilyInviteAcceptRequest(code: code, displayName: displayName, email: email))) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not join the household." }
    }

    func refreshFamilyData() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do {
            caregivers = try await apiClient.familyMembers(homeID: session.homeID).map { account in
                CaregiverAccount(id: account.id, name: account.name, relationship: account.id == session.userID ? "You" : account.relationship, role: account.role, permissions: account.permissions, isCurrentUser: account.id == session.userID)
            }
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not load household access."
        }
        await refreshCareRecipients()
        await refreshConsents()
        if let selectedSubjectID, !medicationSubjects.contains(where: { $0.id == selectedSubjectID }) {
            self.selectedSubjectID = nil
            selectedSubjectName = "Everyone"
        }
        if selectedSubjectID == nil, let subject = medicationSubjects.first {
            selectedSubjectID = subject.id
            selectedSubjectName = subject.name
        }
        await refreshMedicationPlans()
        await refreshMedicationReminders()
    }

    func refreshCareRecipients() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        isCareRecipientsLoading = true
        defer { isCareRecipientsLoading = false }
        do {
            careRecipients = try await apiClient.careRecipients(homeID: session.homeID)
            careRecipientError = nil
            syncActiveCareSpaceRecipients()
        } catch {
            careRecipientError = (error as? LocalizedError)?.errorDescription ?? "Could not load the people cared for in this space."
        }
    }

    @discardableResult
    func createCareRecipient(name: String, relationship: String?, roomLabel: String?) async -> Bool {
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmedName.isEmpty else {
            careRecipientError = "Enter a name for this person."
            return false
        }
        guard canManageCareRecipients else {
            careRecipientError = "Only a caregiver can add people to this care space."
            return false
        }
        let trimmedRelationship = normalizedCareRecipientField(relationship)
        let trimmedRoom = normalizedCareRecipientField(roomLabel)
        isCareRecipientMutating = true
        careRecipientError = nil
        defer { isCareRecipientMutating = false }

        if runtimeConfiguration.isDemoMode {
            careRecipients.append(CareRecipient(id: UUID(), displayName: trimmedName, relationship: trimmedRelationship, roomLabel: trimmedRoom))
            if selectedSubjectID == nil, let recipient = careRecipients.last {
                selectedSubjectID = recipient.id
                selectedSubjectName = recipient.displayName
            }
            syncActiveCareSpaceRecipients()
            return true
        }

        guard let session else {
            careRecipientError = OneAPIError.missingSession.localizedDescription
            return false
        }
        do {
            let recipient = try await apiClient.createCareRecipient(
                homeID: session.homeID,
                request: CareRecipientCreateRequest(displayName: trimmedName, relationship: trimmedRelationship, roomLabel: trimmedRoom)
            )
            careRecipients.append(recipient)
            if selectedSubjectID == nil {
                selectedSubjectID = recipient.id
                selectedSubjectName = recipient.displayName
            }
            syncActiveCareSpaceRecipients()
            await refreshCareSpaces()
            return true
        } catch {
            careRecipientError = (error as? LocalizedError)?.errorDescription ?? "Could not add this person."
            return false
        }
    }

    @discardableResult
    func updateCareRecipient(_ recipient: CareRecipient, name: String, relationship: String?, roomLabel: String?) async -> Bool {
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmedName.isEmpty else {
            careRecipientError = "Enter a name for this person."
            return false
        }
        guard canManageCareRecipients else {
            careRecipientError = "Only a caregiver can edit people in this care space."
            return false
        }
        let trimmedRelationship = normalizedCareRecipientField(relationship)
        let trimmedRoom = normalizedCareRecipientField(roomLabel)
        isCareRecipientMutating = true
        careRecipientError = nil
        defer { isCareRecipientMutating = false }

        if runtimeConfiguration.isDemoMode {
            if let index = careRecipients.firstIndex(where: { $0.id == recipient.id }) {
                careRecipients[index].displayName = trimmedName
                careRecipients[index].relationship = trimmedRelationship
                careRecipients[index].roomLabel = trimmedRoom
            }
            if selectedSubjectID == recipient.id {
                selectedSubjectName = trimmedName
            }
            syncActiveCareSpaceRecipients()
            return true
        }

        guard let session else {
            careRecipientError = OneAPIError.missingSession.localizedDescription
            return false
        }
        do {
            let updated = try await apiClient.updateCareRecipient(
                homeID: session.homeID,
                recipientID: recipient.id,
                request: CareRecipientUpdateRequest(displayName: trimmedName, relationship: trimmedRelationship, roomLabel: trimmedRoom)
            )
            if let index = careRecipients.firstIndex(where: { $0.id == updated.id }) { careRecipients[index] = updated }
            if selectedSubjectID == updated.id {
                selectedSubjectName = updated.displayName
            }
            syncActiveCareSpaceRecipients()
            await refreshCareSpaces()
            return true
        } catch {
            careRecipientError = (error as? LocalizedError)?.errorDescription ?? "Could not update this person."
            return false
        }
    }

    @discardableResult
    func removeCareRecipient(_ recipientID: UUID) async -> Bool {
        guard canManageCareRecipients else {
            careRecipientError = "Only a caregiver can remove people from this care space."
            return false
        }
        isCareRecipientMutating = true
        careRecipientError = nil
        defer { isCareRecipientMutating = false }

        if runtimeConfiguration.isDemoMode {
            careRecipients.removeAll { $0.id == recipientID }
            medicationPlans.removeAll { $0.careRecipientID == recipientID }
            medicationDoses.removeAll { $0.careRecipientID == recipientID }
            if selectedSubjectID == recipientID {
                selectedSubjectID = careRecipients.first?.id
                selectedSubjectName = careRecipients.first?.displayName ?? "Everyone"
            }
            syncActiveCareSpaceRecipients()
            return true
        }

        guard let session else {
            careRecipientError = OneAPIError.missingSession.localizedDescription
            return false
        }
        do {
            try await apiClient.deleteCareRecipient(homeID: session.homeID, recipientID: recipientID)
            careRecipients.removeAll { $0.id == recipientID }
            medicationPlans.removeAll { $0.careRecipientID == recipientID }
            medicationDoses.removeAll { $0.careRecipientID == recipientID }
            if selectedSubjectID == recipientID {
                selectedSubjectID = careRecipients.first?.id
                selectedSubjectName = careRecipients.first?.displayName ?? "Everyone"
            }
            syncActiveCareSpaceRecipients()
            await refreshCareSpaces()
            return true
        } catch {
            careRecipientError = (error as? LocalizedError)?.errorDescription ?? "Could not remove this person."
            return false
        }
    }

    func clearCareRecipientError() {
        careRecipientError = nil
    }

    @discardableResult
    func setMedicationRemindersEnabled(for recipient: CareRecipient, enabled: Bool) async -> Bool {
        guard canManageCareRecipients else {
            careRecipientError = "Only a caregiver can change medication reminders for this person."
            return false
        }

        if runtimeConfiguration.isDemoMode {
            if let index = careRecipients.firstIndex(where: { $0.id == recipient.id }) {
                careRecipients[index].medicationRemindersEnabled = enabled
            }
            return true
        }
        guard let session else {
            careRecipientError = OneAPIError.missingSession.localizedDescription
            return false
        }
        let previousValue = careRecipients.first(where: { $0.id == recipient.id })?.medicationRemindersEnabled
        if let index = careRecipients.firstIndex(where: { $0.id == recipient.id }) {
            careRecipients[index].medicationRemindersEnabled = enabled
        }
        do {
            try await apiClient.recordConsent(
                homeID: session.homeID,
                request: ConsentRequest(purpose: "medication_management", policyVersion: "2026-09", granted: enabled, careRecipientID: recipient.id)
            )
            await refreshCareRecipients()
            if selectedSubjectID == recipient.id {
                await refreshMedicationPlans()
                await refreshMedicationReminders()
            }
            return true
        } catch {
            if let index = careRecipients.firstIndex(where: { $0.id == recipient.id }) {
                careRecipients[index].medicationRemindersEnabled = previousValue
            }
            careRecipientError = (error as? LocalizedError)?.errorDescription ?? "Could not update medication reminders for this person."
            return false
        }
    }

    func sendFamilyAssistantMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        familyAssistantMessages.append(AssistantMessage(isUser: true, text: trimmed))
        if runtimeConfiguration.isDemoMode {
            familyAssistantMessages.append(AssistantMessage(isUser: false, text: "Today's medication plan is ready for review. This demo assistant only summarizes recorded plans and check-ins."))
            return
        }
        guard let session else {
            authError = OneAPIError.missingSession.localizedDescription
            return
        }
        do {
            let result = try await apiClient.familyAssistant(homeID: session.homeID, request: FamilyAssistantRequest(message: trimmed, careRecipientID: selectedSubjectID))
            familyAssistantMessages.append(AssistantMessage(isUser: false, text: "\(result.summary)\n\n\(result.nextAction)\n\n\(result.limitations)"))
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "The caregiver assistant is unavailable."
        }
    }

    func refreshLiveData() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do { events = try await apiClient.events(homeID: session.homeID) } catch { events = [] }
        do {
            let objects = try await apiClient.roomObjects(homeID: session.homeID)
            scan = RoomScan(id: scan.id, schemaVersion: scan.schemaVersion, capturedAt: scan.capturedAt, units: scan.units, upAxis: scan.upAxis, objects: objects, zones: scan.zones, artifactHash: scan.artifactHash, exportedUSDZName: scan.exportedUSDZName)
        } catch { scan = .empty }
        await refreshCameraConfiguration()
        await refreshScene()
        await refreshFamilyData()
    }

    func refreshMapData() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do {
            let objects = try await apiClient.roomObjects(homeID: session.homeID)
            scan = RoomScan(id: scan.id, schemaVersion: scan.schemaVersion, capturedAt: scan.capturedAt, units: scan.units, upAxis: scan.upAxis, objects: objects, zones: scan.zones, artifactHash: scan.artifactHash, exportedUSDZName: scan.exportedUSDZName)
        } catch {
            // Keep the last mapped observations during transient refresh errors.
        }
        await refreshScene()
    }

    func refreshCareSpaces() async {
        guard runtimeConfiguration.isDemoMode || session != nil else { return }
        isCareSpacesLoading = true
        defer { isCareSpacesLoading = false }
        do {
            let refreshed = try await apiClient.careSpaces()
            let activeHomeID = session?.homeID
            careSpaces = refreshed.map { space in
                var updated = space
                if let activeHomeID { updated.active = space.id == activeHomeID }
                return updated
            }
            careSpaceError = nil
        } catch {
            careSpaceError = (error as? LocalizedError)?.errorDescription ?? "Could not load your care spaces."
        }
    }

    @discardableResult
    func activateCareSpace(_ space: CareSpaceSummary) async -> Bool {
        guard !space.active && space.id != session?.homeID else { return true }
        isCareSpaceMutating = true
        switchingCareSpaceID = space.id
        careSpaceError = nil
        defer {
            switchingCareSpaceID = nil
            isCareSpaceMutating = false
        }
        do {
            let authenticated = try await apiClient.activateCareSpace(id: space.id)
            try applySession(authenticated)
            careSpaces = careSpaces.map { item in
                var updated = item
                updated.active = item.id == authenticated.homeID
                return updated
            }
            if !runtimeConfiguration.isDemoMode { await refreshCareSpaces() }
            return true
        } catch {
            careSpaceError = (error as? LocalizedError)?.errorDescription ?? "Could not switch care spaces."
            return false
        }
    }

    @discardableResult
    func createCareSpace(name: String, careSetting: CareSetting, supportFocus: SupportFocus) async -> Bool {
        let trimmedName = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmedName.isEmpty else {
            careSpaceError = "Enter a name for this care space."
            return false
        }
        isCareSpaceMutating = true
        careSpaceError = nil
        defer { isCareSpaceMutating = false }
        do {
            let authenticated = try await apiClient.createCareSpace(CareSpaceCreateRequest(name: trimmedName, careSetting: careSetting, supportFocus: supportFocus))
            try applySession(authenticated)
            careSpaces = careSpaces.map { item in
                var updated = item
                updated.active = false
                return updated
            }
            careSpaces.append(CareSpaceSummary(id: authenticated.homeID, name: trimmedName, residentName: "Resident", careSetting: careSetting, supportFocus: supportFocus, role: .admin, active: true, recipientNames: [], recipientCount: 0))
            if !runtimeConfiguration.isDemoMode { await refreshCareSpaces() }
            return true
        } catch {
            careSpaceError = (error as? LocalizedError)?.errorDescription ?? "Could not create the care space."
            return false
        }
    }

    func clearCareSpaceError() {
        careSpaceError = nil
    }

    func refreshCameraConfiguration() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do {
            pairedCameras = try await apiClient.pairedCameras(homeID: session.homeID)
            cameraCount = pairedCameras.count
        } catch {
            pairedCameras = []
            cameraCount = 0
        }
        do {
            cameraRooms = try await apiClient.cameraRooms(homeID: session.homeID)
        } catch {
            cameraRooms = []
        }
    }

    func createRoom(name: String) async -> Bool {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmed.isEmpty else {
            roomError = "Room name cannot be empty."
            return false
        }
        if runtimeConfiguration.isDemoMode {
            cameraRooms.append(CameraRoom(id: UUID(), name: trimmed))
            roomError = nil
            return true
        }
        guard let session else {
            roomError = OneAPIError.missingSession.localizedDescription
            return false
        }
        isRoomMutating = true
        roomError = nil
        defer { isRoomMutating = false }
        do {
            let room = try await apiClient.createRoom(homeID: session.homeID, name: trimmed)
            cameraRooms.append(room)
            return true
        } catch {
            roomError = (error as? LocalizedError)?.errorDescription ?? "Could not create this room."
            return false
        }
    }

    func renameRoom(_ room: CameraRoom, name: String) async -> Bool {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmed.isEmpty else {
            roomError = "Room name cannot be empty."
            return false
        }
        if runtimeConfiguration.isDemoMode {
            if let index = cameraRooms.firstIndex(where: { $0.id == room.id }) {
                cameraRooms[index] = CameraRoom(id: room.id, name: trimmed)
            }
            roomError = nil
            return true
        }
        guard let session else {
            roomError = OneAPIError.missingSession.localizedDescription
            return false
        }
        isRoomMutating = true
        roomError = nil
        defer { isRoomMutating = false }
        do {
            let updated = try await apiClient.updateRoom(homeID: session.homeID, roomID: room.id, name: trimmed)
            if let index = cameraRooms.firstIndex(where: { $0.id == room.id }) { cameraRooms[index] = updated }
            return true
        } catch {
            roomError = (error as? LocalizedError)?.errorDescription ?? "Could not rename this room."
            return false
        }
    }

    func deleteRoom(_ room: CameraRoom) async -> Bool {
        if runtimeConfiguration.isDemoMode {
            cameraRooms.removeAll { $0.id == room.id }
            pairedCameras = pairedCameras.map { camera in
                guard camera.roomID == room.id else { return camera }
                return PairedCamera(id: camera.id, name: camera.name, roomID: nil, status: camera.status, calibrationNeeded: camera.calibrationNeeded, roomplanRegistrationStatus: camera.roomplanRegistrationStatus, roomplanMapID: camera.roomplanMapID)
            }
            roomError = nil
            return true
        }
        guard let session else {
            roomError = OneAPIError.missingSession.localizedDescription
            return false
        }
        isRoomMutating = true
        roomError = nil
        defer { isRoomMutating = false }
        do {
            try await apiClient.deleteRoom(homeID: session.homeID, roomID: room.id)
            cameraRooms.removeAll { $0.id == room.id }
            pairedCameras = try await apiClient.pairedCameras(homeID: session.homeID)
            cameraCount = pairedCameras.count
            await refreshScene()
            return true
        } catch {
            roomError = (error as? LocalizedError)?.errorDescription ?? "Could not delete this room."
            return false
        }
    }

    func startRoomPlanCalibration(for camera: PairedCamera) async -> RoomPlanCalibrationSession? {
        guard let session else {
            cameraCalibrationError = OneAPIError.missingSession.localizedDescription
            return nil
        }
        cameraCalibrationError = nil
        do {
            return try await apiClient.startRoomPlanCalibrationSession(homeID: session.homeID, cameraID: camera.id)
        } catch {
            cameraCalibrationError = (error as? LocalizedError)?.errorDescription ?? "Could not start camera calibration."
            return nil
        }
    }

    func refreshRoomPlanCalibration(for camera: PairedCamera) async -> RoomPlanCalibrationSession? {
        guard let session else { return nil }
        do {
            let value = try await apiClient.roomPlanCalibrationSession(homeID: session.homeID, cameraID: camera.id)
            cameraCalibrationError = nil
            return value
        } catch {
            cameraCalibrationError = (error as? LocalizedError)?.errorDescription ?? "Could not refresh camera calibration."
            return nil
        }
    }

    func requestRoomPlanCalibrationCapture(for camera: PairedCamera, targetIndex: Int) async -> RoomPlanCalibrationSession? {
        guard let session else { return nil }
        do {
            let value = try await apiClient.requestRoomPlanCalibrationCapture(homeID: session.homeID, cameraID: camera.id, targetIndex: targetIndex)
            cameraCalibrationError = nil
            return value
        } catch {
            cameraCalibrationError = (error as? LocalizedError)?.errorDescription ?? "Could not request the fixed-camera capture."
            return nil
        }
    }

    func confirmRoomPlanCalibration(for camera: PairedCamera, calibration: RoomPlanCalibrationSession) async -> Bool {
        guard let session, let proposal = calibration.proposal else {
            cameraCalibrationError = "The calibration proposal is not ready yet."
            return false
        }
        do {
            _ = try await apiClient.registerRoomPlanCamera(
                homeID: session.homeID,
                request: RoomPlanCameraRegistrationRequest(
                    cameraID: camera.id,
                    mapID: proposal.mapID,
                    cameraToWorld: proposal.cameraToWorld,
                    confidence: proposal.confidence,
                    trackingState: "normal"
                )
            )
            do {
                try await apiClient.commitRoomPlanCalibrationReference(homeID: session.homeID, cameraID: camera.id)
                cameraCalibrationError = nil
            } catch {
                cameraCalibrationError = "The camera position was saved, but its reference image could not be stored. You can refresh the reference view later."
            }
            await refreshCameraConfiguration()
            await refreshScene()
            return true
        } catch {
            cameraCalibrationError = (error as? LocalizedError)?.errorDescription ?? "Could not save the reviewed camera position."
            return false
        }
    }

    func requestCameraReferenceCapture(_ cameraID: UUID) async -> Bool {
        guard let session else {
            cameraReferenceCaptureError = OneAPIError.missingSession.localizedDescription
            return false
        }
        cameraReferenceCaptureError = nil
        do {
            try await apiClient.requestCameraReferenceCapture(homeID: session.homeID, cameraID: cameraID)
            return true
        } catch {
            cameraReferenceCaptureError = (error as? LocalizedError)?.errorDescription ?? "Could not request a fresh camera reference view."
            return false
        }
    }

    func saveManualRoomPlanCamera(
        _ camera: PairedCamera,
        mapID: UUID,
        x: Double,
        z: Double,
        floorY: Double,
        height: Double,
        yawDegrees: Double
    ) async -> Bool {
        guard let session else {
            cameraCalibrationError = OneAPIError.missingSession.localizedDescription
            return false
        }
        let yaw = yawDegrees * .pi / 180
        let cosine = cos(yaw)
        let sine = sin(yaw)
        let matrix = [
            [cosine, 0.0, -sine, x],
            [0.0, 1.0, 0.0, floorY + height],
            [sine, 0.0, cosine, z],
            [0.0, 0.0, 0.0, 1.0],
        ]
        do {
            _ = try await apiClient.registerRoomPlanCamera(
                homeID: session.homeID,
                request: RoomPlanCameraRegistrationRequest(
                    cameraID: camera.id,
                    mapID: mapID,
                    cameraToWorld: matrix,
                    confidence: nil,
                    trackingState: "normal"
                )
            )
            cameraCalibrationError = nil
            await refreshCameraConfiguration()
            await refreshScene()
            return true
        } catch {
            cameraCalibrationError = (error as? LocalizedError)?.errorDescription ?? "Could not save the manual camera position."
            return false
        }
    }

    func cancelRoomPlanCalibration(for camera: PairedCamera) async {
        guard let session else { return }
        do {
            try await apiClient.cancelRoomPlanCalibrationSession(homeID: session.homeID, cameraID: camera.id)
            cameraCalibrationError = nil
        } catch {
            cameraCalibrationError = (error as? LocalizedError)?.errorDescription ?? "Could not cancel camera calibration."
        }
    }

    func startCameraPairing(label: String = "ONE room camera", roomID: UUID? = nil) async {
        guard role != .resident else {
            cameraPairingError = "Only a caregiver can pair a room camera."
            return
        }
        if runtimeConfiguration.isDemoMode {
            let id = UUID()
            cameraPairingChallenge = CameraPairingChallenge(pairingID: id, pairingCode: "482701", expiresInSeconds: 600)
            cameraPairingStatus = CameraPairingStatus(
                pairingID: id,
                status: "connected",
                expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(600)),
                connectedAt: ISO8601DateFormatter().string(from: Date()),
                device: .init(id: id, label: label, role: "publisher")
            )
            pairedCameras.insert(PairedCamera(id: id, name: label, roomID: roomID, status: "online"), at: 0)
            cameraCount = pairedCameras.count
            cameraPairingError = nil
            return
        }
        guard let session else { return }
        isCameraPairingBusy = true
        cameraPairingError = nil
        cameraPairingStatus = nil
        pendingCameraRoomID = roomID
        defer { isCameraPairingBusy = false }
        do {
            cameraPairingChallenge = try await apiClient.startCameraPairing(homeID: session.homeID, label: label)
        } catch {
            cameraPairingChallenge = nil
            cameraPairingError = (error as? LocalizedError)?.errorDescription ?? "Could not start camera pairing."
        }
    }

    func refreshCameraPairingStatus() async {
        guard !runtimeConfiguration.isDemoMode, let session, let challenge = cameraPairingChallenge else { return }
        do {
            let status = try await apiClient.cameraPairingStatus(homeID: session.homeID, pairingID: challenge.pairingID)
            cameraPairingStatus = status
            cameraPairingError = nil
            if status.status == "connected" {
                pairedCameras = try await apiClient.pairedCameras(homeID: session.homeID)
                if let roomID = pendingCameraRoomID,
                   let camera = pairedCameras.first(where: { $0.id == status.device.id }),
                   camera.roomID != roomID {
                    try await apiClient.updateCamera(
                        homeID: session.homeID,
                        cameraID: camera.id,
                        request: CameraUpdateRequest(name: camera.name, roomID: roomID)
                    )
                    pairedCameras = try await apiClient.pairedCameras(homeID: session.homeID)
                }
                cameraCount = pairedCameras.count
            }
        } catch {
            cameraPairingError = (error as? LocalizedError)?.errorDescription ?? "Could not refresh camera status."
        }
    }

    func clearCameraPairing() {
        cameraPairingChallenge = nil
        cameraPairingStatus = nil
        cameraPairingError = nil
        isCameraPairingBusy = false
        pendingCameraRoomID = nil
    }

    func updateCamera(_ camera: PairedCamera, name: String, roomID: UUID?) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            cameraPairingError = "Camera name cannot be empty."
            return false
        }
        if runtimeConfiguration.isDemoMode {
            if let index = pairedCameras.firstIndex(where: { $0.id == camera.id }) {
                pairedCameras[index] = PairedCamera(
                    id: camera.id,
                    name: trimmedName,
                    roomID: roomID,
                    status: camera.status,
                    calibrationNeeded: camera.calibrationNeeded,
                    roomplanRegistrationStatus: camera.roomplanRegistrationStatus,
                    roomplanMapID: camera.roomplanMapID
                )
            }
            cameraCount = pairedCameras.count
            return true
        }
        guard let session else {
            cameraPairingError = OneAPIError.missingSession.localizedDescription
            return false
        }
        isCameraMutating = true
        cameraPairingError = nil
        defer { isCameraMutating = false }
        do {
            try await apiClient.updateCamera(homeID: session.homeID, cameraID: camera.id, request: CameraUpdateRequest(name: trimmedName, roomID: roomID))
            pairedCameras = try await apiClient.pairedCameras(homeID: session.homeID)
            cameraCount = pairedCameras.count
            return true
        } catch {
            cameraPairingError = (error as? LocalizedError)?.errorDescription ?? "Could not update this camera."
            return false
        }
    }

    func deleteCamera(_ camera: PairedCamera) async -> Bool {
        if runtimeConfiguration.isDemoMode {
            pairedCameras.removeAll { $0.id == camera.id }
            cameraCount = pairedCameras.count
            return true
        }
        guard let session else {
            cameraPairingError = OneAPIError.missingSession.localizedDescription
            return false
        }
        isCameraMutating = true
        cameraPairingError = nil
        defer { isCameraMutating = false }
        do {
            try await apiClient.deleteCamera(homeID: session.homeID, cameraID: camera.id)
            pairedCameras.removeAll { $0.id == camera.id }
            cameraCount = pairedCameras.count
            return true
        } catch {
            cameraPairingError = (error as? LocalizedError)?.errorDescription ?? "Could not remove this camera."
            return false
        }
    }

    func refreshScene() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do {
            scene = try await apiClient.refreshScene(homeID: session.homeID)
            await refreshCameraReferenceImages(homeID: session.homeID)
            if scene.isRenderable3D {
                await loadRoomPlanModelIfAvailable()
            } else {
                roomPlanModelURL = nil
                roomPlanModelMapID = nil
                roomPlanModelError = nil
            }
        } catch {
            // Keep the last known scene if a refresh is temporarily unavailable.
            if scene == .empty { roomPlanModelError = "The home scene is not available yet." }
        }
    }

    private func refreshCameraReferenceImages(homeID: UUID) async {
        let registrations = scene.cameraRegistrations.isEmpty ? (scene.cameraRegistration.map { [$0] } ?? []) : scene.cameraRegistrations
        let available = registrations.compactMap { registration -> (UUID, String)? in
            guard registration.status == .positioned,
                  let cameraID = registration.cameraID,
                  let snapshot = registration.referenceSnapshot else { return nil }
            return (cameraID, snapshot.capturedAt ?? snapshot.downloadPath ?? "reference")
        }
        let activeIDs = Set(available.map(\.0))
        cameraReferenceImages = cameraReferenceImages.filter { activeIDs.contains($0.key) }
        cameraReferenceCaptureKeys = cameraReferenceCaptureKeys.filter { activeIDs.contains($0.key) }
        for (cameraID, captureKey) in available where cameraReferenceCaptureKeys[cameraID] != captureKey {
            do {
                let data = try await apiClient.downloadCameraReferenceSnapshot(homeID: homeID, cameraID: cameraID)
                guard !data.isEmpty else { continue }
                cameraReferenceImages[cameraID] = data
                cameraReferenceCaptureKeys[cameraID] = captureKey
            } catch {
                // A missing optional reference image must not hide the map itself.
            }
        }
    }

    func uploadRoomPlan(_ capture: RoomPlanCaptureResult, cameraID: UUID?) async -> Bool {
        do {
            let artifact = try RoomPlanArtifactBuilder.build(from: capture.room)
            let matrix = try capture.cameraToWorld.map { try RoomPlanMatrix.rowMajor($0) }
            return await uploadRoomPlanArtifact(
                artifact,
                visualSamples: capture.visualSamples,
                visualDiagnostics: capture.visualDiagnostics,
                cameraToWorld: matrix,
                trackingState: capture.trackingState,
                cameraID: cameraID
            )
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not prepare the native room scan."
            return false
        }
    }

    func uploadRoomPlanStructure(_ structure: CapturedStructure, captures: [RoomPlanCaptureResult], cameraID: UUID?) async -> Bool {
        guard let lastCapture = captures.last else {
            authError = "Capture at least one room before finishing the home scan."
            return false
        }
        do {
            let artifact = try RoomPlanArtifactBuilder.build(from: structure)
            let visualSamples = captures.flatMap(\.visualSamples)
            let diagnostics = RoomPlanVisualCaptureDiagnostics(
                samplingAttempts: captures.reduce(0) { $0 + $1.visualDiagnostics.samplingAttempts },
                missingFrameCount: captures.reduce(0) { $0 + $1.visualDiagnostics.missingFrameCount },
                imageEncodingFailureCount: captures.reduce(0) { $0 + $1.visualDiagnostics.imageEncodingFailureCount },
                invalidMatrixCount: captures.reduce(0) { $0 + $1.visualDiagnostics.invalidMatrixCount },
                capturedSampleCount: visualSamples.count,
                depthSampleCount: visualSamples.filter { $0.depthData != nil }.count,
                lastTrackingState: lastCapture.visualDiagnostics.lastTrackingState,
                estimatedAreaSquareMeters: captures.compactMap { $0.visualDiagnostics.estimatedAreaSquareMeters }.reduce(0, +),
                recommendedVisualSampleCount: captures.reduce(0) { $0 + $1.visualDiagnostics.recommendedVisualSampleCount }
            )
            let matrix = try lastCapture.cameraToWorld.map { try RoomPlanMatrix.rowMajor($0) }
            return await uploadRoomPlanArtifact(
                artifact,
                visualSamples: visualSamples,
                visualDiagnostics: diagnostics,
                cameraToWorld: matrix,
                trackingState: lastCapture.trackingState,
                cameraID: cameraID
            )
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not prepare the merged RoomPlan home scan."
            return false
        }
    }

    private func uploadRoomPlanArtifact(
        _ artifact: NativeRoomPlanArtifact,
        visualSamples: [RoomPlanVisualSample],
        visualDiagnostics: RoomPlanVisualCaptureDiagnostics,
        cameraToWorld: [[Double]]?,
        trackingState: String,
        cameraID: UUID?
    ) async -> Bool {
        guard !runtimeConfiguration.isDemoMode else {
            authError = "RoomPlan scans can only be saved while connected to the live ONE backend."
            return false
        }
        guard let session else {
            authError = "Your ONE session has expired. Sign in again before saving this LiDAR scan."
            return false
        }
        if let expiresAt = session.expiresAt, expiresAt <= Date() {
            authError = "Your ONE session has expired. Sign in again before saving this LiDAR scan."
            return false
        }
        guard RoomPlanCapability.isSupported else {
            authError = RoomPlanCaptureError.unsupportedDevice.localizedDescription
            return false
        }

        isRoomPlanUploading = true
        authError = nil
        roomPlanModelError = nil
        var uploadedMapID: UUID?
        var artifactData: Data?
        var visualLandmarkWarning: String?
        defer { isRoomPlanUploading = false }

        do {
            setRoomPlanSaveProgress(phase: "preparing", percent: 5, detail: "Preparing the RoomPlan geometry…")
            var scanMetadata = artifact.metadata
            scanMetadata.visualSamplingAttempts = visualDiagnostics.samplingAttempts
            scanMetadata.visualMissingFrameCount = visualDiagnostics.missingFrameCount
            scanMetadata.visualImageEncodingFailureCount = visualDiagnostics.imageEncodingFailureCount
            scanMetadata.visualInvalidMatrixCount = visualDiagnostics.invalidMatrixCount
            scanMetadata.visualSampleCount = visualDiagnostics.capturedSampleCount
            scanMetadata.visualDepthSampleCount = visualDiagnostics.depthSampleCount
            scanMetadata.visualLastTrackingState = visualDiagnostics.lastTrackingState
            scanMetadata.visualRecommendedSampleCount = visualDiagnostics.recommendedVisualSampleCount
            scanMetadata.visualEstimatedAreaSquareMeters = visualDiagnostics.estimatedAreaSquareMeters
            artifactData = artifact.usdzData
            setRoomPlanSaveProgress(phase: "map", percent: 12, detail: "Uploading the measured 3D map…")
            let map = try await apiClient.uploadRoomPlan(roomID: nil, scan: artifact.scan, metadata: scanMetadata)
            uploadedMapID = map.mapID
            pendingRoomPlanMapID = map.mapID
            pendingRoomPlanUSDZData = artifact.usdzData
            setRoomPlanSaveProgress(phase: "landmarks", percent: 25, detail: "Map saved. Preparing localization landmarks…")

            if !visualSamples.isEmpty {
                var visualIndexReady = false
                var receivedLandmarkResponse = false
                // Keep the captured samples as compressed Data and encode only
                // the current one- or two-frame request. Encoding all RGB and
                // LiDAR samples to Base64 up front briefly doubled the scan's
                // memory footprint and could terminate the app while saving a
                // large new-place scan.
                pendingRoomPlanVisualUpload = PendingRoomPlanVisualUpload(mapID: map.mapID, samples: visualSamples)
                let uploadResult = await uploadVisualLandmarkSamples(mapID: map.mapID, samples: visualSamples)
                receivedLandmarkResponse = uploadResult.receivedResponse
                visualIndexReady = uploadResult.ready
                if uploadResult.failedFrameCount == 0 {
                    pendingRoomPlanVisualUpload = nil
                }

                if !visualIndexReady {
                    if uploadResult.failedFrameCount > 0 {
                        visualLandmarkWarning = "The 3D map is saved, but \(uploadResult.failedFrameCount) visual views could not reach the local landmark service. Keep this screen open and retry landmark upload before scanning again."
                    } else {
                        visualLandmarkWarning = receivedLandmarkResponse
                            ? "The 3D map is saved, but the captured views did not contain enough stable visual landmarks to position the fixed camera. Try another scan with furniture, corners, artwork, or other textured surfaces in view."
                            : "The 3D map is saved, but its visual landmark index could not be uploaded. Camera positioning is not ready yet."
                    }
                }
            } else {
                visualLandmarkWarning = "The 3D map is saved, but too few RGB + camera-pose samples were captured for automatic positioning of a separate camera."
            }

            setRoomPlanSaveProgress(
                phase: "finishing",
                percent: 85,
                detail: cameraID == nil ? "Attaching the 3D model…" : "Registering the fixed-camera pose…"
            )

            if let cameraID {
                do {
                    guard let cameraToWorld else {
                        throw RoomPlanCaptureError.captureFailed("Camera tracking was unavailable at the end of the scan. Keep the camera still in its final position and scan again.")
                    }
                    _ = try await apiClient.registerRoomPlanCamera(
                        homeID: session.homeID,
                        request: RoomPlanCameraRegistrationRequest(
                            cameraID: cameraID,
                            mapID: map.mapID,
                            cameraToWorld: cameraToWorld,
                            confidence: nil,
                            trackingState: trackingState
                        )
                    )
                } catch {
                    roomPlanModelError = (error as? LocalizedError)?.errorDescription ?? "The room map was saved, but the camera position needs another setup scan."
                }
            }

            setRoomPlanSaveProgress(phase: "model", percent: 90, detail: "Attaching the 3D model…")
            let attachment = try await apiClient.uploadRoomPlanUSDZ(mapID: map.mapID, data: artifact.usdzData)
            pendingRoomPlanMapID = nil
            pendingRoomPlanUSDZData = nil
            mapUploadResult = ArtifactUploadResponse(artifactID: map.mapID, sha256: attachment.usdz?.sha256 ?? "", expiresAt: nil)
            try cacheRoomPlanModel(mapID: map.mapID, data: artifact.usdzData)
            setRoomPlanSaveProgress(phase: "refreshing", percent: 97, detail: "Refreshing the home map…")
            scene = try await apiClient.refreshScene(homeID: session.homeID)
            setRoomPlanSaveProgress(phase: "complete", percent: 100, detail: "Map and camera-localization data saved.")
            if cameraID != nil, scene.cameraRegistration?.status == .needsRescan {
                roomPlanModelError = "The 3D room map is saved, but this device's camera pose was not stable enough to register. Retry camera placement only if this iPhone is also the fixed camera."
            } else if scene.isRenderable3D {
                roomPlanModelError = visualLandmarkWarning
            } else if !scene.isRenderable3D {
                roomPlanModelError = "The uploaded scan is not ready to display yet."
            }
            return true
        } catch {
            if let uploadedMapID, let artifactData {
                pendingRoomPlanMapID = uploadedMapID
                pendingRoomPlanUSDZData = artifactData
                if let refreshed = try? await apiClient.refreshScene(homeID: session.homeID) {
                    scene = refreshed
                    roomPlanModelError = "The 3D asset could not be attached. Tap retry to upload it again."
                }
            }
            if let apiError = error as? OneAPIError,
               case let .server(status, _) = apiError,
               status == 401 {
                authError = "Your ONE session expired while saving the LiDAR scan. Sign in again, then retry the scan."
            } else {
                authError = (error as? LocalizedError)?.errorDescription ?? "Could not upload the native room scan."
            }
            let detail = (error as? LocalizedError)?.errorDescription ?? "The room scan could not be saved."
            setRoomPlanSaveProgress(
                phase: "failed",
                percent: roomPlanSaveProgress?.percent ?? 0,
                detail: "Save paused: \(detail)"
            )
            return false
        }
    }

    private func setRoomPlanSaveProgress(phase: String, percent: Int, detail: String) {
        roomPlanSaveProgress = RoomPlanSaveProgress(
            phase: phase,
            percent: min(100, max(0, percent)),
            detail: detail
        )
    }

    private func updateRoomPlanLandmarkSaveProgress(phase: String) {
        guard let progress = roomPlanVisualUploadProgress else { return }
        let ratio = progress.totalFrameCount > 0
            ? Double(progress.completedFrameCount) / Double(progress.totalFrameCount)
            : 0
        let percent = 25 + Int((ratio * 60).rounded())
        let detail: String
        switch phase {
        case "retrying": detail = "Retrying a smaller landmark batch…"
        case "failed": detail = "Landmark upload paused; the map can be retried without rescanning."
        default: detail = "Uploading localization landmarks (up to 3 batches at a time)…"
        }
        setRoomPlanSaveProgress(phase: phase, percent: percent, detail: detail)
    }

    private func updateRoomPlanVisualUploadProgress(_ update: (inout RoomPlanVisualLandmarkUploadProgress) -> Void) {
        guard var progress = roomPlanVisualUploadProgress else { return }
        update(&progress)
        roomPlanVisualUploadProgress = progress
    }

    private struct VisualLandmarkUploadResult {
        let ready: Bool
        let receivedResponse: Bool
        let failedFrameCount: Int
        let lastError: String?
    }

    private struct VisualLandmarkBatchUploadResult {
        let uploadedFrameCount: Int
        let ready: Bool
        let receivedResponse: Bool
        let failedFrameCount: Int
        let lastError: String?
    }

    private func visualLandmarkFrame(from sample: RoomPlanVisualSample) async -> RoomPlanVisualLandmarkFrameRequest {
        await Task.detached(priority: .userInitiated) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return RoomPlanVisualLandmarkFrameRequest(
                frameBase64: sample.jpegData.base64EncodedString(),
                width: sample.width,
                height: sample.height,
                depthBase64: sample.depthData?.base64EncodedString(),
                depthWidth: sample.depthWidth,
                depthHeight: sample.depthHeight,
                intrinsics: Matrix3x3Request(values: sample.intrinsics),
                cameraToWorld: sample.cameraToWorld,
                capturedAt: formatter.string(from: sample.capturedAt)
            )
        }.value
    }

    private func uploadVisualLandmarkBatch(
        mapID: UUID,
        frames: [RoomPlanVisualLandmarkFrameRequest],
        currentBatch: Int,
        batchCount: Int,
        deadline: Date
    ) async -> VisualLandmarkBatchUploadResult {
        // Keep requests comfortably below the API's 24 MB decoded-memory
        // guard. A large iPhone RGB frame plus Float32 depth can make four
        // frames unexpectedly large even though the frame count is small.
        let maximumEncodedCharacters = 8_000_000
        var queue = [frames]
        var uploadedFrameCount = 0
        var failedFrameCount = 0
        var receivedResponse = false
        var ready = false
        var lastError: String?

        while !queue.isEmpty {
            let batch = queue.removeFirst()
            if Date() >= deadline {
                let message = "No visual-landmark batch completed within four minutes. Check that the local landmark service is running, then retry."
                lastError = message
                failedFrameCount += batch.count + queue.reduce(0) { $0 + $1.count }
                updateRoomPlanVisualUploadProgress {
                    $0.phase = "failed"
                    $0.retryAttempt = 0
                    $0.lastError = message
                }
                updateRoomPlanLandmarkSaveProgress(phase: "failed")
                break
            }
            guard batch.reduce(0, { $0 + $1.frameBase64.utf8.count + ($1.depthBase64?.utf8.count ?? 0) }) <= maximumEncodedCharacters || batch.count == 1 else {
                let midpoint = batch.count / 2
                queue.insert(Array(batch[midpoint...]), at: 0)
                queue.insert(Array(batch[..<midpoint]), at: 0)
                continue
            }

            updateRoomPlanVisualUploadProgress {
                $0.currentBatch = currentBatch
                $0.batchCount = max($0.batchCount, batchCount)
                $0.phase = "uploading"
                $0.retryAttempt = 0
                $0.lastError = nil
            }
            updateRoomPlanLandmarkSaveProgress(phase: "uploading")

            var response: RoomPlanVisualLandmarksResponse?
            for attempt in 1...3 {
                guard Date() < deadline else { break }
                updateRoomPlanVisualUploadProgress { $0.retryAttempt = attempt }
                do {
                    response = try await apiClient.uploadRoomPlanVisualLandmarks(mapID: mapID, frames: batch)
                    break
                } catch {
                    lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    updateRoomPlanVisualUploadProgress {
                        $0.phase = "retrying"
                        $0.lastError = lastError
                    }
                    updateRoomPlanLandmarkSaveProgress(phase: "retrying")
                    if attempt < 3, Date() < deadline {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 750_000_000)
                    }
                }
            }

            if let response {
                receivedResponse = true
                ready = ready || response.status == "ready"
                uploadedFrameCount += batch.count
                continue
            }

            if batch.count > 1 {
                let midpoint = batch.count / 2
                queue.insert(Array(batch[midpoint...]), at: 0)
                queue.insert(Array(batch[..<midpoint]), at: 0)
                updateRoomPlanVisualUploadProgress {
                    $0.phase = "retrying"
                    $0.batchCount = max($0.batchCount, batchCount + queue.count)
                }
                updateRoomPlanLandmarkSaveProgress(phase: "retrying")
            } else {
                failedFrameCount += batch.count
                updateRoomPlanVisualUploadProgress {
                    $0.failedFrameCount = failedFrameCount
                    $0.phase = "failed"
                }
                updateRoomPlanLandmarkSaveProgress(phase: "failed")
            }
        }

        return VisualLandmarkBatchUploadResult(
            uploadedFrameCount: uploadedFrameCount,
            ready: ready,
            receivedResponse: receivedResponse,
            failedFrameCount: failedFrameCount,
            lastError: lastError
        )
    }

    private func makeVisualLandmarkBatch(
        from samples: [RoomPlanVisualSample],
        startIndex: Int,
        maximumFrames: Int,
        maximumEncodedCharacters: Int
    ) async -> (frames: [RoomPlanVisualLandmarkFrameRequest], nextIndex: Int) {
        var frames: [RoomPlanVisualLandmarkFrameRequest] = []
        frames.reserveCapacity(maximumFrames)
        var encodedCharacters = 0
        var index = startIndex

        while index < samples.count && frames.count < maximumFrames {
            let frame = await visualLandmarkFrame(from: samples[index])
            let frameCharacters = frame.frameBase64.utf8.count + (frame.depthBase64?.utf8.count ?? 0)
            if !frames.isEmpty && encodedCharacters + frameCharacters > maximumEncodedCharacters {
                break
            }
            frames.append(frame)
            encodedCharacters += frameCharacters
            index += 1
        }

        return (frames, index)
    }

    private func uploadVisualLandmarkSamples(mapID: UUID, samples: [RoomPlanVisualSample]) async -> VisualLandmarkUploadResult {
        let totalFrameCount = samples.count
        let maximumFramesPerBatch = 2
        let maximumConcurrentBatches = 3
        let maximumEncodedCharacters = 8_000_000
        let initialBatchCount = max(1, Int(ceil(Double(totalFrameCount) / Double(maximumFramesPerBatch))))
        roomPlanVisualUploadProgress = RoomPlanVisualLandmarkUploadProgress(
            mapID: mapID,
            phase: "uploading",
            completedFrameCount: 0,
            totalFrameCount: totalFrameCount,
            failedFrameCount: 0,
            currentBatch: 0,
            batchCount: initialBatchCount,
            retryAttempt: 0,
            lastError: nil
        )
        updateRoomPlanLandmarkSaveProgress(phase: "landmarks")

        var nextSampleIndex = 0
        var nextBatchNumber = 0
        var completedFrameCount = 0
        var receivedResponse = false
        var ready = false
        var failedFrameCount = 0
        var lastError: String?
        let deadline = Date().addingTimeInterval(240)

        await withTaskGroup(of: VisualLandmarkBatchUploadResult.self) { group in
            var inFlightBatches = 0

            while inFlightBatches < maximumConcurrentBatches && nextSampleIndex < totalFrameCount {
                let prepared = await makeVisualLandmarkBatch(
                    from: samples,
                    startIndex: nextSampleIndex,
                    maximumFrames: maximumFramesPerBatch,
                    maximumEncodedCharacters: maximumEncodedCharacters
                )
                guard !prepared.frames.isEmpty else { break }
                nextSampleIndex = prepared.nextIndex
                nextBatchNumber += 1
                let batchNumber = nextBatchNumber
                inFlightBatches += 1
                group.addTask { [self] in
                    await self.uploadVisualLandmarkBatch(
                        mapID: mapID,
                        frames: prepared.frames,
                        currentBatch: batchNumber,
                        batchCount: initialBatchCount,
                        deadline: deadline
                    )
                }
            }

            while inFlightBatches > 0 {
                guard let result = await group.next() else { break }
                inFlightBatches -= 1
                completedFrameCount += result.uploadedFrameCount
                receivedResponse = receivedResponse || result.receivedResponse
                ready = ready || result.ready
                lastError = result.lastError ?? lastError

                if result.failedFrameCount > 0 {
                    failedFrameCount = max(failedFrameCount, result.failedFrameCount)
                }

                updateRoomPlanVisualUploadProgress {
                    $0.completedFrameCount = min(totalFrameCount, completedFrameCount)
                    $0.failedFrameCount = failedFrameCount
                    $0.phase = result.failedFrameCount > 0 ? "failed" : "uploading"
                    $0.retryAttempt = 0
                    if let resultError = result.lastError {
                        $0.lastError = resultError
                    }
                }
                updateRoomPlanLandmarkSaveProgress(phase: result.failedFrameCount > 0 ? "failed" : "uploading")

                if failedFrameCount == 0 && nextSampleIndex < totalFrameCount {
                    let prepared = await makeVisualLandmarkBatch(
                        from: samples,
                        startIndex: nextSampleIndex,
                        maximumFrames: maximumFramesPerBatch,
                        maximumEncodedCharacters: maximumEncodedCharacters
                    )
                    if !prepared.frames.isEmpty {
                        nextSampleIndex = prepared.nextIndex
                        nextBatchNumber += 1
                        let batchNumber = nextBatchNumber
                        inFlightBatches += 1
                        group.addTask { [self] in
                            await self.uploadVisualLandmarkBatch(
                                mapID: mapID,
                                frames: prepared.frames,
                                currentBatch: batchNumber,
                                batchCount: initialBatchCount,
                                deadline: deadline
                            )
                        }
                    }
                }
            }
        }

        completedFrameCount = min(totalFrameCount, completedFrameCount)
        if completedFrameCount == totalFrameCount && failedFrameCount == 0 {
            updateRoomPlanVisualUploadProgress {
                $0.completedFrameCount = completedFrameCount
                $0.phase = ready ? "complete" : "failed"
                $0.retryAttempt = 0
            }
        } else {
            failedFrameCount = max(failedFrameCount, totalFrameCount - completedFrameCount)
            updateRoomPlanVisualUploadProgress {
                $0.completedFrameCount = completedFrameCount
                $0.failedFrameCount = failedFrameCount
                $0.phase = "failed"
                $0.retryAttempt = 0
            }
            updateRoomPlanLandmarkSaveProgress(phase: "failed")
        }

        return VisualLandmarkUploadResult(ready: ready, receivedResponse: receivedResponse, failedFrameCount: failedFrameCount, lastError: lastError)
    }

    func retryPendingRoomPlanVisualLandmarks() async {
        guard let pendingRoomPlanVisualUpload else { return }
        isRoomPlanUploading = true
        defer { isRoomPlanUploading = false }
        let result = await uploadVisualLandmarkSamples(mapID: pendingRoomPlanVisualUpload.mapID, samples: pendingRoomPlanVisualUpload.samples)
        if result.failedFrameCount == 0 {
            self.pendingRoomPlanVisualUpload = nil
            if let session, let refreshed = try? await apiClient.refreshScene(homeID: session.homeID) {
                scene = refreshed
            }
            roomPlanModelError = nil
        } else {
            roomPlanModelError = "\(result.failedFrameCount) visual views still could not reach the local landmark service. Retry again while this screen is open."
        }
    }

    func uploadARVideoRoom(_ capture: ARVideoRoomCaptureResult) async -> Bool {
        guard !runtimeConfiguration.isDemoMode else {
            authError = "Room video scans can only be saved while connected to the live ONE backend."
            return false
        }
        guard let session else {
            authError = "Your ONE session has expired. Sign in again before saving this room scan."
            return false
        }
        if let expiresAt = session.expiresAt, expiresAt <= Date() {
            authError = "Your ONE session has expired. Sign in again before saving this room scan."
            return false
        }
        guard ARVideoRoomCaptureCapability.isSupported else {
            authError = "ARKit room video capture is not supported on this device."
            return false
        }

        isRoomPlanUploading = true
        authError = nil
        roomPlanModelError = nil
        defer { isRoomPlanUploading = false }

        do {
            let map = try await apiClient.uploadARVideoRoom(scan: capture.scan)
            mapUploadResult = ArtifactUploadResponse(artifactID: map.mapID, sha256: map.usdz?.sha256 ?? "", expiresAt: nil)
            scene = try await apiClient.refreshScene(homeID: session.homeID)

            if scene.mapID == map.mapID, map.usdz?.available == true {
                do {
                    let data = try await apiClient.downloadRoomPlanUSDZ(mapID: map.mapID)
                    try cacheRoomPlanModel(mapID: map.mapID, data: data)
                    roomPlanModelError = "Approximate metric 3D generated from this iPhone's ARKit room video."
                } catch {
                    roomPlanModelError = "The room map is saved, but its generated 3D model could not be cached on this iPhone yet. Tap retry from the map to load it again."
                }
            } else {
                await loadRoomPlanModelIfAvailable()
            }
            return true
        } catch {
            if let apiError = error as? OneAPIError,
               case let .server(status, _) = apiError,
               status == 401 {
                authError = "Your ONE session expired while saving the room video scan. Sign in again, then retry."
            } else {
                authError = (error as? LocalizedError)?.errorDescription ?? "Could not build the room from this ARKit video scan."
            }
            return false
        }
    }

    func retryRoomPlanModel() async {
        if let mapID = pendingRoomPlanMapID, let data = pendingRoomPlanUSDZData {
            do {
                let attachment = try await apiClient.uploadRoomPlanUSDZ(mapID: mapID, data: data)
                pendingRoomPlanMapID = nil
                pendingRoomPlanUSDZData = nil
                mapUploadResult = ArtifactUploadResponse(artifactID: mapID, sha256: attachment.usdz?.sha256 ?? "", expiresAt: nil)
                try cacheRoomPlanModel(mapID: mapID, data: data)
                await refreshScene()
                authError = nil
                return
            } catch {
                authError = (error as? LocalizedError)?.errorDescription ?? "Could not attach the 3D asset."
            }
        }
        await refreshScene()
    }

    private func loadRoomPlanModelIfAvailable() async {
        guard scene.isRenderable3D, let mapID = scene.mapID else { return }
        if roomPlanModelMapID == mapID,
           let roomPlanModelURL,
           FileManager.default.fileExists(atPath: roomPlanModelURL.path) { return }
        roomPlanModelURL = nil
        roomPlanModelMapID = nil
        guard scene.usdz?.available == true else {
            roomPlanModelError = "3D geometry is ready, but its USDZ asset is not available yet."
            return
        }
        isRoomPlanModelLoading = true
        defer { isRoomPlanModelLoading = false }
        do {
            let data = try await apiClient.downloadRoomPlanUSDZ(mapID: mapID)
            try cacheRoomPlanModel(mapID: mapID, data: data)
            roomPlanModelError = nil
        } catch {
            roomPlanModelError = "The 3D asset could not be downloaded. Tap retry to try again."
        }
    }

    private func cacheRoomPlanModel(mapID: UUID, data: Data) throws {
        guard !data.isEmpty else { throw RoomPlanNormalizationError.exportFailed }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("one-roomplan-\(mapID.uuidString).usdz")
        try data.write(to: url, options: [.atomic])
        roomPlanModelURL = url
        roomPlanModelMapID = mapID
    }

    func createFamilyInvite(name: String, email: String?) async {
        guard !runtimeConfiguration.isDemoMode, let session else { inviteCode = "Demo invites require a live household session."; return }
        do { inviteCode = try await apiClient.createFamilyInvite(homeID: session.homeID, request: FamilyInviteRequest(displayName: name, email: email, role: .caregiver, expiresInSeconds: 86_400)) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not create the invitation." }
    }

    /// Updates one existing household member. Demo rows are synthetic and are
    /// changed locally; live mutations are sent to the backend, which remains
    /// authoritative for role and consent policy.
    func updateFamilyMember(_ memberID: UUID, accessRole: CaregiverAccessRole) async -> Bool {
        guard let existing = caregivers.first(where: { $0.id == memberID }) else {
            authError = OneAPIError.familyMemberNotFound.localizedDescription
            return false
        }
        guard !existing.isCurrentUser, session?.userID != memberID else {
            authError = OneAPIError.cannotChangeOwnAccess.localizedDescription
            return false
        }
        guard existing.role != .owner else {
            authError = OneAPIError.cannotChangeOwnerAccess.localizedDescription
            return false
        }
        guard accessRole != .owner else {
            authError = OneAPIError.cannotChangeOwnerAccess.localizedDescription
            return false
        }

        if runtimeConfiguration.isDemoMode {
            caregivers[caregivers.firstIndex(where: { $0.id == memberID })!] = CaregiverAccount(id: existing.id, name: existing.name, relationship: existing.relationship, role: accessRole, permissions: demoPermissions(for: accessRole), isCurrentUser: false)
            authError = nil
            return true
        }

        guard let session else {
            authError = OneAPIError.missingSession.localizedDescription
            return false
        }
        guard let backendRole = accessRole.backendRole else {
            authError = OneAPIError.unsupportedFamilyAccessRole(accessRole).localizedDescription
            return false
        }

        do {
            let result = try await apiClient.updateFamilyMember(homeID: session.homeID, userID: memberID, request: FamilyMemberUpdateRequest(role: backendRole))
            replaceFamilyMember(result.member, preservingCurrentUser: existing.isCurrentUser)
            authError = nil
            return true
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not update household access."
            return false
        }
    }

    /// Revokes one person's membership. Self-removal and owner removal are
    /// blocked before the request; the backend repeats these checks and also
    /// invalidates the removed member's sessions.
    func removeFamilyMember(_ memberID: UUID) async -> Bool {
        guard let existing = caregivers.first(where: { $0.id == memberID }) else {
            authError = OneAPIError.familyMemberNotFound.localizedDescription
            return false
        }
        guard !existing.isCurrentUser, session?.userID != memberID else {
            authError = OneAPIError.cannotChangeOwnAccess.localizedDescription
            return false
        }
        guard existing.role != .owner else {
            authError = OneAPIError.cannotChangeOwnerAccess.localizedDescription
            return false
        }

        if runtimeConfiguration.isDemoMode {
            removeFamilyMemberLocally(memberID)
            authError = nil
            return true
        }

        guard let session else {
            authError = OneAPIError.missingSession.localizedDescription
            return false
        }
        do {
            _ = try await apiClient.removeFamilyMember(homeID: session.homeID, userID: memberID)
            removeFamilyMemberLocally(memberID)
            authError = nil
            return true
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not remove household access."
            return false
        }
    }

    private func demoPermissions(for role: CaregiverAccessRole) -> [String] {
        switch role {
        case .owner: ["Manage people", "Manage plans", "Review events"]
        case .primaryCaregiver: ["Manage plans", "Review events"]
        case .supporter: ["Check in", "View today"]
        case .viewer: ["View today"]
        }
    }

    private func replaceFamilyMember(_ member: CaregiverAccount, preservingCurrentUser: Bool) {
        guard let index = caregivers.firstIndex(where: { $0.id == member.id }) else { return }
        caregivers[index] = CaregiverAccount(id: member.id, name: member.name, relationship: member.relationship, role: member.role, permissions: member.permissions, isCurrentUser: preservingCurrentUser || member.id == session?.userID)
    }

    private func removeFamilyMemberLocally(_ memberID: UUID) {
        caregivers.removeAll { $0.id == memberID }
    }

    private func normalizedCareRecipientField(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        return trimmed.isEmpty ? nil : trimmed
    }

    private func syncActiveCareSpaceRecipients() {
        guard let activeID = session?.homeID ?? careSpaces.first(where: \.active)?.id,
              let index = careSpaces.firstIndex(where: { $0.id == activeID }) else { return }
        let names = careRecipients.map(\.displayName)
        careSpaces[index].recipientNames = names
        careSpaces[index].recipientCount = names.count
        careSpaces[index].residentName = names.first ?? "Resident"
    }

    private func medicationErrorMessage(_ error: Error, careRecipientID: UUID?, fallback: String) -> String {
        guard let apiError = error as? OneAPIError,
              case let .server(status, message) = apiError,
              status == 403,
              message.localizedCaseInsensitiveContains("consent") || message.localizedCaseInsensitiveContains("medication") else {
            return (error as? LocalizedError)?.errorDescription ?? fallback
        }
        if let careRecipientID,
           let recipient = careRecipients.first(where: { $0.id == careRecipientID }) {
            return "Medication reminders are off for \(recipient.displayName). Open their profile and turn on Medication reminders first."
        }
        return "Medication reminders are not enabled for this person. Open their profile and turn on Medication reminders first."
    }

    func refreshMedicationReminders() async {
        guard let selectedSubjectID else {
            medicationDoses = []
            return
        }
        if runtimeConfiguration.isDemoMode {
            ensureDemoMedicationDoses(for: selectedMedicationDate, subjectID: selectedSubjectID)
            return
        }
        guard let session else { return }
        if let recipient = careRecipients.first(where: { $0.id == selectedSubjectID }), recipient.medicationRemindersEnabled == false {
            medicationDoses = []
            return
        }
        do { medicationDoses = try await apiClient.medicationReminders(homeID: session.homeID, careRecipientID: selectedSubjectID, day: selectedMedicationDate) }
        catch { authError = medicationErrorMessage(error, careRecipientID: selectedSubjectID, fallback: "Could not load medication reminders.") }
    }

    private func ensureDemoMedicationDoses(for date: Date, subjectID: UUID) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let plans = medicationPlans.filter { $0.active && $0.careRecipientID == subjectID }

        for plan in plans where demoScheduleRuns(plan.schedule, on: day) {
            let alreadyExists = medicationDoses.contains {
                $0.planID == plan.id && calendar.isDate($0.scheduledAt, inSameDayAs: day)
            }
            guard !alreadyExists else { continue }
            medicationDoses.append(MedicationDose(
                id: UUID(),
                medicationName: plan.name,
                instructions: plan.instructions,
                scheduledAt: demoScheduledDate(for: plan.schedule, on: day),
                status: .scheduled,
                assignedCaregiverName: plan.assignedCaregiverID.flatMap { caregiverID in
                    caregivers.first(where: { $0.id == caregiverID })?.name
                },
                careRecipientID: subjectID,
                planID: plan.id
            ))
        }
    }

    private func demoScheduleRuns(_ schedule: String, on date: Date) -> Bool {
        let lowercased = schedule.lowercased()
        let weekday = Calendar.current.component(.weekday, from: date)
        if lowercased.contains("weekday") { return (2...6).contains(weekday) }
        if lowercased.contains("weekend") { return weekday == 1 || weekday == 7 }

        let aliases = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let explicitDays = aliases.filter { lowercased.contains($0) }
        return explicitDays.isEmpty || explicitDays.contains(aliases[weekday - 1])
    }

    private func demoScheduledDate(for schedule: String, on day: Date) -> Date {
        let clock = schedule.split(separator: "@").last.map(String.init) ?? "08:00"
        let fields = clock.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        let hour = min(max(Int(fields.first ?? "8") ?? 8, 0), 23)
        let minute = min(max(Int(fields.dropFirst().first ?? "0") ?? 0, 0), 59)
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    func uploadCurrentMap() async {
        // This compatibility method is intentionally the legacy 2D route.
        // Native RoomPlan scans use uploadRoomPlan(_:), never this endpoint.
        guard !runtimeConfiguration.isDemoMode, session != nil else { return }
        do { mapUploadResult = try await apiClient.uploadRoomScan(roomID: scan.id, normalizedJSON: JSONEncoder.one.encode(scan), usdz: nil) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not upload the room map." }
    }

    private func applySession(_ authenticated: AuthSession) throws {
        if !runtimeConfiguration.isDemoMode {
            try sessionStore.save(JSONEncoder().encode(authenticated), for: Self.sessionKey)
            clearHomeScopedState()
        }
        session = authenticated; role = authenticated.role
        selectedTab = "overview"
        onboardingStep = 0
        onboardingConsents = Self.onboardingConsentDefaults
        hasCompletedOnboarding = (try? sessionStore.load(Self.onboardingKey(homeID: authenticated.homeID, userID: authenticated.userID))) != nil
        emailChallenge = nil
        apiClient = apiClient.authenticated(accessToken: authenticated.accessToken, homeID: authenticated.homeID)
        backendState = .connected
        Task {
            await refreshCareSpaces()
            await refreshLiveData()
        }
    }

    private func clearHomeScopedState() {
        events = []
        scan = .empty
        scene = .empty
        roomPlanModelURL = nil
        roomPlanModelMapID = nil
        roomPlanModelError = nil
        pendingRoomPlanMapID = nil
        pendingRoomPlanUSDZData = nil
        mapUploadResult = nil
        consents = []
        consentError = nil
        isConsentsLoading = false
        isConsentMutating = false
        caregivers = []
        careRecipients = []
        selectedSubjectID = nil
        selectedSubjectName = "Everyone"
        medicationDoses = []
        medicationPlans = []
        pairedCameras = []
        cameraCount = 0
        clearCameraPairing()
        assistantMessages = []
        familyAssistantMessages = []
        lastDataRequest = nil
    }

    @discardableResult
    func completeOnboarding() -> Bool {
        guard let session else {
            authError = "Your household session is no longer available. Please sign in again."
            return false
        }
        do {
            try sessionStore.save(Data("complete".utf8), for: Self.onboardingKey(homeID: session.homeID, userID: session.userID))
            hasCompletedOnboarding = true
            onboardingStep = 4
            authError = nil
            return true
        } catch {
            authError = "Your choices could not be saved on this device. Please try again."
            return false
        }
    }

    func recordOnboardingConsent(for label: String, granted: Bool) async -> Bool {
        guard let mapping = Self.onboardingConsentMapping.first(where: { $0.label == label }) else {
            authError = "That consent choice is not available."
            return false
        }

        onboardingConsents[label] = granted
        if runtimeConfiguration.isDemoMode {
            upsertOnboardingConsent(label: label, granted: granted)
            return true
        }

        guard let session else {
            authError = OneAPIError.missingSession.localizedDescription
            return false
        }

        do {
            try await apiClient.recordConsent(
                homeID: session.homeID,
                request: ConsentRequest(purpose: mapping.purpose, policyVersion: "2026-09", granted: granted)
            )
            upsertOnboardingConsent(label: label, granted: granted)
            authError = nil
            return true
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not save this choice."
            return false
        }
    }

    func recordOnboardingConsents() async -> Bool {
        for mapping in Self.onboardingConsentMapping {
            guard await recordOnboardingConsent(for: mapping.label, granted: onboardingConsents[mapping.label] ?? false) else {
                return false
            }
        }
        return true
    }

    private func upsertOnboardingConsent(label: String, granted: Bool) {
        let now = Date()
        let mapping = Self.onboardingConsentMapping.first(where: { $0.label == label || $0.purpose == label })
        if let index = consents.firstIndex(where: {
            ($0.purpose == label || $0.purpose == mapping?.purpose)
                && $0.careRecipientID == nil
                && ($0.subjectUserID == nil || $0.subjectUserID == session?.userID)
        }) {
            let existing = consents[index]
            consents[index] = ConsentRecord(
                id: existing.id,
                purpose: label,
                enabled: granted,
                policyVersion: "2026-09",
                updatedAt: now,
                subjectUserID: existing.subjectUserID ?? session?.userID,
                careRecipientID: nil
            )
        } else {
            consents.append(ConsentRecord(
                id: UUID(),
                purpose: label,
                enabled: granted,
                policyVersion: "2026-09",
                updatedAt: now,
                subjectUserID: session?.userID,
                careRecipientID: nil
            ))
        }
    }

    func logout() async {
        defer {
            try? sessionStore.delete(Self.sessionKey)
            session = nil
            authError = nil
            onboardingStep = 0
            onboardingConsents = Self.onboardingConsentDefaults
            hasCompletedOnboarding = false
            emailChallenge = nil
            careSpaces = []
            careSpaceError = nil
            switchingCareSpaceID = nil
            isCareSpaceMutating = false
            apiClient = HTTPOneAPIClient(configuration: runtimeConfiguration)
            backendState = runtimeConfiguration.isDemoMode ? .demo : .unavailable
            if !runtimeConfiguration.isDemoMode {
                clearHomeScopedState()
            }
        }
        guard session != nil else { return }
        do { try await apiClient.logout() } catch { /* Local credentials are cleared even if the network is unavailable. */ }
    }
}

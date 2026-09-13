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
        ("Family sharing", "family_mode"),
        ("Medication reminders", "medication_management")
    ]
    private static let onboardingConsentDefaults = [
        "Daily check-in support": false,
        "Room and camera data": false,
        "Medication reminders": false,
        "Family sharing": false
    ]
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
    var isRoomPlanModelLoading = false
    var roomPlanModelError: String?
    var careRecipients: [CareRecipient] = []
    var pairedCameras: [PairedCamera] = []
    var cameraCount = 0
    private var pendingRoomPlanMapID: UUID?
    private var pendingRoomPlanUSDZData: Data?
    private var roomPlanModelMapID: UUID?
    private let sessionStore: any SessionKeyStore
    let runtimeConfiguration: RuntimeConfiguration

    init(events: [ObservedEvent], scan: RoomScan, consents: [ConsentRecord], caregivers: [CaregiverAccount] = [], medicationDoses: [MedicationDose] = [], medicationPlans: [MedicationPlan] = [], apiClient: any OneAPIClient = MockOneAPIClient(), backendState: BackendConnectionState = .demo, session: AuthSession? = nil, sessionStore: any SessionKeyStore = KeychainSessionStore(), runtimeConfiguration: RuntimeConfiguration = RuntimeConfiguration()) {
        self.events = events; self.scan = scan; self.consents = consents
        self.caregivers = caregivers; self.medicationDoses = medicationDoses; self.medicationPlans = medicationPlans; self.apiClient = apiClient; self.backendState = backendState; self.session = session; self.sessionStore = sessionStore; self.runtimeConfiguration = runtimeConfiguration
        self.careRecipients = caregivers.map { CareRecipient(id: $0.id, name: $0.name, relationship: $0.relationship) }
    }

    static func configured() -> AppStore {
#if DEBUG
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
        return AppStore(events: events, scan: scan, consents: consents, caregivers: caregivers, medicationDoses: medicationDoses, runtimeConfiguration: RuntimeConfiguration(info: [:]))
    }

    func toggleConsent(_ consent: ConsentRecord) {
        guard let index = consents.firstIndex(where: { $0.id == consent.id }) else { return }
        consents[index].enabled.toggle()
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
    var requiresOnboarding: Bool {
        !runtimeConfiguration.isDemoMode && session != nil && !hasCompletedOnboarding
    }

    func login(pairingCode: String) async {
        authError = nil
        do {
            let authenticated = try await apiClient.completePairing(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
            applySession(authenticated)
        } catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not sign in." }
    }

    func requestEmailCode(email: String, purpose: String, displayName: String? = nil, homeName: String = "ONE Home") async -> String? {
        authError = nil
        emailChallenge = nil
        do {
            emailChallenge = try await apiClient.requestEmailCode(EmailAuthRequest(email: email.trimmingCharacters(in: .whitespacesAndNewlines), purpose: purpose, displayName: displayName, homeName: homeName, role: .caregiver))
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

    func acceptFamilyInvite(code: String, displayName: String?, email: String? = nil) async {
        authError = nil
        do { applySession(try await apiClient.acceptFamilyInvite(FamilyInviteAcceptRequest(code: code, displayName: displayName, email: email))) }
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

    func refreshLiveData() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do { events = try await apiClient.events(homeID: session.homeID) } catch { events = [] }
        do {
            let objects = try await apiClient.roomObjects(homeID: session.homeID)
            scan = RoomScan(id: scan.id, schemaVersion: scan.schemaVersion, capturedAt: scan.capturedAt, units: scan.units, upAxis: scan.upAxis, objects: objects, zones: scan.zones, artifactHash: scan.artifactHash, exportedUSDZName: scan.exportedUSDZName)
        } catch { scan = .empty }
        do {
            pairedCameras = try await apiClient.pairedCameras(homeID: session.homeID)
            cameraCount = pairedCameras.count
        } catch {
            pairedCameras = []
            cameraCount = 0
        }
        await refreshScene()
        await refreshFamilyData()
    }

    func refreshScene() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do {
            scene = try await apiClient.refreshScene(homeID: session.homeID)
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

    func uploadRoomPlan(_ capture: RoomPlanCaptureResult, cameraID: UUID?) async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        guard RoomPlanCapability.isSupported else {
            authError = RoomPlanCaptureError.unsupportedDevice.localizedDescription
            return
        }

        isRoomPlanUploading = true
        authError = nil
        roomPlanModelError = nil
        var uploadedMapID: UUID?
        var artifactData: Data?
        defer { isRoomPlanUploading = false }

        do {
            let artifact = try RoomPlanArtifactBuilder.build(from: capture.room)
            artifactData = artifact.usdzData
            let map = try await apiClient.uploadRoomPlan(roomID: nil, scan: artifact.scan, metadata: artifact.metadata)
            uploadedMapID = map.mapID
            pendingRoomPlanMapID = map.mapID
            pendingRoomPlanUSDZData = artifact.usdzData

            if let cameraID {
                do {
                    guard let cameraToWorld = capture.cameraToWorld else {
                        throw RoomPlanCaptureError.captureFailed("Camera tracking was unavailable at the end of the scan. Keep the camera still in its final position and scan again.")
                    }
                    let matrix = try RoomPlanMatrix.rowMajor(cameraToWorld)
                    _ = try await apiClient.registerRoomPlanCamera(
                        homeID: session.homeID,
                        request: RoomPlanCameraRegistrationRequest(
                            cameraID: cameraID,
                            mapID: map.mapID,
                            cameraToWorld: matrix,
                            confidence: nil,
                            trackingState: capture.trackingState
                        )
                    )
                } catch {
                    roomPlanModelError = (error as? LocalizedError)?.errorDescription ?? "The room map was saved, but the camera position needs another setup scan."
                }
            }

            let attachment = try await apiClient.uploadRoomPlanUSDZ(mapID: map.mapID, data: artifact.usdzData)
            pendingRoomPlanMapID = nil
            pendingRoomPlanUSDZData = nil
            mapUploadResult = ArtifactUploadResponse(artifactID: map.mapID, sha256: attachment.usdz?.sha256 ?? "", expiresAt: nil)
            try cacheRoomPlanModel(mapID: map.mapID, data: artifact.usdzData)
            scene = try await apiClient.refreshScene(homeID: session.homeID)
            if scene.cameraRegistration?.status == .needsRescan {
                roomPlanModelError = "The 3D room map is saved. Keep this device still in the camera's final position and run one more setup scan to position it."
            } else if scene.isRenderable3D {
                roomPlanModelError = nil
            } else if !scene.isRenderable3D {
                roomPlanModelError = "The uploaded scan is not ready to display yet."
            }
        } catch {
            if let uploadedMapID, let artifactData {
                pendingRoomPlanMapID = uploadedMapID
                pendingRoomPlanUSDZData = artifactData
                if let refreshed = try? await apiClient.refreshScene(homeID: session.homeID) {
                    scene = refreshed
                    roomPlanModelError = "The 3D asset could not be attached. Tap retry to upload it again."
                }
            }
            authError = (error as? LocalizedError)?.errorDescription ?? "Could not upload the native room scan."
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
        careRecipients = caregivers.filter { !$0.isCurrentUser }.map { CareRecipient(id: $0.id, name: $0.name, relationship: $0.relationship) }
    }

    private func removeFamilyMemberLocally(_ memberID: UUID) {
        caregivers.removeAll { $0.id == memberID }
        careRecipients.removeAll { $0.id == memberID }
        if selectedSubjectID == memberID {
            selectedSubjectID = nil
            selectedSubjectName = "Everyone"
        }
    }

    func refreshMedicationReminders() async {
        guard !runtimeConfiguration.isDemoMode, let session else { return }
        do { medicationDoses = try await apiClient.medicationReminders(homeID: session.homeID, subjectUserID: selectedSubjectID, day: selectedMedicationDate) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not load medication reminders." }
    }

    func uploadCurrentMap() async {
        // This compatibility method is intentionally the legacy 2D route.
        // Native RoomPlan scans use uploadRoomPlan(_:), never this endpoint.
        guard !runtimeConfiguration.isDemoMode, session != nil else { return }
        do { mapUploadResult = try await apiClient.uploadRoomScan(roomID: scan.id, normalizedJSON: JSONEncoder.one.encode(scan), usdz: nil) }
        catch { authError = (error as? LocalizedError)?.errorDescription ?? "Could not upload the room map." }
    }

    private func applySession(_ authenticated: AuthSession) {
        if !runtimeConfiguration.isDemoMode {
            try? sessionStore.save(JSONEncoder().encode(authenticated), for: Self.sessionKey)
            events = []
            scan = .empty
            scene = .empty
            roomPlanModelURL = nil
            roomPlanModelMapID = nil
            roomPlanModelError = nil
            pendingRoomPlanMapID = nil
            pendingRoomPlanUSDZData = nil
            consents = []
            caregivers = []
            careRecipients = []
            medicationDoses = []
            medicationPlans = []
            pairedCameras = []
            cameraCount = 0
            assistantMessages = []
        }
        session = authenticated; role = authenticated.role
        onboardingStep = 0
        onboardingConsents = Self.onboardingConsentDefaults
        hasCompletedOnboarding = (try? sessionStore.load(Self.onboardingKey(homeID: authenticated.homeID, userID: authenticated.userID))) != nil
        emailChallenge = nil
        apiClient = HTTPOneAPIClient(configuration: runtimeConfiguration, accessToken: authenticated.accessToken, homeID: authenticated.homeID)
        backendState = .connected
        Task { await refreshLiveData() }
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
        if let index = consents.firstIndex(where: { $0.purpose == label }) {
            let existing = consents[index]
            consents[index] = ConsentRecord(id: existing.id, purpose: label, enabled: granted, policyVersion: "2026-09", updatedAt: now)
        } else {
            consents.append(ConsentRecord(id: UUID(), purpose: label, enabled: granted, policyVersion: "2026-09", updatedAt: now))
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
            apiClient = HTTPOneAPIClient(configuration: runtimeConfiguration)
            backendState = runtimeConfiguration.isDemoMode ? .demo : .unavailable
            if !runtimeConfiguration.isDemoMode {
                events = []
                scan = .empty
                scene = .empty
                roomPlanModelURL = nil
                roomPlanModelMapID = nil
                roomPlanModelError = nil
                pendingRoomPlanMapID = nil
                pendingRoomPlanUSDZData = nil
                consents = []
                caregivers = []
                careRecipients = []
                medicationDoses = []
                medicationPlans = []
                pairedCameras = []
                cameraCount = 0
                assistantMessages = []
            }
        }
        guard session != nil else { return }
        do { try await apiClient.logout() } catch { /* Local credentials are cleared even if the network is unavailable. */ }
    }
}

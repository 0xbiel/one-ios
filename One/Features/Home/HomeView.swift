import Foundation
import SwiftUI

struct CaregiverShell: View {
    @Bindable var store: AppStore
    var body: some View {
        Group {
            if store.selectedTab == "map" {
                MapView(store: store)
            } else {
                TabView(selection: $store.selectedTab) {
                    HomeView(store: store).tabItem { Label("Home", systemImage: "house.fill") }.tag("overview")
                    Color.clear.tabItem { Label("Map", systemImage: "map.fill") }.tag("map")
                    FamilyView(store: store).tabItem { Label("Family", systemImage: "person.2.fill") }.tag("family")
                    CaregiverAssistantView(store: store).tabItem { Label("Assistant", systemImage: "sparkles") }.tag("assistant")
                    SettingsView(store: store).tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("settings")
                }
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.regularMaterial, for: .tabBar)
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
    }
}

struct ResidentShell: View {
    @Bindable var store: AppStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            ResidentHomeView(store: store).tabItem { Label("Today", systemImage: "sun.max.fill") }.tag("overview")
            AssistantView(store: store).tabItem { Label("Assistant", systemImage: "waveform") }.tag("assistant")
            SettingsView(store: store).tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("settings")
        }.toolbarBackground(.visible, for: .tabBar).toolbarBackground(.regularMaterial, for: .tabBar)
    }
}

struct HomeView: View {
    @Bindable var store: AppStore
    @State private var showCameraSetup = false
    @State private var showCareSpaces = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    CareSpaceContextButton(space: store.activeCareSpace, isLoading: store.isCareSpacesLoading) {
                        showCareSpaces = true
                    }
                    todayCard
                    homeAtGlance
                    recentEvents
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .refreshable {
                await store.refreshCareSpaces()
                await store.refreshFamilyData()
                await store.refreshLiveData()
            }
            .background(OneTheme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 88) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showCareSpaces) {
            CareSpaceSwitcherView(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCameraSetup) {
            CameraManagerSheet(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if store.careSpaces.isEmpty { await store.refreshCareSpaces() }
            await store.refreshFamilyData()
            await store.refreshLiveData()
        }
#if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-one-show-care-spaces")
                || ProcessInfo.processInfo.arguments.contains("-one-show-care-space-create") {
                showCareSpaces = true
            }
        }
#endif
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                    .foregroundStyle(OneTheme.ink)
                if let person = selectedPersonName {
                    Text("Here’s what matters for \(person) today.")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            }
            Spacer(minLength: 12)
            OneBrandMark(compact: true)
        }
    }

    private var greeting: String {
        guard let fullName = store.currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty else {
            return "Welcome back"
        }
        return "Welcome back, \(fullName.split(separator: " ").first.map(String.init) ?? fullName)"
    }

    private var selectedPersonName: String? {
        if store.selectedSubjectName != "Everyone" { return store.selectedSubjectName }
        return store.careRecipients.first?.displayName
    }

    private var todayCard: some View {
        SurfaceCard(radius: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    sectionHeading("TODAY", selectedPersonName ?? "Care overview")
                    Spacer()
                    if store.isMedicationLoading { ProgressView().controlSize(.small) }
                }

                if let dose = nextDose {
                    HStack(spacing: 12) {
                        Image(systemName: dose.status == .acknowledged ? "checkmark.circle.fill" : "pills.fill")
                            .font(.title2)
                            .foregroundStyle(dose.status == .acknowledged ? OneTheme.mint : OneTheme.accentBlue)
                            .frame(width: 42, height: 42)
                            .background((dose.status == .acknowledged ? OneTheme.mint : OneTheme.accentBlue).opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dose.medicationName).font(.headline)
                            Text(dose.status == .acknowledged ? completionText(for: dose) : "Due \(dose.scheduledAt.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                        }
                        Spacer()
                    }
                } else {
                    Label("Nothing scheduled right now", systemImage: "checkmark.circle")
                        .font(.headline)
                        .foregroundStyle(OneTheme.secondaryInk)
                }

                HStack(spacing: 10) {
                    Label("\(store.events.count) events", systemImage: "bell")
                    if let checkIn = store.events.first(where: { $0.kind == .checkIn }) {
                        Label(checkIn.timestamp.formatted(date: .omitted, time: .shortened), systemImage: "checkmark.bubble")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(OneTheme.secondaryInk)

                Button {
                    store.selectedTab = "family"
                } label: {
                    HStack {
                        Text("Open today’s plan").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(OneTheme.accentBlue)
            }
            .padding(18)
        }
    }

    private var nextDose: MedicationDose? {
        store.medicationDoses.first(where: { $0.status == .scheduled || $0.status == .needsConfirmation }) ?? store.medicationDoses.first
    }

    private func completionText(for dose: MedicationDose) -> String {
        var parts = ["Done"]
        if let marker = dose.markedByName { parts.append("by \(marker)") }
        if let markedAt = dose.markedAt { parts.append(markedAt.formatted(date: .omitted, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    private var hasOnlineCamera: Bool { store.pairedCameras.contains { $0.status == "online" } }

    private var homeAtGlance: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("HOME", "At a glance")
            HStack(spacing: 12) {
                Button { store.selectedTab = "map" } label: {
                    glanceCard(
                        title: "Map",
                        detail: store.scene.isRenderable3D ? "3D home ready" : (store.scan.objects.isEmpty ? "Set up your home" : "\(store.scan.objects.count) mapped objects"),
                        symbol: "map.fill",
                        status: store.scene.isRenderable3D ? OneTheme.mint : OneTheme.accentBlue
                    )
                }
                .buttonStyle(.plain)

                Button { showCameraSetup = true } label: {
                    glanceCard(
                        title: "Cameras",
                        detail: store.cameraCount == 0 ? "Pair a camera" : "\(store.cameraCount) paired · \(hasOnlineCamera ? "online" : "offline")",
                        symbol: hasOnlineCamera ? "video.fill" : "video.badge.ellipsis",
                        status: hasOnlineCamera ? OneTheme.mint : OneTheme.amber
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func glanceCard(title: String, detail: String, symbol: String, status: Color) -> some View {
        SurfaceCard(radius: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol).font(.title2).foregroundStyle(OneTheme.accentBlue)
                    Spacer()
                    Circle().fill(status).frame(width: 9, height: 9)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(OneTheme.ink)
                    Text(detail).font(.caption).foregroundStyle(OneTheme.secondaryInk).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(16)
        }
    }

    private var recentEvents: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                sectionHeading("RECENT", "Events")
                Spacer()
                NavigationLink("See all") { EventsView(store: store) }
                    .font(.subheadline.weight(.semibold))
            }
            if store.events.isEmpty {
                SurfaceCard(radius: 28) {
                    Label("No recent events", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.secondaryInk)
                        .padding(18)
                }
            } else {
                SurfaceCard(radius: 28) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.events.prefix(3))) { event in
                            NavigationLink { EventDetailView(event: event) } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                            if event.id != store.events.prefix(3).last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func sectionHeading(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(OneTheme.secondaryInk)
            Text(title).font(.title2.weight(.bold)).tracking(-0.5).foregroundStyle(OneTheme.ink)
        }
    }
}

private struct CameraManagerSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showPairing = false
    @State private var editingCamera: PairedCamera?
    @State private var cameraToDelete: PairedCamera?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.pairedCameras.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No cameras yet", systemImage: "video.badge.plus")
                                .font(.headline)
                                .foregroundStyle(OneTheme.ink)
                            Text("Pair a phone, Mac, or browser camera and choose which room it belongs to.")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                            Button("Add camera") { showPairing = true }
                                .buttonStyle(.borderedProminent)
                                .tint(OneTheme.accentBlue)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(store.pairedCameras) { camera in
                            Button {
                                editingCamera = camera
                            } label: {
                                CameraManagerRow(camera: camera, roomName: roomName(for: camera.roomID))
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    cameraToDelete = camera
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Connected cameras")
                } footer: {
                    if !store.pairedCameras.isEmpty {
                        Text("Tap a camera to rename it or move it to another room. Swipe left to remove it.")
                    }
                }

                if let error = store.cameraPairingError, !error.isEmpty {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.amber)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(OneTheme.canvas.ignoresSafeArea())
            .navigationTitle("Cameras")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPairing = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add camera")
                }
            }
            .task { await store.refreshCameraConfiguration() }
            .sheet(isPresented: $showPairing, onDismiss: {
                Task { await store.refreshCameraConfiguration() }
            }) {
                CameraPairingSheet(store: store)
            }
            .sheet(item: $editingCamera) { camera in
                CameraEditorSheet(store: store, camera: camera)
            }
            .confirmationDialog("Remove this camera?", isPresented: $showDeleteConfirmation) {
                if let cameraToDelete {
                    Button("Remove camera", role: .destructive) {
                        let camera = cameraToDelete
                        self.cameraToDelete = nil
                        Task { _ = await store.deleteCamera(camera) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(cameraToDelete.map { "Remove \($0.name) from this care space? The camera will need to be paired again before it can reconnect." } ?? "This camera will be disconnected from the care space.")
            }
        }
    }

    private func roomName(for id: UUID?) -> String {
        guard let id else { return "No room assigned" }
        return store.cameraRooms.first(where: { $0.id == id })?.name ?? "Assigned room"
    }
}

private struct CameraManagerRow: View {
    let camera: PairedCamera
    let roomName: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: camera.status == "online" ? "video.fill" : "video.slash.fill")
                .font(.headline)
                .foregroundStyle(camera.status == "online" ? OneTheme.mint : OneTheme.secondaryInk)
                .frame(width: 40, height: 40)
                .background((camera.status == "online" ? OneTheme.mint : OneTheme.secondaryInk).opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(camera.name)
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)
                Text(roomName)
                    .font(.subheadline)
                    .foregroundStyle(OneTheme.secondaryInk)
                if camera.calibrationNeeded {
                    Label("Calibration needed", systemImage: "scope")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(OneTheme.amber)
                }
            }
            Spacer(minLength: 8)
            Text(camera.status.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(camera.status == "online" ? OneTheme.mint : OneTheme.secondaryInk)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(OneTheme.secondaryInk.opacity(0.6))
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct CameraEditorSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let camera: PairedCamera
    @State private var name: String
    @State private var roomID: UUID?
    @State private var showDeleteConfirmation = false
    @State private var showCalibration = false

    init(store: AppStore, camera: PairedCamera) {
        self.store = store
        self.camera = camera
        _name = State(initialValue: camera.name)
        _roomID = State(initialValue: camera.roomID)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !store.isCameraMutating
            && (name.trimmingCharacters(in: .whitespacesAndNewlines) != camera.name || roomID != camera.roomID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Camera") {
                    TextField("Camera name", text: $name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: name) { _, value in if value.count > 120 { name = String(value.prefix(120)) } }
                    Picker("Room", selection: $roomID) {
                        Text("No room assigned").tag(Optional<UUID>.none)
                        ForEach(store.cameraRooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                }

                Section {
                    Label(camera.status.capitalized, systemImage: camera.status == "online" ? "checkmark.circle.fill" : "wifi.slash")
                        .foregroundStyle(camera.status == "online" ? OneTheme.mint : OneTheme.secondaryInk)
                    if camera.roomplanMapID != nil {
                        HStack {
                            Label(
                                camera.calibrationNeeded ? "Calibration needed" : "Camera positioned",
                                systemImage: camera.calibrationNeeded ? "scope" : "camera.viewfinder"
                            )
                            .foregroundStyle(camera.calibrationNeeded ? OneTheme.amber : OneTheme.accentBlue)
                            Spacer()
                            Button(camera.calibrationNeeded ? "Calibrate" : "Recalibrate") {
                                showCalibration = true
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Label("Scan the room with LiDAR before positioning this camera.", systemImage: "viewfinder")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                    Text("Changing the room or camera details can require camera positioning to be refreshed on the map.")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
                }

                if let error = store.cameraPairingError, !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }

                Section {
                    Button("Remove camera", role: .destructive) { showDeleteConfirmation = true }
                        .disabled(store.isCameraMutating)
                } footer: {
                    Text("Removing a camera revokes its connection. Pair it again if you want to use it later.")
                }
            }
            .navigationTitle("Edit camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isCameraMutating ? "Saving…" : "Save") {
                        Task {
                            if await store.updateCamera(camera, name: name, roomID: roomID) { dismiss() }
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Remove this camera?", isPresented: $showDeleteConfirmation) {
                Button("Remove camera", role: .destructive) {
                    Task {
                        if await store.deleteCamera(camera) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $showCalibration) {
                CameraCalibrationSheet(store: store, camera: camera)
            }
        }
    }
}

struct CameraCalibrationSheet: View {
    @Bindable var store: AppStore
    let camera: PairedCamera
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var calibration: RoomPlanCalibrationSession?
    @State private var isWorking = false
    @State private var manualMode = false
    @State private var manualPoint: SIMD2<Double>?
    @State private var manualHeight = 1.25
    @State private var manualYaw = 0.0
    @State private var saved = false

    private var scan: RoomPlanNormalizedScan? { store.scene.canonicalGeometry ?? store.scene.geometry }
    private var currentTarget: RoomPlanCalibrationTarget? {
        guard let calibration else { return nil }
        return calibration.targets.first(where: { $0.index == calibration.currentTargetIndex })
    }
    private var proposalPoint: SIMD2<Double>? {
        guard let matrix = calibration?.proposal?.cameraToWorld,
              matrix.count == 4,
              matrix[0].count == 4,
              matrix[2].count == 4 else { return nil }
        return SIMD2(matrix[0][3], matrix[2][3])
    }
    private var defaultMapPoint: SIMD2<Double> {
        let points = scan?.floors.flatMap { floor -> [SIMD2<Double>] in
            if floor.vertices.count >= 3 {
                return floor.vertices.map { SIMD2($0.x, $0.z) }
            }
            let halfX = floor.dimensions.x / 2
            let halfZ = floor.dimensions.z / 2
            return [
                SIMD2(floor.center.x - halfX, floor.center.z - halfZ),
                SIMD2(floor.center.x + halfX, floor.center.z - halfZ),
                SIMD2(floor.center.x + halfX, floor.center.z + halfZ),
                SIMD2(floor.center.x - halfX, floor.center.z + halfZ),
            ]
        } ?? []
        guard !points.isEmpty else { return SIMD2(0, 0) }
        return SIMD2(
            points.reduce(0.0) { $0 + $1.x } / Double(points.count),
            points.reduce(0.0) { $0 + $1.y } / Double(points.count)
        )
    }
    private var floorY: Double { scan?.floors.first?.center.y ?? 0 }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let contentWidth = min(max(proxy.size.width - 40, 1), 560)
                VStack(spacing: 0) {
                    header
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity)
                    ScrollView(showsIndicators: false) {
                        content
                            .frame(width: contentWidth, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 22)
                            .padding(.bottom, 22)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: calibration?.status)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    footer
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(OneTheme.canvas.opacity(0.98).ignoresSafeArea(edges: .horizontal))
                }
            }
            .background(OneBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(isWorking)
        .task {
            if store.scene.hasReadyUSDZ, store.roomPlanModelURL == nil {
                await store.retryRoomPlanModel()
            }
        }
        .task(id: calibration?.sessionID) {
            guard calibration != nil else { return }
            while !Task.isCancelled && !saved {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled, !saved else { break }
                if let refreshed = await store.refreshRoomPlanCalibration(for: camera) {
                    calibration = refreshed
                    if refreshed.status == .review, manualPoint == nil {
                        manualPoint = proposalPoint ?? defaultMapPoint
                    }
                }
            }
        }
        .onDisappear {
            guard calibration != nil, !saved else { return }
            Task { await store.cancelRoomPlanCalibration(for: camera) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            OneBrandMark(compact: true)
            Spacer()
            Text("CAMERA CALIBRATION")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(OneTheme.secondaryInk)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(OneTheme.surface, in: Circle())
                    .overlay { Circle().stroke(OneTheme.secondaryInk.opacity(0.14), lineWidth: 0.75) }
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityLabel("Close camera calibration")
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private var content: some View {
        if saved {
            VStack(alignment: .leading, spacing: 20) {
                title(eyebrow: "POSITION SAVED", title: "The fixed camera is calibrated.", body: "ONE will use this reviewed position for RoomPlan projections while the camera stays in the same physical place.")
                SurfaceCard(radius: 24) {
                    Label("Camera positioned in the RoomPlan map", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(OneTheme.accentBlue)
                        .padding(18)
                }
            }
        } else if calibration == nil {
            VStack(alignment: .leading, spacing: 20) {
                title(eyebrow: "GUIDED SETUP", title: "Walk four points. Keep the room camera still.", body: "This iPhone guides you to known LiDAR floor positions. The paired fixed camera captures the calibration frames itself, so the pose matches the camera that will actually remain in the room.")
                SurfaceCard(radius: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        requirement("Leave \(camera.name) in its final fixed position", symbol: "camera.fill")
                        requirement("Keep its browser camera preview open", symbol: "macbook.and.iphone")
                        requirement("Stand briefly on each highlighted floor point", symbol: "figure.stand")
                        requirement("Other people may stay in frame", symbol: "person.2.fill")
                    }
                    .padding(18)
                }
                Text("Calibration images are held only for this short session and are not saved as room media.")
                    .font(.footnote)
                    .foregroundStyle(OneTheme.secondaryInk)
            }
        } else if calibration?.status == .review, !manualMode {
            VStack(alignment: .leading, spacing: 18) {
                title(eyebrow: "REVIEW", title: "Check the camera placement.", body: "The dark camera marker is ONE’s proposed fixed-camera position. Save it only if it matches where the camera really is.")
                CameraCalibrationFloorMap(
                    scan: scan,
                    targets: calibration?.targets ?? [],
                    cameraPoint: proposalPoint,
                    selection: nil,
                    onSelect: nil
                )
                .frame(height: 320)
                if let confidence = calibration?.proposal?.confidence {
                    Label("Automatic placement confidence \(Int((confidence * 100).rounded()))%", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                Button {
                    manualPoint = proposalPoint ?? defaultMapPoint
                    manualMode = true
                } label: {
                    Label("Position it manually instead", systemImage: "hand.tap.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        } else if manualMode, let calibration {
            VStack(alignment: .leading, spacing: 18) {
                title(eyebrow: "MANUAL POSITION", title: "Tap where the camera really is.", body: "Place the marker on the floor plan, then set its mounting height and viewing direction before saving.")
                CameraCalibrationFloorMap(
                    scan: scan,
                    targets: calibration.targets,
                    cameraPoint: nil,
                    selection: manualPoint,
                    onSelect: { manualPoint = $0 }
                )
                .frame(height: 320)
                SurfaceCard(radius: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Height").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.2f m", manualHeight)).font(.subheadline.monospacedDigit())
                        }
                        Slider(value: $manualHeight, in: 0.4...3.0, step: 0.05)
                        HStack {
                            Text("Direction").font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(Int(manualYaw.rounded()))°").font(.subheadline.monospacedDigit())
                        }
                        Slider(value: $manualYaw, in: 0...359, step: 1)
                    }
                    .padding(18)
                }
                Button("Back to automatic proposal") { manualMode = false }
                    .font(.subheadline.weight(.semibold))
            }
        } else if let calibration, calibration.status == .failed || calibration.status == .expired {
            VStack(alignment: .leading, spacing: 18) {
                title(eyebrow: "TRY AGAIN", title: "The camera position needs another pass.", body: calibration.error ?? "The temporary calibration session expired or did not produce a stable pose.")
                SurfaceCard(radius: 22) {
                    Label("The existing camera position was not replaced.", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.secondaryInk)
                        .padding(18)
                }
            }
        } else if let calibration {
            VStack(alignment: .leading, spacing: 18) {
                let number = min(calibration.currentTargetIndex + 1, calibration.targets.count)
                title(
                    eyebrow: calibration.status == .solving ? "SOLVING" : "POINT \(number) OF \(calibration.targets.count)",
                    title: calibration.status == .solving ? "Finding the fixed camera in 3D." : "Stand on the highlighted point.",
                    body: calibration.status == .captureRequested
                        ? "Stay on the point for a moment. The fixed camera is capturing two short frames now."
                        : calibration.status == .solving
                            ? "All four points are captured. ONE is matching them with the RoomPlan landmark index."
                            : "Move to the amber marker, then tell ONE when you are standing there. Exact centimetres are not required."
                )
                CameraCalibrationFloorMap(
                    scan: scan,
                    targets: calibration.targets,
                    cameraPoint: nil,
                    selection: nil,
                    onSelect: nil
                )
                .frame(height: 320)
                calibration3DGuide(calibration)
                if let target = currentTarget, calibration.status != .solving {
                    HStack(spacing: 10) {
                        metric("X", value: target.x)
                        metric("Z", value: target.z)
                        metric("DONE", text: "\(calibration.capturedTargetCount)/\(calibration.targets.count)")
                    }
                }
                if calibration.status == .captureRequested || calibration.status == .solving {
                    HStack(spacing: 10) {
                        ProgressView().tint(OneTheme.accentBlue)
                        Text(calibration.status == .solving ? "Solving locally…" : "Waiting for \(camera.name)…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }
                if calibration.status == .waitingForPerson, let message = calibration.error, !message.isEmpty {
                    Label(message, systemImage: "camera.viewfinder")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OneTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }

        if let error = store.cameraCalibrationError, !error.isEmpty, !saved {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(OneTheme.amber)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OneTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func calibration3DGuide(_ calibration: RoomPlanCalibrationSession) -> some View {
        if let url = store.roomPlanModelURL, store.scene.hasReadyUSDZ {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("3D room guide", systemImage: "cube.transparent")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.ink)
                    Spacer()
                    Text("Drag to rotate")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                RoomPlanUSDZView(
                    url: url,
                    mapID: calibration.mapID,
                    cameraRegistration: nil,
                    objects: [],
                    calibrationTargets: calibration.targets
                )
                .frame(height: 260)
                Text("The same four floor targets are pinned directly onto the RoomPlan model. Furniture stays visible so you can match the point to the real room before walking to it.")
                    .font(.footnote)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if saved {
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(OneTheme.accentBlue)
                .controlSize(.large)
        } else if calibration == nil {
            Button(isWorking ? "Starting…" : "Start calibration") { Task { await startCalibration() } }
                .buttonStyle(.borderedProminent)
                .tint(OneTheme.accentBlue)
                .controlSize(.large)
                .disabled(isWorking || camera.roomplanMapID == nil)
        } else if manualMode, let calibration, let manualPoint {
            Button(isWorking ? "Saving…" : "Save manual position") {
                Task {
                    isWorking = true
                    let success = await store.saveManualRoomPlanCamera(
                        camera,
                        mapID: calibration.mapID,
                        x: manualPoint.x,
                        z: manualPoint.y,
                        floorY: floorY,
                        height: manualHeight,
                        yawDegrees: manualYaw
                    )
                    isWorking = false
                    if success { saved = true }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OneTheme.accentBlue)
            .controlSize(.large)
            .disabled(isWorking)
        } else if calibration?.status == .review, let calibration {
            Button(isWorking ? "Saving…" : "Yes, save this position") {
                Task {
                    isWorking = true
                    let success = await store.confirmRoomPlanCalibration(for: camera, calibration: calibration)
                    isWorking = false
                    if success { saved = true }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OneTheme.accentBlue)
            .controlSize(.large)
            .disabled(isWorking)
        } else if calibration?.status == .failed || calibration?.status == .expired {
            Button(isWorking ? "Restarting…" : "Run four points again") { Task { await restartCalibration() } }
                .buttonStyle(.borderedProminent)
                .tint(OneTheme.accentBlue)
                .controlSize(.large)
                .disabled(isWorking)
        } else if let calibration, calibration.status == .waitingForPerson {
            Button("I’m standing on point \(calibration.currentTargetIndex + 1)") {
                Task {
                    isWorking = true
                    if let updated = await store.requestRoomPlanCalibrationCapture(for: camera, targetIndex: calibration.currentTargetIndex) {
                        self.calibration = updated
                    }
                    isWorking = false
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OneTheme.accentBlue)
            .controlSize(.large)
            .disabled(isWorking)
        } else {
            HStack {
                ProgressView().tint(OneTheme.accentBlue)
                Text(calibration?.status == .solving ? "Solving camera position…" : "Waiting for the fixed camera…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private func startCalibration() async {
        isWorking = true
        manualMode = false
        manualPoint = nil
        calibration = await store.startRoomPlanCalibration(for: camera)
        isWorking = false
    }

    private func restartCalibration() async {
        isWorking = true
        await store.cancelRoomPlanCalibration(for: camera)
        manualMode = false
        manualPoint = nil
        calibration = await store.startRoomPlanCalibration(for: camera)
        isWorking = false
    }

    private func title(eyebrow: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(OneTheme.cyan)
            Text(title)
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(OneTheme.ink)
            Text(body)
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func requirement(_ text: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(OneTheme.accentBlue)
                .frame(width: 24)
            Text(text).font(.subheadline.weight(.medium))
        }
    }

    private func metric(_ label: String, value: Double) -> some View {
        metric(label, text: String(format: "%.2f m", value))
    }

    private func metric(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(OneTheme.secondaryInk)
            Text(text).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(OneTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CameraCalibrationFloorMap: View {
    let scan: RoomPlanNormalizedScan?
    let targets: [RoomPlanCalibrationTarget]
    let cameraPoint: SIMD2<Double>?
    let selection: SIMD2<Double>?
    let onSelect: ((SIMD2<Double>) -> Void)?

    private var floorPolygons: [[SIMD2<Double>]] {
        scan?.floors.compactMap { floor in
            if floor.vertices.count >= 3 {
                return floor.vertices.map { SIMD2($0.x, $0.z) }
            }
            let halfX = floor.dimensions.x / 2
            let halfZ = floor.dimensions.z / 2
            return [
                SIMD2(floor.center.x - halfX, floor.center.z - halfZ),
                SIMD2(floor.center.x + halfX, floor.center.z - halfZ),
                SIMD2(floor.center.x + halfX, floor.center.z + halfZ),
                SIMD2(floor.center.x - halfX, floor.center.z + halfZ),
            ]
        } ?? []
    }

    private var objectPolygons: [[SIMD2<Double>]] {
        scan?.objects.map { object in
            let halfX = object.dimensions.x * 0.5
            let halfZ = object.dimensions.z * 0.5
            let local = [
                SIMD2(-halfX, -halfZ),
                SIMD2(halfX, -halfZ),
                SIMD2(halfX, halfZ),
                SIMD2(-halfX, halfZ),
            ]
            guard object.transform.count == 4,
                  object.transform.allSatisfy({ $0.count == 4 }) else {
                return local.map { SIMD2(object.center.x + $0.x, object.center.z + $0.y) }
            }
            return local.map { point in
                SIMD2(
                    object.transform[0][0] * point.x + object.transform[0][2] * point.y + object.transform[0][3],
                    object.transform[2][0] * point.x + object.transform[2][2] * point.y + object.transform[2][3]
                )
            }
        } ?? []
    }

    private var wallSegments: [(SIMD2<Double>, SIMD2<Double>)] {
        scan?.walls.compactMap { wall in
            var points: [SIMD2<Double>] = []
            for vertex in wall.vertices {
                let candidate = SIMD2(vertex.x, vertex.z)
                if !points.contains(where: { abs($0.x - candidate.x) < 0.001 && abs($0.y - candidate.y) < 0.001 }) {
                    points.append(candidate)
                }
            }
            guard points.count >= 2 else { return nil }
            var best = (points[0], points[1])
            var bestDistance = -Double.infinity
            for start in points.indices {
                for end in points.indices where end > start {
                    let dx = points[end].x - points[start].x
                    let dz = points[end].y - points[start].y
                    let distance = dx * dx + dz * dz
                    if distance > bestDistance {
                        bestDistance = distance
                        best = (points[start], points[end])
                    }
                }
            }
            return best
        } ?? []
    }

    private var bounds: (minX: Double, maxX: Double, minZ: Double, maxZ: Double) {
        var points = floorPolygons.flatMap { $0 }
        points.append(contentsOf: objectPolygons.flatMap { $0 })
        points.append(contentsOf: wallSegments.flatMap { [$0.0, $0.1] })
        points.append(contentsOf: targets.map { SIMD2($0.x, $0.z) })
        if let cameraPoint { points.append(cameraPoint) }
        if let selection { points.append(selection) }
        guard !points.isEmpty else { return (-1, 1, -1, 1) }
        let minX = points.map(\.x).min() ?? -1
        let maxX = points.map(\.x).max() ?? 1
        let minZ = points.map(\.y).min() ?? -1
        let maxZ = points.map(\.y).max() ?? 1
        let spanX = max(maxX - minX, 0.5)
        let spanZ = max(maxZ - minZ, 0.5)
        return (minX - spanX * 0.08, maxX + spanX * 0.08, minZ - spanZ * 0.08, maxZ + spanZ * 0.08)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.15, blue: 0.22))
                Canvas { context, size in
                    for polygon in floorPolygons where polygon.count >= 3 {
                        var path = Path()
                        path.move(to: screenPoint(polygon[0], size: size))
                        for point in polygon.dropFirst() { path.addLine(to: screenPoint(point, size: size)) }
                        path.closeSubpath()
                        context.fill(path, with: .color(Color.white.opacity(0.88)))
                        context.stroke(path, with: .color(OneTheme.accentBlue.opacity(0.42)), lineWidth: 1)
                    }
                    for (start, end) in wallSegments {
                        var wall = Path()
                        wall.move(to: screenPoint(start, size: size))
                        wall.addLine(to: screenPoint(end, size: size))
                        context.stroke(wall, with: .color(Color.white.opacity(0.78)), lineWidth: 3)
                    }
                    for polygon in objectPolygons where polygon.count >= 3 {
                        var path = Path()
                        path.move(to: screenPoint(polygon[0], size: size))
                        for point in polygon.dropFirst() { path.addLine(to: screenPoint(point, size: size)) }
                        path.closeSubpath()
                        context.fill(path, with: .color(Color(red: 0.77, green: 0.82, blue: 0.86).opacity(0.88)))
                        context.stroke(path, with: .color(Color(red: 0.25, green: 0.39, blue: 0.50).opacity(0.75)), lineWidth: 1.25)
                    }
                    for target in targets {
                        let point = screenPoint(SIMD2(target.x, target.z), size: size)
                        let color: Color = target.state == "complete" ? OneTheme.accentCyan : (target.state == "active" ? OneTheme.amber : OneTheme.secondaryInk.opacity(0.55))
                        let circle = Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
                        context.fill(circle, with: .color(color))
                        context.stroke(circle, with: .color(.white), lineWidth: 2)
                    }
                    if let cameraPoint {
                        let point = screenPoint(cameraPoint, size: size)
                        let outer = Path(ellipseIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22))
                        context.fill(outer, with: .color(OneTheme.ink))
                        let inner = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                        context.fill(inner, with: .color(.white))
                    }
                    if let selection {
                        let point = screenPoint(selection, size: size)
                        let outer = Path(ellipseIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
                        context.fill(outer, with: .color(OneTheme.amber))
                        context.stroke(outer, with: .color(.white), lineWidth: 3)
                    }
                }
                .padding(16)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard let onSelect else { return }
                        onSelect(worldPoint(value.location, size: proxy.size))
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(onSelect == nil ? "RoomPlan calibration floor map" : "RoomPlan floor map. Tap to place the fixed camera.")
    }

    private func screenPoint(_ point: SIMD2<Double>, size: CGSize) -> CGPoint {
        let inset = 28.0
        let width = max(Double(size.width) - inset * 2, 1)
        let height = max(Double(size.height) - inset * 2, 1)
        let normalizedX = (point.x - bounds.minX) / max(bounds.maxX - bounds.minX, 0.001)
        let normalizedZ = (point.y - bounds.minZ) / max(bounds.maxZ - bounds.minZ, 0.001)
        return CGPoint(x: inset + normalizedX * width, y: inset + (1 - normalizedZ) * height)
    }

    private func worldPoint(_ point: CGPoint, size: CGSize) -> SIMD2<Double> {
        let inset = 28.0
        let width = max(Double(size.width) - inset * 2, 1)
        let height = max(Double(size.height) - inset * 2, 1)
        let nx = min(max((Double(point.x) - inset) / width, 0), 1)
        let nz = min(max((Double(point.y) - inset) / height, 0), 1)
        return SIMD2(
            bounds.minX + nx * (bounds.maxX - bounds.minX),
            bounds.minZ + (1 - nz) * (bounds.maxZ - bounds.minZ)
        )
    }
}

private struct CameraPairingSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var label = "Room camera"
    @State private var selectedRoomID: UUID?
    @State private var step: Step = .details
    @State private var validationMessage: String?
    @FocusState private var isNameFocused: Bool

    private enum Step: Int, CaseIterable {
        case details
        case connect
    }

    private var status: String { store.cameraPairingStatus?.status ?? (store.cameraPairingChallenge == nil ? "not started" : "pending") }
    private var isConnected: Bool { status == "connected" }
    private var isExpired: Bool { status == "expired" }
    private var normalizedLabel: String {
        let value = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Room camera" : value
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let contentWidth = min(max(proxy.size.width - 40, 1), 520)

                VStack(spacing: 0) {
                    pairingHeader
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity)

                    ScrollViewReader { scrollProxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                pairingHero
                                    .padding(.top, 28)

                                stepContent
                                    .padding(.top, 22)

                                if let message = validationMessage ?? store.cameraPairingError {
                                    Label(message, systemImage: "exclamationmark.triangle.fill")
                                        .font(.footnote)
                                        .foregroundStyle(OneTheme.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(OneTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .padding(.top, 16)
                                }
                            }
                            .frame(width: contentWidth, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 18)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: step)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: isNameFocused) { _, isFocused in
                            guard isFocused else { return }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 160_000_000)
                                guard !Task.isCancelled, isNameFocused else { return }
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                    scrollProxy.scrollTo("camera-pairing-name", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    pairingFooter(contentWidth: contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(OneTheme.canvas.opacity(0.98).ignoresSafeArea(edges: .horizontal))
                }
            }
            .background(OneBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(store.isCameraPairingBusy)
        .task(id: store.cameraPairingChallenge?.pairingID) {
            guard store.cameraPairingChallenge != nil else { return }
            while !Task.isCancelled {
                await store.refreshCameraPairingStatus()
                if let status = store.cameraPairingStatus?.status, status == "connected" || status == "expired" { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .onDisappear { store.clearCameraPairing() }
    }

    private var pairingHeader: some View {
        HStack(spacing: 10) {
            OneBrandMark(compact: true)

            Spacer()

            Text("PAIR CAMERA \(step.rawValue + 1) OF \(Step.allCases.count)")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(OneTheme.secondaryInk)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneTheme.ink)
                    .frame(width: 38, height: 38)
                    .background(OneTheme.surface, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(OneTheme.secondaryInk.opacity(0.14), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close camera setup")
        }
        .padding(.top, 14)
    }

    private var pairingHero: some View {
        HStack {
            Image(systemName: step == .details ? "video.badge.plus" : (isConnected ? "checkmark.circle.fill" : "qrcode"))
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isConnected ? OneTheme.mint : OneTheme.accentBlue)
                .frame(width: 68, height: 68)
                .background((isConnected ? OneTheme.mint : OneTheme.accentBlue).opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .details:
            detailsStep
        case .connect:
            connectStep
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SET UP A ROOM CAMERA")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(OneTheme.accentBlue)

            Text("Which camera are you pairing?")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(OneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            Text("Give the device a clear name. On the next step, ONE will create a one-time code for the phone or laptop that will stay in the room.")
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 10) {
                Text("Camera name")
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)

                TextField("Room camera", text: $label)
                    .focused($isNameFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .font(.body)
                    .foregroundStyle(OneTheme.ink)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(OneTheme.controlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isNameFocused ? OneTheme.accentBlue.opacity(0.55) : OneTheme.secondaryInk.opacity(0.12), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                    .onSubmit { beginPairing() }
                    .accessibilityIdentifier("camera-pairing-name")
                    .id("camera-pairing-name")

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Room")
                        .font(.headline)
                        .foregroundStyle(OneTheme.ink)
                    Picker("Room", selection: $selectedRoomID) {
                        Text("No room assigned").tag(Optional<UUID>.none)
                        ForEach(store.cameraRooms) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(OneTheme.accentBlue)

                    Text(store.cameraRooms.isEmpty
                         ? "No saved rooms are available yet. You can pair the camera now and assign a room later."
                         : "Choose where this camera will stay. You can change the room later from Cameras.")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("This pairs a camera publisher only. It does not sign anyone into this care space.", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(OneTheme.secondaryInk.opacity(0.12), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .padding(.top, 22)
        }
    }

    private var connectStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isConnected ? "CAMERA CONNECTED" : "CONNECT THE CAMERA")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(isConnected ? OneTheme.mint : OneTheme.accentBlue)

            Text(isConnected ? "Your camera is ready." : "Enter this code on the camera.")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(OneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            Text(isConnected
                 ? "ONE confirmed the publisher connection. The camera now appears with your other connected devices, and viewing remains consent-based."
                 : "Keep this sheet open while you enter the code on the phone or laptop that will stay in the room. ONE checks the connection automatically.")
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            if let challenge = store.cameraPairingChallenge {
                VStack(alignment: .leading, spacing: 14) {
                    Text("ONE-TIME CAMERA CODE")
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(OneTheme.secondaryInk)

                    Text(challenge.pairingCode)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .tracking(5)
                        .foregroundStyle(OneTheme.ink)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .accessibilityLabel("Camera pairing code \(challenge.pairingCode)")

                    Label(
                        isConnected ? "Camera connected" : (isExpired ? "Code expired" : "Waiting for camera"),
                        systemImage: isConnected ? "checkmark.circle.fill" : (isExpired ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right")
                    )
                    .font(.headline)
                    .foregroundStyle(isConnected ? OneTheme.mint : (isExpired ? OneTheme.amber : OneTheme.accentBlue))

                    Text("Code expires in about \(max(1, challenge.expiresInSeconds / 60)) minutes and can be used once.")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                .padding(18)
                .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke((isConnected ? OneTheme.mint : OneTheme.secondaryInk).opacity(isConnected ? 0.34 : 0.12), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
                .padding(.top, 22)

                if !isConnected {
                    VStack(alignment: .leading, spacing: 13) {
                        pairingInstruction(number: "1", text: "Open the ONE camera pairing page on the device that will stay in the room.")
                        pairingInstruction(number: "2", text: "Enter the six-digit code above and allow camera access on that device.")
                        pairingInstruction(number: "3", text: "Wait here until ONE confirms that the publisher is connected.")
                    }
                    .padding(16)
                    .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(OneTheme.secondaryInk.opacity(0.12), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    private func pairingInstruction(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(OneTheme.accentBlue)
                .frame(width: 28, height: 28)
                .background(OneTheme.accentBlue.opacity(0.10), in: Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func pairingFooter(contentWidth: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == step ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(0.20))
                        .frame(width: item == step ? 24 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.allCases.count)")

            HStack(spacing: 12) {
                if step != .details {
                    Button(action: goBack) {
                        Image(systemName: "arrow.left")
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(OneSecondaryButtonStyle())
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("camera-pairing-back")
                }

                Button(action: primaryAction) {
                    HStack {
                        Text(primaryButtonTitle)
                        Spacer()
                        if store.isCameraPairingBusy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: primaryButtonSymbol)
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(OnePrimaryButtonStyle())
                .disabled(primaryButtonDisabled)
                .accessibilityIdentifier("camera-pairing-continue")
            }
        }
        .frame(width: contentWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .padding(.vertical, 12)
    }

    private var primaryButtonTitle: String {
        if store.isCameraPairingBusy { return step == .details ? "Generating…" : "Refreshing…" }
        if step == .details { return "Continue" }
        if isConnected { return "Done" }
        if isExpired { return "Generate new code" }
        return "Waiting for camera…"
    }

    private var primaryButtonSymbol: String {
        if step == .details { return "arrow.right" }
        if isConnected { return "checkmark" }
        if isExpired { return "arrow.clockwise" }
        return "dot.radiowaves.left.and.right"
    }

    private var primaryButtonDisabled: Bool {
        if store.isCameraPairingBusy { return true }
        if step == .details { return false }
        return !isConnected && !isExpired
    }

    private func primaryAction() {
        validationMessage = nil
        if step == .details {
            beginPairing()
        } else if isConnected {
            dismiss()
        } else if isExpired {
            regeneratePairingCode()
        }
    }

    private func beginPairing() {
        guard !store.isCameraPairingBusy else { return }
        isNameFocused = false
        validationMessage = nil

        Task { @MainActor in
            await store.startCameraPairing(label: normalizedLabel, roomID: selectedRoomID)
            guard store.cameraPairingChallenge != nil else {
                validationMessage = store.cameraPairingError ?? "Could not create a camera pairing code."
                return
            }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                step = .connect
            }
        }
    }

    private func regeneratePairingCode() {
        guard !store.isCameraPairingBusy else { return }
        store.clearCameraPairing()
        validationMessage = nil

        Task { @MainActor in
            await store.startCameraPairing(label: normalizedLabel, roomID: selectedRoomID)
            if store.cameraPairingChallenge == nil {
                validationMessage = store.cameraPairingError ?? "Could not create a new camera pairing code."
            }
        }
    }

    private func goBack() {
        guard step == .connect, !store.isCameraPairingBusy else { return }
        store.clearCameraPairing()
        validationMessage = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            step = .details
        }
    }
}

struct ObjectCard: View { let title: String; let subtitle: String; let symbol: String; let color: Color; var body: some View { SurfaceCard(radius: 24) { VStack(alignment: .leading, spacing: 10) { ZStack { RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [color.opacity(0.7), OneTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing)); Image(systemName: symbol).font(.system(size: 38, weight: .medium)).foregroundStyle(OneTheme.ink) }.frame(width: 188, height: 100); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(OneTheme.secondaryInk) }.padding(12) } } }

struct ResidentHomeView: View { @Bindable var store: AppStore; var body: some View { NavigationStack { VStack(alignment: .leading, spacing: 24) { Text("Today").font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.2); Text("A little support for a more independent day.").font(.title3).foregroundStyle(OneTheme.secondaryInk); Spacer(); Button { store.selectedTab = "assistant" } label: { Label("Start check-in", systemImage: "waveform").font(.headline).frame(maxWidth: .infinity).padding(18) }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue); Spacer() }.padding(20).background(OneTheme.canvas.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar) } } }

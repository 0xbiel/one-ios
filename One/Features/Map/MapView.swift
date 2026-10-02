import SwiftUI
import UniformTypeIdentifiers
import ARKit
import RoomPlan
import UIKit

struct MapView: View {
    @Bindable var store: AppStore
    @State private var showEvidence = false
#if DEBUG
    @State private var evidenceDetent: PresentationDetent = ProcessInfo.processInfo.arguments.contains("-one-map-expanded") ? .large : Self.compactEvidenceDetent
#else
    @State private var evidenceDetent: PresentationDetent = Self.compactEvidenceDetent
#endif
    @State private var sheetSelectedTab = "map"
    @State private var selectedPresence: RoomObject?
    @State private var selectedCamera: CameraRegistrationDescriptor?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let compactEvidenceDetent = PresentationDetent.height(140)

    var body: some View {
        Group {
            if store.scene.isRenderable3D {
                RoomPlan3DSceneView(
                    store: store,
                    onPresenceSelected: { presence in
                        selectedCamera = nil
                        selectedPresence = presence
                        evidenceDetent = .medium
                    },
                    onCameraSelected: { camera in
                        selectedPresence = nil
                        selectedCamera = camera
                        evidenceDetent = .medium
                    }
                )
            } else {
                RoomMapCanvas(scan: store.scan)
            }
        }
        .padding(.bottom, 140)
        .background(OneTheme.canvas)
        .ignoresSafeArea()
        .sheet(isPresented: $showEvidence) {
            evidenceSheetTabView
                .presentationDetents([Self.compactEvidenceDetent, .medium, .large], selection: $evidenceDetent)
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationContentInteraction(.scrolls)
                .presentationBackground(.regularMaterial)
                .interactiveDismissDisabled()
        }
        .onChange(of: dynamicTypeSize, initial: true) { _, size in
            if size.isAccessibilitySize && evidenceDetent == Self.compactEvidenceDetent {
                evidenceDetent = .medium
            }
        }
        .task {
            // Let the map surface get its first frame before presenting the
            // evidence sheet and starting the initial network refresh.
            await Task.yield()
            showEvidence = true
            await Task.yield()
            while !Task.isCancelled {
                await store.refreshMapData()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private var evidenceSheetTabView: some View {
        TabView(selection: $sheetSelectedTab) {
            Color.clear
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag("overview")
            MapEvidenceSheet(store: store, selectedPresence: $selectedPresence, selectedCamera: $selectedCamera, isCompact: evidenceDetent == Self.compactEvidenceDetent)
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag("map")
            Color.clear
                .tabItem { Label("Family", systemImage: "person.2.fill") }
                .tag("family")
            Color.clear
                .tabItem { Label("Assistant", systemImage: "sparkles") }
                .tag("assistant")
            Color.clear
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
                .tag("settings")
        }
        .toolbar(.visible, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.regularMaterial, for: .tabBar)
        .onChange(of: sheetSelectedTab) { _, tab in
            guard tab != "map" else { return }
            showEvidence = false
            Task { @MainActor in
                await Task.yield()
                store.selectedTab = tab
                sheetSelectedTab = "map"
            }
        }
    }
}

struct RoomMapCanvas: View {
    let scan: RoomScan
    private var labels: [String] { Array((scan.objects.map(\.name) + scan.zones.map(\.name)).prefix(4)) }

    var body: some View { ZStack { LinearGradient(colors: [Color(red: 0.70, green: 0.90, blue: 0.94), Color(red: 0.92, green: 0.95, blue: 0.91)], startPoint: .top, endPoint: .bottom); GeometryReader { _ in Canvas { context, size in for x in stride(from: 0, through: size.width, by: 28) { var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) }; for y in stride(from: 0, through: size.height, by: 28) { var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) } }.overlay { RoundedRectangle(cornerRadius: 26).stroke(OneTheme.accentBlue.opacity(0.45), lineWidth: 2).padding(.horizontal, 42).padding(.vertical, 180).overlay { if labels.isEmpty { Label("No room map yet", systemImage: "map") .font(.headline) .foregroundStyle(OneTheme.secondaryInk) } else { LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 18) { ForEach(Array(labels.enumerated()), id: \.offset) { index, label in RoomMapPin(title: label, color: index.isMultiple(of: 2) ? OneTheme.accentCyan : OneTheme.accentBlue) } }.padding(.horizontal, 48) } } } } }.accessibilityElement(children: .combine).accessibilityLabel(labels.isEmpty ? "No room map available" : "Room map with \(labels.joined(separator: ", "))") } }

struct RoomMapPin: View {
    let title: String
    let color: Color

    var body: some View {
        OneStatusBadge(title: title, symbol: "mappin", tint: color)
            .background(OneTheme.surface, in: Capsule())
    }
}

struct MapEvidenceSheet: View {
    @Bindable var store: AppStore
    @Binding var selectedPresence: RoomObject?
    @Binding var selectedCamera: CameraRegistrationDescriptor?
    let isCompact: Bool
    @State private var showScanSetup = false
    @State private var showRooms = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            mapTitle
                            mapActions
                        }
                    } else {
                        HStack {
                            mapTitle
                            Spacer()
                            mapActions
                        }
                    }

                    if !isCompact {
                        if !store.cameraRooms.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Rooms")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OneTheme.ink)
                                ForEach(store.cameraRooms) { room in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(room.name).font(.subheadline.weight(.semibold))
                                        Text(roomObservationSummary(roomID: room.id)).font(.caption).foregroundStyle(OneTheme.secondaryInk)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(OneTheme.controlFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            }
                            .accessibilityIdentifier("map-room-observations")
                        } else {
                            Label("No rooms added yet", systemImage: "square.grid.2x2")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                        }
                        if selectedPresence != nil || selectedCamera != nil {
                            SurfaceCard(radius: 20) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Selected marker").font(.caption).foregroundStyle(OneTheme.secondaryInk)
                                        Spacer()
                                        Button {
                                            selectedPresence = nil
                                            selectedCamera = nil
                                        } label: {
                                            Image(systemName: "xmark").frame(width: 44, height: 44)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Clear marker selection")
                                    }
                                    if let selectedPresence {
                                        MapPresenceDetails(presence: selectedPresence, store: store)
                                    } else if let selectedCamera {
                                        MapCameraDetails(camera: selectedCamera, store: store)
                                    }
                                }
                                .padding(16)
                            }
                            .accessibilityIdentifier("map-marker-details")
                        }

                        if store.scene.isRenderable3D {
                            SurfaceCard(radius: 20) {
                                DisclosureGroup("Map details") {
                                    VStack(alignment: .leading, spacing: 12) {
                                    Text("Coverage unknown").font(.subheadline)
                                    Text("Neutral floors have no validated coverage measurement. Blue and red require current, validated visible floor data; stale observations do not show whether a room is empty.").font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                                    Text("Marker key").font(.caption.weight(.semibold)).foregroundStyle(OneTheme.secondaryInk)
                                    LazyVGrid(
                                        columns: dynamicTypeSize.isAccessibilitySize
                                            ? [GridItem(.flexible(), alignment: .leading)]
                                            : [GridItem(.adaptive(minimum: 140), alignment: .leading)],
                                        alignment: .leading,
                                        spacing: 8
                                    ) {
                                        ForEach(MapMarkerStyle.allCases) { style in
                                            Label {
                                                Text(style.title).foregroundStyle(OneTheme.secondaryInk)
                                            } icon: {
                                                Image(systemName: style.symbol).foregroundStyle(style.color)
                                            }
                                            .font(.caption)
                                            .accessibilityHint(style.detail)
                                        }
                                    }
                                        Text(mapDescription)
                                            .font(.footnote)
                                            .foregroundStyle(OneTheme.secondaryInk)
                                        Text("Tap a marker for details. Faded markers were seen recently; unknown people stay anonymous.")
                                            .font(.footnote)
                                            .foregroundStyle(OneTheme.secondaryInk)
                                        ForEach(store.scan.objects.filter { MapPresenceAppearance.presence($0) != nil }) { person in
                                            Button {
                                                selectedCamera = nil
                                                selectedPresence = person
                                            } label: {
                                                Label((person.identityStatus == "matched" || person.identityStatus == "simulated") ? (person.identityName ?? "Person") : "Unknown person", systemImage: MapPresenceAppearance.presence(person)?.style.symbol ?? "person.fill")
                                                    .frame(minHeight: 44)
                                            }
                                            .accessibilityLabel("\(MapPresenceAppearance.presence(person)?.style.title ?? "Person"), \((person.identityStatus == "matched" || person.identityStatus == "simulated") ? (person.identityName ?? "Person") : "Anonymous person")")
                                        }
                                        ForEach(Array(store.scene.cameraRegistrations.enumerated()), id: \.offset) { _, camera in
                                            Button {
                                                selectedPresence = nil
                                                selectedCamera = camera
                                            } label: {
                                                Label(camera.cameraName ?? "Camera", systemImage: "camera.fill")
                                                    .frame(minHeight: 44)
                                            }
                                        }
                                        if store.scene.source == .roomplanLidar3D {
                                            let registrations = store.scene.cameraRegistrations.isEmpty
                                                ? (store.scene.cameraRegistration.map { [$0] } ?? [])
                                                : store.scene.cameraRegistrations
                                            if registrations.isEmpty {
                                                CameraRegistrationStatusCard(registration: nil)
                                            } else {
                                                ForEach(Array(registrations.enumerated()), id: \.offset) { _, registration in
                                                    CameraRegistrationStatusCard(registration: registration)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 10)
                                }
                                .font(.subheadline.weight(.semibold))
                                .tint(OneTheme.accentBlue)
                                .padding(16)
                                .accessibilityIdentifier("map-details")
                            }
                        }

                        Text("Recent observations")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneTheme.ink)
                        if store.events.isEmpty {
                            SurfaceCard(radius: 20) {
                                Label("No observations yet", systemImage: "tray").font(.subheadline).foregroundStyle(OneTheme.secondaryInk).padding(16)
                            }
                        } else {
                            SurfaceCard(radius: 20) {
                                VStack(spacing: 0) {
                                    ForEach(store.events.prefix(3)) { event in
                                        NavigationLink {
                                            EventDetailView(event: event, apiClient: store.apiClient, homeID: store.session?.homeID)
                                        } label: {
                                            EventRow(event: event)
                                        }
                                        .buttonStyle(.plain)
                                        if event.id != store.events.prefix(3).last?.id { Divider() }
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                            .accessibilityIdentifier("map-recent-observations")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, isCompact ? 4 : 8)
                .padding(.bottom, isCompact ? 0 : 20)
            }
            // Keep evidence hit targets clear of the floating tab bar.
            .safeAreaPadding(.bottom, 80)
            .background(.regularMaterial)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showScanSetup) {
            NavigationStack { ScanView(store: store) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showRooms) {
            RoomManagementSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }


    }

    private var mapTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Home map")
                .font(.system(isCompact ? .headline : .title2, design: .rounded).weight(.bold))
            if !store.cameraRooms.isEmpty {
                Text("\(store.cameraRooms.count) rooms")
                    .font(.subheadline)
                    .foregroundStyle(OneTheme.secondaryInk)
            }
        }
    }

    private var mapActions: some View {
        Menu {
            Button("Manage rooms", systemImage: "square.grid.2x2") { showRooms = true }
            Button("Update room scan", systemImage: "viewfinder") { showScanSetup = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(OneTheme.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Map options")
    }

    private func roomObservationSummary(roomID: UUID) -> String {
        guard let observation = store.scan.objects.filter({ object in
            object.zoneID == roomID && object.mapID == store.scene.mapID
                && ["person", "people", "human"].contains(object.category.lowercased())
                && object.observedAt != nil
        }).max(by: { ($0.observedAt ?? .distantPast) < ($1.observedAt ?? .distantPast) }),
              let observedAt = observation.observedAt else { return "No current observation · coverage unknown" }
        let time = observedAt.formatted(date: .abbreviated, time: .shortened)
        if observation.identityStatus == "simulated" {
            let appearance = MapPresenceAppearance.presence(observation)
            let name = observation.identityName ?? "Unknown person"
            if appearance?.style == .simulatedStale { return "Earlier observation: \(name) · \(time). Current location unknown." }
            if appearance?.isRecent == true { return "Recent observation: \(name) · \(time)" }
            return "\(name) · \(time). Current location unknown."
        }
        guard let appearance = MapPresenceAppearance.presence(observation) else { return "Last observation \(time) · current presence unknown" }
        let name = observation.identityStatus == "matched" ? (observation.identityName ?? "Person") : "Unknown person"
        return "\(appearance.isRecent ? "Recent" : "Current") observation: \(name) · \(time)"
    }

    private var mapDescription: String {
        switch store.scene.source {
        case .roomplanLidar3D: "LiDAR room scan · metric 3D"
        case .arkitVideo3D: "Video room scan · approximate 3D"
        case .imported3D: "Imported 3D · \(store.scene.provenance) · manual placement"
        default: "Approximate locations"
        }
    }

}

private struct RoomManagementSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newRoomName = ""
    @State private var editingRoom: CameraRoom?
    @State private var editName = ""
    @State private var deletingRoom: CameraRoom?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Room name", text: $newRoomName)
                            .textInputAutocapitalization(.words)
                        Button("Add") {
                            let name = newRoomName
                            Task {
                                if await store.createRoom(name: name) { newRoomName = "" }
                            }
                        }
                        .disabled(newRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isRoomMutating)
                    }
                } footer: {
                    Text("Assign cameras to rooms here; capture the map with a room scan.")
                }

                Section("Rooms") {
                    ForEach(store.cameraRooms) { room in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(room.name).font(.body.weight(.semibold))
                                let assigned = store.pairedCameras.filter { $0.roomID == room.id }.count
                                Text(assigned == 0 ? "No cameras assigned" : "\(assigned) camera\(assigned == 1 ? "" : "s") assigned")
                                    .font(.caption)
                                    .foregroundStyle(OneTheme.secondaryInk)
                            }
                            Spacer()
                            Menu {
                                Button("Rename", systemImage: "pencil") {
                                    editingRoom = room
                                    editName = room.name
                                }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deletingRoom = room
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                            }
                        }
                    }
                    if store.cameraRooms.isEmpty {
                        Text("No rooms yet. Add one here or scan rooms with RoomPlan.")
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }

                if let error = store.roomError, !error.isEmpty {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Rooms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Rename room", isPresented: Binding(
                get: { editingRoom != nil },
                set: { if !$0 { editingRoom = nil } }
            )) {
                TextField("Room name", text: $editName)
                Button("Cancel", role: .cancel) { editingRoom = nil }
                Button("Save") {
                    guard let room = editingRoom else { return }
                    Task {
                        if await store.renameRoom(room, name: editName) { editingRoom = nil }
                    }
                }
            }
            .confirmationDialog("Delete this room?", isPresented: Binding(
                get: { deletingRoom != nil },
                set: { if !$0 { deletingRoom = nil } }
            ), titleVisibility: .visible) {
                if let room = deletingRoom {
                    Button("Delete \(room.name)", role: .destructive) {
                        Task {
                            if await store.deleteRoom(room) { deletingRoom = nil }
                        }
                    }
                }
                Button("Cancel", role: .cancel) { deletingRoom = nil }
            } message: {
                if let room = deletingRoom {
                    let assigned = store.pairedCameras.filter { $0.roomID == room.id }.count
                    Text(assigned == 0
                         ? "The 3D home map is kept."
                         : "\(assigned) camera\(assigned == 1 ? "" : "s") will stay paired and become Unassigned. The 3D home map is kept.")
                }
            }
        }
    }
}

private struct CameraRegistrationStatusCard: View {
    let registration: CameraRegistrationDescriptor?

    private var copy: (title: String, detail: String) {
        switch registration?.status ?? .unavailable {
        case .positioned:
            return ("Positioned", "Saved on this room map.")
        case .needsRescan:
            return ("Retry placement", "Keep the camera still and retry positioning from its live view.")
        case .unavailable:
            return ("Placement pending", "Position this camera from its live view. No new room scan is needed.")
        }
    }

    var body: some View {
        let state = registration?.status ?? .unavailable
        SurfaceCard(radius: 20) {
            HStack(spacing: 12) {
                Image(systemName: state == .positioned ? "camera.viewfinder" : "camera.badge.ellipsis")
                    .foregroundStyle(state == .positioned ? OneTheme.accentBlue : OneTheme.secondaryInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text(registration?.cameraName.map { "\($0) · \(copy.title)" } ?? copy.title)
                        .font(.subheadline.weight(.semibold))
                    Text(copy.detail)
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            }
            .padding(16)
        }
    }
}

private struct CameraReferenceImageCard: View {
    let registration: CameraRegistrationDescriptor
    let image: UIImage?
    let captureError: String?
    let onCapture: () async -> Bool
    @State private var isRequesting = false
    @State private var notice: String?

    var body: some View {
        SurfaceCard(radius: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Reference view", systemImage: "photo.fill.on.rectangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OneTheme.accentBlue)
                    Spacer()
                    if let capturedAt = registration.referenceSnapshot?.capturedAt {
                        Text(capturedAt.prefix(10))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(OneTheme.secondaryInk.opacity(0.08))
                        .frame(height: 126)
                        .overlay {
                            Label("No saved reference photo yet", systemImage: "camera.viewfinder")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OneTheme.secondaryInk)
                        }
                }
                Text("Refresh only when \(registration.cameraName ?? "the camera") is in the position shown on the map.")
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task {
                        isRequesting = true
                        let success = await onCapture()
                        notice = success
                            ? "Capture requested. Keep the fixed camera preview open; this image will update when it arrives."
                            : (captureError ?? "The fresh reference capture could not be requested.")
                        isRequesting = false
                    }
                } label: {
                    Label(isRequesting ? "Requesting…" : "Refresh reference view", systemImage: "camera.rotate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRequesting)
                if let notice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }
}

private enum RoomScanSetupStep: Int, CaseIterable {
    case prepare, camera, scan, rooms, complete
}

struct ScanView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: RoomScanSetupStep = .prepare
    @State private var isCapturing = false
    @State private var showCapture = false
    @State private var isCancellingCapture = false
    @State private var captureError: String?
    @State private var selectedCameraID: UUID?
    @State private var roomPlanARSession = ARSession()
    @State private var roomPlanCaptures: [RoomPlanCaptureResult] = []
    @State private var roomNames: [String] = []
    @State private var editingRoomIndex: Int?
    @State private var deletingRoomIndex: Int?
    @State private var showExitConfirmation = false
    @State private var roomNameDraft = ""
    @State private var pendingRoomSync: [CameraRoom] = []
    @State private var isBuildingStructure = false

    private var stepNumber: Int { step.rawValue + 1 }
    private var canGoBack: Bool { step != .prepare && step != .rooms && step != .complete && !store.isRoomPlanUploading && !isBuildingStructure }
    private var usesLiDAR: Bool { RoomPlanCapability.isSupported }
    private var canCaptureRoom: Bool { usesLiDAR || ARVideoRoomCaptureCapability.isSupported }

    var body: some View {
        ZStack {
            if showCapture && usesLiDAR {
                RoomPlanCaptureView(isCapturing: $isCapturing, arSession: roomPlanARSession) { result in
                    handleRoomPlanResult(result)
                }
                .ignoresSafeArea(edges: .bottom)
            } else if showCapture && ARVideoRoomCaptureCapability.isSupported {
                ARVideoRoomCaptureView(isCapturing: $isCapturing) { result in
                    handleARVideoResult(result)
                }
                .ignoresSafeArea(edges: .bottom)
            } else {
                VStack(spacing: 0) {
                    setupHeader
                    ScrollView(showsIndicators: false) {
                        stepContent
                            .frame(maxWidth: 620, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.top, 28)
                            // The setup footer is fixed in the safe area. Leave
                            // enough scrollable tail space for the last text or
                            // card to clear both buttons and the home indicator.
                            .padding(.bottom, 112)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    setupFooter
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .background(
                            OneTheme.canvas
                                .ignoresSafeArea(edges: [.horizontal, .bottom])
                        )
                }
            }
        }
        .background(OneBackground())
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(showCapture || store.isRoomPlanUploading)
        .confirmationDialog("Remove this room scan?", isPresented: Binding(
            get: { deletingRoomIndex != nil },
            set: { if !$0 { deletingRoomIndex = nil } }
        ), titleVisibility: .visible) {
            if let index = deletingRoomIndex, roomNames.indices.contains(index) {
                Button("Remove \(roomNames[index])", role: .destructive) {
                    removeCapturedRoom(at: index)
                }
            }
            Button("Keep room", role: .cancel) { deletingRoomIndex = nil }
        } message: {
            Text("Only this captured room is removed. Earlier rooms stay available and will not need to be scanned again.")
        }
        .confirmationDialog("Leave room setup?", isPresented: $showExitConfirmation, titleVisibility: .visible) {
            Button("Discard captured rooms", role: .destructive) {
                roomPlanCaptures.removeAll()
                roomNames.removeAll()
                roomPlanARSession.pause()
                dismiss()
            }
            Button("Keep editing", role: .cancel) { }
        } message: {
            Text("Your captured rooms are still local to this scan. Keep editing to finish them or remove rooms individually.")
        }
        .toolbar {
            if showCapture && canCaptureRoom {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel room", role: .cancel) {
                        cancelCapture()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCapturing = false
                    } label: {
                        Label("Done scanning", systemImage: "checkmark.circle.fill")
                    }
                    .disabled(!isCapturing)
                }
            } else if !store.isRoomPlanUploading {
                ToolbarItem(placement: .topBarLeading) {
                    Button(roomPlanCaptures.isEmpty || step == .complete ? "Close" : "Exit") {
                        if roomPlanCaptures.isEmpty || step == .complete {
                            dismiss()
                        } else {
                            showExitConfirmation = true
                        }
                    }
                }
            }
        }
    }

    private var setupHeader: some View {
        HStack(spacing: 10) {
            OneBrandMark(compact: true)
            Spacer()
            Text("ROOM SETUP \(stepNumber) OF \(RoomScanSetupStep.allCases.count)")
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(OneTheme.secondaryInk)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .prepare:
            VStack(alignment: .leading, spacing: 20) {
                setupTitle(title: "Scan your home.",
                    body: usesLiDAR
                        ? "Move slowly around the room to capture a LiDAR map."
                        : "Move slowly around the room to capture an approximate 3D map."
                )
                SurfaceCard(radius: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        setupRequirement("Move slowly around the whole room", symbol: "figure.walk.motion")
                        setupRequirement(usesLiDAR ? "Keep furniture, corners, artwork, and textured surfaces in view" : "Keep the floor and wall boundaries visible from several angles", symbol: "photo.on.rectangle.angled")
                        setupRequirement(usesLiDAR ? "Finish only after RoomPlan has covered the visible walls" : "Finish after ARKit has tracked the floor and at least two walls", symbol: "viewfinder")
                    }
                    .padding(18)
                }
                if usesLiDAR {
                    Label("LiDAR available", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.accentBlue)
                } else if ARVideoRoomCaptureCapability.isSupported {
                    Label("Video scan available", systemImage: "video.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.accentBlue)
                } else {
                    Label("3D room capture is not available on this device.", systemImage: "iphone.slash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

        case .camera:
            VStack(alignment: .leading, spacing: 20) {
                setupTitle(title: usesLiDAR ? "Choose the scan camera." : "Save the room map first.", body: usesLiDAR ? "For a Mac or browser camera, scan the map only. The fixed camera can be positioned later." : "Scan with this iPhone. Set up room cameras later.")
                VStack(spacing: 12) {
                    cameraChoice(id: nil, title: "Map only", detail: usesLiDAR ? "Recommended when the fixed camera is a Mac, browser, or another device." : "Uses only this iPhone's guided ARKit room video; no live room camera is required.", symbol: "map.fill")
                    if usesLiDAR {
                        ForEach(store.pairedCameras) { camera in
                            cameraChoice(id: camera.id, title: "This iPhone is \(camera.name)", detail: "Choose this only if this exact iPhone will stay in place as that paired camera after the scan.", symbol: "iphone.gen3")
                        }
                    }
                }
            }

        case .scan:
            VStack(alignment: .leading, spacing: 20) {
                setupTitle(title: roomPlanCaptures.isEmpty ? "Ready to scan." : "Continue into the next room.",
                    body: usesLiDAR
                        ? (roomPlanCaptures.isEmpty
                            ? "Move steadily and capture several angles. Tap Done scanning when the room is covered."
                            : "Walk into the connected room, scan from several angles, then tap Done scanning.")
                        : "Keep the floor and walls visible as you move. Tap Done scanning when coverage is stable."
                )
                SurfaceCard(radius: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        setupRequirement("Keep the phone upright and avoid fast turns", symbol: "iphone.gen3")
                        setupRequirement(usesLiDAR ? "Get multiple angles of the area seen by the fixed camera" : "Sweep the floor edge and each wall from more than one position", symbol: "camera.viewfinder")
                        setupRequirement("Do not close the app while the map is being saved", symbol: "arrow.up.circle")
                    }
                    .padding(18)
                }
                if store.isRoomPlanUploading {
                    SurfaceCard(radius: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                if let saveProgress = store.roomPlanSaveProgress {
                                    ProgressView(value: Double(saveProgress.percent), total: 100)
                                        .tint(OneTheme.accentBlue)
                                        .frame(width: 42)
                                } else {
                                    ProgressView().tint(OneTheme.accentBlue)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Building the 3D map").font(.headline)
                                    Group {
                                        if let saveProgress = store.roomPlanSaveProgress {
                                            Text("Estimated save \(saveProgress.percent)% · \(saveProgress.detail)")
                                        } else {
                                            Text(usesLiDAR ? "Saving native geometry and preparing localization landmarks." : "Saving ARKit floor and wall geometry and generating the USDZ model.")
                                        }
                                    }
                                        .font(.caption)
                                        .foregroundStyle(OneTheme.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if let progress = store.roomPlanVisualUploadProgress, progress.totalFrameCount > 0 {
                                ProgressView(value: Double(progress.completedFrameCount), total: Double(progress.totalFrameCount))
                                    .tint(OneTheme.accentBlue)
                                Text("Landmark upload \(progress.percent)% · \(progress.completedFrameCount)/\(progress.totalFrameCount) views · batch \(progress.currentBatch)/\(progress.batchCount)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(OneTheme.secondaryInk)
                                if progress.phase == "retrying", let lastError = progress.lastError {
                                    Text("Retrying a smaller batch: \(lastError)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(18)
                    }
                }
                errorMessages
            }

        case .rooms:
            VStack(alignment: .leading, spacing: 20) {
                setupTitle(title: roomPlanCaptures.count == 1 ? "One room is ready." : "\(roomPlanCaptures.count) rooms ready.",
                    body: "Scan another connected room or finish your home map."
                )
                VStack(spacing: 10) {
                    ForEach(roomNames.indices, id: \.self) { index in
                        SurfaceCard(radius: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(roomNames[index])
                                            .font(.headline)
                                        Text("Captured")
                                            .font(.caption)
                                            .foregroundStyle(OneTheme.secondaryInk)
                                    }
                                    Spacer()
                                    Button("Change name") {
                                        editingRoomIndex = index
                                        roomNameDraft = roomNames[index]
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                                DisclosureGroup("Details") {
                                    Image(systemName: "scope")
                                        .foregroundStyle(OneTheme.accentBlue)
                                    if let area = roomPlanCaptures[index].visualDiagnostics.estimatedAreaSquareMeters {
                                        Text("Estimated \(Int(area.rounded())) m² · adaptive target \(roomPlanCaptures[index].visualDiagnostics.recommendedVisualSampleCount) views")
                                    } else {
                                        Text("Adaptive landmark coverage · \(roomPlanCaptures[index].visualDiagnostics.depthSampleCount) depth views")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(OneTheme.secondaryInk)
                                if editingRoomIndex == index {
                                    HStack(spacing: 8) {
                                        TextField("Room name", text: $roomNameDraft)
                                            .textInputAutocapitalization(.words)
                                            .textFieldStyle(.roundedBorder)
                                            .onChange(of: roomNameDraft) { _, value in
                                                if value.count > 120 { roomNameDraft = String(value.prefix(120)) }
                                            }
                                        Button("Save") {
                                            let trimmed = roomNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                            if !trimmed.isEmpty { roomNames[index] = trimmed }
                                            editingRoomIndex = nil
                                        }
                                        .disabled(roomNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                                Button(role: .destructive) {
                                    deletingRoomIndex = index
                                } label: {
                                    Label("Remove this room scan", systemImage: "trash")
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                Button {
                    captureError = nil
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = .scan }
                } label: {
                    Label("Add another room", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(OneSecondaryButtonStyle())
                .disabled(isBuildingStructure || store.isRoomPlanUploading)
                Text("Remove any room before finishing. Saving replaces the earlier saved rooms.")
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                errorMessages
            }

        case .complete:
            VStack(alignment: .leading, spacing: 20) {
                setupTitle(title: "Scan complete.", body: usesLiDAR ? (selectedCameraID == nil ? "Your home map is saved. Position cameras later." : "Your home map is saved. Check this iPhone’s placement below.") : "Your approximate 3D map is saved.")
                SurfaceCard(radius: 24) {
                    Label(usesLiDAR ? "3D RoomPlan map saved" : "3D ARKit video map saved", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(OneTheme.accentBlue)
                        .padding(18)
                }
                if usesLiDAR, store.scene.isRenderable3D {
                    CameraRegistrationStatusCard(registration: store.scene.cameraRegistration)
                }
                if !pendingRoomSync.isEmpty {
                    SurfaceCard(radius: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Room names still need to sync", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                            Text("The 3D map is already saved. Retry room sync without scanning again.")
                                .font(.caption)
                                .foregroundStyle(OneTheme.secondaryInk)
                            Button(store.isRoomMutating ? "Syncing…" : "Retry room sync") {
                                Task { await syncPendingRooms() }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isRoomMutating)
                        }
                        .padding(16)
                    }
                }
                errorMessages
            }
        }
    }

    private func setupTitle(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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

    private func setupRequirement(_ text: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(OneTheme.accentBlue)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(OneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func cameraChoice(id: UUID?, title: String, detail: String, symbol: String) -> some View {
        let selected = selectedCameraID == id
        return Button {
            selectedCameraID = id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? OneTheme.accentBlue : OneTheme.secondaryInk)
                Image(systemName: symbol)
                    .foregroundStyle(OneTheme.accentBlue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(OneTheme.ink)
                    Text(detail).font(.caption).foregroundStyle(OneTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? OneTheme.accentBlue.opacity(0.10) : OneTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selected ? OneTheme.accentBlue.opacity(0.42) : OneTheme.secondaryInk.opacity(0.12), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorMessages: some View {
        if let captureError {
            Label(captureError, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
        if let authError = store.authError, !isMedicationReminderError(authError) {
            Label(authError, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
        if let mapError = store.roomPlanModelError {
            Text(mapError)
                .font(.footnote)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        if store.canRetryRoomPlanVisualLandmarks {
            Button {
                Task { await store.retryPendingRoomPlanVisualLandmarks() }
            } label: {
                Label("Retry landmark upload", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.bordered)
        }
    }

    private func isMedicationReminderError(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("medication reminder")
    }

    private var setupFooter: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(RoomScanSetupStep.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == step ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(0.20))
                        .frame(width: item == step ? 24 : 7, height: 7)
                }
            }

            HStack(spacing: 12) {
                if canGoBack {
                    Button {
                        guard let previous = RoomScanSetupStep(rawValue: step.rawValue - 1) else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = previous }
                    } label: {
                        Image(systemName: "arrow.left").frame(width: 54, height: 54)
                    }
                    .buttonStyle(OneSecondaryButtonStyle())
                    .accessibilityLabel("Back")
                }

                Button(action: advanceSetup) {
                    HStack {
                        Text(primaryActionTitle)
                        Spacer()
                        if store.isRoomPlanUploading || isBuildingStructure {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: step == .complete ? "checkmark" : (step == .scan ? "viewfinder" : "arrow.right"))
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(OnePrimaryButtonStyle())
                .disabled(store.isRoomPlanUploading || isBuildingStructure || (step == .prepare && !canCaptureRoom))
            }
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var primaryActionTitle: String {
        if store.isRoomPlanUploading { return "Saving…" }
        if isBuildingStructure { return "Merging rooms…" }
        switch step {
        case .prepare, .camera: return "Continue"
        case .scan: return usesLiDAR ? "Start LiDAR scan" : "Start room video scan"
        case .rooms: return "Finish home scan"
        case .complete: return "Done"
        }
    }

    private func advanceSetup() {
        guard !store.isRoomPlanUploading else { return }
        switch step {
        case .prepare:
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = .camera }
        case .camera:
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = .scan }
        case .scan:
            captureError = nil
            store.authError = nil
            isCancellingCapture = false
            showCapture = true
            isCapturing = true
        case .rooms:
            finishRoomPlanHomeScan()
        case .complete:
            roomPlanARSession.pause()
            dismiss()
        }
    }

    private func handleRoomPlanResult(_ result: Result<RoomPlanCaptureResult, RoomPlanCaptureError>) {
        isCapturing = false
        showCapture = false
        guard !isCancellingCapture else { return }
        switch result {
        case let .success(capture):
            captureError = nil
            roomPlanCaptures.append(capture)
            roomNames.append("Room \(roomPlanCaptures.count)")
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = .rooms }
        case let .failure(error):
            captureError = error.localizedDescription
        }
    }

    private func handleARVideoResult(_ result: Result<ARVideoRoomCaptureResult, RoomPlanCaptureError>) {
        isCapturing = false
        showCapture = false
        guard !isCancellingCapture else { return }
        selectedCameraID = nil
        switch result {
        case let .success(capture):
            captureError = nil
            Task { @MainActor in
                let saved = await store.uploadARVideoRoom(capture)
                if saved {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = .complete }
                }
            }
        case let .failure(error):
            captureError = error.localizedDescription
        }
    }

    private func cancelCapture() {
        guard showCapture, !store.isRoomPlanUploading else { return }
        isCancellingCapture = true
        isCapturing = false
        showCapture = false
        captureError = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            step = roomPlanCaptures.isEmpty ? .scan : .rooms
        }
    }

    private func removeCapturedRoom(at index: Int) {
        guard roomPlanCaptures.indices.contains(index), roomNames.indices.contains(index) else {
            deletingRoomIndex = nil
            return
        }
        roomPlanCaptures.remove(at: index)
        roomNames.remove(at: index)
        editingRoomIndex = nil
        deletingRoomIndex = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            step = roomPlanCaptures.isEmpty ? .scan : .rooms
        }
    }

    private func finishRoomPlanHomeScan() {
        guard usesLiDAR, !roomPlanCaptures.isEmpty, !isBuildingStructure, !store.isRoomPlanUploading else { return }
        isBuildingStructure = true
        captureError = nil
        let captures = roomPlanCaptures
        let cameraID = selectedCameraID
        Task { @MainActor in
            defer { isBuildingStructure = false }
            do {
                let structure = try await StructureBuilder(options: []).capturedStructure(from: captures.map(\.room))
                let saved = await store.uploadRoomPlanStructure(structure, captures: captures, roomNames: roomNames, cameraID: cameraID)
                if saved {
                    // The backend replaces the previous logical room set when
                    // a new native scan is saved. Refresh before creating the
                    // names for this scan so the local store matches it.
                    await store.refreshCameraConfiguration()
                    pendingRoomSync = captures.indices.map { index in
                        CameraRoom(
                            id: captures[index].room.identifier,
                            name: roomNames.indices.contains(index) ? roomNames[index] : "Room \(index + 1)"
                        )
                    }
                    await syncPendingRooms()
                    roomPlanARSession.pause()
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = .complete }
                }
            } catch {
                captureError = "Could not merge the captured rooms into one home scan: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func syncPendingRooms() async {
        while let room = pendingRoomSync.first {
            guard await store.createRoom(id: room.id, name: room.name) else { return }
            pendingRoomSync.removeFirst()
        }
    }
}

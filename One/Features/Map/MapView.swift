import SwiftUI

struct MapView: View {
    @Bindable var store: AppStore
    @State private var showEvidence = false
    @State private var evidenceDetent: PresentationDetent = Self.compactEvidenceDetent
    @State private var sheetSelectedTab = "map"

    private static let compactEvidenceDetent = PresentationDetent.height(205)

    var body: some View {
        Group {
            if store.scene.isRenderable3D {
                RoomPlan3DSceneView(store: store)
            } else {
                RoomMapCanvas(scan: store.scan)
            }
        }
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
        .task {
            showEvidence = true
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
            MapEvidenceSheet(store: store)
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

    var body: some View { ZStack { LinearGradient(colors: [Color(red: 0.70, green: 0.90, blue: 0.94), Color(red: 0.92, green: 0.95, blue: 0.91)], startPoint: .top, endPoint: .bottom); GeometryReader { _ in Canvas { context, size in for x in stride(from: 0, through: size.width, by: 28) { var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) }; for y in stride(from: 0, through: size.height, by: 28) { var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) } }.overlay { RoundedRectangle(cornerRadius: 26).stroke(OneTheme.accentBlue.opacity(0.45), lineWidth: 2).padding(.horizontal, 42).padding(.vertical, 180).overlay { if labels.isEmpty { Label("No room map yet", systemImage: "map") .font(.headline) .foregroundStyle(OneTheme.secondaryInk) } else { HStack(spacing: 18) { ForEach(Array(labels.enumerated()), id: \.offset) { index, label in RoomMapPin(title: label, color: index.isMultiple(of: 2) ? OneTheme.accentCyan : OneTheme.accentBlue) } }.padding(.horizontal, 48) } } } } }.accessibilityElement(children: .combine).accessibilityLabel(labels.isEmpty ? "No room map available" : "Room map with \(labels.joined(separator: ", "))") } }

struct RoomMapPin: View { let title: String; let color: Color; var body: some View { VStack(spacing: 5) { Circle().fill(color).frame(width: 30, height: 30).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 6); Text(title).font(.caption.weight(.semibold)).foregroundStyle(OneTheme.ink).padding(.horizontal, 8).padding(.vertical, 4).background(OneTheme.surface, in: Capsule()) } } }

struct MapEvidenceSheet: View {
    @Bindable var store: AppStore
    @State private var showScanSetup = false
    @State private var calibrationCamera: PairedCamera?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Home map").font(.largeTitle.weight(.bold)).tracking(-1)
                            Text(
                                store.scene.source == .roomplanLidar3D && store.scene.isRenderable3D
                                    ? "Native RoomPlan · metric 3D"
                                    : store.scene.source == .arkitVideo3D && store.scene.isRenderable3D
                                        ? "ARKit video · approximate metric 3D"
                                        : "Approximate locations · local view"
                            )
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                        }
                        Spacer()
                        Button { showScanSetup = true } label: {
                            Image(systemName: "viewfinder").font(.title3).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Update room scan")
                    }

                    if store.scene.isRenderable3D {
                        SurfaceCard(radius: 20) {
                            Label(
                                store.scene.source == .roomplanLidar3D
                                    ? (store.scene.hasReadyUSDZ ? "LiDAR model available" : "LiDAR geometry available · 3D asset pending")
                                    : (store.scene.hasReadyUSDZ ? "ARKit video model available" : "ARKit geometry available · 3D asset pending"),
                                systemImage: store.scene.hasReadyUSDZ ? "cube.fill" : "arrow.triangle.2.circlepath"
                            )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OneTheme.accentBlue)
                                .padding(16)
                        }
                        if store.scene.source == .roomplanLidar3D {
                            CameraRegistrationStatusCard(registration: store.scene.cameraRegistration)
                            if let camera = store.pairedCameras.first(where: { $0.calibrationNeeded }) {
                                SurfaceCard(radius: 20) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 10) {
                                            Label("Calibration needed", systemImage: "scope")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(OneTheme.amber)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(OneTheme.amber.opacity(0.12), in: Capsule())
                                            Spacer()
                                        }
                                        Text(camera.name)
                                            .font(.headline)
                                            .foregroundStyle(OneTheme.ink)
                                        Text("The LiDAR map is ready, but this fixed camera still needs a reviewed position before its observations can be projected into the room.")
                                            .font(.caption)
                                            .foregroundStyle(OneTheme.secondaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Button {
                                            calibrationCamera = camera
                                        } label: {
                                            Label("Calibrate camera", systemImage: "camera.viewfinder")
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(OneTheme.accentBlue)
                                    }
                                    .padding(16)
                                }
                            }
                        }
                    } else if store.events.isEmpty {
                        SurfaceCard(radius: 20) {
                            Label("No observations yet", systemImage: "tray").font(.subheadline).foregroundStyle(OneTheme.secondaryInk).padding(16)
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(store.events.prefix(3)) { event in
                                EventRow(event: event)
                                if event.id != store.events.prefix(3).last?.id { Divider() }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(.regularMaterial)
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showScanSetup) {
            NavigationStack { ScanView(store: store) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $calibrationCamera) { camera in
            CameraCalibrationSheet(store: store, camera: camera)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
    }
}

private struct CameraRegistrationStatusCard: View {
    let registration: CameraRegistrationDescriptor?

    private var copy: (title: String, detail: String) {
        switch registration?.status ?? .unavailable {
        case .positioned:
            return ("Camera positioned", "Placed in the RoomPlan coordinate frame.")
        case .needsRescan:
            return ("Camera placement needs another attempt", "Keep the fixed camera still and retry Position this camera in 3D from that camera's own live view.")
        case .unavailable:
            return ("Camera placement pending", "The LiDAR map is ready. Position the fixed Mac or browser camera later from its own live view; the room does not need another LiDAR scan.")
        }
    }

    var body: some View {
        let state = registration?.status ?? .unavailable
        SurfaceCard(radius: 20) {
            HStack(spacing: 12) {
                Image(systemName: state == .positioned ? "camera.viewfinder" : "camera.badge.ellipsis")
                    .foregroundStyle(state == .positioned ? OneTheme.accentBlue : OneTheme.secondaryInk)
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.title)
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

private enum RoomScanSetupStep: Int, CaseIterable {
    case prepare, camera, scan, complete
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

    private var stepNumber: Int { step.rawValue + 1 }
    private var canGoBack: Bool { step != .prepare && step != .complete && !store.isRoomPlanUploading }
    private var usesLiDAR: Bool { RoomPlanCapability.isSupported }
    private var canCaptureRoom: Bool { usesLiDAR || ARVideoRoomCaptureCapability.isSupported }

    var body: some View {
        ZStack {
            if showCapture && usesLiDAR {
                RoomPlanCaptureView(isCapturing: $isCapturing) { result in
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
                            .padding(.bottom, 24)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    setupFooter
                        .frame(maxWidth: .infinity)
                        .background(OneTheme.canvas.opacity(0.98).ignoresSafeArea(edges: .horizontal))
                }
            }
        }
        .background(OneBackground())
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(showCapture || store.isRoomPlanUploading)
        .toolbar {
            if showCapture && canCaptureRoom {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", role: .cancel) {
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
                    Button("Close") { dismiss() }
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
                setupTitle(
                    eyebrow: "MAP THE ROOM",
                    title: "Create a metric 3D home map.",
                    body: usesLiDAR
                        ? "Walk around the room with this iPhone. ONE uses RoomPlan, RGB frames, and LiDAR depth to build the most precise native map."
                        : "Walk around the room with this iPhone. ONE uses ARKit camera motion and tracked floor and wall planes to build an approximate metric 3D model without LiDAR."
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
                    Label("LiDAR and RoomPlan are available on this device.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.accentBlue)
                } else if ARVideoRoomCaptureCapability.isSupported {
                    Label("This iPhone will use the LiDAR-free ARKit video scan.", systemImage: "video.fill")
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
                setupTitle(eyebrow: "CAMERA PLACEMENT", title: usesLiDAR ? "Tell ONE what this iPhone is doing." : "Save the room map first.", body: usesLiDAR ? "For a Mac or browser camera, scan the map only. The fixed camera can be positioned later." : "The fixed room camera is not needed for this scan. Build the room from this iPhone now and set up cameras later.")
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
                setupTitle(eyebrow: "READY TO SCAN", title: "Walk the room once, carefully.", body: usesLiDAR ? "The RoomPlan camera view will open full screen. Move steadily and cover several viewpoints. When the room is complete, tap Done scanning." : "The ARKit camera view will open full screen. Move steadily around the room, keeping the floor and walls visible. When coverage is stable, tap Done scanning.")
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
                        HStack(spacing: 12) {
                            ProgressView().tint(OneTheme.accentBlue)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Building the 3D map").font(.headline)
                                Text(usesLiDAR ? "Saving native geometry and preparing localization landmarks." : "Saving ARKit floor and wall geometry and generating the USDZ model.")
                                    .font(.caption)
                                    .foregroundStyle(OneTheme.secondaryInk)
                            }
                        }
                        .padding(18)
                    }
                }
                errorMessages
            }

        case .complete:
            VStack(alignment: .leading, spacing: 20) {
                setupTitle(eyebrow: "MAP SAVED", title: "Room setup is complete.", body: usesLiDAR ? (selectedCameraID == nil ? "The metric RoomPlan map is saved. Camera positioning can be completed later." : "The metric RoomPlan map is saved and ONE has attempted to register this iPhone directly.") : "The approximate metric ARKit room model is saved. It was created without LiDAR and without using a fixed live camera.")
                SurfaceCard(radius: 24) {
                    Label(usesLiDAR ? "3D RoomPlan map saved" : "3D ARKit video map saved", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(OneTheme.accentBlue)
                        .padding(18)
                }
                if usesLiDAR, store.scene.isRenderable3D {
                    CameraRegistrationStatusCard(registration: store.scene.cameraRegistration)
                }
                errorMessages
            }
        }
    }

    private func setupTitle(eyebrow: String, title: String, body: String) -> some View {
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
        if let authError = store.authError {
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
                        if store.isRoomPlanUploading {
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
                .disabled(store.isRoomPlanUploading || (step == .prepare && !canCaptureRoom))
            }
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var primaryActionTitle: String {
        if store.isRoomPlanUploading { return "Saving…" }
        switch step {
        case .prepare, .camera: return "Continue"
        case .scan: return usesLiDAR ? "Start LiDAR scan" : "Start room video scan"
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
        case .complete:
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
            Task { @MainActor in
                let saved = await store.uploadRoomPlan(capture, cameraID: selectedCameraID)
                if saved {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { step = .complete }
                }
            }
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
    }
}

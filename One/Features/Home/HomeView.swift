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
                    EventsView(store: store).tabItem { Label("Events", systemImage: "bell") }.tag("events")
                    SettingsView(store: store).tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("settings")
                }
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarBackground(.regularMaterial, for: .tabBar)
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
    @State private var selectedPill = "Today"
    @State private var showCameraSetup = false
    @State private var showCareSpaces = false
    private let pills = ["Today", "Objects", "Cameras", "Check-in"]
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        OneBrandMark(compact: true)
                        Text("Your home, in view.").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.4).foregroundStyle(OneTheme.ink)
                        Text("A calm, human-readable picture of today.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                    }
                    CareSpaceContextButton(space: store.activeCareSpace, isLoading: store.isCareSpacesLoading) {
                        showCareSpaces = true
                    }
                    if store.runtimeConfiguration.isDemoMode { cameraHero } else { liveCameraHero }
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(pills, id: \.self) { pill in Button { withAnimation(.snappy) { selectedPill = pill } } label: { Text(pill).font(.subheadline.weight(.semibold)).foregroundStyle(selectedPill == pill ? .white : OneTheme.ink).padding(.horizontal, 18).frame(height: 44).background(selectedPill == pill ? OneTheme.accentBlue : OneTheme.surface, in: Capsule()).overlay { if selectedPill != pill { Capsule().stroke(OneTheme.secondaryInk.opacity(0.3), lineWidth: 0.75) } } }.buttonStyle(.plain).accessibilityAddTraits(selectedPill == pill ? .isSelected : []) } } }.scrollIndicators(.hidden)
                    if store.runtimeConfiguration.isDemoMode { contentForPill } else { liveContentForPill }
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 34)
            }
            .refreshable {
                await store.refreshCareSpaces()
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
#if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-one-show-care-spaces")
                || ProcessInfo.processInfo.arguments.contains("-one-show-care-space-create") {
                showCareSpaces = true
            }
        }
#endif
    }
    private var cameraHero: some View { ZStack(alignment: .bottomLeading) { RoundedRectangle(cornerRadius: 30, style: .continuous).fill(LinearGradient(colors: [OneTheme.inverseSurface, OneTheme.accentBlue.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 236); VStack { HStack { Label("LIVING ROOM CAMERA", systemImage: "video.fill").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.white.opacity(0.9)); Spacer(); HStack(spacing: 6) { Circle().fill(OneTheme.accentCyan).frame(width: 9, height: 9); Text("LIVE").font(.caption2.weight(.bold)).foregroundStyle(.white) } }; Spacer(); Image(systemName: "camera.metering.center.weighted.average").font(.system(size: 76, weight: .thin)).foregroundStyle(.white.opacity(0.42)); Spacer(); HStack { Text("A steady view of the room").font(.title3.weight(.semibold)).foregroundStyle(.white); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.white) } }.padding(20) }.accessibilityElement(children: .combine).accessibilityLabel("Living room camera, live. A steady view of the room.") }
    private var primaryLiveCamera: PairedCamera? { store.pairedCameras.first }
    private var hasOnlineCamera: Bool { store.pairedCameras.contains { $0.status == "online" } }
    private var liveCameraHero: some View { ZStack(alignment: .bottomLeading) { RoundedRectangle(cornerRadius: 30, style: .continuous).fill(LinearGradient(colors: [OneTheme.inverseSurface, hasOnlineCamera ? OneTheme.accentBlue.opacity(0.78) : OneTheme.secondaryInk.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 236); VStack { HStack { Label((primaryLiveCamera?.name ?? "CAMERA SETUP").uppercased(), systemImage: "video.fill").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.white.opacity(0.9)); Spacer(); Text(primaryLiveCamera?.status.uppercased() ?? "NOT PAIRED").font(.caption2.weight(.bold)).foregroundStyle(.white) }; Spacer(); Image(systemName: store.cameraCount == 0 ? "video.slash" : (hasOnlineCamera ? "video.fill" : "video.badge.ellipsis")).font(.system(size: 76, weight: .thin)).foregroundStyle(.white.opacity(0.42)); Spacer(); HStack { Text(store.cameraCount == 0 ? "No room camera connected" : (hasOnlineCamera ? "Live camera available" : "Camera paired · currently paused")).font(.title3.weight(.semibold)).foregroundStyle(.white); Spacer(); Image(systemName: hasOnlineCamera ? "checkmark.circle.fill" : "arrow.up.right").foregroundStyle(.white) } }.padding(20) }.accessibilityElement(children: .combine).accessibilityLabel(store.cameraCount == 0 ? "No room camera connected" : "\(store.cameraCount) paired camera devices, \(hasOnlineCamera ? "online" : "not currently online")") }
    @ViewBuilder private var contentForPill: some View { if selectedPill == "Objects" { objectsSection } else if selectedPill == "Cameras" { camerasSection } else if selectedPill == "Check-in" { checkInSection } else { todaySection } }
    @ViewBuilder private var liveContentForPill: some View { if selectedPill == "Objects" { liveObjectsSection } else if selectedPill == "Cameras" { liveCamerasSection } else if selectedPill == "Check-in" { liveCheckInSection } else { liveTodaySection } }
    private var liveTodaySection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("TODAY", "Live observations"); if store.events.isEmpty { liveEmptyCard(title: "No observations yet", detail: "ONE will show backend observations here when the household records them.", symbol: "tray") } else { ForEach(store.events.prefix(3)) { event in EventRow(event: event) } }; liveHouseholdRows } }
    private var liveObjectsSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("MEMORY", "Mapped objects"); if store.scan.objects.isEmpty { liveEmptyCard(title: "No mapped objects yet", detail: "Upload a room map or record an observation to add household objects.", symbol: "square.3.layers.3d") } else { ForEach(store.scan.objects) { object in ObjectCard(title: object.name, subtitle: "Live backend object · \(object.confidence.title) confidence", symbol: "cube.fill", color: OneTheme.accentCyan) } } } }
    private var liveCamerasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                sectionHeading("CAMERAS", "Connected devices")
                Spacer()
                if store.role != .resident {
                    Button {
                        showCameraSetup = true
                    } label: {
                        Label("Pair camera", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OneTheme.accentBlue)
                }
            }
            if store.pairedCameras.isEmpty {
                liveEmptyCard(title: "No cameras connected", detail: "Pair a phone or laptop that will stay in the room. ONE will show it here only after the publisher code is completed.", symbol: "video.badge.plus")
            } else {
                ForEach(store.pairedCameras) { camera in
                    SurfaceCard(radius: 24) {
                        HStack(spacing: 14) {
                            Image(systemName: camera.status == "online" ? "video.fill" : "video.slash")
                                .font(.title2)
                                .foregroundStyle(camera.status == "online" ? OneTheme.accentBlue : OneTheme.secondaryInk)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(camera.name).font(.headline)
                                Text(camera.status == "online" ? "Connected to the local ONE backend" : camera.status.capitalized)
                                    .font(.subheadline)
                                    .foregroundStyle(OneTheme.secondaryInk)
                            }
                            Spacer()
                            Circle()
                                .fill(camera.status == "online" ? OneTheme.mint : OneTheme.amber)
                                .frame(width: 11, height: 11)
                                .accessibilityLabel(camera.status)
                        }
                        .padding(18)
                    }
                }
            }
            Text("Status comes from the authenticated local backend. Camera viewing remains consent-based.").font(.footnote).foregroundStyle(OneTheme.secondaryInk)
        }
        .sheet(isPresented: $showCameraSetup) {
            CameraPairingSheet(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
    private var liveCheckInSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("CHECK-IN", "A human signal"); if let event = store.events.first(where: { $0.kind == .checkIn }) { EventRow(event: event) } else { liveEmptyCard(title: "No check-in recorded", detail: "A check-in will appear here after the backend records one.", symbol: "checkmark.circle") } } }
    private var liveHouseholdRows: some View { VStack(spacing: 0) { householdRow("Backend status", store.backendState.label, "network", OneTheme.accentBlue); Divider(); householdRow("Available observations", "\(store.events.count)", "list.bullet.rectangle", OneTheme.mint) }.padding(.horizontal, 4) }
    private func liveEmptyCard(title: String, detail: String, symbol: String) -> some View { SurfaceCard(radius: 24) { Label { VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(OneTheme.secondaryInk) } } icon: { Image(systemName: symbol).font(.title2).foregroundStyle(OneTheme.accentBlue) }.padding(18) } }
    private var todaySection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("TODAY", "Observed objects"); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { ObjectCard(title: "Blue mug", subtitle: "Kitchen · remembered", symbol: "cup.and.saucer.fill", color: OneTheme.accentCyan); ObjectCard(title: "Front door", subtitle: "Entry · mapped", symbol: "door.left.hand.open", color: OneTheme.accentBlue); ObjectCard(title: "Reading chair", subtitle: "Living room", symbol: "chair.lounge.fill", color: OneTheme.mint) } }.scrollIndicators(.hidden); householdRows } }
    private var objectsSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("MEMORY", "Objects in the map"); ObjectCard(title: "Blue mug", subtitle: "Kitchen · high confidence", symbol: "cup.and.saucer.fill", color: OneTheme.accentCyan); ObjectCard(title: "Front door", subtitle: "Entry · medium confidence", symbol: "door.left.hand.open", color: OneTheme.accentBlue); Text("Pins are approximate and show a confidence radius.").font(.footnote).foregroundStyle(OneTheme.secondaryInk) } }
    private var camerasSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("CAMERAS", "Paired views"); SurfaceCard(radius: 24) { HStack { Image(systemName: "video.fill").font(.title2).foregroundStyle(OneTheme.accentBlue); VStack(alignment: .leading) { Text("Living room").font(.headline); Text(store.backendState == .connected ? "Backend connected · live on local network" : "Calibrated · \(store.backendState.label)").font(.subheadline).foregroundStyle(OneTheme.secondaryInk) }; Spacer(); Circle().fill(store.backendState == .unavailable ? OneTheme.amber : OneTheme.mint).frame(width: 12).accessibilityLabel(store.backendState.label) }.padding(18) }; Text("Camera viewing is local and consent-based.").font(.footnote).foregroundStyle(OneTheme.secondaryInk) } }
    private var checkInSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("CHECK-IN", "A human signal"); SurfaceCard(radius: 24) { VStack(alignment: .leading, spacing: 12) { Label("Completed today", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(OneTheme.mint); Text("A familiar morning check-in was completed. The trend is compared with the resident’s own recent rhythm.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk); Text("Observation, not diagnosis.").font(.caption.weight(.semibold)).foregroundStyle(OneTheme.amber) }.padding(20) } } }
    private var householdRows: some View { VStack(spacing: 0) { householdRow("Household status", "All connected", "checkmark.circle.fill", OneTheme.mint); Divider(); householdRow("This week’s plan", "3 check-ins · 1 review", "calendar", OneTheme.accentBlue) }.padding(.horizontal, 4) }
    private func householdRow(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View { HStack(spacing: 12) { Image(systemName: symbol).foregroundStyle(color).frame(width: 28); VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.subheadline).foregroundStyle(OneTheme.secondaryInk) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(.vertical, 14) }
    private func sectionHeading(_ eyebrow: String, _ title: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(eyebrow).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(OneTheme.secondaryInk); Text(title).font(.title2.weight(.bold)).tracking(-0.5).foregroundStyle(OneTheme.ink) } }
}

private struct CameraPairingSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var label = "Room camera"
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
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    pairingFooter
                        .frame(width: contentWidth)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
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

    private var pairingFooter: some View {
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
        .padding(.horizontal, 2)
        .padding(.vertical, 12)
        .background(OneTheme.canvas.opacity(0.98))
        .overlay {
            Rectangle()
                .fill(OneTheme.secondaryInk.opacity(0.10))
                .frame(height: 0.5)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        }
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
            await store.startCameraPairing(label: normalizedLabel)
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
            await store.startCameraPairing(label: normalizedLabel)
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

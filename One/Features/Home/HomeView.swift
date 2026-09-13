import SwiftUI

struct CaregiverShell: View {
    @Bindable var store: AppStore
    var body: some View {
        TabView(selection: $store.selectedTab) {
            HomeView(store: store).tabItem { Label("Home", systemImage: "house.fill") }.tag("overview")
            MapView(store: store).tabItem { Label("Map", systemImage: "map.fill") }.tag("map")
            FamilyView(store: store).tabItem { Label("Family", systemImage: "person.2.fill") }.tag("family")
            EventsView(store: store).tabItem { Label("Events", systemImage: "bell") }.tag("events")
            SettingsView(store: store).tabItem { Label("Account", systemImage: "person.crop.circle") }.tag("settings")
        }.toolbarBackground(.visible, for: .tabBar).toolbarBackground(.regularMaterial, for: .tabBar)
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
                    if store.runtimeConfiguration.isDemoMode { cameraHero } else { liveCameraHero }
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(pills, id: \.self) { pill in Button { withAnimation(.snappy) { selectedPill = pill } } label: { Text(pill).font(.subheadline.weight(.semibold)).foregroundStyle(selectedPill == pill ? .white : OneTheme.ink).padding(.horizontal, 18).frame(height: 44).background(selectedPill == pill ? OneTheme.accentBlue : OneTheme.surface, in: Capsule()).overlay { if selectedPill != pill { Capsule().stroke(OneTheme.secondaryInk.opacity(0.3), lineWidth: 0.75) } } }.buttonStyle(.plain).accessibilityAddTraits(selectedPill == pill ? .isSelected : []) } } }.scrollIndicators(.hidden)
                    if store.runtimeConfiguration.isDemoMode { contentForPill } else { liveContentForPill }
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 34)
            }.background(OneTheme.canvas.ignoresSafeArea()).safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 88) }.toolbar(.hidden, for: .navigationBar)
        }
    }
    private var cameraHero: some View { ZStack(alignment: .bottomLeading) { RoundedRectangle(cornerRadius: 30, style: .continuous).fill(LinearGradient(colors: [OneTheme.inverseSurface, OneTheme.accentBlue.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 236); VStack { HStack { Label("LIVING ROOM CAMERA", systemImage: "video.fill").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.white.opacity(0.9)); Spacer(); HStack(spacing: 6) { Circle().fill(OneTheme.accentCyan).frame(width: 9, height: 9); Text("LIVE").font(.caption2.weight(.bold)).foregroundStyle(.white) } }; Spacer(); Image(systemName: "camera.metering.center.weighted.average").font(.system(size: 76, weight: .thin)).foregroundStyle(.white.opacity(0.42)); Spacer(); HStack { Text("A steady view of the room").font(.title3.weight(.semibold)).foregroundStyle(.white); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.white) } }.padding(20) }.accessibilityElement(children: .combine).accessibilityLabel("Living room camera, live. A steady view of the room.") }
    private var liveCameraHero: some View { ZStack(alignment: .bottomLeading) { RoundedRectangle(cornerRadius: 30, style: .continuous).fill(LinearGradient(colors: [OneTheme.inverseSurface, OneTheme.secondaryInk.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 236); VStack { HStack { Label("CAMERA SETUP", systemImage: "video.fill").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.white.opacity(0.9)); Spacer(); Text(store.cameraCount == 0 ? "NOT PAIRED" : "CONNECTED").font(.caption2.weight(.bold)).foregroundStyle(.white) }; Spacer(); Image(systemName: store.cameraCount == 0 ? "video.slash" : "video.fill").font(.system(size: 76, weight: .thin)).foregroundStyle(.white.opacity(0.42)); Spacer(); HStack { Text(store.cameraCount == 0 ? "No live camera connected" : "Live camera available").font(.title3.weight(.semibold)).foregroundStyle(.white); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.white) } }.padding(20) }.accessibilityElement(children: .combine).accessibilityLabel(store.cameraCount == 0 ? "No live camera connected" : "Live camera available") }
    @ViewBuilder private var contentForPill: some View { if selectedPill == "Objects" { objectsSection } else if selectedPill == "Cameras" { camerasSection } else if selectedPill == "Check-in" { checkInSection } else { todaySection } }
    @ViewBuilder private var liveContentForPill: some View { if selectedPill == "Objects" { liveObjectsSection } else if selectedPill == "Cameras" { liveCamerasSection } else if selectedPill == "Check-in" { liveCheckInSection } else { liveTodaySection } }
    private var liveTodaySection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("TODAY", "Live observations"); if store.events.isEmpty { liveEmptyCard(title: "No observations yet", detail: "ONE will show backend observations here when the household records them.", symbol: "tray") } else { ForEach(store.events.prefix(3)) { event in EventRow(event: event) } }; liveHouseholdRows } }
    private var liveObjectsSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("MEMORY", "Mapped objects"); if store.scan.objects.isEmpty { liveEmptyCard(title: "No mapped objects yet", detail: "Upload a room map or record an observation to add household objects.", symbol: "square.3.layers.3d") } else { ForEach(store.scan.objects) { object in ObjectCard(title: object.name, subtitle: "Live backend object · \(object.confidence.title) confidence", symbol: "cube.fill", color: OneTheme.accentCyan) } } } }
    private var liveCamerasSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("CAMERAS", "Connected devices"); SurfaceCard(radius: 24) { HStack { Image(systemName: store.cameraCount == 0 ? "video.slash" : "video.fill").font(.title2).foregroundStyle(OneTheme.accentBlue); VStack(alignment: .leading) { Text(store.cameraCount == 0 ? "No cameras connected" : "\(store.cameraCount) camera\(store.cameraCount == 1 ? "" : "s") connected").font(.headline); Text("Status: \(store.backendState.label)").font(.subheadline).foregroundStyle(OneTheme.secondaryInk) }; Spacer() }.padding(18) }; Text("Camera viewing is local and consent-based.").font(.footnote).foregroundStyle(OneTheme.secondaryInk) } }
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

struct ObjectCard: View { let title: String; let subtitle: String; let symbol: String; let color: Color; var body: some View { SurfaceCard(radius: 24) { VStack(alignment: .leading, spacing: 10) { ZStack { RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [color.opacity(0.7), OneTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing)); Image(systemName: symbol).font(.system(size: 38, weight: .medium)).foregroundStyle(OneTheme.ink) }.frame(width: 188, height: 100); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(OneTheme.secondaryInk) }.padding(12) } } }

struct ResidentHomeView: View { @Bindable var store: AppStore; var body: some View { NavigationStack { VStack(alignment: .leading, spacing: 24) { Text("Today").font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.2); Text("A little support for a more independent day.").font(.title3).foregroundStyle(OneTheme.secondaryInk); Spacer(); Button { store.selectedTab = "assistant" } label: { Label("Start check-in", systemImage: "waveform").font(.headline).frame(maxWidth: .infinity).padding(18) }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue); Spacer() }.padding(20).background(OneTheme.canvas.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar) } } }

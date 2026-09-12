import SwiftUI

struct RootView: View {
    @Bindable var store: AppStore
    var body: some View {
        if !store.isAuthenticated { LoginView(store: store) }
        else if store.requiresOnboarding { OnboardingView(store: store) }
        else if store.role == .caregiver { CaregiverShell(store: store) }
        else { ResidentShell(store: store) }
    }
}

struct LoginView: View {
    @Bindable var store: AppStore
    @State private var pairingCode = ""
    @State private var emailCode = ""
    @State private var emailChallenge = false
    @State private var isSubmitting = false
    @State private var mode = 0
    @State private var name = ""
    @State private var email = ""
    @State private var homeName = ""
    @State private var consent = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("ONE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(OneTheme.accentBlue)
            Text("Sign in to your home.").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.2).foregroundStyle(OneTheme.ink)
            Text("Use your email to keep your household with you when you change phones. Camera pairing remains device-scoped.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
            Picker("Account action", selection: $mode) { Text("Sign in").tag(0); Text("Create household").tag(1); Text("Join household").tag(2) }.pickerStyle(.segmented)
            if mode == 1 {
                TextField("Your name", text: $name).textFieldStyle(.roundedBorder)
                TextField("Email", text: $email).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                TextField("Household name", text: $homeName).textFieldStyle(.roundedBorder)
                Toggle("I consent to ONE storing household account data needed for this service.", isOn: $consent).tint(OneTheme.accentBlue).font(.footnote)
                if emailChallenge { TextField("Email code", text: $emailCode).textFieldStyle(.roundedBorder).keyboardType(.numberPad).accessibilityLabel("Email verification code") }
            } else {
                if mode == 0 {
                    TextField("Email", text: $email).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    if emailChallenge { TextField("Email code", text: $emailCode).textFieldStyle(.roundedBorder).keyboardType(.numberPad).accessibilityLabel("Email verification code") }
                } else {
                    TextField("Invitation code", text: $pairingCode).textInputAutocapitalization(.characters).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityLabel("Invitation code")
                    TextField("Invited email", text: $email).textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField("Your name (optional)", text: $name).textFieldStyle(.roundedBorder)
                }
            }
            if let authError = store.authError { Text(authError).font(.footnote).foregroundStyle(OneTheme.amber).accessibilityAddTraits(.isStaticText) }
            Button { isSubmitting = true; Task { if mode == 0 || mode == 1 { if emailChallenge { await store.login(email: email, code: emailCode) } else { let purpose = mode == 1 ? "create" : "login"; emailChallenge = await store.requestEmailCode(email: email, purpose: purpose, displayName: mode == 1 ? name : nil, homeName: homeName.isEmpty ? "ONE Home" : homeName) != nil } } else { await store.acceptFamilyInvite(code: pairingCode, displayName: name.isEmpty ? nil : name, email: email.isEmpty ? nil : email) }; isSubmitting = false } } label: { Label(isSubmitting ? "Working…" : (mode == 0 ? (emailChallenge ? "Sign in" : "Email me a code") : mode == 1 ? (emailChallenge ? "Verify account" : "Email me a code") : "Join household"), systemImage: "arrow.right").frame(maxWidth: .infinity).padding(16) }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue).disabled(isSubmitting || (mode == 1 ? (name.isEmpty || email.isEmpty || !consent || (emailChallenge && emailCode.isEmpty)) : mode == 0 ? (email.isEmpty || (emailChallenge && emailCode.isEmpty)) : (pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.isEmpty))).accessibilityHint("Account access is protected by a backend session")
            Spacer()
        }.padding(24).background(OneTheme.canvas.ignoresSafeArea()).onChange(of: mode) { _, _ in emailChallenge = false; emailCode = ""; pairingCode = ""; store.authError = nil }.task { await store.checkBackend() }
    }
}

struct OnboardingView: View {
    @Bindable var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            Text("ONE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(OneTheme.accentBlue)
            if store.onboardingStep == 0 { Text("Welcome to your home.").font(.largeTitle.weight(.bold)); Text("ONE helps your care circle notice daily rhythms with clarity and consent.").foregroundStyle(OneTheme.secondaryInk) }
            else if store.onboardingStep == 1 { Text("Choose what ONE may use.").font(.largeTitle.weight(.bold)); Text("You can change these choices later in Account.").foregroundStyle(OneTheme.secondaryInk); ForEach(Array(store.onboardingConsents.keys.sorted()), id: \.self) { purpose in Toggle(purpose, isOn: Binding(get: { store.onboardingConsents[purpose] ?? false }, set: { store.onboardingConsents[purpose] = $0 })).tint(OneTheme.accentBlue) } }
            else if store.onboardingStep == 2 { Text("Set up at your pace.").font(.largeTitle.weight(.bold)); Text("Camera pairing and inviting family are optional. You can do them later from the care circle.").foregroundStyle(OneTheme.secondaryInk); Label("No camera or family access is enabled automatically.", systemImage: "lock.shield").font(.footnote) }
            else { Text("You’re ready.").font(.largeTitle.weight(.bold)); Text("Your choices are saved. ONE will keep observations understandable and non-diagnostic.").foregroundStyle(OneTheme.secondaryInk) }
            if let authError = store.authError { Text(authError).font(.footnote).foregroundStyle(OneTheme.amber).accessibilityAddTraits(.isStaticText) }
            Spacer()
            Button { Task { let saved = store.onboardingStep == 1 ? await store.recordOnboardingConsents() : true; guard saved else { return }; if store.onboardingStep < 2 { store.onboardingStep += 1 } else { store.completeOnboarding() } } } label: { Text(store.onboardingStep < 2 ? "Continue" : "Finish setup").frame(maxWidth: .infinity).padding(16) }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue)
        }.padding(24).background(OneTheme.canvas.ignoresSafeArea()).accessibilityElement(children: .contain)
    }
}

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
                        Text("ONE").font(.caption.weight(.bold)).tracking(2).foregroundStyle(OneTheme.accentBlue)
                        Text("Your home, in view.").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.4).foregroundStyle(OneTheme.ink)
                        Text("A calm, human-readable picture of today.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                    }
                    cameraHero
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { ForEach(pills, id: \.self) { pill in Button { withAnimation(.snappy) { selectedPill = pill } } label: { Text(pill).font(.subheadline.weight(.semibold)).foregroundStyle(selectedPill == pill ? .white : OneTheme.ink).padding(.horizontal, 18).frame(height: 44).background(selectedPill == pill ? OneTheme.accentBlue : OneTheme.surface, in: Capsule()).overlay { if selectedPill != pill { Capsule().stroke(OneTheme.secondaryInk.opacity(0.3), lineWidth: 0.75) } } }.buttonStyle(.plain).accessibilityAddTraits(selectedPill == pill ? .isSelected : []) } } }.scrollIndicators(.hidden)
                    contentForPill
                }.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 34)
            }.background(OneTheme.canvas.ignoresSafeArea()).safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 88) }.toolbar(.hidden, for: .navigationBar)
        }
    }
    private var cameraHero: some View { ZStack(alignment: .bottomLeading) { RoundedRectangle(cornerRadius: 30, style: .continuous).fill(LinearGradient(colors: [OneTheme.inverseSurface, OneTheme.accentBlue.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(height: 236); VStack { HStack { Label("LIVING ROOM CAMERA", systemImage: "video.fill").font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.white.opacity(0.9)); Spacer(); HStack(spacing: 6) { Circle().fill(OneTheme.accentCyan).frame(width: 9, height: 9); Text("LIVE").font(.caption2.weight(.bold)).foregroundStyle(.white) } }; Spacer(); Image(systemName: "camera.metering.center.weighted.average").font(.system(size: 76, weight: .thin)).foregroundStyle(.white.opacity(0.42)); Spacer(); HStack { Text("A steady view of the room").font(.title3.weight(.semibold)).foregroundStyle(.white); Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(.white) } }.padding(20) }.accessibilityElement(children: .combine).accessibilityLabel("Living room camera, live. A steady view of the room.") }
    @ViewBuilder private var contentForPill: some View { if selectedPill == "Objects" { objectsSection } else if selectedPill == "Cameras" { camerasSection } else if selectedPill == "Check-in" { checkInSection } else { todaySection } }
    private var todaySection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("TODAY", "Observed objects"); ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 14) { ObjectCard(title: "Blue mug", subtitle: "Kitchen · remembered", symbol: "cup.and.saucer.fill", color: OneTheme.accentCyan); ObjectCard(title: "Front door", subtitle: "Entry · mapped", symbol: "door.left.hand.open", color: OneTheme.accentBlue); ObjectCard(title: "Reading chair", subtitle: "Living room", symbol: "chair.lounge.fill", color: OneTheme.mint) } }.scrollIndicators(.hidden); householdRows } }
    private var objectsSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("MEMORY", "Objects in the map"); ObjectCard(title: "Blue mug", subtitle: "Kitchen · high confidence", symbol: "cup.and.saucer.fill", color: OneTheme.accentCyan); ObjectCard(title: "Front door", subtitle: "Entry · medium confidence", symbol: "door.left.hand.open", color: OneTheme.accentBlue); Text("Pins are approximate and show a confidence radius.").font(.footnote).foregroundStyle(OneTheme.secondaryInk) } }
    private var camerasSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("CAMERAS", "Paired views"); SurfaceCard(radius: 24) { HStack { Image(systemName: "video.fill").font(.title2).foregroundStyle(OneTheme.accentBlue); VStack(alignment: .leading) { Text("Living room").font(.headline); Text(store.backendState == .connected ? "Backend connected · live on local network" : "Calibrated · \(store.backendState.label)").font(.subheadline).foregroundStyle(OneTheme.secondaryInk) }; Spacer(); Circle().fill(store.backendState == .unavailable ? OneTheme.amber : OneTheme.mint).frame(width: 12).accessibilityLabel(store.backendState.label) }.padding(18) }; Text("Camera viewing is local and consent-based.").font(.footnote).foregroundStyle(OneTheme.secondaryInk) } }
    private var checkInSection: some View { VStack(alignment: .leading, spacing: 14) { sectionHeading("CHECK-IN", "A human signal"); SurfaceCard(radius: 24) { VStack(alignment: .leading, spacing: 12) { Label("Completed today", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(OneTheme.mint); Text("A familiar morning check-in was completed. The trend is compared with the resident’s own recent rhythm.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk); Text("Observation, not diagnosis.").font(.caption.weight(.semibold)).foregroundStyle(OneTheme.amber) }.padding(20) } } }
    private var householdRows: some View { VStack(spacing: 0) { householdRow("Household status", "All connected", "checkmark.circle.fill", OneTheme.mint); Divider(); householdRow("This week’s plan", "3 check-ins · 1 review", "calendar", OneTheme.accentBlue) }.padding(.horizontal, 4) }
    private func householdRow(_ title: String, _ subtitle: String, _ symbol: String, _ color: Color) -> some View { HStack(spacing: 12) { Image(systemName: symbol).foregroundStyle(color).frame(width: 28); VStack(alignment: .leading) { Text(title).font(.headline); Text(subtitle).font(.subheadline).foregroundStyle(OneTheme.secondaryInk) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(.vertical, 14) }
    private func sectionHeading(_ eyebrow: String, _ title: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(eyebrow).font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(OneTheme.secondaryInk); Text(title).font(.title2.weight(.bold)).tracking(-0.5).foregroundStyle(OneTheme.ink) } }
}

struct ObjectCard: View { let title: String; let subtitle: String; let symbol: String; let color: Color; var body: some View { SurfaceCard(radius: 24) { VStack(alignment: .leading, spacing: 10) { ZStack { RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [color.opacity(0.7), OneTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing)); Image(systemName: symbol).font(.system(size: 38, weight: .medium)).foregroundStyle(OneTheme.ink) }.frame(width: 188, height: 100); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(OneTheme.secondaryInk) }.padding(12) } } }

struct MapView: View {
    @Bindable var store: AppStore
    @State private var showEvidence = true
    var body: some View {
        ZStack(alignment: .bottom) {
            RoomMapCanvas().ignoresSafeArea().onTapGesture { showEvidence = true }
            if !showEvidence { LiquidGlassControl { Button { showEvidence = true } label: { Label("Show evidence", systemImage: "line.3.horizontal.decrease.circle").padding(.horizontal, 16).padding(.vertical, 10) } }.padding(.bottom, 32) }
        }.sheet(isPresented: $showEvidence) { MapEvidenceSheet(store: store).presentationDetents([.height(245), .medium, .large]).presentationDragIndicator(.visible).presentationBackgroundInteraction(.enabled(upThrough: .medium)).presentationContentInteraction(.scrolls) }
    }
}

struct RoomMapCanvas: View {
    var body: some View { ZStack { LinearGradient(colors: [Color(red: 0.70, green: 0.90, blue: 0.94), Color(red: 0.92, green: 0.95, blue: 0.91)], startPoint: .top, endPoint: .bottom); GeometryReader { geo in Canvas { context, size in for x in stride(from: 0, through: size.width, by: 28) { var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) }; for y in stride(from: 0, through: size.height, by: 28) { var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(p, with: .color(.white.opacity(0.3)), lineWidth: 0.6) } }.overlay { RoundedRectangle(cornerRadius: 26).stroke(OneTheme.accentBlue.opacity(0.45), lineWidth: 2).padding(.horizontal, 42).padding(.vertical, 180).overlay { VStack { Spacer(); HStack { RoomMapPin(title: "Blue mug", color: OneTheme.accentCyan); Spacer(); RoomMapPin(title: "Kitchen", color: OneTheme.accentBlue) }.padding(.horizontal, 78).padding(.bottom, 300); Spacer() } } } } }.accessibilityElement(children: .combine).accessibilityLabel("Room map with Kitchen and Living room zones. Blue mug and Kitchen pins are approximate.") } }
struct RoomMapPin: View { let title: String; let color: Color; var body: some View { VStack(spacing: 5) { Circle().fill(color).frame(width: 30, height: 30).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 6); Text(title).font(.caption.weight(.semibold)).foregroundStyle(OneTheme.ink).padding(.horizontal, 8).padding(.vertical, 4).background(OneTheme.surface, in: Capsule()) } } }
struct MapEvidenceSheet: View { @Bindable var store: AppStore; var body: some View { NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) { HStack { VStack(alignment: .leading, spacing: 4) { Text("Home map").font(.largeTitle.weight(.bold)).tracking(-1); Text("Approximate locations · local view").font(.subheadline).foregroundStyle(OneTheme.secondaryInk) }; Spacer(); NavigationLink { ScanView(store: store) } label: { Image(systemName: "viewfinder").font(.title3).frame(width: 44, height: 44) }.buttonStyle(.bordered).accessibilityLabel("Update room scan") }; LazyVStack(spacing: 0) { ForEach(store.events.prefix(3)) { event in EventRow(event: event); if event.id != store.events.prefix(3).last?.id { Divider() } } } }.padding(20) }.background(.regularMaterial).navigationBarTitleDisplayMode(.inline) } } }

struct FamilyView: View {
    @Bindable var store: AppStore
    @State private var showInviteSheet = false
    @State private var showMedicationPlanSheet = false
    @State private var editingMedicationPlan: MedicationPlan?
    @State private var planToArchive: MedicationPlan?
    @State private var assistantNote = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CARE CIRCLE").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(OneTheme.accentBlue)
                        Text("Family, in sync.").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.4).foregroundStyle(OneTheme.ink)
                        Text("People, reminders, and permissions around the home.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                    }
                    Picker("Person or household", selection: $store.selectedSubjectName) {
                        Text("Everyone").tag("Everyone")
                        ForEach(store.careRecipients) { recipient in Text(recipient.name).tag(recipient.name) }
                    }.pickerStyle(.menu).accessibilityLabel("Selected person or household").onChange(of: store.selectedSubjectName) { _, value in store.selectedSubjectID = store.careRecipients.first(where: { $0.name == value })?.id; Task { await store.refreshMedicationReminders(); await store.refreshMedicationPlans() } }
                    DatePicker("Reminder date", selection: $store.selectedMedicationDate, displayedComponents: .date).datePickerStyle(.compact).onChange(of: store.selectedMedicationDate) { _, _ in Task { await store.refreshMedicationReminders() } }
                    Text("Showing plans and observations for \(store.selectedSubjectName). Switch people before reviewing sensitive details.").font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                    peopleSection
                    medicationSection
                    caregiverAssistant
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 34)
            }
            .background(OneTheme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 88) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showInviteSheet) { InviteCaregiverSheet(store: store) }
            .sheet(isPresented: $showMedicationPlanSheet) { MedicationPlanSheet(store: store, plan: editingMedicationPlan, subjectName: store.selectedSubjectName) }
            .confirmationDialog("Archive this medication plan?", item: $planToArchive) { plan in
                Button("Archive plan", role: .destructive) { Task { _ = await store.archiveMedicationPlan(plan) } }
                Button("Cancel", role: .cancel) { }
            } message: { plan in
                Text("\(plan.name) will stop creating future reminders, while its history stays available.")
            }
            .task { await store.refreshFamilyData() }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                sectionHeading("PEOPLE WITH ACCESS", "A smaller, safer circle")
                Spacer()
                Button { showInviteSheet = true } label: {
                    Image(systemName: "person.badge.plus").font(.headline).frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Invite a caregiver")
            }
            VStack(spacing: 0) {
                ForEach(store.caregivers) { caregiver in
                    CaregiverAccountRow(account: caregiver)
                    if caregiver.id != store.caregivers.last?.id { Divider().padding(.leading, 58) }
                }
            }
            .padding(.horizontal, 16).background(OneTheme.surface, in: .rect(cornerRadius: 26))
            .overlay(.black.opacity(0.04), in: .rect(cornerRadius: 26))
            Text("Roles limit what each person can view or change. ONE never grants access by default.")
                .font(.footnote).foregroundStyle(OneTheme.secondaryInk)
        }
    }

    private var medicationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                sectionHeading("TODAY'S PLAN", "Medication reminders · " + store.selectedSubjectName)
                Spacer()
                Button { editingMedicationPlan = nil; showMedicationPlanSheet = true } label: {
                    Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(OneTheme.accentBlue)
                .accessibilityLabel("Add medication reminder")
                .disabled(store.isMedicationMutating)
            }
            if let nextDose = nextDose {
                SurfaceCard(radius: 24) {
                    HStack(spacing: 14) {
                        Image(systemName: "clock.badge.checkmark").font(.title2).foregroundStyle(OneTheme.accentBlue).frame(width: 44, height: 44).background(OneTheme.accentBlue.opacity(0.11), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Next dose").font(.caption.weight(.bold)).foregroundStyle(OneTheme.secondaryInk)
                            Text(nextDose.medicationName).font(.headline)
                            Text("\(nextDose.scheduledAt.formatted(date: .omitted, time: .shortened)) · \(nextDose.instructions)").font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                        }
                        Spacer()
                    }.padding(18)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next dose, \(nextDose.medicationName), \(nextDose.scheduledAt.formatted(date: .omitted, time: .shortened)), \(nextDose.instructions)")
            }
            VStack(spacing: 0) {
                ForEach(store.medicationDoses) { dose in
                    MedicationDoseRow(dose: dose) { store.updateMedicationDose(dose.id, status: nextStatus(after: dose.status)) }
                    if dose.id != store.medicationDoses.last?.id { Divider().padding(.leading, 52) }
                }
            }
            .padding(.horizontal, 16).background(OneTheme.surface, in: .rect(cornerRadius: 26))
            .overlay(.black.opacity(0.04), in: .rect(cornerRadius: 26))
            if !store.runtimeConfiguration.isDemoMode {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("ACTIVE PLAN RULES").font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(OneTheme.secondaryInk)
                        Spacer()
                        if store.isMedicationLoading { ProgressView().controlSize(.small).accessibilityLabel("Loading medication plans") }
                    }
                    if store.medicationPlans.isEmpty && !store.isMedicationLoading {
                        Text("No active plan for this person yet. Add a schedule rule to start a shared rhythm.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk).padding(.vertical, 12)
                    }
                    ForEach(store.medicationPlans) { plan in
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(OneTheme.accentBlue).frame(width: 30, height: 30).background(OneTheme.accentBlue.opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(plan.name).font(.headline).foregroundStyle(OneTheme.ink)
                                Text("\(plan.dose) · \(plan.schedule)").font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                                if !plan.instructions.isEmpty { Text(plan.instructions).font(.caption).foregroundStyle(OneTheme.secondaryInk) }
                            }
                            Spacer()
                            Button("Edit") { editingMedicationPlan = plan; showMedicationPlanSheet = true }
                                .buttonStyle(.bordered).tint(OneTheme.accentBlue)
                                .accessibilityLabel("Edit \(plan.name)")
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { planToArchive = plan } label: { Label("Archive", systemImage: "archivebox") }
                        }
                        if plan.id != store.medicationPlans.last?.id { Divider().padding(.leading, 42) }
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .contain)
            }
            Text("Reminders support organization only. Confirm medication decisions with the resident and their care team.")
                .font(.footnote).foregroundStyle(OneTheme.secondaryInk)
        }
    }

    private var caregiverAssistant: some View {
        SurfaceCard(radius: 28) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Caregiver assistant", systemImage: "sparkles").font(.headline).foregroundStyle(OneTheme.accentCyan)
                    Spacer()
                    Image(systemName: "waveform").foregroundStyle(.white.opacity(0.7))
                }
                Text("Keep the care circle organized.").font(.title3.weight(.bold)).foregroundStyle(.white)
                Text("Draft reminders, assign a check-in, and prepare a review list. This assistant organizes information; it does not diagnose or make care decisions.").font(.subheadline).foregroundStyle(.white.opacity(0.78))
                HStack(spacing: 10) {
                    Button { assistantNote = "A reminder draft is ready for review." } label: { Label("Draft reminder", systemImage: "bell.badge").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 11) }
                    Button { assistantNote = "A check-in assignment is ready for review." } label: { Label("Assign check-in", systemImage: "person.badge.clock").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 11) }
                }
                .buttonStyle(.bordered)
                .tint(OneTheme.accentCyan)
                .foregroundStyle(.white)
                if !assistantNote.isEmpty { Text(assistantNote).font(.footnote.weight(.semibold)).foregroundStyle(OneTheme.accentCyan).accessibilityAddTraits(.isHeader) }
            }
            .padding(20)
            .background(OneTheme.inverseSurface, in: .rect(cornerRadius: 28))
        }
        .accessibilityElement(children: .contain)
    }

    private var nextDose: MedicationDose? {
        store.medicationDoses.first(where: { $0.status == .scheduled || $0.status == .needsConfirmation }) ?? store.medicationDoses.first
    }

    private func nextStatus(after status: MedicationDoseStatus) -> MedicationDoseStatus {
        switch status { case .scheduled: .acknowledged; case .acknowledged: .needsConfirmation; case .needsConfirmation: .missed; case .missed: .scheduled }
    }

    private func sectionHeading(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(OneTheme.secondaryInk)
            Text(title).font(.title2.weight(.bold)).tracking(-0.5).foregroundStyle(OneTheme.ink)
        }
    }
}

struct MedicationPlanSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let plan: MedicationPlan?
    let subjectName: String
    @State private var name: String
    @State private var dose: String
    @State private var instructions: String
    @State private var schedule: String
    @State private var active: Bool
    @State private var assignedCaregiverID: UUID?
    @State private var validationMessage = ""

    init(store: AppStore, plan: MedicationPlan?, subjectName: String) {
        self.store = store; self.plan = plan; self.subjectName = subjectName
        _name = State(initialValue: plan?.name ?? "")
        _dose = State(initialValue: plan?.dose ?? "")
        _instructions = State(initialValue: plan?.instructions ?? "")
        _schedule = State(initialValue: plan?.schedule ?? "")
        _active = State(initialValue: plan?.active ?? true)
        _assignedCaregiverID = State(initialValue: plan?.assignedCaregiverID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("For this person") {
                    Label(subjectName, systemImage: "person.crop.circle").foregroundStyle(OneTheme.ink)
                    Text("Plans are date-aware: use daily, weekday, weekly, or specific-date rules.").font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                }
                Section("Reminder details") {
                    TextField("Medication or reminder name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Instructions (optional)", text: $instructions, axis: .vertical).lineLimit(2...4)
                    TextField("Schedule rule", text: $schedule, prompt: Text("Mon,Wed,Fri @ 08:00"))
                        .textInputAutocapitalization(.never)
                    Text("Examples: Daily @ 08:00 · Tue,Thu @ 20:00 · 2026-09-20 @ 10:00").font(.caption).foregroundStyle(OneTheme.secondaryInk)
                }
                Section("Care circle") {
                    Picker("Assigned caregiver", selection: $assignedCaregiverID) {
                        Text("Unassigned").tag(Optional<UUID>.none)
                        ForEach(store.caregivers.filter { $0.role != .viewer }) { caregiver in
                            Text(caregiver.name).tag(Optional(caregiver.id))
                        }
                    }
                    if plan != nil { Toggle("Active plan", isOn: $active).tint(OneTheme.accentBlue) }
                }
                if !validationMessage.isEmpty { Section { Text(validationMessage).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) } }
                if let authError = store.authError, !authError.isEmpty { Section { Text(authError).foregroundStyle(.red).accessibilityAddTraits(.isStaticText) } }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack { Spacer(); if store.isMedicationMutating { ProgressView().controlSize(.small) }; Text(store.isMedicationMutating ? "Saving…" : (plan == nil ? "Add plan" : "Save changes")).fontWeight(.semibold); Spacer() }
                    }
                    .disabled(store.isMedicationMutating)
                }
            }
            .navigationTitle(plan == nil ? "Add medication plan" : "Edit medication plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDose = dose.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSchedule = schedule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedDose.isEmpty, !trimmedSchedule.isEmpty else {
            validationMessage = "Name, dose, and a schedule rule are required."
            return
        }
        validationMessage = ""
        let succeeded: Bool
        if let plan {
            succeeded = await store.updateMedicationPlan(plan, name: trimmedName, dose: trimmedDose, instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines), schedule: trimmedSchedule, active: active, assignedCaregiverID: assignedCaregiverID)
        } else {
            succeeded = await store.createMedicationPlan(name: trimmedName, dose: trimmedDose, instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines), schedule: trimmedSchedule, assignedCaregiverID: assignedCaregiverID, subjectUserID: store.selectedSubjectID)
        }
        if succeeded { dismiss() }
    }
}

struct InviteCaregiverSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    var body: some View {
        NavigationStack { Form {
            Section("Invite a caregiver") {
                TextField("Name", text: $name)
                TextField("Email (optional)", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                Text("The invitation is single-use and expires in 24 hours.").font(.footnote).foregroundStyle(.secondary)
                Button("Create invitation") { Task { await store.createFamilyInvite(name: name, email: email.isEmpty ? nil : email) } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let code = store.inviteCode { Section("Share this code") { Text(code).font(.title2.monospaced().weight(.bold)).textSelection(.enabled) } }
        }.navigationTitle("Invite caregiver").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
    }
}

struct CaregiverAccountRow: View {
    let account: CaregiverAccount
    var body: some View {
        HStack(spacing: 12) {
            Text(account.name.prefix(1)).font(.headline.weight(.bold)).foregroundStyle(OneTheme.accentBlue).frame(width: 42, height: 42).background(OneTheme.accentBlue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) { Text(account.name).font(.headline); if account.isCurrentUser { Text("YOU").font(.caption2.weight(.bold)).foregroundStyle(OneTheme.accentBlue) } }
                Text(account.relationship).font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                Text(account.permissions.prefix(2).joined(separator: " · ")).font(.caption).foregroundStyle(OneTheme.secondaryInk)
            }
            Spacer()
            Text(account.role.title).font(.caption.weight(.semibold)).multilineTextAlignment(.trailing).foregroundStyle(roleColor).padding(.horizontal, 9).padding(.vertical, 6).background(roleColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.name), \(account.relationship), role \(account.role.title). Permissions: \(account.permissions.joined(separator: ", "))")
    }
    private var roleColor: Color {
        switch account.role { case .owner, .primaryCaregiver: OneTheme.accentBlue; case .supporter: OneTheme.accentCyan; case .viewer: OneTheme.secondaryInk }
    }
}

struct MedicationDoseRow: View {
    let dose: MedicationDose
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: dose.status.symbol).font(.title3).foregroundStyle(statusColor).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(dose.medicationName).font(.headline).foregroundStyle(OneTheme.ink)
                    Text("\(dose.scheduledAt.formatted(date: .omitted, time: .shortened)) · \(dose.instructions)").font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                    if !dose.scheduleRule.isEmpty { Text("Rule: \(dose.scheduleRule)").font(.caption).foregroundStyle(OneTheme.accentBlue) }
                    Text(dose.assignedCaregiverName.map { "Assigned to \($0)" } ?? "No caregiver assigned").font(.caption).foregroundStyle(OneTheme.secondaryInk)
                }
                Spacer()
                Text(dose.status.title).font(.caption.weight(.semibold)).multilineTextAlignment(.trailing).foregroundStyle(statusColor).frame(maxWidth: 94, alignment: .trailing)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dose.medicationName), \(dose.scheduledAt.formatted(date: .omitted, time: .shortened)), \(dose.assignedCaregiverName.map { "assigned to \($0)" } ?? "no caregiver assigned"), status \(dose.status.title). Tap to update status.")
    }
    private var statusColor: Color {
        switch dose.status { case .acknowledged: OneTheme.mint; case .missed: OneTheme.amber; case .needsConfirmation: OneTheme.accentBlue; case .scheduled: OneTheme.secondaryInk }
    }
}

struct EventsView: View { @Bindable var store: AppStore; var body: some View { NavigationStack { ScrollView { LazyVStack(alignment: .leading, spacing: 14) { Text("Events · \(store.selectedSubjectName)").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1); Text("A reviewable record of observed moments.").font(.subheadline).foregroundStyle(OneTheme.secondaryInk); ForEach(store.events) { event in NavigationLink { EventDetailView(event: event) } label: { EventRow(event: event) }.buttonStyle(.plain) } }.padding(20) }.background(OneTheme.canvas.ignoresSafeArea()).safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 88) }.toolbar(.hidden, for: .navigationBar) } } }
struct EventRow: View { let event: ObservedEvent; var body: some View { HStack(spacing: 14) { Image(systemName: event.kind.symbol).font(.title3).foregroundStyle(OneTheme.accentBlue).frame(width: 40, height: 40).background(OneTheme.accentBlue.opacity(0.10), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text(event.kind.title).font(.headline); Text(event.explanation).font(.subheadline).foregroundStyle(OneTheme.secondaryInk); Text("\(event.location) · \(event.timestamp.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary) }; Spacer(); ConfidenceBadge(confidence: event.confidence) }.padding(.vertical, 10).accessibilityElement(children: .combine).accessibilityLabel("\(event.kind.title), \(event.location), \(event.confidence.title) confidence") } }
struct EventDetailView: View { let event: ObservedEvent; var body: some View { ScrollView { VStack(alignment: .leading, spacing: 18) { Text(event.kind.title).font(.largeTitle.weight(.bold)); EventRow(event: event); if event.hasClip { SurfaceCard { Label("Local clip ready for review", systemImage: "play.circle.fill").font(.headline).padding(20) } }; Text("This is an observational signal for human review, not a diagnosis.").font(.footnote).foregroundStyle(OneTheme.amber) }.padding(20) }.background(OneTheme.canvas.ignoresSafeArea()).navigationTitle("Review").navigationBarTitleDisplayMode(.inline) } }

struct ScanView: View { @Bindable var store: AppStore; @Environment(\.dismiss) private var dismiss; @State private var isCapturing = false; @State private var showCapture = false; var body: some View { ZStack { if showCapture && RoomPlanCapability.isSupported { RoomPlanCaptureView(isCapturing: $isCapturing) { _ in isCapturing = false; showCapture = false; dismiss() }.ignoresSafeArea() } else { VStack(alignment: .leading, spacing: 18) { Text("Refresh the home map").font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-1); if RoomPlanCapability.isSupported { Text("Walk slowly around the room. The scan stays on this device until you choose to share it.").foregroundStyle(OneTheme.secondaryInk); Button { showCapture = true; isCapturing = true } label: { Label("Start LiDAR scan", systemImage: "viewfinder") }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue).foregroundStyle(.white) } else { Label("LiDAR is not available on this device.", systemImage: "iphone.slash").font(.headline); Text("You can still use ONE with a simple caregiver-created zone map.").foregroundStyle(OneTheme.secondaryInk); Button("Create zones manually") { dismiss() }.buttonStyle(.bordered) }; Spacer() }.padding(24) } }.background(OneTheme.canvas.ignoresSafeArea()).navigationTitle("Room scan").navigationBarTitleDisplayMode(.inline) } }
struct ResidentHomeView: View { @Bindable var store: AppStore; var body: some View { NavigationStack { VStack(alignment: .leading, spacing: 24) { Text("Today").font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.2); Text("A little support for a more independent day.").font(.title3).foregroundStyle(OneTheme.secondaryInk); Spacer(); Button { store.selectedTab = "assistant" } label: { Label("Start check-in", systemImage: "waveform").font(.headline).frame(maxWidth: .infinity).padding(18) }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue); Spacer() }.padding(20).background(OneTheme.canvas.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar) } } }
struct AssistantView: View { @Bindable var store: AppStore; var body: some View { NavigationStack { VStack { ScrollView { LazyVStack(alignment: .leading, spacing: 12) { Text("Assistant").font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1); ForEach(store.assistantMessages) { message in HStack { if message.isUser { Spacer() }; Text(message.text).foregroundStyle(OneTheme.ink).padding(14).background(message.isUser ? OneTheme.accentCyan.opacity(0.25) : OneTheme.surface, in: RoundedRectangle(cornerRadius: 20)); if !message.isUser { Spacer() } } } }.padding(20) }; Button { store.isListening.toggle(); if !store.isListening { store.sendAssistantMessage() } } label: { Label(store.isListening ? "Release to send" : "Press and hold to talk", systemImage: store.isListening ? "waveform.circle.fill" : "mic.circle.fill").font(.headline).frame(maxWidth: .infinity).padding(18) }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue).foregroundStyle(.white).padding(20) }.background(OneTheme.canvas.ignoresSafeArea()).navigationTitle("Assistant").navigationBarTitleDisplayMode(.inline) } } }
struct SettingsView: View { @Bindable var store: AppStore; var body: some View { NavigationStack { Form { Section("Privacy and consent") { ForEach(store.consents) { consent in Toggle(consent.purpose, isOn: Binding(get: { consent.enabled }, set: { _ in store.toggleConsent(consent) })).tint(OneTheme.accentBlue) }; Text("Sensitive room, audio, and clip data stays local unless you explicitly enable sharing.").font(.footnote) }; Section("Your data") { Button { store.lastDataRequest = DataRequest(kind: .export) } label: { Label("Prepare a data export", systemImage: "square.and.arrow.up") }; Button(role: .destructive) { store.lastDataRequest = DataRequest(kind: .delete) } label: { Label("Request deletion", systemImage: "trash") } }; Section("Session") { Button(role: .destructive) { Task { await store.logout() } } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }; Text("Signing out revokes the backend session and clears this device’s stored credential.").font(.footnote) }; Section("About") { Label("ONE · build 1", systemImage: "sparkles"); Text("Observations support human attention. They are not medical advice or a diagnosis.").font(.footnote).foregroundStyle(.secondary) } }.scrollContentBackground(.hidden).background(OneTheme.canvas.ignoresSafeArea()).navigationTitle("Account") } } }

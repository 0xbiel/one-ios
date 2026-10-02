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
    @State private var showDailyCheckIn = false
    @State private var todayActionError: String?
    @State private var lastCompletedDose: MedicationDose?
    @ScaledMetric(relativeTo: .subheadline) private var todayRowHeight = 80.0
    @ScaledMetric(relativeTo: .title) private var greetingSize = 32.0

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    CareSpaceContextButton(
                        space: store.activeCareSpace,
                        selectedPersonName: selectedPersonName,
                        isLoading: store.isCareSpacesLoading
                    ) {
                        showCareSpaces = true
                    }
                    checkInAction
                    todayCard
                    homeAtGlance
                    if let review = store.dayStoryReview { DayStoryReviewCard(review: review) }
                    recentEvents
                    ActivityReviewCard(review: store.activityReview, error: store.dataReviewError)
                    CollectionReviewCard(review: store.collectionReview)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .refreshable {
                await store.refreshCareSpaces()
                await store.refreshFamilyData()
                await store.refreshLiveData()
                await store.refreshDataReview()
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
        .sheet(isPresented: $showDailyCheckIn) {
            DailyCheckInFlowView(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if store.careSpaces.isEmpty { await store.refreshCareSpaces() }
            await store.refreshFamilyData()
            await store.refreshLiveData()
            await store.refreshDataReview()
        }
        .task(id: store.selectedSubjectID) {
            lastCompletedDose = nil
            todayActionError = nil
            await store.refreshDataReview()
        }
#if DEBUG
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-one-show-care-spaces")
                || arguments.contains("-one-show-care-space-create") {
                showCareSpaces = true
            }
            if arguments.contains("-one-show-daily-check-in") {
                showDailyCheckIn = true
            }
        }
#endif
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.system(size: greetingSize, weight: .bold, design: .rounded))
                    .tracking(-1.1)
                    .foregroundStyle(OneTheme.ink)

            }
            Spacer(minLength: 12)
            OneBrandMark(compact: true)
        }
    }

    private var greeting: String {
        guard let fullName = store.currentUserName?.trimmingCharacters(in: .whitespacesAndNewlines), !fullName.isEmpty else {
            return "Welcome"
        }
        return "Hello, \(fullName.split(separator: " ").first.map(String.init) ?? fullName)"
    }

    private var selectedPersonName: String? {
        if store.selectedSubjectName != "Everyone" { return store.selectedSubjectName }
        return store.careRecipients.first?.displayName
    }

    private var checkInAction: some View {
        Button {
            showDailyCheckIn = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: todaysCheckIn == nil ? "heart.text.square.fill" : "checkmark.circle.fill")
                Text(todaysCheckIn == nil ? "Daily check-in" : "Review check-in")
                Spacer()
                Image(systemName: "arrow.right")
            }
        }
        .buttonStyle(OnePrimaryButtonStyle())
        .accessibilityIdentifier("home-daily-check-in")
    }

    private var todaysCheckIn: ObservedEvent? {
        store.events.first { $0.kind == .checkIn && Calendar.current.isDateInToday($0.timestamp) }
    }

    private var todayCard: some View {
        SurfaceCard(radius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Today’s care plan").font(.subheadline.weight(.semibold))
                    Spacer()
                    if store.isMedicationLoading || store.isMedicationMutating {
                        ProgressView().controlSize(.small)
                    }
                }

                if !todayDoses.isEmpty {
                    List {
                        ForEach(Array(todayDoses.prefix(3).enumerated()), id: \.element.id) { index, dose in
                            todayDoseRow(dose)
                                .accessibilityIdentifier("home-care-dose-\(index)")
                                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(OneTheme.secondaryInk.opacity(0.15))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if dose.status != .acknowledged {
                                        Button {
                                            completeTodayDose(dose)
                                        } label: {
                                            Label("Done", systemImage: "checkmark")
                                        }
                                        .tint(OneTheme.mint)
                                        .disabled(store.isMedicationMutating)
                                        .accessibilityIdentifier("home-care-dose-done")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .environment(\.defaultMinListRowHeight, todayRowHeight)
                    .frame(height: todayRowHeight * Double(min(todayDoses.count, 3)))
                } else {
                    Text(store.isMedicationLoading ? "Loading today’s reminders…" : (store.selectedSubjectID == nil ? "Choose a person to see their care plan" : "No reminders scheduled today"))
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .padding(.vertical, 8)
                }

                if let dose = lastCompletedDose {
                    HStack {
                        Text("Reminder marked done").font(.caption)
                        Spacer()
                        Button("Undo") {
                            Task {
                                if await store.markMedicationDose(dose, status: dose.status) {
                                    lastCompletedDose = nil
                                    todayActionError = nil
                                } else {
                                    todayActionError = "Couldn’t undo. Please try again."
                                }
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .disabled(store.isMedicationMutating)
                        .accessibilityIdentifier("home-care-plan-undo")
                    }
                }
                if let todayActionError {
                    Text(todayActionError).font(.caption).foregroundStyle(OneTheme.amber)
                }
                if todayDoses.count > 3 {
                    Text("\(todayDoses.count - 3) more in the care plan")
                        .font(.caption).foregroundStyle(OneTheme.secondaryInk)
                }
                if !todayDoses.isEmpty {
                    Text("Swipe left to mark done. Acknowledgements do not confirm medication was taken.")
                        .font(.caption2).foregroundStyle(OneTheme.secondaryInk)
                }
                Button {
                    store.selectedTab = "family"
                } label: {
                    HStack {
                        Text("View care plan").font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.right").font(.subheadline)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(OneTheme.accentBlue)
                .accessibilityIdentifier("home-care-plan")
                .accessibilityHint("Opens care plans in Family")
            }
            .padding(16)
        }
    }

    private func todayDoseRow(_ dose: MedicationDose) -> some View {
        HStack(spacing: 10) {
            Image(systemName: dose.status.symbol)
                .font(.body)
                .foregroundStyle(dose.status == .acknowledged ? OneTheme.mint : OneTheme.accentBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(dose.medicationName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(doseStatusText(for: dose))
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Mark done") {
            if dose.status != .acknowledged && !store.isMedicationMutating { completeTodayDose(dose) }
        }
    }

    private func completeTodayDose(_ dose: MedicationDose) {
        guard !store.isMedicationMutating else { return }
        Task {
            if await store.markMedicationDose(dose, status: .acknowledged) {
                lastCompletedDose = dose
                todayActionError = nil
            } else {
                todayActionError = "Couldn’t mark this reminder. Please try again."
            }
        }
    }

    private var todayDoses: [MedicationDose] {
        guard let recipientID = store.selectedSubjectID else { return [] }
        return store.medicationDoses.filter {
            $0.careRecipientID == recipientID && Calendar.current.isDateInToday($0.scheduledAt)
        }.sorted {
            if ($0.status == .acknowledged) != ($1.status == .acknowledged) {
                return $0.status != .acknowledged
            }
            return $0.scheduledAt < $1.scheduledAt
        }
    }

    private func doseStatusText(for dose: MedicationDose) -> String {
        if dose.status == .acknowledged { return completionText(for: dose) }
        let time = dose.scheduledAt.formatted(date: .omitted, time: .shortened)
        switch dose.status {
        case .scheduled: return "Scheduled \(time)"
        case .missed: return "Marked missed · \(time)"
        case .needsConfirmation:
            return "\(dose.markedByName == nil ? "Needs confirmation" : "Skipped") · \(time)"
        case .acknowledged: return completionText(for: dose)
        }
    }

    private func completionText(for dose: MedicationDose) -> String {
        var parts = ["Acknowledged"]
        if let marker = dose.markedByName { parts.append("by \(marker)") }
        if let markedAt = dose.markedAt { parts.append(markedAt.formatted(date: .omitted, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    private func displayedCameraOnline(_ camera: PairedCamera) -> Bool { camera.simulationStatus == "simulated_online" || (camera.simulationStatus == nil && camera.status == "online") }
    private var hasOnlineCamera: Bool { store.pairedCameras.contains(where: displayedCameraOnline) }
    private var cameraConnectionSummary: String {
        guard !store.pairedCameras.isEmpty else { return "Status unknown" }
        let online = store.pairedCameras.filter(displayedCameraOnline).count
        let offline = store.pairedCameras.filter { !displayedCameraOnline($0) && ($0.status == "offline" || $0.simulationStatus == "simulated_offline") }.count
        if online == store.pairedCameras.count { return store.pairedCameras.contains { $0.simulationStatus != nil } ? "active" : "online" }
        if offline == store.pairedCameras.count { return "offline" }
        if online > 0 { return "\(online) online · others unconfirmed" }
        return "status unknown"
    }

    private var homeAtGlance: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeading("Home")
            HStack(spacing: 12) {
                Button { store.selectedTab = "map" } label: {
                    glanceCard(
                        title: "Map",
                        detail: store.scene.isRenderable3D ? "3D ready" : (store.scan.objects.isEmpty ? "Set up your home" : "\(store.scan.objects.count) mapped objects"),
                        symbol: "map.fill",
                        status: store.scene.isRenderable3D ? OneTheme.mint : OneTheme.accentBlue
                    )
                }
                .buttonStyle(.plain)

                Button { showCameraSetup = true } label: {
                    glanceCard(
                        title: "Cameras",
                        detail: store.cameraCount == 0 ? "Pair a camera" : "\(store.cameraCount) paired · \(cameraConnectionSummary)",
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
                sectionHeading("Recent events")
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
                            NavigationLink { EventDetailView(event: event, apiClient: store.apiClient, homeID: store.session?.homeID) } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                            if event.id != store.events.prefix(3).last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(.title2, design: .rounded).weight(.bold))
            .foregroundStyle(OneTheme.ink)
    }

}

private struct DailyCheckInFlowView: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var started = false
    @State private var step = 0
    @State private var answers: [String: String] = [:]

    private let prompts: [(id: String, title: String, detail: String, options: [String])] = [
        ("moment", "How are you feeling in this moment?", "Choose the answer that feels closest. There is no right answer.", ["Good", "Okay", "Hard to say"]),
        ("routine", "How did the morning go?", "A simple reflection helps compare with the person’s own familiar rhythm.", ["Familiar", "A little different", "I’m not sure"]),
        ("note", "Anything you want a caregiver to know?", "Keep it short, or choose that there is nothing to add.", ["Nothing to add", "I’d like to share something", "Skip for now"])
    ]

    private var currentPrompt: (id: String, title: String, detail: String, options: [String]) { prompts[step] }
    private var currentAnswer: String? { answers[currentPrompt.id] }
    private var residentName: String {
        let selected = store.selectedSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selected.isEmpty, selected != "Everyone" { return selected }
        if let first = store.careRecipients.first?.displayName, !first.isEmpty { return first }
        return "Care recipient"
    }
    private var todaysCheckIn: ObservedEvent? {
        store.events.first { $0.kind == .checkIn && Calendar.current.isDateInToday($0.timestamp) }
    }
    private var completed: Bool { todaysCheckIn != nil || store.dailyCheckInResult != nil }
    private var statusTint: Color { started ? OneTheme.accentBlue : completed ? OneTheme.mint : OneTheme.accentBlue }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    mainCard

                    if let error = store.dailyCheckInError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.amber)
                            .padding(.horizontal, 4)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(OneTheme.accentBlue)
                            .frame(width: 22)
                        Text("Only answer summaries are kept. Raw audio is not stored.")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 124)
            }
            .background(OneTheme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle("Daily check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private var mainCard: some View {
        SurfaceCard(radius: 30) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: !started && completed ? "checkmark.circle.fill" : "heart.text.square.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .frame(width: 44, height: 44)
                        .background(statusTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(residentName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneTheme.ink)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                    statusPill
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text(started ? currentPrompt.title : completed ? "Check-in recorded." : "Ready for a check-in?")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .tracking(-0.7)
                        .foregroundStyle(OneTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(started
                         ? currentPrompt.detail
                         : completed
                            ? "Review this alongside recent check-ins."
                            : "Three short questions. About two minutes.")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 34)

                if started {
                    promptContent
                        .padding(.top, 28)
                } else if let result = store.dailyCheckInResult {
                    resultContent(result)
                        .padding(.top, 28)
                }

                Divider()
                    .padding(.top, 26)

                VStack(alignment: .leading, spacing: 8) {
                    Label(started ? "About 2 minutes" : todaysCheckIn.map { "Recorded \($0.timestamp.formatted(date: .omitted, time: .shortened))" } ?? "About 2 minutes", systemImage: "clock")
                    Label("Observation, not diagnosis", systemImage: "shield.checkered")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(OneTheme.secondaryInk)
                .padding(.top, 18)
            }
            .padding(20)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusTint)
                .frame(width: 7, height: 7)
            Text(started ? "Prompt \(step + 1)/\(prompts.count)" : completed ? "Recorded" : "Ready")
                .font(.caption2.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(OneTheme.secondaryInk)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(OneTheme.controlFill, in: Capsule())
    }

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: Double(step + 1), total: Double(prompts.count))
                    .tint(OneTheme.accentBlue)
            }

            VStack(spacing: 10) {
                ForEach(Array(currentPrompt.options.enumerated()), id: \.element) { index, option in
                    Button {
                        answers[currentPrompt.id] = option
                    } label: {
                        HStack(spacing: 14) {
                            Text(option)
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 10)
                            Image(systemName: currentAnswer == option ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(currentAnswer == option ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(0.35))
                        }
                        .foregroundStyle(currentAnswer == option ? OneTheme.accentBlue : OneTheme.ink)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(
                            currentAnswer == option ? OneTheme.accentBlue.opacity(0.08) : OneTheme.canvas,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(currentAnswer == option ? OneTheme.accentBlue.opacity(0.42) : OneTheme.secondaryInk.opacity(0.10), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("daily-checkin-option-\(index)")
                }
            }
        }
    }

    private func resultContent(_ result: DailyCheckInResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECORDED RESULT · \(result.status.uppercased())")
                .font(.caption2.weight(.bold))
                .tracking(1.0)
                .foregroundStyle(OneTheme.mint)
            Text(result.trend == "unknown" ? "Keep the context human." : "Trend: \(result.trend)")
                .font(.title3.weight(.bold))
                .foregroundStyle(OneTheme.ink)
            Text(result.explanation)
                .font(.subheadline)
                .foregroundStyle(OneTheme.secondaryInk)
            Text(result.limitations)
                .font(.footnote)
                .foregroundStyle(OneTheme.amber)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OneTheme.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OneTheme.mint.opacity(0.13), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                if started {
                    Button {
                        if step == 0 { started = false } else { step -= 1 }
                    } label: {
                        Image(systemName: "arrow.left")
                            .frame(width: 54, height: 54)
                    }
                    .buttonStyle(OneSecondaryButtonStyle())
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("daily-checkin-back")

                    Button(action: continueFlow) {
                        HStack {
                            Text(store.isDailyCheckInLoading ? "Recording…" : step == prompts.count - 1 ? "Record check-in" : "Continue")
                            Spacer()
                            if store.isDailyCheckInLoading {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: step == prompts.count - 1 ? "checkmark" : "arrow.right")
                            }
                        }
                    }
                    .buttonStyle(OnePrimaryButtonStyle())
                    .disabled(currentAnswer == nil || store.isDailyCheckInLoading)
                    .accessibilityIdentifier("daily-checkin-continue")
                } else {
                    Button {
                        answers = [:]
                        step = 0
                        started = true
                    } label: {
                        HStack {
                            Label(completed ? "Check in again" : "Start check-in", systemImage: "heart.text.square.fill")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(OnePrimaryButtonStyle())
                    .accessibilityIdentifier("daily-checkin-start")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(OneTheme.canvas.ignoresSafeArea(edges: [.horizontal, .bottom]))
    }

    private func continueFlow() {
        guard currentAnswer != nil, !store.isDailyCheckInLoading else { return }
        if step < prompts.count - 1 {
            step += 1
            return
        }

        let transcript = prompts.map { "\($0.title): \(answers[$0.id] ?? "Not answered")" }.joined(separator: "\n")
        Task {
            await store.submitDailyCheckIn(transcript: transcript)
            if store.dailyCheckInResult != nil {
                started = false
            }
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
                            Text("Pair a camera, then position it on your map.")
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
                    Text("Tap to edit. Swipe to remove.")
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

    private var displayedOnline: Bool { camera.simulationStatus == "simulated_online" || (camera.simulationStatus == nil && camera.status == "online") }
    private var displayedStatus: String { camera.simulationStatus == "simulated_online" ? "Active" : camera.simulationStatus == "simulated_offline" ? "Inactive" : camera.status.capitalized }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: displayedOnline ? "video.fill" : "video.slash.fill")
                .font(.headline)
                .foregroundStyle(displayedOnline ? OneTheme.mint : OneTheme.secondaryInk)
                .frame(width: 40, height: 40)
                .background((displayedOnline ? OneTheme.mint : OneTheme.secondaryInk).opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(camera.name)
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)
                Text(roomName)
                    .font(.subheadline)
                    .foregroundStyle(OneTheme.secondaryInk)
                if camera.simulationLabel != nil {
                    Text("Device \(camera.status.lowercased()) · capture paused")
                        .font(.caption2)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                if camera.calibrationNeeded {
                    Label("3D position not set", systemImage: "camera.viewfinder")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            }
            Spacer(minLength: 8)
            Text(displayedStatus)
                .font(.caption.weight(.semibold))
                .foregroundStyle(displayedOnline ? OneTheme.mint : OneTheme.secondaryInk)
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
                    Text("Assigned from the saved position. Change the room if needed.")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
                }

                Section {
                    if camera.simulationLabel != nil {
                        Label(camera.simulationStatus == "simulated_online" ? "Active" : "Inactive", systemImage: camera.simulationStatus == "simulated_online" ? "checkmark.circle.fill" : "wifi.slash")
                            .foregroundStyle(camera.simulationStatus == "simulated_online" ? OneTheme.mint : OneTheme.secondaryInk)
                        Text("Device \(camera.status.lowercased()) · capture paused")
                            .font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                    } else {
                        Label(camera.status.capitalized, systemImage: camera.status == "online" ? "checkmark.circle.fill" : "wifi.slash")
                            .foregroundStyle(camera.status == "online" ? OneTheme.mint : OneTheme.secondaryInk)
                    }
                    if camera.roomplanMapID != nil {
                        HStack {
                            Label(
                                camera.calibrationNeeded ? "3D position not set" : "Camera positioned",
                                systemImage: "camera.viewfinder"
                            )
                            .foregroundStyle(camera.calibrationNeeded ? OneTheme.secondaryInk : OneTheme.accentBlue)
                            Spacer()
                            Menu {
                                Button {
                                    showCalibration = true
                                } label: {
                                    Label(camera.calibrationNeeded ? "Calibrate camera" : "Run calibration again", systemImage: "camera.viewfinder")
                                }
                            } label: {
                                Label("Positioning", systemImage: "ellipsis.circle")
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        Text("Review and save a proposed position before it replaces the current one.")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.secondaryInk)
                    } else {
                        Label("Scan the room with LiDAR before positioning this camera.", systemImage: "viewfinder")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
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
    @State private var selectedRoomID: UUID?
    @State private var saved = false
    @State private var lastRequestedRound: Int?

    private var scan: RoomPlanNormalizedScan? { store.scene.canonicalGeometry ?? store.scene.geometry }
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
    private var selectedFloor: RoomPlanElement? { scan?.floors.first { UUID(uuidString: $0.id) == selectedRoomID } }
    private var floorY: Double { selectedFloor?.center.y ?? scan?.floors.first?.center.y ?? 0 }
    private var imported: Bool { store.scene.source == .imported3D }


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
                            // Keep calibration content clear of the fixed
                            // footer when the review/manual controls are tall.
                            .padding(.bottom, 112)
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
            if imported { manualMode = true }
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
                    if refreshed.status == .waitingForScene,
                       refreshed.currentTargetIndex < refreshed.captureRoundCount,
                       lastRequestedRound != refreshed.currentTargetIndex {
                        await requestCurrentCapture()
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
                title(eyebrow: "POSITION SAVED", title: "Position saved.", body: "Keep the camera in this physical position.")
                SurfaceCard(radius: 24) {
                    Label("Camera position saved in the map", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(OneTheme.accentBlue)
                        .padding(18)
                }
            }
        } else if manualMode {
            VStack(alignment: .leading, spacing: 18) {
                title(eyebrow: "MANUAL POSITION", title: "Tap where the camera really is.", body: "Place the marker on the floor plan, then set its mounting height and viewing direction before saving.")
                if imported {
                    Text("Imported geometry has no visual index. This marker is tentative until you save it.")
                        .font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                    Picker("Placement room", selection: $selectedRoomID) {
                        Text("Choose a room").tag(UUID?.none)
                        ForEach(store.cameraRooms.filter { room in scan?.floors.contains { UUID(uuidString: $0.id) == room.id } == true }) { room in
                            Text(room.name).tag(Optional(room.id))
                        }
                    }
                    .accessibilityIdentifier("placement-room")
                    .onChange(of: selectedRoomID) { _, _ in
                        if let floor = selectedFloor { manualPoint = SIMD2(floor.center.x, floor.center.z) }
                    }
                }
                CameraCalibrationFloorMap(
                    scan: scan,
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
                if !imported {
                    Button("Back to automatic proposal") { manualMode = false }
                        .font(.subheadline.weight(.semibold))
                }
            }
        } else if calibration == nil {
            VStack(alignment: .leading, spacing: 20) {
                title(eyebrow: "CAMERA POSITION", title: "Position your camera.", body: "Keep the camera still. ONE will capture three short bursts and show a position for you to review.")
                SurfaceCard(radius: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        requirement("Keep \(camera.name) in its final position with its preview open", symbol: "camera.fill")
                        requirement("Three reference bursts run automatically after you tap Start", symbol: "camera.viewfinder")
                        requirement("People and movable chairs are ignored as calibration anchors", symbol: "person.2.fill")
                    }
                    .padding(18)
                }
                Text("Frames are temporary. Nothing is saved until you approve the position.")
                    .font(.footnote)
                    .foregroundStyle(OneTheme.secondaryInk)
            }
        } else if calibration?.status == .review, !manualMode {
            VStack(alignment: .leading, spacing: 18) {
                title(eyebrow: "REVIEW", title: "Check the camera placement.", body: "Save only if the marker matches the camera’s actual position.")
                CameraCalibrationFloorMap(
                    scan: scan,
                    cameraPoint: proposalPoint,
                    selection: nil,
                    onSelect: nil
                )
                .frame(height: 320)
                calibration3DGuide(calibration!)
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
        } else if let calibration, calibration.status == .failed || calibration.status == .expired {
            VStack(alignment: .leading, spacing: 18) {
                let calibrationError = calibration.error ?? ""
                let localizationServiceUnavailable = calibrationError.localizedCaseInsensitiveContains("local camera localization service")
                    || calibrationError.localizedCaseInsensitiveContains("local room-layout service")
                title(
                    eyebrow: localizationServiceUnavailable ? "SERVICE UNAVAILABLE" : "TRY AGAIN",
                    title: localizationServiceUnavailable ? "The camera position was not changed." : "The camera position needs another pass.",
                    body: calibration.error ?? "The temporary calibration session expired or did not produce a stable pose."
                )
                SurfaceCard(radius: 22) {
                    Label("The existing camera position was not replaced.", systemImage: "lock.shield.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(OneTheme.secondaryInk)
                        .padding(18)
                }
            }
        } else if let calibration {
            VStack(alignment: .leading, spacing: 18) {
                let number = min(calibration.currentTargetIndex + 1, calibration.captureRoundCount)
                let solveProgress = max(1, min(100, calibration.solveProgress ?? 1))
                title(
                    eyebrow: calibration.status == .solving ? "MATCHING FIXED VIEW" : "REFERENCE \(number) OF \(calibration.captureRoundCount)",
                    title: calibration.status == .solving ? "Matching the fixed view to RoomPlan…" : "Capturing the fixed view.",
                    body: calibration.status == .captureRequested
                        ? "Keep the room camera still. ONE is capturing this reference burst now."
                        : calibration.status == .solving
                            ? "Keep the camera still while ONE matches its view to the room."
                            : "The next reference burst will start automatically. You do not need to stand anywhere, and people or chairs may move through the frame."
                )
                SurfaceCard(radius: 22) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            ForEach(0..<calibration.captureRoundCount, id: \.self) { index in
                                Capsule()
                                    .fill(index < calibration.capturedTargetCount ? OneTheme.mint : index == calibration.currentTargetIndex ? OneTheme.accentBlue : OneTheme.controlFill)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 7)
                            }
                        }
                        Text(calibration.status == .solving ? "All reference bursts captured" : "\(calibration.capturedTargetCount) of \(calibration.captureRoundCount) captured")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                    .padding(16)
                }
                if calibration.status == .solving {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(calibration.solveStage ?? "Matching locally…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OneTheme.secondaryInk)
                            Spacer()
                            Text("\(solveProgress)%")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(OneTheme.accentBlue)
                        }
                        ProgressView(value: Double(solveProgress), total: 100)
                            .tint(OneTheme.accentBlue)
                    }
                } else if calibration.status == .captureRequested {
                    HStack(spacing: 10) {
                        ProgressView().tint(OneTheme.accentBlue)
                        Text("Waiting for \(camera.name)…")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }
                if calibration.status == .waitingForScene, let message = calibration.error, !message.isEmpty {
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
                    objects: []
                )
                .frame(height: 260)
                DisclosureGroup("Details") {
                    Text("Room structure and fixed landmarks guide positioning. People and movable furniture are ignored.")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                .font(.subheadline)
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
        } else if manualMode {
            Button(isWorking ? "Saving…" : "Save manual position") {
                Task {
                    guard let manualPoint, let mapID = calibration?.mapID ?? store.scene.mapID else { return }
                    isWorking = true
                    let success = await store.saveManualRoomPlanCamera(
                        camera,
                        mapID: mapID,
                        x: manualPoint.x,
                        z: manualPoint.y,
                        floorY: floorY,
                        height: manualHeight,
                        yawDegrees: manualYaw,
                        roomID: imported ? selectedRoomID : nil
                    )
                    isWorking = false
                    if success { saved = true }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OneTheme.accentBlue)
            .controlSize(.large)
            .disabled(isWorking || manualPoint == nil || (imported && selectedRoomID == nil))
        } else if calibration == nil {
            Button(isWorking ? "Starting…" : "Start calibration") { Task { await startCalibration() } }
                .buttonStyle(.borderedProminent)
                .tint(OneTheme.accentBlue)
                .controlSize(.large)
                .disabled(isWorking || camera.roomplanMapID == nil)
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
            Button(isWorking ? "Restarting…" : "Run calibration again") { Task { await restartCalibration() } }
                .buttonStyle(.borderedProminent)
                .tint(OneTheme.accentBlue)
                .controlSize(.large)
                .disabled(isWorking)
        } else if calibration?.status == .waitingForScene {
            HStack(spacing: 10) {
                ProgressView().tint(OneTheme.accentBlue)
                Text("Preparing next reference…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if calibration?.status == .captureRequested {
            Button(isWorking ? "Retrying capture…" : "Retry fixed-camera capture") {
                Task { await requestCurrentCapture() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isWorking)
        } else {
            EmptyView()
        }
    }

    private func requestCurrentCapture() async {
        guard let calibration else { return }
        isWorking = true
        if let updated = await store.requestRoomPlanCalibrationCapture(
            for: camera,
            targetIndex: calibration.currentTargetIndex
        ) {
            lastRequestedRound = calibration.currentTargetIndex
            self.calibration = updated
        }
        isWorking = false
    }

    private func startCalibration() async {
        isWorking = true
        manualMode = false
        manualPoint = nil
        lastRequestedRound = nil
        calibration = await store.startRoomPlanCalibration(for: camera)
        isWorking = false
        if calibration?.status == .waitingForScene {
            await requestCurrentCapture()
        }
    }

    private func restartCalibration() async {
        isWorking = true
        await store.cancelRoomPlanCalibration(for: camera)
        manualMode = false
        manualPoint = nil
        lastRequestedRound = nil
        calibration = await store.startRoomPlanCalibration(for: camera)
        isWorking = false
        if calibration?.status == .waitingForScene {
            await requestCurrentCapture()
        }
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
    @State private var cameraKind: CameraKind = .oneCamera
    @State private var wifiName = ""
    @State private var wifiPassword = ""
    @State private var videoConsent = true
    @State private var audioConsent = false
    @State private var selectedOneCameraID: UUID?
    @State private var oneCameraBLE = OneCameraBLEProvisioner()
    @State private var step: Step = .details
    @State private var validationMessage: String?
    @FocusState private var isNameFocused: Bool

    private enum Step: Int, CaseIterable {
        case details
        case connect
    }

    private enum CameraKind: String, CaseIterable, Identifiable {
        case oneCamera
        case browser

        var id: String { rawValue }
        var title: String { self == .oneCamera ? "ONE Camera" : "Phone or browser" }
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
                            // The pairing actions stay pinned below the scroll
                            // view, so the final helper text must scroll above
                            // their full height.
                            .padding(.bottom, 112)
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
        .onChange(of: step) { _, next in
            if next == .connect && cameraKind == .oneCamera { oneCameraBLE.startScanning() }
            else { oneCameraBLE.stopScanning() }
        }
        .onChange(of: cameraKind) { _, next in
            selectedOneCameraID = nil
            if step == .connect && next == .oneCamera { oneCameraBLE.startScanning() }
            else { oneCameraBLE.stopScanning() }
        }
        .onChange(of: oneCameraBLE.nearby) { _, cameras in
            if selectedOneCameraID == nil { selectedOneCameraID = cameras.first?.id }
        }
        .onDisappear {
            oneCameraBLE.stopScanning()
            oneCameraBLE.reset()
            store.clearCameraPairing()
        }
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
            Text("Pair a camera.")
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(OneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            Text(cameraKind == .oneCamera
                 ? "Name your camera, then connect it over Bluetooth."
                 : "Name your device, then connect it with a one-time code.")
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            VStack(alignment: .leading, spacing: 10) {
                Text("Camera type")
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)

                Picker("Camera type", selection: $cameraKind) {
                    ForEach(CameraKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .pickerStyle(.segmented)

                Text(cameraKind == .oneCamera
                     ? "Connects over Bluetooth. No code needed."
                     : "Use a phone, tablet, or laptop browser.")
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

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

                Label("Room will be detected from the saved RoomPlan position. You can correct it later in Cameras.", systemImage: "location.viewfinder")
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

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
            Text(isConnected ? "Your camera is ready." : (cameraKind == .oneCamera ? "Bring your ONE Camera nearby." : "Enter this code on the camera."))
                .font(.system(size: 30, weight: .semibold))
                .tracking(-0.9)
                .foregroundStyle(OneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 7)

            Text(isConnected
                 ? "Position it on the map later from its Positioning menu."
                 : (cameraKind == .oneCamera
                    ? "Choose your camera and Wi-Fi network. Bluetooth is used only for setup."
                    : "Enter the code on your camera device and keep this sheet open."))
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            if let challenge = store.cameraPairingChallenge {
                if cameraKind == .oneCamera {
                    oneCameraSetup(challenge: challenge)
                        .padding(.top, 22)
                } else {
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
    }

    private func oneCameraSetup(challenge: CameraPairingChallenge) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isConnected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(isConnected ? OneTheme.mint : OneTheme.accentBlue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isConnected ? "ONE Camera connected" : "Nearby ONE Camera")
                        .font(.headline)
                    Text(oneCameraStatusText)
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                Spacer()
                if !isConnected {
                    Button("Scan") { oneCameraBLE.startScanning() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(OneTheme.accentBlue)
                }
            }

            if !isConnected {
                if oneCameraBLE.nearby.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Power on the ONE Camera and keep it near this iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(oneCameraBLE.nearby) { camera in
                            Button {
                                selectedOneCameraID = camera.id
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "video.fill")
                                        .foregroundStyle(OneTheme.accentBlue)
                                        .frame(width: 30, height: 30)
                                        .background(OneTheme.accentBlue.opacity(0.10), in: Circle())
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(camera.name).font(.subheadline.weight(.semibold)).foregroundStyle(OneTheme.ink)
                                        Text(camera.signal > -60 ? "Very close" : camera.signal > -75 ? "Nearby" : "In range")
                                            .font(.caption).foregroundStyle(OneTheme.secondaryInk)
                                    }
                                    Spacer()
                                    Image(systemName: selectedOneCameraID == camera.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedOneCameraID == camera.id ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(0.45))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("Wi-Fi")
                        .font(.headline)
                    TextField("Network name", text: $wifiName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(OneTheme.controlFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    SecureField("Password", text: $wifiPassword)
                        .textContentType(.password)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(OneTheme.controlFill, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    Text("These credentials go directly to the nearby camera over Bluetooth and are not stored in your ONE account.")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Toggle("Allow video capture for this camera", isOn: $videoConsent)
                    .font(.subheadline.weight(.medium))
                Toggle("Allow microphone capture", isOn: $audioConsent)
                    .font(.subheadline.weight(.medium))
                Text("You can change capture consent later. Pairing the device does not run room mapping or 3D positioning.")
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .failed(let message) = oneCameraBLE.phase {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(OneTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(OneTheme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke((isConnected ? OneTheme.mint : OneTheme.secondaryInk).opacity(isConnected ? 0.34 : 0.12), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }

    private var oneCameraStatusText: String {
        if isConnected { return "Linked to this care space and ready to reconnect automatically." }
        switch oneCameraBLE.phase {
        case .idle, .scanning: return "Scanning securely over Bluetooth."
        case .connecting: return "Connecting to the camera…"
        case .sending: return "Sending Wi-Fi and the private account link…"
        case .waitingForNetwork: return "Camera is joining Wi-Fi…"
        case .linkingAccount: return "Camera is linking to this care space…"
        case .paired: return "Camera linked. Waiting for ONE to confirm it…"
        case .bluetoothUnavailable(let message), .failed(let message): return message
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
        if cameraKind == .oneCamera {
            switch oneCameraBLE.phase {
            case .connecting, .sending: return "Sending setup…"
            case .waitingForNetwork: return "Joining Wi-Fi…"
            case .linkingAccount, .paired: return "Finishing setup…"
            default: return "Set up ONE Camera"
            }
        }
        return "Waiting for camera…"
    }

    private var primaryButtonSymbol: String {
        if step == .details { return "arrow.right" }
        if isConnected { return "checkmark" }
        if isExpired { return "arrow.clockwise" }
        if cameraKind == .oneCamera { return "dot.radiowaves.left.and.right" }
        return "dot.radiowaves.left.and.right"
    }

    private var primaryButtonDisabled: Bool {
        if store.isCameraPairingBusy { return true }
        if step == .details { return false }
        if cameraKind == .oneCamera && !isConnected && !isExpired {
            switch oneCameraBLE.phase {
            case .connecting, .sending, .waitingForNetwork, .linkingAccount, .paired: return true
            default: return selectedOneCameraID == nil || wifiName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
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
        } else if cameraKind == .oneCamera {
            provisionOneCamera()
        }
    }

    private func provisionOneCamera() {
        guard let challenge = store.cameraPairingChallenge,
              let deviceID = selectedOneCameraID else { return }
        let network = wifiName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !network.isEmpty else {
            validationMessage = "Enter the Wi-Fi network the camera should use."
            return
        }
        validationMessage = nil
        oneCameraBLE.provision(
            deviceID: deviceID,
            ssid: network,
            password: wifiPassword,
            pairingCode: challenge.pairingCode,
            apiBaseURL: store.runtimeConfiguration.apiBaseURL,
            videoConsent: videoConsent,
            audioConsent: audioConsent
        )
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
            if cameraKind == .oneCamera { oneCameraBLE.startScanning() }
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
        oneCameraBLE.reset()
        validationMessage = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            step = .details
        }
    }
}

struct ObjectCard: View { let title: String; let subtitle: String; let symbol: String; let color: Color; var body: some View { SurfaceCard(radius: 24) { VStack(alignment: .leading, spacing: 10) { ZStack { RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [color.opacity(0.7), OneTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing)); Image(systemName: symbol).font(.system(size: 38, weight: .medium)).foregroundStyle(OneTheme.ink) }.frame(width: 188, height: 100); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(OneTheme.secondaryInk) }.padding(12) } } }

struct ResidentHomeView: View { @Bindable var store: AppStore; var body: some View { NavigationStack { VStack(alignment: .leading, spacing: 24) { Text("Today").font(.system(.largeTitle, design: .rounded).weight(.bold)).tracking(-1.2); Spacer(); Button { store.selectedTab = "assistant" } label: { Label("Start check-in", systemImage: "waveform").font(.headline).frame(maxWidth: .infinity).padding(18) }.buttonStyle(.borderedProminent).tint(OneTheme.accentBlue); Spacer() }.padding(20).background(OneTheme.canvas.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar) } } }

import SwiftUI

struct FamilyView: View {
    @Bindable var store: AppStore
    @State private var showInviteSheet = false
    @State private var editingCaregiver: CaregiverAccount?
    @State private var memberToRemove: CaregiverAccount?
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
            .sheet(item: $editingCaregiver) { caregiver in FamilyAccessSheet(store: store, member: caregiver) }
            .sheet(isPresented: $showMedicationPlanSheet) { MedicationPlanSheet(store: store, plan: editingMedicationPlan, subjectName: store.selectedSubjectName) }
            .confirmationDialog("Remove this person?", item: $memberToRemove) { member in
                Button("Remove access", role: .destructive) { Task { _ = await store.removeFamilyMember(member.id) } }
                Button("Cancel", role: .cancel) { }
            } message: { member in
                Text("Remove \(member.name) from this household? Their active sessions will be revoked, and this cannot be undone from the app.")
            }
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
                    CaregiverAccountRow(account: caregiver, editAction: canEdit(caregiver) ? { editingCaregiver = caregiver } : nil)
                        .contentShape(Rectangle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if canRemove(caregiver) {
                                Button(role: .destructive) { memberToRemove = caregiver } label: {
                                    Label("Remove access", systemImage: "person.crop.circle.badge.minus")
                                }
                            }
                        }
                    if caregiver.id != store.caregivers.last?.id { Divider().padding(.leading, 58) }
                }
            }
            .padding(.horizontal, 16).background(OneTheme.surface, in: .rect(cornerRadius: 26))
            .overlay(.black.opacity(0.04), in: .rect(cornerRadius: 26))
            Text("Roles limit what each person can view or change. ONE never grants access by default.")
                .font(.footnote).foregroundStyle(OneTheme.secondaryInk)
        }
    }

    private func canEdit(_ caregiver: CaregiverAccount) -> Bool {
        !caregiver.isCurrentUser && caregiver.role != .owner
    }

    private func canRemove(_ caregiver: CaregiverAccount) -> Bool {
        canEdit(caregiver)
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
    var editAction: (() -> Void)? = nil
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
            if let editAction {
                Button(action: editAction) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OneTheme.accentBlue)
                        .frame(width: 34, height: 34)
                        .background(OneTheme.accentBlue.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit access for \(account.name)")
            }
        }
        .padding(.vertical, 14)
        // Keep the pencil action discoverable to VoiceOver when this row is editable.
        .accessibilityElement(children: editAction == nil ? .combine : .contain)
        .accessibilityLabel("\(account.name), \(account.relationship), role \(account.role.title). Permissions: \(account.permissions.joined(separator: ", "))")
    }
    private var roleColor: Color {
        switch account.role { case .owner, .primaryCaregiver: OneTheme.accentBlue; case .supporter: OneTheme.accentCyan; case .viewer: OneTheme.secondaryInk }
    }
}

struct FamilyAccessSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let member: CaregiverAccount
    @State private var accessRole: CaregiverAccessRole
    @State private var isSaving = false

    init(store: AppStore, member: CaregiverAccount) {
        self.store = store
        self.member = member
        _accessRole = State(initialValue: member.role)
    }

    private var availableRoles: [CaregiverAccessRole] {
        if store.runtimeConfiguration.isDemoMode {
            return CaregiverAccessRole.allCases.filter { $0 != .owner }
        }
        return [.primaryCaregiver, .viewer]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Person") {
                    Label(member.name, systemImage: "person.crop.circle")
                    Text(member.relationship).font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                }

                Section("Access level") {
                    Picker("Role", selection: $accessRole) {
                        ForEach(availableRoles) { role in
                            Text(role.title).tag(role)
                        }
                    }
                    Text("Roles control what this person can see or change. Owner access cannot be edited here.")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
                }

                Section("Current permissions") {
                    Text(member.permissions.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                }

                Section {
                    Button {
                        Task {
                            isSaving = true
                            let saved = await store.updateFamilyMember(member.id, accessRole: accessRole)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving { ProgressView().controlSize(.small) }
                            Text(isSaving ? "Saving…" : "Save access").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSaving || accessRole == member.role)
                }
            }
            .navigationTitle("Edit access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
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

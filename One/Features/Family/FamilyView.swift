import SwiftUI
import AVFoundation
import Combine
import CoreImage
import ImageIO
import UIKit
import Vision

struct FamilyView: View {
    @Bindable var store: AppStore
    @State private var showCareRecipientSheet = false
    @State private var editingCareRecipient: CareRecipient?
    @State private var recipientToRemove: CareRecipient?
    @State private var showRecipientRemoveConfirmation = false
    @State private var showInviteSheet = false
    @State private var editingCaregiver: CaregiverAccount?
    @State private var memberToRemove: CaregiverAccount?
    @State private var showRemoveConfirmation = false
    @State private var showMedicationPlanSheet = false
    @State private var editingMedicationPlan: MedicationPlan?

    var body: some View {
        NavigationStack {
            List {
                familyHeader
                caredForSection
                medicationSection
                peopleSection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(10))
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(OneTheme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 88) }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCareRecipientSheet) {
                CareRecipientWizardSheet(
                    store: store,
                    recipient: nil,
                    canEdit: store.canManageCareRecipients
                )
            }
            .sheet(item: $editingCareRecipient) { recipient in
                CareRecipientWizardSheet(
                    store: store,
                    recipient: recipient,
                    canEdit: store.canManageCareRecipients
                )
            }
            .sheet(isPresented: $showInviteSheet) { InviteCaregiverSheet(store: store) }
            .sheet(item: $editingCaregiver) { caregiver in FamilyAccessSheet(store: store, member: caregiver) }
            .sheet(isPresented: $showMedicationPlanSheet) { MedicationPlanSheet(store: store, plan: editingMedicationPlan) }
            .confirmationDialog("Remove this person?", isPresented: $showRemoveConfirmation) {
                if let member = memberToRemove {
                    Button("Remove access", role: .destructive) {
                        memberToRemove = nil
                        Task { _ = await store.removeFamilyMember(member.id) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(memberToRemove.map { "Remove \($0.name) from this household? Their active sessions will be revoked, and this cannot be undone from the app." } ?? "This person will lose access to the household.")
            }
            .confirmationDialog("Remove from this care space?", isPresented: $showRecipientRemoveConfirmation) {
                if let recipient = recipientToRemove {
                    Button("Remove person", role: .destructive) {
                        recipientToRemove = nil
                        Task { _ = await store.removeCareRecipient(recipient.id) }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(recipientToRemove.map { "Remove \($0.displayName) from this care space? This does not remove anyone’s app access." } ?? "This removes the person from the care-space record.")
            }
            .task { await store.refreshFamilyData() }
        }
    }

    private var familyHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CARE CIRCLE")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(OneTheme.accentBlue)
            Text("Family")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(-1.4)
                .foregroundStyle(OneTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var caredForSection: some View {
        Section {
            if store.isCareRecipientsLoading && store.careRecipients.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading people in this care space…")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            } else if store.careRecipients.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("No one added yet", systemImage: "person.2")
                        .font(.headline)
                        .foregroundStyle(OneTheme.ink)
                    Text("Add the people supported in this care space. This does not create app access.")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                    if store.canManageCareRecipients {
                        Button("Add first person") {
                            editingCareRecipient = nil
                            store.clearCareRecipientError()
                            showCareRecipientSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(OneTheme.accentBlue)
                    }
                }
            } else {
                ForEach(store.careRecipients) { recipient in
                    CareRecipientRow(
                        recipient: recipient,
                        canEdit: store.canManageCareRecipients
                    ) {
                        if store.canManageCareRecipients {
                            editingCareRecipient = recipient
                            store.clearCareRecipientError()
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if store.canManageCareRecipients {
                            Button(role: .destructive) {
                                recipientToRemove = recipient
                                showRecipientRemoveConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 14))
                }
            }

            if let error = store.careRecipientError {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(OneTheme.amber)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(error).font(.footnote).foregroundStyle(OneTheme.ink)
                        Button("Try again") { Task { await store.refreshCareRecipients() } }
                            .font(.footnote.weight(.semibold))
                    }
                    Spacer()
                }
            }
        } header: {
            HStack(alignment: .center, spacing: 12) {
                sectionHeading("PEOPLE CARED FOR", store.activeCareSpace?.name ?? "Current care space")
                Spacer()
                if store.canManageCareRecipients {
                    Button {
                        editingCareRecipient = nil
                        store.clearCareRecipientError()
                        showCareRecipientSheet = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(OneTheme.accentBlue)
                            .frame(width: 34, height: 34)
                            .background(OneTheme.accentBlue.opacity(0.11), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isCareRecipientMutating)
                    .accessibilityLabel("Add a person cared for")
                }
            }
            .textCase(nil)
        } footer: {
            Text(store.canManageCareRecipients
                 ? "Care profiles do not grant app access."
                 : "These are the people supported in this care space. A caregiver manages this list.")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
        }
    }

    private var peopleSection: some View {
        Section {
            ForEach(store.caregivers) { caregiver in
                CaregiverAccountRow(
                    account: caregiver,
                    editAction: canEdit(caregiver) ? { editingCaregiver = caregiver } : nil
                )
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if canRemove(caregiver) {
                        Button(role: .destructive) {
                            memberToRemove = caregiver
                            showRemoveConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            HStack(alignment: .center, spacing: 12) {
                sectionHeading("ACCESS", "People with access")
                Spacer()
                Button { showInviteSheet = true } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(OneTheme.accentBlue)
                        .frame(width: 34, height: 34)
                        .background(OneTheme.accentBlue.opacity(0.11), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Invite a caregiver")
            }
            .textCase(nil)
        } footer: {
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
        Section {
            if store.medicationSubjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Add someone first", systemImage: "person.crop.circle.badge.plus").font(.headline)
                    Text("Medication plans follow the people you care for, even when they do not have a ONE login.")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            } else {
                HStack(spacing: 12) {
                    medicationPersonPicker
                        .layoutPriority(1)
                    medicationAddButton
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 14))

                if selectedMedicationPerson?.medicationRemindersEnabled != true, let person = selectedMedicationPerson {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(OneTheme.amber)
                            .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reminders are off for \(person.displayName)")
                                .font(.headline)
                            Text("Enable them for this person to create and use medication reminders.")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                            if store.canManageCareRecipients {
                                Button("Enable reminders") {
                                    Task { _ = await store.setMedicationRemindersEnabled(for: person, enabled: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(OneTheme.accentBlue)
                                .disabled(store.isCareRecipientMutating)
                            }
                        }
                    }
                } else {
                    medicationWeekPicker
                        .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14))

                    if store.medicationDosesForSelectedSubject.isEmpty {
                        Label("No reminders on this day", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(OneTheme.secondaryInk)
                    } else {
                        ForEach(store.medicationDosesForSelectedSubject) { dose in
                            MedicationDoseRow(dose: dose, isBusy: store.isMedicationMutating)
                                .listRowInsets(EdgeInsets(top: 3, leading: 18, bottom: 3, trailing: 14))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if Calendar.current.isDateInToday(store.selectedMedicationDate), dose.status != .acknowledged {
                                        Button {
                                            Task { _ = await store.markMedicationDose(dose, status: .acknowledged) }
                                        } label: {
                                            Label("Done", systemImage: "checkmark.circle.fill")
                                        }
                                        .tint(OneTheme.mint)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if Calendar.current.isDateInToday(store.selectedMedicationDate), dose.status != .acknowledged {
                                        Button {
                                            Task { _ = await store.markMedicationDose(dose, status: .needsConfirmation) }
                                        } label: {
                                            Label("Skip", systemImage: "forward.fill")
                                        }
                                        .tint(OneTheme.accentBlue)

                                        Button {
                                            Task { _ = await store.markMedicationDose(dose, status: .missed) }
                                        } label: {
                                            Label("Missed", systemImage: "xmark.circle.fill")
                                        }
                                        .tint(OneTheme.amber)
                                    }
                                }
                            }
                    }

                }
            }
        } header: {
            HStack(alignment: .center, spacing: 12) {
                sectionHeading("MEDICATION", "Daily reminders")
                Spacer()
                NavigationLink {
                    MedicationPlansView(store: store)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Plans")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OneTheme.accentBlue)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(OneTheme.accentBlue.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Medication plans, \(planCountText)")
            }
            .textCase(nil)
        } footer: {
            Text("Shared routine only; reminders do not confirm ingestion.")
                .font(.caption)
                .foregroundStyle(OneTheme.secondaryInk)
        }
    }

    private var medicationAddButton: some View {
        Button {
            editingMedicationPlan = nil
            showMedicationPlanSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(OneTheme.accentBlue)
                .frame(width: 36, height: 36)
                .background(OneTheme.accentBlue.opacity(0.11), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add medication reminder")
        .disabled(store.isMedicationMutating || store.medicationSubjects.isEmpty)
    }

    private var medicationPersonPicker: some View {
        Menu {
            ForEach(store.medicationSubjects) { subject in
                Button {
                    store.selectedSubjectID = subject.id
                } label: {
                    if subject.id == store.selectedSubjectID {
                        Label(subject.displayName, systemImage: "checkmark")
                    } else {
                        Text(subject.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Medication for")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                    Text(selectedMedicationPerson?.displayName ?? "Choose a person")
                        .font(.headline)
                        .foregroundStyle(OneTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OneTheme.accentBlue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .tint(OneTheme.accentBlue)
        .accessibilityLabel("Medication for")
        .accessibilityValue(selectedMedicationPerson?.displayName ?? "Choose a person")
        .accessibilityHint("Choose a different person for medication reminders")
        .onChange(of: store.selectedSubjectID) { _, value in
            store.selectedSubjectName = store.medicationSubjects.first(where: { $0.id == value })?.displayName ?? "Everyone"
            Task { await store.refreshMedicationPlans(); await store.refreshMedicationReminders() }
        }
    }

    private var selectedMedicationPerson: CareRecipient? {
        guard let id = store.selectedSubjectID else { return nil }
        return store.medicationSubjects.first(where: { $0.id == id })
    }

    private var planCountText: String {
        let count = store.medicationPlansForSelectedSubject.count
        if store.isMedicationLoading { return "Loading plans…" }
        return count == 1 ? "1 active plan" : "\(count) active plans"
    }

    private var medicationWeekPicker: some View {
        HStack(spacing: 7) {
            ForEach(weekDates, id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: store.selectedMedicationDate)
                Button {
                    store.selectedMedicationDate = date
                    Task { await store.refreshMedicationReminders() }
                } label: {
                    VStack(spacing: 5) {
                        Text(date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.bold))
                        Text(date.formatted(.dateTime.day()))
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(selected ? .white : OneTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(selected ? OneTheme.accentBlue : OneTheme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: store.selectedMedicationDate)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func sectionHeading(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).font(.caption.weight(.bold)).tracking(1.1).foregroundStyle(OneTheme.secondaryInk)
            Text(title).font(.title2.weight(.bold)).tracking(-0.5).foregroundStyle(OneTheme.ink)
        }
    }
}

private struct MedicationPlansView: View {
    @Bindable var store: AppStore
    @State private var showPlanSheet = false
    @State private var editingPlan: MedicationPlan?
    @State private var planToArchive: MedicationPlan?
    @State private var showArchiveConfirmation = false

    private var selectedPerson: CareRecipient? {
        guard let id = store.selectedSubjectID else { return nil }
        return store.medicationSubjects.first(where: { $0.id == id })
    }

    var body: some View {
        List {
            if store.medicationSubjects.count > 1 {
                Section("For") {
                    Picker("Person", selection: $store.selectedSubjectID) {
                        ForEach(store.medicationSubjects) { person in
                            Text(person.displayName).tag(Optional(person.id))
                        }
                    }
                }
            }

            if let person = selectedPerson, person.medicationRemindersEnabled != true {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "bell.slash.fill")
                            .foregroundStyle(OneTheme.amber)
                            .frame(width: 32, height: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reminders are off for \(person.displayName)")
                                .font(.headline)
                            Text("Enable reminders before adding or editing medication plans.")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                            Button("Enable reminders") {
                                Task { _ = await store.setMedicationRemindersEnabled(for: person, enabled: true) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OneTheme.accentBlue)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section {
                    if store.isMedicationLoading && store.medicationPlansForSelectedSubject.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading medication plans…")
                                .foregroundStyle(OneTheme.secondaryInk)
                        }
                    } else if store.medicationPlansForSelectedSubject.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("No active plans", systemImage: "calendar.badge.plus")
                                .font(.headline)
                            Text("Add a plan to create recurring reminders for \(selectedPerson?.displayName ?? "this person").")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                            Button("Add medication plan") {
                                editingPlan = nil
                                showPlanSheet = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(OneTheme.accentBlue)
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(store.medicationPlansForSelectedSubject) { plan in
                            Button {
                                editingPlan = plan
                                showPlanSheet = true
                            } label: {
                                MedicationPlanRow(plan: plan)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    planToArchive = plan
                                    showArchiveConfirmation = true
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                        }
                    }
                } header: {
                    Text(selectedPerson.map { "Active plans for \($0.displayName)" } ?? "Active plans")
                        .textCase(nil)
                } footer: {
                    Text("Open a plan to change its schedule, dose, instructions, or assigned caregiver. Swipe left to archive it.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.custom(16))
        .contentMargins(.top, 10, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(OneTheme.canvas.ignoresSafeArea())
        .navigationTitle("Medication plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingPlan = nil
                    showPlanSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(store.medicationSubjects.isEmpty || selectedPerson?.medicationRemindersEnabled != true)
                .accessibilityLabel("Add medication plan")
            }
        }
        .sheet(isPresented: $showPlanSheet) {
            MedicationPlanSheet(store: store, plan: editingPlan)
        }
        .confirmationDialog("Archive this medication plan?", isPresented: $showArchiveConfirmation) {
            if let plan = planToArchive {
                Button("Archive plan", role: .destructive) {
                    planToArchive = nil
                    Task { _ = await store.archiveMedicationPlan(plan) }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(planToArchive.map { "\($0.name) will stop creating future reminders, while its history stays available." } ?? "This plan will stop creating future reminders, while its history stays available.")
        }
        .task { await store.refreshMedicationPlans() }
        .onChange(of: store.selectedSubjectID) { _, value in
            store.selectedSubjectName = store.medicationSubjects.first(where: { $0.id == value })?.displayName ?? "Everyone"
            Task { await store.refreshMedicationPlans() }
        }
    }
}

private struct MedicationPlanRow: View {
    let plan: MedicationPlan

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(OneTheme.accentBlue)
                .frame(width: 38, height: 38)
                .background(OneTheme.accentBlue.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)
                Text("\(plan.dose) · \(MedicationRecurrence.displayText(plan.schedule))")
                    .font(.subheadline)
                    .foregroundStyle(OneTheme.secondaryInk)
                    .lineLimit(2)
                if !plan.instructions.isEmpty {
                    Text(plan.instructions)
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(OneTheme.secondaryInk.opacity(0.7))
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct CareRecipientRow: View {
    let recipient: CareRecipient
    let canEdit: Bool
    let editAction: () -> Void

    var body: some View {
        Group {
            if canEdit {
                Button(action: editAction) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(canEdit ? "Opens this person's profile. Swipe left to delete them." : "Profile is read only")
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Text(recipient.displayName.prefix(1))
                .font(.headline.weight(.bold))
                .foregroundStyle(OneTheme.accentBlue)
                .frame(width: 40, height: 40)
                .background(OneTheme.accentBlue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(recipient.displayName)
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let relationship = recipient.relationship {
                    Text(relationship)
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                if let roomLabel = recipient.roomLabel {
                    Label(roomLabel, systemImage: "door.left.hand.closed")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                if let faceStatus = recipient.faceRecognitionStatus {
                    Label(faceStatus.title, systemImage: faceStatus == .ready ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.questionmark")
                        .font(.caption)
                        .foregroundStyle(faceStatus == .ready ? OneTheme.mint : OneTheme.secondaryInk)
                }
            }

            Spacer(minLength: 12)

            if canEdit {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OneTheme.secondaryInk.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var accessibilityLabel: String {
        [recipient.displayName, recipient.relationship, recipient.roomLabel]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct CareRecipientEditorSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let recipient: CareRecipient?
    let canEdit: Bool

    @FocusState private var nameFocused: Bool
    @State private var name: String
    @State private var relationship: String
    @State private var roomLabel: String
    @State private var medicationRemindersEnabled: Bool
    @State private var isUpdatingMedicationReminders = false

    init(store: AppStore, recipient: CareRecipient?, canEdit: Bool) {
        self.store = store
        self.recipient = recipient
        self.canEdit = canEdit
        _name = State(initialValue: recipient?.displayName ?? "")
        _relationship = State(initialValue: recipient?.relationship ?? "")
        _roomLabel = State(initialValue: recipient?.roomLabel ?? "")
        _medicationRemindersEnabled = State(initialValue: recipient?.medicationRemindersEnabled ?? false)
    }

    private var isEditing: Bool { recipient != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var currentSetting: CareSetting { store.activeCareSpace?.careSetting ?? .home }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .focused($nameFocused)
                    TextField("Relationship (optional)", text: $relationship)
                    TextField(currentSetting == .residence ? "Room or unit (optional)" : "Room or area (optional)", text: $roomLabel)
                } header: {
                    Text("Care details")
                } footer: {
                    Text(currentSetting == .residence
                         ? "Room labels help distinguish several people in the same residence."
                         : "Relationship and room details are optional and can be changed later.")
                }

                Section {
                    Label("This person is part of the care context only.", systemImage: "person.crop.circle.badge.checkmark")
                    Text("Adding someone here does not create a ONE login, household membership, or app permissions.")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
                }

                if recipient != nil {
                    Section("Medication") {
                        Toggle("Medication reminders", isOn: $medicationRemindersEnabled)
                            .tint(OneTheme.accentBlue)
                            .disabled(isUpdatingMedicationReminders)
                        Text("Allows this care space to create recurring medication reminders and record who marks them done.")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }

                if let error = store.careRecipientError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(OneTheme.amber)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(OneTheme.canvas.ignoresSafeArea())
            .disabled(!canEdit)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if canEdit {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack(spacing: 8) {
                            if store.isCareRecipientMutating { ProgressView().controlSize(.small) }
                            Text(store.isCareRecipientMutating ? "Saving…" : (isEditing ? "Save person" : "Add person"))
                        }
                    }
                    .buttonStyle(OnePrimaryButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(trimmedName.isEmpty || store.isCareRecipientMutating || isUpdatingMedicationReminders)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(OneTheme.canvas.ignoresSafeArea(edges: .horizontal))
                }
            }
            .navigationTitle(canEdit ? (isEditing ? "Edit person" : "Add person") : "Person profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(canEdit ? "Cancel" : "Done") { dismiss() }
                }
            }
            .onAppear { nameFocused = recipient == nil && canEdit }
            .onChange(of: name) { _, value in if value.count > 120 { name = String(value.prefix(120)) } }
            .onChange(of: relationship) { _, value in if value.count > 120 { relationship = String(value.prefix(120)) } }
            .onChange(of: roomLabel) { _, value in if value.count > 120 { roomLabel = String(value.prefix(120)) } }
            .onChange(of: medicationRemindersEnabled) { _, value in
                guard let recipient, canEdit else { return }
                let previousValue = recipient.medicationRemindersEnabled ?? false
                isUpdatingMedicationReminders = true
                Task { @MainActor in
                    let saved = await store.setMedicationRemindersEnabled(for: recipient, enabled: value)
                    if !saved { medicationRemindersEnabled = previousValue }
                    isUpdatingMedicationReminders = false
                }
            }
            .onDisappear { store.clearCareRecipientError() }
        }
    }

    private func save() async {
        let saved: Bool
        if let recipient {
            saved = await store.updateCareRecipient(recipient, name: trimmedName, relationship: relationship, roomLabel: roomLabel)
            guard saved else { return }
        } else {
            saved = await store.createCareRecipient(name: trimmedName, relationship: relationship, roomLabel: roomLabel)
        }
        if saved { dismiss() }
    }
}

private enum FaceEnrollmentCameraPosition: String, CaseIterable, Identifiable, Sendable {
    case front
    case back

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .front: "camera.front.viewfinder"
        case .back: "camera.viewfinder"
        }
    }

    var capturePosition: AVCaptureDevice.Position {
        self == .front ? .front : .back
    }
}

private enum FaceCameraPermission: Equatable {
    case unknown
    case authorized
    case denied
}

private enum FaceEnrollmentStage: Equatable, Sendable {
    case ready
    case center
    case turnRight
    case turnLeft
    case complete

    var title: String {
        switch self {
        case .ready: "Ready when they are"
        case .center: "Look straight ahead"
        case .turnRight: "Turn slowly right"
        case .turnLeft: "Turn slowly left"
        case .complete: "Guided capture complete"
        }
    }

    var instruction: String {
        switch self {
        case .ready: "Hand the phone to the cared-for person, then start the guided capture."
        case .center: "Keep the face inside the circle and look toward the camera."
        case .turnRight: "Keep the face inside the circle and slowly turn to the right."
        case .turnLeft: "Slowly turn to the left for the final side view."
        case .complete: "The three guided views are ready to review."
        }
    }

    func accepts(yaw: Double?) -> Bool {
        guard let yaw else { return true }
        switch self {
        case .ready, .complete:
            return false
        case .center:
            return abs(yaw) <= 0.18
        case .turnRight, .turnLeft:
            return abs(yaw) >= 0.18
        }
    }
}

private struct FaceEnrollmentSample: Identifiable, Equatable, Sendable {
    let id = UUID()
    let frameBase64: String
    let width: Int
    let height: Int
    let cameraPosition: FaceEnrollmentCameraPosition

    var request: FaceEnrollmentFrameRequest {
        FaceEnrollmentFrameRequest(
            frameBase64: frameBase64,
            width: width,
            height: height,
            cameraPosition: cameraPosition.rawValue
        )
    }
}

private final class FaceEnrollmentCameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    @Published private(set) var samples: [FaceEnrollmentSample] = []
    @Published private(set) var permission: FaceCameraPermission = .unknown
    @Published private(set) var message = FaceEnrollmentStage.ready.instruction
    @Published private(set) var isConfigured = false
    @Published private(set) var position: FaceEnrollmentCameraPosition = .front
    @Published private(set) var stage: FaceEnrollmentStage = .ready
    @Published private(set) var isCapturing = false

    private let sessionQueue = DispatchQueue(label: "one.face-enrollment.camera", qos: .userInitiated)
    private let imageContext = CIContext()
    private var output: AVCaptureVideoDataOutput?
    private var configuredPosition: AVCaptureDevice.Position = .front
    private var lastCaptureAt = Date.distantPast
    private let maximumSamples = 6
    private var firstSideYawSign: Double?

    func start() {
        let authorization = AVCaptureDevice.authorizationStatus(for: .video)
        switch authorization {
        case .authorized:
            permission = .authorized
            configureAndStart(for: position)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permission = granted ? .authorized : .denied
                    if granted { self.configureAndStart(for: self.position) }
                }
            }
        default:
            permission = .denied
            message = "Camera access is off. Enable it in Settings to collect recognition samples."
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func resetSamples() {
        samples.removeAll()
        stage = .ready
        isCapturing = false
        firstSideYawSign = nil
        message = FaceEnrollmentStage.ready.instruction
        lastCaptureAt = .distantPast
    }

    func startCapture() {
        guard permission == .authorized, isConfigured else {
            message = "Allow camera access before starting the guided capture."
            return
        }
        samples.removeAll()
        stage = .center
        isCapturing = true
        firstSideYawSign = nil
        lastCaptureAt = .distantPast
        message = FaceEnrollmentStage.center.instruction
    }

    func setPosition(_ newPosition: FaceEnrollmentCameraPosition) {
        guard position != newPosition else { return }
        resetSamples()
        position = newPosition
        guard permission == .authorized else { return }
        configureAndStart(for: newPosition)
    }

    private func configureAndStart(for requestedPosition: FaceEnrollmentCameraPosition) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: requestedPosition.capturePosition)
            guard let device else {
                DispatchQueue.main.async { self.message = "This device does not have the selected camera." }
                return
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                self.session.beginConfiguration()
                self.session.inputs.forEach { self.session.removeInput($0) }
                if let output = self.output { self.session.removeOutput(output) }
                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.message = "The selected camera is unavailable right now." }
                    return
                }
                self.session.addInput(input)
                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                guard self.session.canAddOutput(videoOutput) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.message = "The selected camera cannot provide a live preview." }
                    return
                }
                self.session.addOutput(videoOutput)
                self.output = videoOutput
                self.configuredPosition = requestedPosition.capturePosition
                self.session.commitConfiguration()
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.isConfigured = true }
            } catch {
                DispatchQueue.main.async { self.message = "The selected camera could not be started." }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isCapturing, samples.count < maximumSamples, stage != .ready, stage != .complete else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCaptureAt) >= 0.75 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let faceRequest = VNDetectFaceRectanglesRequest()
        let qualityRequest = VNDetectFaceCaptureQualityRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([faceRequest, qualityRequest])
        } catch {
            return
        }
        guard let faces = faceRequest.results, faces.count == 1, let face = faces.first else {
            publishMessage("Show one face at a time, looking toward the camera.")
            return
        }
        let box = face.boundingBox
        let quality = (qualityRequest.results?.first as? VNFaceObservation)?.faceCaptureQuality ?? 0
        guard box.width >= 0.16, box.height >= 0.16, quality >= 0.18 else {
            publishMessage("Move a little closer and use even light on the face.")
            return
        }
        let yaw = face.yaw?.doubleValue
        guard stage.accepts(yaw: yaw) else {
            publishMessage(stage.instruction)
            return
        }
        if stage == .turnRight, let yaw, abs(yaw) >= 0.18 {
            firstSideYawSign = yaw < 0 ? -1 : 1
        }
        if stage == .turnLeft, let yaw, let firstSideYawSign, (yaw < 0 ? -1 : 1) == firstSideYawSign {
            publishMessage("Now turn slowly to the opposite side for the final view.")
            return
        }
        guard let jpeg = makeJPEG(from: pixelBuffer) else { return }
        lastCaptureAt = now
        let capturedStage = stage
        let sample = FaceEnrollmentSample(
            frameBase64: jpeg.base64EncodedString(),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            cameraPosition: configuredPosition == .front ? .front : .back
        )
        DispatchQueue.main.async { [weak self] in
            guard let self, self.samples.count < self.maximumSamples else { return }
            self.samples.append(sample)
            switch capturedStage {
            case .center:
                self.stage = .turnRight
                self.message = FaceEnrollmentStage.turnRight.instruction
            case .turnRight:
                self.stage = .turnLeft
                self.message = FaceEnrollmentStage.turnLeft.instruction
            case .turnLeft:
                self.stage = .complete
                self.isCapturing = false
                self.message = FaceEnrollmentStage.complete.instruction
            case .ready, .complete:
                break
            }
        }
    }

    private func makeJPEG(from pixelBuffer: CVPixelBuffer) -> Data? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = imageContext.createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.72)
    }

    private func publishMessage(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.message = text }
    }
}

private struct FaceEnrollmentPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeUIView(context: Context) -> FaceEnrollmentPreviewView {
        let view = FaceEnrollmentPreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: FaceEnrollmentPreviewView, context: Context) {
        uiView.previewLayer.session = session
        uiView.previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        uiView.previewLayer.connection?.isVideoMirrored = mirrored
    }
}

private final class FaceEnrollmentPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

private struct FaceGuideOverlay: View {
    let stage: FaceEnrollmentStage
    let isCapturing: Bool

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width * 0.72, proxy.size.height * 0.82)
            ZStack {
                Circle()
                    .fill(.black.opacity(0.12))
                    .frame(width: diameter, height: diameter)
                Circle()
                    .stroke(stage == .complete ? OneTheme.mint : OneTheme.accentBlue, lineWidth: 3)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [8, 7]))
                    .frame(width: diameter + 14, height: diameter + 14)
                VStack(spacing: 4) {
                    Spacer()
                    Text(stage.title)
                        .font(.caption.weight(.bold))
                    Text(isCapturing ? stage.instruction : FaceEnrollmentStage.ready.instruction)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}

private struct CareRecipientWizardSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let recipient: CareRecipient?
    let canEdit: Bool

    @FocusState private var nameFocused: Bool
    @State private var step = 0
    @State private var name: String
    @State private var relationship: String
    @State private var roomLabel: String
    @State private var medicationRemindersEnabled: Bool
    @State private var faceChoice: Bool?
    @State private var isSaving = false
    @StateObject private var camera = FaceEnrollmentCameraModel()

    init(store: AppStore, recipient: CareRecipient?, canEdit: Bool) {
        self.store = store
        self.recipient = recipient
        self.canEdit = canEdit
        _name = State(initialValue: recipient?.displayName ?? "")
        _relationship = State(initialValue: recipient?.relationship ?? "")
        _roomLabel = State(initialValue: recipient?.roomLabel ?? "")
        _medicationRemindersEnabled = State(initialValue: recipient?.medicationRemindersEnabled == true)
        _faceChoice = State(initialValue: recipient?.faceRecognitionStatus == .ready ? true : nil)
    }

    private var isEditing: Bool { recipient != nil }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var currentSetting: CareSetting { store.activeCareSpace?.careSetting ?? .home }
    private var totalSteps: Int { faceChoice == true ? 4 : 3 }
    private var isCaptureStep: Bool { faceChoice == true && step == 2 }
    private var isReviewStep: Bool { step == totalSteps - 1 }
    private var canContinue: Bool {
        guard canEdit, !isSaving, !store.isCareRecipientMutating else { return false }
        switch step {
        case 0: return !trimmedName.isEmpty
        case 1: return faceChoice != nil
        case 2 where isCaptureStep: return camera.samples.count >= 3
        default: return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                wizardProgress
                Form { stepContent }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollContentBackground(.hidden)
                    .background(OneTheme.canvas.ignoresSafeArea())
                    .disabled(!canEdit || isSaving)
            }
            .background(OneTheme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { wizardFooter }
            .navigationTitle(canEdit ? (isEditing ? "Edit person" : "Add person") : "Person profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(canEdit ? "Cancel" : "Done") { dismiss() }
                }
            }
            .onAppear {
                nameFocused = canEdit && recipient == nil
                if !canEdit { faceChoice = recipient?.faceRecognitionStatus == .ready }
            }
            .onChange(of: step) { _, newValue in
                if newValue == 2 && isCaptureStep { camera.start() } else { camera.stop() }
            }
            .onDisappear {
                camera.stop()
                store.clearCareRecipientError()
            }
            .onChange(of: name) { _, value in if value.count > 120 { name = String(value.prefix(120)) } }
            .onChange(of: relationship) { _, value in if value.count > 120 { relationship = String(value.prefix(120)) } }
            .onChange(of: roomLabel) { _, value in if value.count > 120 { roomLabel = String(value.prefix(120)) } }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: detailsStep
        case 1: recognitionStep
        case 2 where isCaptureStep: captureStep
        default: reviewStep
        }
    }

    private var wizardProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stepTitle.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(OneTheme.accentBlue)
                Spacer()
                Text("Step \(min(step + 1, totalSteps)) of \(totalSteps)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OneTheme.secondaryInk)
            }
            ProgressView(value: Double(min(step + 1, totalSteps)), total: Double(totalSteps))
                .tint(OneTheme.accentBlue)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(OneTheme.canvas)
    }

    private var stepTitle: String {
        switch step {
        case 0: "Care details"
        case 1: "Recognition choice"
        case 2 where isCaptureStep: "Capture face"
        default: "Review"
        }
    }

    private var detailsStep: some View {
        Group {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .focused($nameFocused)
                TextField("Relationship (optional)", text: $relationship)
                TextField(currentSetting == .residence ? "Room or unit (optional)" : "Room or area (optional)", text: $roomLabel)
            } header: {
                Text("Who is this care profile for?")
            } footer: {
                Text(currentSetting == .residence
                     ? "Room labels help distinguish several people in the same residence."
                     : "Relationship and room details are optional and can be changed later.")
            }

            Section {
                Label("This person is part of the care context only.", systemImage: "person.crop.circle.badge.checkmark")
                Text("Adding someone here does not create a ONE login, household membership, or app permissions.")
                    .font(.footnote)
                    .foregroundStyle(OneTheme.secondaryInk)
            }

            if recipient != nil {
                Section("Medication") {
                    Toggle("Medication reminders", isOn: $medicationRemindersEnabled)
                        .tint(OneTheme.accentBlue)
                    Text("Allows this care space to create recurring medication reminders and record who marks them done.")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            }

            if let error = store.careRecipientError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(OneTheme.amber) }
            }
        }
    }

    private var recognitionStep: some View {
        Group {
            Section {
                recognitionChoiceButton(
                    title: "Set up recognition",
                    detail: "Use this iPhone to learn a local face template so the system can distinguish this person from an unknown person.",
                    symbol: "person.crop.circle.badge.checkmark",
                    selected: faceChoice == true
                ) { faceChoice = true }
                recognitionChoiceButton(
                    title: "Not now",
                    detail: "Presence tracking can remain anonymous. You can set this up later from this person’s profile.",
                    symbol: "person.crop.circle.badge.questionmark",
                    selected: faceChoice == false
                ) { faceChoice = false }
            } header: {
                Text("Identify this person in the camera view?")
            } footer: {
                Text("Recognition is optional, local to this care space, and uses derived face embeddings only. Raw enrollment photos and live frames are not stored.")
            }

            Section {
                Label("Caregiver-controlled", systemImage: "lock.shield")
                Text("Only a caregiver or admin can add, change, or turn off recognition. An unknown person is never guessed as someone in this care space.")
                    .font(.footnote)
                    .foregroundStyle(OneTheme.secondaryInk)
            }
        }
    }

    private func recognitionChoiceButton(title: String, detail: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? OneTheme.accentBlue : OneTheme.secondaryInk)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(OneTheme.ink)
                    Text(detail).font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? OneTheme.accentBlue : OneTheme.secondaryInk.opacity(0.45))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var captureStep: some View {
        Group {
            Section {
                FaceEnrollmentPreview(session: camera.session, mirrored: camera.position == .front)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay { FaceGuideOverlay(stage: camera.stage, isCapturing: camera.isCapturing) }
                    .overlay(alignment: .topLeading) {
                        Label(camera.isCapturing ? "Capturing" : "Preview only", systemImage: camera.isCapturing ? "circle.fill" : "eye")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(12)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
            } header: {
                Text("One person at a time")
            }

            Section {
                Picker("Camera", selection: Binding(
                    get: { camera.position },
                    set: { camera.setPosition($0) }
                )) {
                    ForEach(FaceEnrollmentCameraPosition.allCases) { position in
                        Label(position.title, systemImage: position.symbol).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                if camera.stage == .ready || camera.stage == .complete {
                    Button {
                        camera.startCapture()
                    } label: {
                        Label(camera.stage == .complete ? "Capture again" : "Start guided capture", systemImage: camera.stage == .complete ? "arrow.counterclockwise" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OnePrimaryButtonStyle())
                    .disabled(camera.permission != .authorized || !camera.isConfigured)
                    .accessibilityIdentifier("face-enrollment-start")
                }

                HStack(spacing: 12) {
                    Image(systemName: camera.samples.count >= 3 ? "checkmark.circle.fill" : "camera.circle")
                        .foregroundStyle(camera.samples.count >= 3 ? OneTheme.mint : OneTheme.accentBlue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(camera.samples.count) of 3 guided views")
                            .font(.headline)
                        Text(camera.message)
                            .font(.footnote)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }

                if camera.permission == .denied {
                    Label("Camera access is required for this optional step. You can go back and choose Not now.", systemImage: "camera.slash")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.amber)
                }

                if !camera.samples.isEmpty && camera.stage != .complete {
                    Button("Retake samples", role: .destructive) { camera.resetSamples() }
                        .font(.footnote.weight(.semibold))
                }
            } header: {
                Text("Capture")
            } footer: {
                Text("Hand the phone to the cared-for person before tapping Start. The guide captures a centered view, then one slow turn right and one slow turn left. Changing cameras resets the guided capture. Samples stay in memory until this setup is submitted or cancelled.")
            }
        }
    }

    private var reviewStep: some View {
        Group {
            Section("Review this care profile") {
                reviewRow(label: "Name", value: trimmedName)
                reviewRow(label: "Relationship", value: relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not added" : relationship)
                reviewRow(label: "Room or area", value: roomLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Not added" : roomLabel)
            }

            Section("Recognition") {
                if faceChoice == true {
                    Label("Ready to set up with \(camera.samples.count) temporary samples", systemImage: "person.crop.circle.badge.checkmark")
                        .foregroundStyle(OneTheme.accentBlue)
                } else {
                    Label("Presence stays anonymous for now", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                Text("Fall detection is not enabled by this setup. This step only prepares identity-aware presence for later safety signals.")
                    .font(.footnote)
                    .foregroundStyle(OneTheme.secondaryInk)
            }

            if let error = store.careRecipientError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(OneTheme.amber) }
            }
        }
    }

    private func reviewRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(OneTheme.secondaryInk)
            Spacer()
            Text(value).foregroundStyle(OneTheme.ink).multilineTextAlignment(.trailing)
        }
    }

    private var wizardFooter: some View {
        HStack(spacing: 12) {
            Button("Back") { goBack() }
                .buttonStyle(.bordered)
                .tint(OneTheme.accentBlue)
                .accessibilityIdentifier("care-recipient-back")
            Spacer()
            Button {
                Task { await advance() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving || store.isCareRecipientMutating { ProgressView().controlSize(.small) }
                    Text(isReviewStep ? (isEditing ? "Save changes" : "Add person") : "Continue")
                }
            }
            .buttonStyle(OnePrimaryButtonStyle())
            .disabled(!canContinue)
            .accessibilityIdentifier("care-recipient-continue")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(OneTheme.canvas.ignoresSafeArea(edges: .horizontal))
    }

    private func goBack() {
        guard step > 0 else {
            dismiss()
            return
        }
        step -= 1
    }

    private func advance() async {
        guard canContinue else { return }
        if !isReviewStep {
            step += 1
            return
        }
        await save()
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let relationshipValue = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomValue = roomLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let relationshipValueOptional = relationshipValue.isEmpty ? nil : relationshipValue
        let roomValueOptional = roomValue.isEmpty ? nil : roomValue

        let saved: Bool
        if let recipient {
            saved = await store.updateCareRecipient(recipient, name: trimmedName, relationship: relationshipValueOptional, roomLabel: roomValueOptional)
        } else {
            saved = await store.createCareRecipient(name: trimmedName, relationship: relationshipValueOptional, roomLabel: roomValueOptional)
        }
        guard saved else { return }

        let savedRecipient = recipient.flatMap { existing in
            store.careRecipients.first(where: { $0.id == existing.id })
        } ?? store.careRecipients
            .filter { $0.displayName == trimmedName }
            .max { $0.createdAt < $1.createdAt }
        if let recipient, medicationRemindersEnabled != (recipient.medicationRemindersEnabled == true) {
            guard await store.setMedicationRemindersEnabled(for: recipient, enabled: medicationRemindersEnabled) else { return }
        }
        guard let savedRecipient else {
            store.careRecipientError = "The person was saved, but the new care profile could not be loaded."
            return
        }

        if faceChoice == true {
            guard await store.enrollFaceProfile(for: savedRecipient, samples: camera.samples.map(\.request)) else { return }
        } else if recipient?.faceRecognitionStatus == .ready || recipient?.faceRecognitionStatus == .unavailable {
            guard await store.disableFaceProfile(for: savedRecipient) else { return }
        }
        dismiss()
    }
}

struct MedicationPlanSheet: View {
    @Bindable var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let plan: MedicationPlan?
    @State private var name: String
    @State private var dose: String
    @State private var instructions: String
    @State private var careRecipientID: UUID?
    @State private var selectedDays: Set<MedicationWeekday>
    @State private var reminderTime: Date
    @State private var active: Bool
    @State private var assignedCaregiverID: UUID?
    @State private var medicationRemindersEnabled: Bool
    @State private var isUpdatingMedicationReminders = false
    @State private var validationMessage = ""

    init(store: AppStore, plan: MedicationPlan?) {
        self.store = store
        self.plan = plan
        let recurrence = MedicationRecurrence.parse(plan?.schedule)
        _name = State(initialValue: plan?.name ?? "")
        _dose = State(initialValue: plan?.dose ?? "")
        _instructions = State(initialValue: plan?.instructions ?? "")
        let initialRecipientID = plan?.careRecipientID ?? store.selectedSubjectID ?? store.medicationSubjects.first?.id
        _careRecipientID = State(initialValue: initialRecipientID)
        _selectedDays = State(initialValue: recurrence.days)
        _reminderTime = State(initialValue: recurrence.time)
        _active = State(initialValue: plan?.active ?? true)
        _assignedCaregiverID = State(initialValue: plan?.assignedCaregiverID)
        _medicationRemindersEnabled = State(initialValue: store.medicationSubjects.first(where: { $0.id == initialRecipientID })?.medicationRemindersEnabled == true)
    }

    private var selectedPerson: CareRecipient? {
        guard let careRecipientID else { return nil }
        return store.medicationSubjects.first(where: { $0.id == careRecipientID })
    }

    private var canSave: Bool {
        !store.isMedicationMutating
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !dose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedDays.isEmpty
            && careRecipientID != nil
            && medicationRemindersEnabled
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("For") {
                    if plan == nil {
                        Picker("Person", selection: $careRecipientID) {
                            ForEach(store.medicationSubjects) { person in
                                Text(person.displayName).tag(Optional(person.id))
                            }
                        }
                    } else if let selectedPerson {
                        Label(selectedPerson.displayName, systemImage: "person.crop.circle")
                    }
                    if let selectedPerson, selectedPerson.medicationRemindersEnabled != true {
                        Label("Medication reminders are off for \(selectedPerson.displayName). Enable them below before saving a plan.", systemImage: "bell.slash.fill")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.amber)
                    }
                    if let selectedPerson {
                        Toggle("Medication reminders", isOn: $medicationRemindersEnabled)
                            .tint(OneTheme.accentBlue)
                            .disabled(isUpdatingMedicationReminders)
                        Text("This setting belongs to \(selectedPerson.displayName), not to general privacy settings.")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }

                Section("Medication") {
                    TextField("Medication or reminder name", text: $name)
                    TextField("Dose", text: $dose)
                    TextField("Instructions (optional)", text: $instructions, axis: .vertical).lineLimit(2...4)
                }

                Section("Repeats") {
                    HStack(spacing: 7) {
                        ForEach(MedicationWeekday.allCases) { day in
                            Button {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            } label: {
                                Text(day.shortLabel)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(selectedDays.contains(day) ? .white : OneTheme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(
                                        selectedDays.contains(day) ? OneTheme.accentBlue : OneTheme.canvas,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(day.fullName)
                            .accessibilityAddTraits(selectedDays.contains(day) ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)

                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)

                    Text(MedicationRecurrence.summary(days: selectedDays, time: reminderTime))
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
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
                    .disabled(!canSave)
                }
            }
            .navigationTitle(plan == nil ? "Add medication plan" : "Edit medication plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: careRecipientID) { _, _ in
                medicationRemindersEnabled = selectedPerson?.medicationRemindersEnabled == true
            }
            .onChange(of: medicationRemindersEnabled) { _, value in
                guard let selectedPerson else { return }
                let previousValue = selectedPerson.medicationRemindersEnabled == true
                isUpdatingMedicationReminders = true
                Task { @MainActor in
                    let saved = await store.setMedicationRemindersEnabled(for: selectedPerson, enabled: value)
                    if !saved { medicationRemindersEnabled = previousValue }
                    isUpdatingMedicationReminders = false
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDose = dose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let careRecipientID, let selectedPerson else {
            validationMessage = "Choose who this plan is for."
            return
        }
        guard medicationRemindersEnabled else {
            validationMessage = "Enable medication reminders for \(selectedPerson.displayName) before saving a plan."
            return
        }
        guard !trimmedName.isEmpty, !trimmedDose.isEmpty else {
            validationMessage = "Medication name and dose are required."
            return
        }
        guard !selectedDays.isEmpty else {
            validationMessage = "Choose at least one day."
            return
        }
        let schedule = MedicationRecurrence.schedule(days: selectedDays, time: reminderTime)
        validationMessage = ""
        let succeeded: Bool
        if let plan {
            succeeded = await store.updateMedicationPlan(plan, name: trimmedName, dose: trimmedDose, instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines), schedule: schedule, active: active, assignedCaregiverID: assignedCaregiverID)
        } else {
            store.selectedSubjectID = careRecipientID
            store.selectedSubjectName = selectedPerson.displayName
            succeeded = await store.createMedicationPlan(name: trimmedName, dose: trimmedDose, instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines), schedule: schedule, assignedCaregiverID: assignedCaregiverID, careRecipientID: careRecipientID)
        }
        if succeeded { dismiss() }
    }
}

private enum MedicationWeekday: String, CaseIterable, Identifiable, Hashable {
    case mon = "Mon", tue = "Tue", wed = "Wed", thu = "Thu", fri = "Fri", sat = "Sat", sun = "Sun"

    var id: String { rawValue }
    var shortLabel: String {
        switch self {
        case .mon: "M"
        case .tue: "T"
        case .wed: "W"
        case .thu: "T"
        case .fri: "F"
        case .sat: "S"
        case .sun: "S"
        }
    }
    var fullName: String {
        switch self {
        case .mon: "Monday"
        case .tue: "Tuesday"
        case .wed: "Wednesday"
        case .thu: "Thursday"
        case .fri: "Friday"
        case .sat: "Saturday"
        case .sun: "Sunday"
        }
    }
}

private enum MedicationRecurrence {
    struct Parsed {
        let days: Set<MedicationWeekday>
        let time: Date
    }

    static func parse(_ schedule: String?) -> Parsed {
        let calendar = Calendar.current
        let fallbackTime = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
        guard let raw = schedule?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return Parsed(days: Set(MedicationWeekday.allCases), time: fallbackTime)
        }

        let lower = raw.lowercased()
        let days: Set<MedicationWeekday>
        if lower.contains("weekday") {
            days = [.mon, .tue, .wed, .thu, .fri]
        } else if lower.contains("weekend") {
            days = [.sat, .sun]
        } else {
            let found = Set(MedicationWeekday.allCases.filter { day in
                lower.range(of: day.rawValue.lowercased()) != nil
            })
            days = found.isEmpty ? Set(MedicationWeekday.allCases) : found
        }

        let components = raw.components(separatedBy: "@")
        let clockSource = components.count > 1 ? components[1] : raw
        let time = firstClock(in: clockSource).flatMap { parseClock($0) } ?? fallbackTime
        return Parsed(days: days, time: time)
    }

    static func schedule(days: Set<MedicationWeekday>, time: Date) -> String {
        let clock = clockString(time)
        let ordered = MedicationWeekday.allCases.filter(days.contains)
        if ordered.count == MedicationWeekday.allCases.count {
            return "Daily @ \(clock)"
        }
        return "\(ordered.map(\.rawValue).joined(separator: ",")) @ \(clock)"
    }

    static func displayText(_ schedule: String) -> String {
        let parsed = parse(schedule)
        return summary(days: parsed.days, time: parsed.time)
    }

    static func summary(days: Set<MedicationWeekday>, time: Date) -> String {
        let ordered = MedicationWeekday.allCases.filter(days.contains)
        let dayText: String
        if ordered.count == MedicationWeekday.allCases.count {
            dayText = "Every day"
        } else if ordered == [.mon, .tue, .wed, .thu, .fri] {
            dayText = "Weekdays"
        } else if ordered == [.sat, .sun] {
            dayText = "Weekends"
        } else {
            dayText = ordered.map(\.rawValue).joined(separator: ", ")
        }
        return "\(dayText) · \(time.formatted(date: .omitted, time: .shortened))"
    }

    private static func firstClock(in value: String) -> String? {
        let pattern = #"(?:[01]\d|2[0-3]):[0-5]\d"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range, in: value) else { return nil }
        return String(value[range])
    }

    private static func parseClock(_ value: String) -> Date? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    private static func clockString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0)
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
        Group {
            if let editAction {
                Button(action: editAction) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .padding(.vertical, 14)
        .accessibilityLabel("\(account.name), \(account.relationship), role \(account.role.title). Permissions: \(account.permissions.joined(separator: ", "))")
        .accessibilityHint(editAction == nil ? "This access cannot be edited here" : "Opens access settings")
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Text(account.name.prefix(1)).font(.headline.weight(.bold)).foregroundStyle(OneTheme.accentBlue).frame(width: 42, height: 42).background(OneTheme.accentBlue.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) { Text(account.name).font(.headline); if account.isCurrentUser { Text("YOU").font(.caption2.weight(.bold)).foregroundStyle(OneTheme.accentBlue) } }
                Text(account.relationship).font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                Text(account.permissions.prefix(2).joined(separator: " · ")).font(.caption).foregroundStyle(OneTheme.secondaryInk)
            }
            Spacer(minLength: 8)
            Text(account.role.title).font(.caption.weight(.semibold)).multilineTextAlignment(.trailing).foregroundStyle(roleColor).padding(.horizontal, 9).padding(.vertical, 6).background(roleColor.opacity(0.12), in: Capsule())
            if editAction != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OneTheme.accentBlue)
                    .frame(width: 24, height: 34)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: dose.status.symbol)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(dose.medicationName)
                    .font(.headline)
                    .foregroundStyle(OneTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Text(dose.scheduledAt.formatted(date: .omitted, time: .shortened))
                    if !dose.instructions.isEmpty {
                        Text("·")
                        Text(dose.instructions).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(OneTheme.secondaryInk)

                if let completion = completionText {
                    Text(completion)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                } else if let caregiver = dose.assignedCaregiverName {
                    Text("Assigned to \(caregiver)")
                        .font(.caption)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityHint(dose.status == .acknowledged ? "Marked done" : "Swipe left to mark done. Swipe right for skip or missed.")
    }

    private var statusTitle: String {
        if dose.status == .acknowledged { return "Done" }
        if dose.status == .needsConfirmation, dose.markedByName != nil { return "Skipped" }
        return dose.status.title
    }

    private var completionText: String? {
        guard dose.status != .scheduled else { return nil }
        var parts = [statusTitle]
        if let marker = dose.markedByName { parts.append("by \(marker)") }
        if let markedAt = dose.markedAt { parts.append(markedAt.formatted(date: .omitted, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch dose.status { case .acknowledged: OneTheme.mint; case .missed: OneTheme.amber; case .needsConfirmation: OneTheme.accentBlue; case .scheduled: OneTheme.secondaryInk }
    }
}

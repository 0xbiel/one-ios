import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var showCareSpaces = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CareSpaceContextButton(space: store.activeCareSpace, selectedPersonName: nil, isLoading: store.isCareSpacesLoading) {
                        showCareSpaces = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Care space")
                }

                Section("Privacy and consent") {
                    if store.isConsentsLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading choices…")
                                .font(.subheadline)
                                .foregroundStyle(OneTheme.secondaryInk)
                        }
                    }
                    ForEach(store.privacyConsents) { consent in
                        Toggle(
                            consent.purpose,
                            isOn: Binding(
                                get: { store.privacyConsents.first(where: { $0.id == consent.id })?.enabled ?? false },
                                set: { value in
                                    Task { _ = await store.setConsent(consent, enabled: value) }
                                }
                            )
                        )
                        .tint(OneTheme.accentBlue)
                        .disabled(store.isConsentMutating || store.isConsentsLoading)
                    }
                    if let error = store.consentError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(OneTheme.amber)
                    }
                    Text("Room, audio, and clip data stays local unless you enable sharing. Manage medication reminders in each person’s profile.")
                        .font(.footnote)
                }

                if store.canManageCareRecipients && !store.careRecipients.isEmpty {
                    Section("Check-ins and analytics") {
                        ForEach(store.careRecipients) { recipient in
                            Toggle(isOn: Binding(
                                get: { store.analyticsConsent(for: recipient) },
                                set: { value in
                                    Task { _ = await store.setAnalyticsConsent(for: recipient, enabled: value) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(recipient.displayName)
                                    Text("Check-ins and household analytics")
                                        .font(.footnote)
                                        .foregroundStyle(OneTheme.secondaryInk)
                                }
                            }
                            .tint(OneTheme.accentBlue)
                            .disabled(store.isConsentMutating || store.isConsentsLoading)
                        }
                        Text("Consent is required separately for each person.")
                            .font(.footnote)
                    }
                }

                Section("Your data") {
                    HouseholdPrivacyActions(
                        homeID: store.session?.homeID,
                        canManage: store.canManageHouseholdData,
                        export: { try await store.exportHouseholdData() },
                        delete: { try await store.deleteHouseholdData(confirmationHomeID: $0) }
                    )
                }

                Section("Session") {
                    Button(role: .destructive) {
                        Task { await store.logout() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("About") {
                    Label("ONE · build 1", systemImage: "sparkles")
                    Text("Observations support human attention. They are not medical advice or a diagnosis.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(OneTheme.canvas.ignoresSafeArea())
            .navigationTitle("Account")
            .task {
                if store.careSpaces.isEmpty { await store.refreshCareSpaces() }
                if store.careRecipients.isEmpty { await store.refreshCareRecipients() }
                await store.refreshConsents()
            }
        }
        .sheet(isPresented: $showCareSpaces) {
            CareSpaceSwitcherView(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

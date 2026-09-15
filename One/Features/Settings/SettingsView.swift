import SwiftUI

struct SettingsView: View {
    @Bindable var store: AppStore
    @State private var showCareSpaces = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    CareSpaceContextButton(space: store.activeCareSpace, isLoading: store.isCareSpacesLoading) {
                        showCareSpaces = true
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Care space")
                } footer: {
                    Text("Switch homes or residences without mixing their people, cameras, maps, or consent choices.")
                }

                Section("Privacy and consent") {
                    if store.isConsentsLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Loading your privacy choices…")
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
                    Text("Sensitive room, audio, and clip data stays local unless you explicitly enable sharing. Medication reminders belong to each cared-for person and can be enabled from that person’s profile.")
                        .font(.footnote)
                }

                Section("Your data") {
                    Button {
                        store.lastDataRequest = DataRequest(kind: .export)
                    } label: {
                        Label("Prepare a data export", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        store.lastDataRequest = DataRequest(kind: .delete)
                    } label: {
                        Label("Request deletion", systemImage: "trash")
                    }
                }

                Section("Session") {
                    Button(role: .destructive) {
                        Task { await store.logout() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Text("Signing out revokes the backend session and clears this device’s stored credential.")
                        .font(.footnote)
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

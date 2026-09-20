import SwiftUI

struct AssistantView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Assistant")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .tracking(-1)
                        ForEach(store.assistantMessages) { message in
                            messageBubble(message)
                        }
                    }
                    .padding(20)
                }
                Button {
                    store.isListening.toggle()
                    if !store.isListening { store.sendAssistantMessage() }
                } label: {
                    Label(store.isListening ? "Release to send" : "Press and hold to talk", systemImage: store.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                }
                .buttonStyle(.borderedProminent)
                .tint(OneTheme.accentBlue)
                .foregroundStyle(.white)
                .padding(20)
            }
            .background(OneTheme.canvas.ignoresSafeArea())
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func messageBubble(_ message: AssistantMessage) -> some View {
        HStack {
            if message.isUser { Spacer() }
            Text(message.text)
                .foregroundStyle(OneTheme.ink)
                .padding(14)
                .fixedSize(horizontal: false, vertical: true)
                .background(message.isUser ? OneTheme.accentCyan.opacity(0.25) : OneTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            if !message.isUser { Spacer() }
        }
    }
}

struct CaregiverAssistantView: View {
    @Bindable var store: AppStore
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    // Enable when the new-question reset behavior is implemented.
    private let isNewQuestionEnabled = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assistant")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .tracking(-1)
                        Text("Bounded context from medication records, daily check-ins, and reviewable safety signals.")
                            .font(.subheadline)
                            .foregroundStyle(OneTheme.secondaryInk)
                    }

                    SafetyAnalyticsCard(events: store.events)

                    if !store.medicationSubjects.isEmpty {
                        Picker("For", selection: $store.selectedSubjectName) {
                            ForEach(store.medicationSubjects) { person in
                                Text(person.displayName).tag(person.displayName)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: store.selectedSubjectName) { _, name in
                            store.selectedSubjectID = store.medicationSubjects.first(where: { $0.displayName == name })?.id
                        }
                    }

                    ForEach(store.familyAssistantMessages) { message in
                        HStack {
                            if message.isUser { Spacer(minLength: 40) }
                            Text(message.text)
                                .font(.body)
                                .foregroundStyle(OneTheme.ink)
                                .padding(14)
                                .fixedSize(horizontal: false, vertical: true)
                                .background(message.isUser ? OneTheme.accentCyan.opacity(0.22) : OneTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            if !message.isUser { Spacer(minLength: 40) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                assistantComposer
            }
            .background(OneTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if store.careRecipients.isEmpty { await store.refreshFamilyData() }
            }
        }
    }

    private var assistantComposer: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                assistantActionButton(
                    systemName: "plus",
                    accessibilityLabel: "Start a new question",
                    tint: nil
                ) {
                    inputFocused = true
                }
                .disabled(!isNewQuestionEnabled)

                HStack(spacing: 8) {
                    TextField("Ask anything about the recorded plan", text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .font(.body)
                        .foregroundStyle(OneTheme.ink)
                        .tint(OneTheme.accentBlue)
                        .submitLabel(.send)
                        .onSubmit { send() }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 50)
                .modifier(AssistantGlassInput(tint: nil))

                assistantActionButton(
                    systemName: "arrow.up",
                    accessibilityLabel: "Send",
                    tint: OneTheme.accentBlue,
                    foreground: .white
                ) {
                    send()
                }
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.selectedSubjectID != nil
    }

    @ViewBuilder
    private func assistantActionButton(
        systemName: String,
        accessibilityLabel: String,
        tint: Color?,
        foreground: Color = OneTheme.ink,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)

        if #available(iOS 26.0, *) {
            button
                .glassEffect(.regular.tint(tint?.opacity(0.58)).interactive(), in: Circle())
                .overlay {
                    Circle()
                        .stroke((tint?.opacity(0.42) ?? OneTheme.ink.opacity(0.20)), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
        } else {
            if let tint {
                button
                    .background(.ultraThinMaterial, in: Circle())
                    .background(tint.opacity(0.18), in: Circle())
                    .overlay {
                        Circle()
                            .stroke(tint.opacity(0.42), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
            } else {
                button
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(OneTheme.ink.opacity(0.20), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
            }
        }
    }

    private func send() {
        guard canSend else { return }
        let message = draft
        draft = ""
        inputFocused = false
        Task { await store.sendFamilyAssistantMessage(message) }
    }
}

private struct AssistantGlassInput: ViewModifier {
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 25, style: .continuous)

        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint?.opacity(0.48)).interactive(), in: shape)
                .overlay {
                    shape
                        .stroke((tint?.opacity(0.38) ?? OneTheme.ink.opacity(0.16)), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
        } else {
            if let tint {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .background(tint.opacity(0.15), in: shape)
                    .overlay {
                        shape
                            .stroke(tint.opacity(0.38), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
            } else {
                content
                    .background(.ultraThinMaterial, in: shape)
                    .overlay {
                        shape
                            .stroke(OneTheme.ink.opacity(0.16), lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
            }
        }
    }
}

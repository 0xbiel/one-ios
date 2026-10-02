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
    private struct PendingReview: Identifiable {
        let id = UUID()
        let question: String
        let recipientID: UUID?
    }
    @State private var pendingReview: PendingReview?
    @FocusState private var inputFocused: Bool
    @State private var showingAssistantConsent = false

    @State private var isStartingNewQuestion = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Assistant")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .tracking(-1)
                    }

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

                    assistantStatus
                    if store.assistantCapability?.state == .unconfigured {
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
                    } else {
                        ForEach(store.normalAssistantMessages) { message in
                            normalMessage(text: message.text, isUser: message.isUser)
                        }
                        if !store.assistantStreamingText.isEmpty {
                            normalMessage(text: store.assistantStreamingText, isUser: false)
                        }
                        if store.isAssistantStreaming {
                            HStack(spacing: 8) { ProgressView(); Text("Responding…").font(.footnote).foregroundStyle(OneTheme.secondaryInk) }
                        }
                        if let batch = store.assistantPendingQuestions {
                            AssistantQuestionBatchCard(store: store, batch: batch)
                                .id(batch.toolCallID)
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
                await store.refreshAssistantCapability()
            }
            .task(id: store.selectedSubjectID) { await store.refreshAssistantCapability() }
            .onChange(of: store.session?.homeID) { _, _ in pendingReview = nil; draft = "" }
            .onChange(of: store.selectedSubjectID) { _, _ in pendingReview = nil; draft = "" }
        }
        .sheet(isPresented: $showingAssistantConsent) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Consent for external AI").font(.title2.bold())
                    Text("Using this assistant may send your question and the selected person’s permitted care context to an external AI provider. Provider setup does not grant permission.")
                    Text("An authorized person must explicitly record external AI processing consent for this person before chatting. No permission is changed here.")
                        .foregroundStyle(OneTheme.secondaryInk)
                    Button("Open privacy settings") { showingAssistantConsent = false; store.selectedTab = "settings" }
                        .buttonStyle(.borderedProminent)
                    Button("Check consent again") { showingAssistantConsent = false; Task { await store.refreshAssistantCapability() } }
                    Spacer()
                }.padding(24)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAssistantConsent = false } } }
            }.presentationDetents([.medium, .large])
        }
        .sheet(item: $pendingReview) { request in
            AssistantContextReviewSheet(
                review: store.assistantContextReview,
                error: store.dataReviewError,
                isLoading: store.isAssistantContextReviewLoading,
                question: request.question,
                onConfirm: {
                    guard store.selectedSubjectID == request.recipientID else { return }
                    let message = request.question
                    draft = ""
                    Task { await store.sendFamilyAssistantMessage(message) }
                },
                onCancel: { pendingReview = nil }
            )
            .task { await store.refreshAssistantContextReview(message: request.question) }
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
                    guard !isStartingNewQuestion else { return }
                    isStartingNewQuestion = true
                    Task {
                        if await store.startNewAssistantConversation() {
                            pendingReview = nil
                            draft = ""
                            inputFocused = true
                        }
                        isStartingNewQuestion = false
                    }
                }
                .disabled(isStartingNewQuestion || store.isAssistantCancelling || store.isAssistantCapabilityLoading)

                HStack(spacing: 8) {
                    TextField("Ask about today", text: $draft, axis: .vertical)
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
        !isStartingNewQuestion && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.selectedSubjectID != nil
            && (store.assistantCapability?.state == .unconfigured || store.assistantCanSend)
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
        let request = PendingReview(question: draft.trimmingCharacters(in: .whitespacesAndNewlines), recipientID: store.selectedSubjectID)
        inputFocused = false
        if store.assistantCapability?.state == .unconfigured {
            pendingReview = request
        } else {
            store.sendNormalAssistantMessage(request.question)
            draft = ""
        }
    }

    @ViewBuilder private var assistantStatus: some View {
        if store.isAssistantCapabilityLoading {
            ProgressView("Connecting…").font(.footnote)
        } else if store.assistantCapability?.state == .unconfigured {
            VStack(alignment: .leading, spacing: 10) {
                Text("Context preview").font(.subheadline.weight(.semibold))
                Text("No AI provider is configured. Review the available context or set up a provider.")
                    .font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                Button("Open settings") { store.selectedTab = "settings" }
                    .font(.subheadline.weight(.semibold))
            }.padding(14).modifier(AssistantGlassCard())
        } else if store.assistantCapability?.requiresConsent == true {
            VStack(alignment: .leading, spacing: 10) {
                Text("Consent is needed before using this assistant.").font(.subheadline)
                Button("Review consent") { showingAssistantConsent = true }.font(.subheadline.weight(.semibold))
            }.padding(14).modifier(AssistantGlassCard())
        } else if store.assistantCapability?.state == .unavailable {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.assistantCapability?.reason == "unsupported_chat_model" ? "This model’s chat support has not been verified. Review the provider settings." : "The assistant is temporarily unavailable.").font(.subheadline)
                Button("Try again") { Task { await store.refreshAssistantCapability() } }
            }.padding(14).modifier(AssistantGlassCard())
        }
        if let error = store.assistantChatError {
            VStack(alignment: .leading, spacing: 10) {
                Text(error).font(.subheadline)
                HStack {
                    if store.assistantCanRetry { Button("Retry") { Task { await store.retryAssistantResponse() } } }
                    else if store.assistantCapability == nil { Button("Try again") { Task { await store.refreshAssistantCapability() } } }
                    if !store.normalAssistantMessages.isEmpty || store.assistantPendingQuestions != nil {
                        Button("Cancel turn") { Task { await store.cancelAssistantTurn() } }
                            .disabled(store.isAssistantCancelling)
                    }
                }.font(.subheadline.weight(.semibold))
            }.padding(14).modifier(AssistantGlassCard())
        } else if store.isAssistantStreaming {
            Button("Cancel response") { Task { await store.cancelAssistantTurn() } }
                .font(.footnote.weight(.semibold)).disabled(store.isAssistantCancelling)
        }
    }

    private func normalMessage(text: String, isUser: Bool) -> some View {
        HStack {
            if isUser { Spacer(minLength: 36) }
            Text(text).font(.body).foregroundStyle(OneTheme.ink)
                .padding(14).fixedSize(horizontal: false, vertical: true)
                .modifier(AssistantGlassCard(tint: isUser ? OneTheme.accentCyan : nil))
            if !isUser { Spacer(minLength: 36) }
        }
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

private struct AssistantGlassCard: ViewModifier {
    var tint: Color? = nil
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if #available(iOS 26.0, *) { content.glassEffect(.regular.tint(tint?.opacity(0.22)), in: shape) }
        else { content.background(.ultraThinMaterial, in: shape) }
    }
}

private struct AssistantQuestionBatchCard: View {
    @Bindable var store: AppStore
    let batch: AssistantQuestionBatch
    @State private var index = 0
    @State private var customQuestions: Set<String> = []
    private var question: AssistantQuestion { batch.questions[min(index, batch.questions.count - 1)] }
    private var selection: AssistantQuestionAnswer? { store.assistantQuestionAnswers[question.id] }
    private var isCustom: Bool { customQuestions.contains(question.id) || selection?.customText != nil }
    private var hasAnswer: Bool {
        selection?.optionID != nil || selection?.customText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(question.header).font(.caption.weight(.semibold)).foregroundStyle(OneTheme.secondaryInk)
                    Spacer()
                    Text("\(index + 1) of \(batch.questions.count)").font(.caption).foregroundStyle(OneTheme.secondaryInk)
                }
                Text(question.question).font(.subheadline.weight(.semibold))
                VStack(spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.element.id) { number, option in
                        Button {
                            customQuestions.remove(question.id)
                            store.setAssistantAnswer(questionID: question.id, optionID: option.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(number + 1)")
                                    .font(.caption.weight(.semibold)).frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(OneTheme.secondaryInk.opacity(0.55), lineWidth: 0.8))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.label).font(.subheadline.weight(.medium))
                                    Text(option.description).font(.caption).foregroundStyle(OneTheme.secondaryInk)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if selection?.optionID == option.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(OneTheme.accentBlue) }
                            }.foregroundStyle(OneTheme.ink).padding(12).contentShape(RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                            .modifier(AssistantGlassCard(tint: selection?.optionID == option.id ? OneTheme.accentBlue : nil))
                    }
                    Button {
                        customQuestions.insert(question.id)
                        store.setAssistantAnswer(questionID: question.id, customText: selection?.customText ?? "")
                    } label: {
                        HStack { Image(systemName: "pencil"); Text("Write my own"); Spacer() }.font(.subheadline).padding(12)
                    }.buttonStyle(.plain).modifier(AssistantGlassCard(tint: isCustom ? OneTheme.accentBlue : nil))
                    if isCustom {
                        TextField("Your answer", text: Binding(
                            get: { store.assistantQuestionAnswers[question.id]?.customText ?? "" },
                            set: { store.setAssistantAnswer(questionID: question.id, customText: String($0.prefix(500))) }
                        ), axis: .vertical)
                        .lineLimit(2...4).font(.subheadline).padding(12).modifier(AssistantGlassCard())
                    }
                }
                .disabled(store.isAssistantStreaming || store.isAssistantCancelling || store.assistantCanRetry)
                HStack {
                    if index > 0 { Button("Back") { index -= 1 } }
                    Button("Cancel") { Task { await store.cancelAssistantTurn() } }
                    Spacer()
                    if index + 1 < batch.questions.count {
                        Button("Next") { index += 1 }.disabled(!hasAnswer)
                    } else {
                        Button("Send answers") { store.submitAssistantAnswers() }
                            .disabled(!store.assistantBatchComplete || store.assistantCanRetry)
                    }
                }.font(.subheadline.weight(.semibold))
                    .disabled(store.isAssistantStreaming || store.isAssistantCancelling)
            }.padding(16).modifier(AssistantGlassCard())
        }
        .accessibilityElement(children: .contain)
    }
}

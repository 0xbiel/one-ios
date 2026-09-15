import SwiftUI

struct CareSpaceContextButton: View {
    let space: CareSpaceSummary?
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LiquidGlassSurface(radius: 28) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(OneTheme.accentBlue.opacity(0.12))
                        Image(systemName: space?.careSetting.symbol ?? "house.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(OneTheme.accentBlue)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("CARING FOR")
                            .font(.caption2.weight(.bold))
                            .tracking(1.15)
                            .foregroundStyle(OneTheme.cyan)
                        Text(space?.name ?? "Current care space")
                            .font(.headline)
                            .foregroundStyle(OneTheme.ink)
                            .lineLimit(1)
                        Text(contextDescription)
                            .font(.caption)
                            .foregroundStyle(OneTheme.secondaryInk)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if isLoading && space == nil {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(OneTheme.secondaryInk)
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Shows care spaces you can switch to or lets you create another one.")
        .accessibilityIdentifier("care-space-context")
    }

    private var contextDescription: String {
        guard let space else { return isLoading ? "Loading household details" : "Manage homes and residences" }
        return "\(space.peopleSummary) · \(space.careSetting.connectedTitle)"
    }

    private var accessibilityLabel: String {
        guard let space else { return "Manage care spaces" }
        return "Caring for \(space.name), \(space.peopleSummary), \(space.careSetting.connectedTitle)"
    }
}

struct CareSpaceSwitcherView: View {
    @Bindable var store: AppStore

    @Environment(\.dismiss) private var dismiss
    @State private var showsCreation = ProcessInfo.processInfo.arguments.contains("-one-show-care-space-create")

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    introduction
                    content
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.refreshCareSpaces() }
            .background(OneTheme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .navigationTitle("Care spaces")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $showsCreation) {
                CreateCareSpaceView(store: store) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if store.careSpaces.isEmpty { await store.refreshCareSpaces() }
        }
        .onDisappear { store.clearCareSpaceError() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR CARE CIRCLE")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(OneTheme.cyan)
            Text("Choose where you’re caring.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(OneTheme.ink)
            Text("Each care space keeps its people, cameras, maps, routines, and consent choices separate.")
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.isCareSpacesLoading && store.careSpaces.isEmpty {
            SurfaceCard(radius: 24) {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Loading your care spaces…")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        } else if store.careSpaces.isEmpty {
            emptyState
        } else {
            VStack(spacing: 12) {
                ForEach(store.careSpaces) { space in
                    CareSpaceRow(
                        space: space,
                        isSwitching: store.switchingCareSpaceID == space.id,
                        isDisabled: store.isCareSpaceMutating
                    ) {
                        Task {
                            if await store.activateCareSpace(space) { dismiss() }
                        }
                    }
                }
            }
        }

        if let error = store.careSpaceError {
            errorBanner(error)
        }
    }

    private var emptyState: some View {
        SurfaceCard(radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "house.badge.plus")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(OneTheme.accentBlue)
                Text("No care spaces available")
                    .font(.headline)
                Text("Your current session remains active. Try loading the list again, or create another care space.")
                    .font(.subheadline)
                    .foregroundStyle(OneTheme.secondaryInk)
                Button("Try again") {
                    Task { await store.refreshCareSpaces() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        LiquidGlassSurface(radius: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(OneTheme.amber)
                VStack(alignment: .leading, spacing: 7) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(OneTheme.ink)
                    Button("Retry") {
                        Task { await store.refreshCareSpaces() }
                    }
                    .font(.footnote.weight(.semibold))
                }
                Spacer()
            }
            .padding(16)
        }
        .accessibilityIdentifier("care-space-error")
    }

    private var footer: some View {
        Button {
            store.clearCareSpaceError()
            showsCreation = true
        } label: {
            Label("Add care space", systemImage: "plus")
        }
        .buttonStyle(OnePrimaryButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(store.isCareSpaceMutating)
        .accessibilityIdentifier("care-space-add")
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(OneTheme.canvas.ignoresSafeArea(edges: .horizontal))
    }
}

private struct CareSpaceRow: View {
    let space: CareSpaceSummary
    let isSwitching: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard !space.active else { return }
            action()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(space.active ? OneTheme.accentBlue.opacity(0.16) : OneTheme.canvas)
                    Image(systemName: space.careSetting.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(space.active ? OneTheme.accentBlue : OneTheme.secondaryInk)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(space.name)
                        .font(.headline)
                        .foregroundStyle(OneTheme.ink)
                        .lineLimit(2)
                    Text("\(space.peopleSummary) · \(space.careSetting.title)")
                        .font(.subheadline)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .lineLimit(2)
                    ViewThatFits(in: .horizontal) {
                        Text("\(space.supportFocus.title) · \(space.role.title)")
                            .lineLimit(1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(space.supportFocus.title)
                            Text(space.role.title)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(OneTheme.secondaryInk)
                }

                Spacer(minLength: 8)

                if isSwitching {
                    ProgressView()
                        .controlSize(.small)
                } else if space.active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(OneTheme.accentBlue)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(
                space.active ? OneTheme.accentBlue.opacity(0.07) : OneTheme.surface,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(space.active ? OneTheme.accentBlue.opacity(0.24) : OneTheme.secondaryInk.opacity(0.1), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(space.name), \(space.peopleSummary), \(space.careSetting.title), \(space.supportFocus.title), \(space.role.title)\(space.active ? ", current care space" : "")")
        .accessibilityHint(space.active ? "This care space is active." : "Switches to this care space.")
        .accessibilityIdentifier("care-space-row-\(space.id.uuidString.lowercased())")
    }
}

private struct CreateCareSpaceView: View {
    @Bindable var store: AppStore
    let onCreated: () -> Void

    @FocusState private var nameIsFocused: Bool
    @State private var name = ""
    @State private var careSetting: CareSetting = .home
    @State private var supportFocus: SupportFocus = .general

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    nameCard
                    settingCard
                    supportCard
                    if let error = store.careSpaceError { errorBanner(error) }
                    Label("ONE supports attention and human review. It does not provide a diagnosis.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(OneTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: nameIsFocused) { _, isFocused in
                guard isFocused else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    guard !Task.isCancelled, nameIsFocused else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo("care-space-name", anchor: .bottom)
                    }
                }
            }
        }
        .background(OneTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .navigationTitle("New care space")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: name) { _, value in
            if value.count > 120 { name = String(value.prefix(120)) }
        }
        .onAppear { nameIsFocused = true }
        .onDisappear { store.clearCareSpaceError() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A NEW PLACE TO CARE")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(OneTheme.cyan)
            Text("Set up the essentials.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(OneTheme.ink)
            Text("You’ll choose privacy and sharing preferences for this space next.")
                .font(.body)
                .foregroundStyle(OneTheme.secondaryInk)
        }
    }

    private var nameCard: some View {
        SurfaceCard(radius: 24) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Care-space name")
                        .font(.headline)
                    Spacer()
                    Text("\(name.count)/120")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(OneTheme.secondaryInk)
                }
                TextField("For example, Mum’s home", text: $name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($nameIsFocused)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(OneTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("care-space-name")
                    .id("care-space-name")
            }
            .padding(18)
        }
    }

    private var settingCard: some View {
        SurfaceCard(radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Place")
                    .font(.headline)
                Picker("Place", selection: $careSetting) {
                    ForEach(CareSetting.allCases) { setting in
                        Label(setting.title, systemImage: setting.symbol).tag(setting)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("care-space-setting")
                Text(careSetting == .home ? "A private household and its care circle." : "A shared or professional residential setting.")
                    .font(.footnote)
                    .foregroundStyle(OneTheme.secondaryInk)
            }
            .padding(18)
        }
    }

    private var supportCard: some View {
        SurfaceCard(radius: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Support focus")
                    .font(.headline)
                ForEach(SupportFocus.allCases) { focus in
                    Button {
                        supportFocus = focus
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: supportFocus == focus ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(supportFocus == focus ? OneTheme.accentBlue : OneTheme.secondaryInk)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(focus.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OneTheme.ink)
                                Text(focus.detail)
                                    .font(.caption)
                                    .foregroundStyle(OneTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(supportFocus == focus ? OneTheme.accentBlue.opacity(0.08) : OneTheme.canvas, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(supportFocus == focus ? .isSelected : [])
                    .accessibilityIdentifier("care-space-focus-\(focus.rawValue)")
                }
            }
            .padding(18)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(OneTheme.amber)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OneTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("care-space-create-error")
    }

    private var footer: some View {
        Button {
            nameIsFocused = false
            Task {
                if await store.createCareSpace(name: trimmedName, careSetting: careSetting, supportFocus: supportFocus) {
                    onCreated()
                }
            }
        } label: {
            if store.isCareSpaceMutating {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Text("Create care space")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
        }
        .buttonStyle(OnePrimaryButtonStyle())
        .frame(maxWidth: .infinity)
        .disabled(trimmedName.isEmpty || store.isCareSpaceMutating)
        .accessibilityIdentifier("care-space-create")
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(OneTheme.canvas.ignoresSafeArea(edges: .horizontal))
    }
}

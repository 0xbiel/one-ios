import SwiftUI
import UIKit

struct EventsView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text("Events · \(store.selectedSubjectName)")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .tracking(-1)
                    if store.events.isEmpty {
                        SurfaceCard(radius: 24) {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No observations yet").font(.headline)
                                }
                            } icon: {
                                Image(systemName: "tray").font(.title2).foregroundStyle(OneTheme.accentBlue)
                            }
                            .padding(18)
                        }
                    } else {
                        ForEach(store.events) { event in
                            NavigationLink { EventDetailView(event: event, apiClient: store.apiClient, homeID: store.session?.homeID) } label: { EventRow(event: event) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(OneTheme.canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 88) }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct EventRow: View { let event: ObservedEvent; private var accent: Color { event.kind == .fallSuspected ? .orange : OneTheme.accentBlue }; var body: some View { HStack(spacing: 14) { Image(systemName: event.kind.symbol).font(.title3).foregroundStyle(accent).frame(width: 40, height: 40).background(accent.opacity(0.12), in: Circle()); VStack(alignment: .leading, spacing: 4) { Text(event.kind.title).font(.headline); Text(event.explanation).font(.subheadline).foregroundStyle(OneTheme.secondaryInk); Text("\(event.location) · \(event.timestamp.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.tertiary) }; Spacer(); if event.kind == .fallSuspected { HStack(spacing: 6) { if event.snapshotPath != nil { Image(systemName: "photo").font(.caption2).foregroundStyle(.orange) }; Text("REVIEW").font(.caption2.weight(.bold)).foregroundStyle(.orange).padding(.horizontal, 8).padding(.vertical, 5).background(.orange.opacity(0.12), in: Capsule()) } } else { ConfidenceBadge(confidence: event.confidence) } }.padding(.vertical, 10).accessibilityElement(children: .combine).accessibilityLabel("\(event.kind.title), \(event.location), \(event.confidence.title) confidence\(event.kind == .fallSuspected ? ", needs review\(event.snapshotPath != nil ? ", snapshot available" : "")" : "")") } }

struct EventDetailView: View {
    let event: ObservedEvent
    let apiClient: any OneAPIClient
    let homeID: UUID?
    @State private var snapshotData: Data?
    @State private var snapshotLoading = false
    @State private var snapshotFailed = false

    init(event: ObservedEvent, apiClient: any OneAPIClient = MockOneAPIClient(), homeID: UUID? = nil) {
        self.event = event
        self.apiClient = apiClient
        self.homeID = homeID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(event.kind.title).font(.largeTitle.weight(.bold))
                EventRow(event: event)
                if event.snapshotPath != nil {
                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Snapshot captured with this signal", systemImage: "photo.on.rectangle")
                                .font(.headline)
                            if let snapshotData, let image = UIImage(data: snapshotData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .accessibilityLabel("Snapshot captured when this safety signal was recorded")
                            } else if snapshotLoading {
                                ProgressView("Loading encrypted snapshot…")
                                    .frame(maxWidth: .infinity, minHeight: 160)
                            } else if snapshotFailed {
                                Label("The event image is not available right now.", systemImage: "photo.badge.exclamationmark")
                                    .foregroundStyle(OneTheme.secondaryInk)
                            }
                        }
                        .padding(16)
                    }
                }
                if event.hasClip { SurfaceCard { Label("Local clip ready for review", systemImage: "play.circle.fill").font(.headline).padding(20) } }
                Text("This is an observational signal for human review, not a diagnosis.").font(.footnote).foregroundStyle(OneTheme.amber)
            }
            .padding(20)
        }
        .background(OneTheme.canvas.ignoresSafeArea())
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: event.id) { await loadSnapshot() }
    }

    private func loadSnapshot() async {
        guard event.snapshotPath != nil, let homeID else { return }
        snapshotLoading = true
        snapshotFailed = false
        do {
            snapshotData = try await apiClient.eventSnapshot(homeID: homeID, eventID: event.id)
        } catch {
            snapshotFailed = true
        }
        snapshotLoading = false
    }
}

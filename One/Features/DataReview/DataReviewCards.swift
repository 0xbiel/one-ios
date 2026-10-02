import SwiftUI
import Charts

struct DayStoryReviewCard: View {
    let review: DayStoryReviewModel
    var body: some View {
        SurfaceCard(radius: 28) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(review.recipientName)’s day").font(.title2.bold())
                    Spacer()
                    if review.synthetic { Text("Simulated data").font(.caption2).foregroundStyle(OneTheme.secondaryInk) }
                }
                Text(review.headline).font(.headline)
                Text(review.summary).font(.subheadline).foregroundStyle(OneTheme.secondaryInk).lineLimit(3)
                ForEach(review.attentionItems) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(item.title, systemImage: "eye").font(.subheadline.weight(.semibold))
                        Text(item.detail).font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                    }
                }
                Text(review.coverageLabel).font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(review.summary).font(.footnote)
                        Text(review.uncertainty).font(.footnote).foregroundStyle(OneTheme.secondaryInk)
                        ForEach(review.facts, id: \.self) { Text($0).font(.footnote) }
                        if !review.sources.isEmpty { Text("Based on recorded observations and check-ins in this time window.").font(.caption).foregroundStyle(OneTheme.secondaryInk) }
                    }.padding(.top, 6)
                }.font(.subheadline)
            }.padding(18)
        }
    }
}

struct ActivityReviewCard: View {
    let review: ActivityReviewModel?
    let error: String?
    var body: some View {
        SurfaceCard(radius: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Activity details").font(.headline)
                if let review {
                    Text(review.totalObservations == 0 ? "No observations to compare yet." : "\(review.totalObservations) observations available for \(review.recipientName).")
                        .font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(review.windowLabel).font(.caption)
                            Text(review.coverageLabel).font(.footnote)
                            Text("Comparison: \(review.trend)").font(.footnote)
                            if !review.days.isEmpty {
                                Chart(review.days) { day in
                                    BarMark(x: .value("Day", day.date), y: .value("Observations", day.count)).foregroundStyle(OneTheme.accentBlue)
                                }.chartXAxis(.hidden).frame(height: 100).accessibilityLabel("Daily observation counts")
                                DisclosureGroup("Daily counts") {
                                    ForEach(review.days) { day in HStack { Text(day.date); Spacer(); Text("\(day.count)") }.font(.caption) }
                                }
                            }
                            ForEach(review.limitations, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                            if review.synthetic { Label("Simulated data", systemImage: "info.circle").font(.caption) }
                            DisclosureGroup("Sources and times") {
                                ForEach(review.sources, id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity, alignment: .leading) }
                            }
                        }.padding(.top, 8)
                    }.font(.subheadline)
                } else {
                    Text(error ?? "Choose a person to review their activity. We need enough observations before making comparisons.").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(18)
        }
    }
}

struct CollectionReviewCard: View {
    let review: CollectionReviewModel?
    var body: some View {
        SurfaceCard(radius: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Camera status").font(.headline)
                if let review {
                    Text(review.status).font(.subheadline).foregroundStyle(OneTheme.secondaryInk)
                    DisclosureGroup("Details") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Checked \(review.evaluatedAt)").font(.caption).foregroundStyle(.secondary)
                            ForEach(review.blockers, id: \.self) { Text($0).font(.footnote) }
                            ForEach(review.cameras) { camera in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(camera.name) · \(camera.status)").font(.subheadline.weight(.semibold))
                                    Text("\(camera.placement) · \(camera.freshness)").font(.caption).foregroundStyle(.secondary)
                                    ForEach(camera.blockers, id: \.self) { Text($0).font(.caption) }
                                }
                            }
                            Text(review.retention).font(.caption).foregroundStyle(.secondary)
                        }.padding(.top, 8)
                    }.font(.subheadline)
                } else {
                    Text("Camera status is unknown. Pairing a camera does not mean it is collecting observations.").font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(18)
        }
    }
}

struct AssistantContextReviewSheet: View {
    let review: AssistantContextReviewModel?
    let error: String?
    let isLoading: Bool
    let question: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Your question") { Text(question) }
                if isLoading { ProgressView("Loading context…") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let review {
                    Section("Scope and time window") { Text(review.scope); Text(review.windowLabel) }
                    Section("Coverage limitations") { ForEach(review.missingCoverage, id: \.self) { Text($0) } }
                    Section("Observations and sources") {
                        if review.observations.isEmpty { Text("No observations in this window.") }
                        else { DisclosureGroup("\(review.observations.count) retained observation records") { ForEach(review.observations, id: \.self) { Text($0).font(.footnote) } } }
                    }
                    Section("Inferences") {
                        if review.inferences.isEmpty { Text("No supported inferences.") }
                        else { DisclosureGroup("\(review.inferences.count) retained event and summary records") { ForEach(review.inferences, id: \.self) { Text($0).font(.footnote) } } }
                    }
                    if !review.syntheticProvenance.isEmpty {
                        Section("Synthetic provenance") { ForEach(review.syntheticProvenance, id: \.self) { Text($0) } }
                    }
                    Section("Privacy boundary") { Text(review.privacyBoundary) }
                    Section { Button("Send reviewed question") { onConfirm(); dismiss() } }
                }
            }
            .navigationTitle("Review context")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } } }
        }
    }
}

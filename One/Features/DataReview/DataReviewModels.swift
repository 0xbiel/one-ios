import Foundation

struct ActivityReviewModel: Sendable {
    struct Day: Identifiable, Sendable {
        var id: String { date }
        let date: String
        let count: Int
    }
    let recipientName: String
    let windowLabel: String
    let days: [Day]
    let totalObservations: Int
    let trend: String
    let coverageLabel: String
    let limitations: [String]
    let sources: [String]
    let synthetic: Bool
}

struct CollectionReviewModel: Sendable {
    struct Camera: Identifiable, Sendable {
        let id: String
        let name: String
        let status: String
        let placement: String
        let freshness: String
        let blockers: [String]
    }
    let evaluatedAt: String
    let status: String
    let blockers: [String]
    let cameras: [Camera]
    let retention: String
}

struct AssistantContextReviewModel: Sendable {
    let scope: String
    let windowLabel: String
    let observations: [String]
    let inferences: [String]
    let missingCoverage: [String]
    let syntheticProvenance: [String]
    let privacyBoundary: String
}

struct DayStoryReviewModel: Sendable {
    struct AttentionItem: Identifiable, Sendable {
        let id: String
        let title: String
        let detail: String
    }
    let recipientName: String
    let headline: String
    let summary: String
    let attentionItems: [AttentionItem]
    let coverageLabel: String
    let uncertainty: String
    let facts: [String]
    let sources: [String]
    let synthetic: Bool
}

/// Only explicit, validated visibility data can color a floor as covered/uncovered.
/// Camera connection and person sightings do not establish whole-room coverage.
struct MapFloorCoverageModel: Sendable {
    enum State: Sendable { case covered, uncovered, unknown }
    let floorID: String
    let state: State
    let evaluatedAt: Date?
    let validatedGeometry: Bool
    let simulated: Bool

    func currentState(now: Date = Date()) -> State {
        guard validatedGeometry, let evaluatedAt else { return .unknown }
        let age = now.timeIntervalSince(evaluatedAt)
        guard age >= -5, age <= 15 else { return .unknown }
        return state
    }
}

import Foundation

/// Bounded metadata decoded without storing credentials, frames or biometric samples.
indirect enum DataReviewJSON: Codable, Sendable {
    case object([String: DataReviewJSON]), array([DataReviewJSON]), string(String), number(Double), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([DataReviewJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: DataReviewJSON].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    subscript(_ key: String) -> DataReviewJSON { if case .object(let value) = self { return value[key] ?? .null }; return .null }
    var strings: [String] { array.compactMap { if case .string(let value) = $0 { return value }; return nil } }
    var array: [DataReviewJSON] { if case .array(let value) = self { return value }; return [] }
    var string: String { if case .string(let value) = self { return value }; return "" }
    var int: Int { if case .number(let value) = self { return Int(exactly: value) ?? 0 }; return 0 }
    var bool: Bool { if case .bool(let value) = self { return value }; return false }
    var isObject: Bool { if case .object = self { return true }; return false }
}

extension OneAPIClient {
    func dayStory(homeID: UUID, recipientID: UUID, timezone: String) async throws -> DataReviewJSON { throw OneAPIError.server(status: 501, message: "Daily story is unavailable.") }
    func analyticsReview(homeID: UUID, recipientID: UUID?, timezone: String) async throws -> DataReviewJSON { throw OneAPIError.server(status: 501, message: "Analytics review is unavailable.") }
    func collectionReview(homeID: UUID) async throws -> DataReviewJSON { throw OneAPIError.server(status: 501, message: "Collection review is unavailable.") }
    func assistantContextReview(homeID: UUID, recipientID: UUID?, timezone: String, message: String) async throws -> DataReviewJSON { throw OneAPIError.server(status: 501, message: "Context review is unavailable.") }
    func exportHouseholdData(homeID: UUID) async throws -> Data { throw OneAPIError.server(status: 501, message: "Household export is unavailable.") }
    func deleteHouseholdData(homeID: UUID, confirmationHomeID: UUID) async throws { throw OneAPIError.server(status: 501, message: "Confirmed deletion is unavailable.") }
}

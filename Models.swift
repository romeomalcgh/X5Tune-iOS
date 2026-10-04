import Foundation

struct CharacteristicSnapshot: Codable, Identifiable {
    let id: String
    let uuid: String
    let properties: String
    var valueHex: String?
    var valueUTF8: String?
    var isNotifying: Bool
}
struct ServiceSnapshot: Codable, Identifiable {
    let id: String
    let uuid: String
    var characteristics: [CharacteristicSnapshot]
}
struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
}
struct PacketEvent: Identifiable, Codable {
    let id: UUID
    let date: Date
    let uuid: String
    let hex: String
    let text: String?
    let changedBytes: [Int]
}
struct ObservationMarker: Identifiable, Codable {
    let id: UUID
    let date: Date
    let label: String
}
struct PacketDiff: Identifiable, Codable {
    let id: UUID
    let date: Date
    let action: String
    let uuid: String
    let before: String
    let after: String
    let changedBytes: [Int]
}
struct PacketComparison: Identifiable, Codable {
    let id: UUID
    let date: Date
    let uuid: String
    let firstEventID: UUID
    let secondEventID: UUID
    let changedBytes: [Int]
    let firstHex: String
    let secondHex: String
}
struct PacketFieldStat: Identifiable, Codable {
    var id: String { "\(uuid):\(offset)" }
    let uuid: String
    let offset: Int
    let sampleCount: Int
    let distinctValues: Int
    let stabilityPercent: Double
    let minValue: UInt8
    let maxValue: UInt8
}
struct PacketFamilySummary: Identifiable, Codable {
    var id: String { "\(uuid):\(length):\(prefix)" }
    let uuid: String
    let length: Int
    let prefix: String
    let count: Int
    let firstSeen: Date
    let lastSeen: Date
}
struct PacketAnalysisSnapshot: Codable {
    let generatedAt: Date
    let familySummaries: [PacketFamilySummary]
    let fieldStats: [PacketFieldStat]
    let repeatedPackets: Int
    let variablePackets: Int
}
struct ResearchSession: Codable {
    let version: Int
    let savedAt: Date
    let deviceName: String
    let deviceIdentifier: String
    let boundary: String
    let services: [ServiceSnapshot]
    let markers: [ObservationMarker]
    let packetEvents: [PacketEvent]
    let diffs: [PacketDiff]
    let comparisons: [PacketComparison]
    let analysis: PacketAnalysisSnapshot
    let notes: [String]
}
enum ResearchConfidence: String, CaseIterable, Codable {
    case observed = "Observed"
    case correlated = "Correlated"
    case likely = "Likely"
    case confirmed = "Confirmed"
}
struct ResearchNote: Identifiable, Codable {
    let id: UUID
    var date: Date
    var title: String
    var body: String
    var confidence: ResearchConfidence
}
struct Experiment: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var startedAt: Date
    var endedAt: Date?
    var eventIDs: [UUID]
    var confidence: ResearchConfidence
}
struct NumericInterpretation: Identifiable {
    let id = UUID()
    let label: String
    let value: String
}
struct PacketInsight: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let confidence: ResearchConfidence
}
struct ChecksumCandidate: Identifiable {
    let id = UUID()
    let name: String
    let offset: Int
    let matchPercent: Double
}
struct SequenceCandidate: Identifiable {
    let id = UUID()
    let uuid: String
    let offset: Int
    let matchPercent: Double
}

struct SessionComparison: Identifiable {
    let id = UUID()
    let baselineCount: Int
    let currentCount: Int
    let sharedCount: Int
    let addedCount: Int
    let removedCount: Int
    let changedCount: Int
    let changedUUIDs: [String]
}

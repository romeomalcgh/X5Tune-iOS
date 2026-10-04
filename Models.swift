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
struct BLESnapshot: Codable {
    let createdAt: Date
    let peripheralName: String
    let peripheralIdentifier: String
    let services: [ServiceSnapshot]
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
struct GuidedStep: Identifiable {
    let id: Int
    let title: String
    let instruction: String
    let safety: String
    let marker: String
}
enum ResearchTestProfile: String, CaseIterable, Identifiable {
    case brake = "Brake telemetry", power = "Power-state telemetry", lights = "Lights telemetry", lock = "Lock-state telemetry", battery = "Battery telemetry", charging = "Charging-state telemetry", baseline = "Passive baseline"
    var id: String { rawValue }
    var instruction: String {
        switch self {
        case .brake: return "Stationary: observe before, during and after normal brake use."
        case .power: return "Stationary: observe the normal power control and wait for telemetry to settle."
        case .lights: return "Stationary: observe normal light controls."
        case .lock: return "Stationary: observe normal lock/unlock behavior only."
        case .battery: return "Observe battery telemetry without changing settings."
        case .charging: return "Observe normal charging-state telemetry only."
        case .baseline: return "Collect passive notifications for a stable baseline."
        }
    }
    var safety: String { "Read/notify only. Do not ride or bypass safety controls." }
}
enum ResearchScenario: String, CaseIterable, Identifiable {
    case zeroStart = "Zero-start", speedLimit = "Speed limit", acceleration = "Acceleration curve", region = "Region profile"
    var id: String { rawValue }
    var summary: String {
        switch self {
        case .zeroStart: return "Hypothetical representation only. No controller setting is read or changed."
        case .speedLimit: return "Hypothetical ceiling model only. No limit is modified."
        case .acceleration: return "Hypothetical acceleration model only."
        case .region: return "Hypothetical region/profile model only."
        }
    }
    var boundary: String { "SIMULATION ONLY — X5Tune exposes no BLE write operation." }
}
struct ResearchReport: Codable {
    let generatedAt: Date
    let deviceName: String
    let deviceIdentifier: String
    let boundary: String
    let services: [ServiceSnapshot]
    let markers: [ObservationMarker]
    let packetEvents: [PacketEvent]
    let diffs: [PacketDiff]
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
struct ReplayFrame: Identifiable {
    let id: UUID
    let event: PacketEvent
    let index: Int
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

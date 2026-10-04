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
    case brake = "Brake telemetry"
    case power = "Power-state telemetry"
    case lights = "Lights telemetry"
    case lock = "Lock-state telemetry"
    case battery = "Battery telemetry"
    case charging = "Charging-state telemetry"
    case baseline = "Passive baseline"

    var id: String { rawValue }

    var instruction: String {
        switch self {
        case .brake: return "Stationary: observe the scooter before, during, and after normal brake-lever use."
        case .power: return "Stationary: observe the normal power button and wait for telemetry to settle."
        case .lights: return "Stationary: observe normal light controls without riding."
        case .lock: return "Stationary: observe only the scooter's normal lock/unlock behavior."
        case .battery: return "Observe battery telemetry without changing scooter settings."
        case .charging: return "With the scooter stationary, observe normal charging-state telemetry only."
        case .baseline: return "Collect passive notifications for a stable baseline before another test."
        }
    }

    var safety: String {
        switch self {
        case .brake: return "Do not ride or accelerate."
        case .power: return "Do not enter reset, update, or pairing flows."
        case .lights: return "Keep the scooter stationary."
        case .lock: return "Do not attempt to bypass the lock."
        case .battery: return "Read-only observation."
        case .charging: return "Use only the normal charger and normal charging procedure."
        case .baseline: return "No controls need to be touched."
        }
    }
}

enum ResearchScenario: String, CaseIterable, Identifiable {
    case zeroStart = "Zero-start"
    case speedLimit = "Speed limit"
    case acceleration = "Acceleration curve"
    case region = "Region profile"

    var id: String { rawValue }

    var summary: String {
        switch self {
        case .zeroStart: return "Hypothetical study of how a controller might distinguish a stationary throttle command from a moving-start condition."
        case .speedLimit: return "Hypothetical study of a configured speed ceiling. No controller value is read, changed, or bypassed."
        case .acceleration: return "Hypothetical study of how an acceleration curve could be represented by a controller."
        case .region: return "Hypothetical study of region/profile-dependent configuration without changing the scooter."
        }
    }

    var boundary: String {
        "SIMULATION ONLY — X5Tune exposes no BLE write operation and cannot enable, remove, raise, or bypass this setting."
    }
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

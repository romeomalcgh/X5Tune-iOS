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
struct GuidedStep: Identifiable {
    let id: Int
    let title: String
    let instruction: String
    let safety: String
}
enum ResearchScenario: String, CaseIterable, Identifiable {
    case zeroStart = "Zero-start behavior"
    case speedLimit = "Speed-limit behavior"
    case telemetry = "Telemetry mapping"
    var id: String { rawValue }
    var summary: String {
        switch self {
        case .zeroStart: return "Theoretical study of whether a controller distinguishes a stationary throttle command from a moving-start condition."
        case .speedLimit: return "Theoretical study of how a controller could represent a configured speed ceiling. No value is changed."
        case .telemetry: return "Map notification traffic to physical state changes without sending commands."
        }
    }
    var boundary: String {
        switch self {
        case .zeroStart: return "Simulation/research only. X5Tune sends no command and cannot enable zero-start."
        case .speedLimit: return "Simulation/research only. X5Tune does not remove, raise, or write a speed limit."
        case .telemetry: return "Read/notify only. Physical tests must remain stationary and controlled."
        }
    }
}

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

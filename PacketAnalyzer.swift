import Foundation

enum PacketAnalyzer {
    static func data(from hex: String) -> Data? {
        var bytes: [UInt8] = []
        for token in hex.split(separator: " ") { guard let b = UInt8(token, radix: 16) else { return nil }; bytes.append(b) }
        return Data(bytes)
    }

    static func changed(_ a: Data, _ b: Data) -> [Int] {
        let count = max(a.count, b.count)
        return (0..<count).filter { i in
            let av: UInt8? = i < a.count ? a[i] : nil
            let bv: UInt8? = i < b.count ? b[i] : nil
            return av != bv
        }
    }
}

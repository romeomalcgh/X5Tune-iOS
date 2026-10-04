import Foundation

enum PacketAnalyzer {
    static func data(from hex: String) -> Data? {
        let tokens = hex.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        guard !tokens.isEmpty else { return Data() }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(tokens.count)
        for token in tokens {
            guard token.count <= 2, let b = UInt8(token, radix: 16) else { return nil }
            bytes.append(b)
        }
        return Data(bytes)
    }
    static func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
    static func changed(_ a: Data, _ b: Data) -> [Int] {
        let count = max(a.count, b.count)
        return (0..<count).filter { i in
            let av: UInt8? = i < a.count ? a[i] : nil
            let bv: UInt8? = i < b.count ? b[i] : nil
            return av != bv
        }
    }
    static func interpretations(_ data: Data) -> [NumericInterpretation] {
        var out: [NumericInterpretation] = []
        let bytes = Array(data)
        for width in [1,2,4] where bytes.count >= width {
            let slice = Array(bytes.prefix(width))
            func le() -> UInt64 { slice.enumerated().reduce(0) { $0 | (UInt64($1.element) << UInt64(8*$1.offset)) } }
            func be() -> UInt64 { slice.reduce(0) { ($0 << 8) | UInt64($1) } }
            out.append(NumericInterpretation(label: "UInt\(width*8) LE", value: String(le())))
            out.append(NumericInterpretation(label: "UInt\(width*8) BE", value: String(be())))
            if width > 1 {
                let signBit = UInt64(1) << UInt64(width * 8 - 1)
                let leValue = le()
                let beValue = be()
                let leSigned = Int64(bitPattern: (leValue & signBit) != 0 ? leValue | (UInt64.max << UInt64(width * 8)) : leValue)
                let beSigned = Int64(bitPattern: (beValue & signBit) != 0 ? beValue | (UInt64.max << UInt64(width * 8)) : beValue)
                out.append(NumericInterpretation(label: "Int\(width*8) LE", value: String(leSigned)))
                out.append(NumericInterpretation(label: "Int\(width*8) BE", value: String(beSigned)))
            }
        }
        if bytes.count >= 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            out.append(NumericInterpretation(label: "Float32 LE", value: String(Float(bitPattern: bits))))
        }
        return out
    }
    static func bitRows(_ byte: UInt8) -> [(Int,Bool)] { (0..<8).map { ($0, byte & (1 << $0) != 0) } }
    static func checksumCandidates(_ events: [PacketEvent]) -> [ChecksumCandidate] {
        var out: [ChecksumCandidate] = []
        let grouped = Dictionary(grouping: events.compactMap { e -> (PacketEvent,Data)? in guard let d=data(from:e.hex),d.count>1 else{return nil}; return (e,d) }, by: { $0.1.count })
        for (_, group) in grouped {
            guard group.count >= 5 else { continue }
            let width = group[0].1.count
            for offset in max(0,width-2)..<width {
                var sumMatches=0
                for (_,d) in group {
                    let sum = d.dropLast(width-offset).reduce(0) { ($0 + UInt16($1)) & 0xFF }
                    if Int(sum) == Int(d[offset]) { sumMatches += 1 }
                }
                let pct=Double(sumMatches)/Double(group.count)*100
                if pct >= 60 { out.append(ChecksumCandidate(name:"8-bit sum candidate",offset:offset,matchPercent:pct)) }
            }
        }
        return out.sorted { $0.matchPercent > $1.matchPercent }
    }
    static func sequenceCandidates(_ events: [PacketEvent]) -> [SequenceCandidate] {
        var result:[SequenceCandidate]=[]
        for uuid in Set(events.map(\.uuid)) {
            let es=events.filter{$0.uuid==uuid}.sorted{$0.date<$1.date}
            guard es.count >= 5 else { continue }
            let ds=es.compactMap{data(from:$0.hex)}
            guard ds.count == es.count else { continue }
            let width = ds.map(\.count).min() ?? 0
            for offset in 0..<width {
                var hits=0, total=0
                for i in 1..<ds.count {
                    let expected = (Int(ds[i-1][offset]) + 1) & 255
                    if Int(ds[i][offset]) == expected { hits += 1 }
                    total += 1
                }
                if total > 0 && Double(hits)/Double(total) >= 0.7 {
                    result.append(SequenceCandidate(uuid:uuid,offset:offset,matchPercent:Double(hits)/Double(total)*100))
                }
            }
        }
        return result.sorted{$0.matchPercent>$1.matchPercent}
    }
    static func insights(events:[PacketEvent], fields:[PacketFieldStat], families:[PacketFamilySummary]) -> [PacketInsight] {
        var out:[PacketInsight]=[]
        if !families.isEmpty { out.append(PacketInsight(title:"Packet families",detail:"Detected \(families.count) characteristic/length/prefix families.",confidence:.observed)) }
        let variable=fields.filter{$0.stabilityPercent < 70}
        if !variable.isEmpty { out.append(PacketInsight(title:"Variable regions",detail:"\(variable.count) byte offsets show substantial variation.",confidence:.observed)) }
        let stable=fields.filter{$0.sampleCount >= 5 && $0.stabilityPercent >= 95}
        if !stable.isEmpty { out.append(PacketInsight(title:"Stable fields",detail:"\(stable.count) offsets are ≥95% stable across their characteristic samples.",confidence:.observed)) }
        return out
    }
}

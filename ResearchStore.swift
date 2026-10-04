import Foundation
import SwiftUI

@MainActor
final class ResearchStore: ObservableObject {
    @Published var experiments: [Experiment] = []
    @Published var notes: [ResearchNote] = []
    @Published var baselineEvents: [PacketEvent] = []
    @Published var lastComparison: SessionComparison?

    private let experimentsKey = "X5Tune.Experiments.v1"
    private let notesKey = "X5Tune.Notes.v1"
    private let baselineKey = "X5Tune.SessionBaseline.v1"

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = UserDefaults.standard.data(forKey: experimentsKey),
           let value = try? decoder.decode([Experiment].self, from: data) { experiments = value }
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let value = try? decoder.decode([ResearchNote].self, from: data) { notes = value }
        if let data = UserDefaults.standard.data(forKey: baselineKey),
           let value = try? decoder.decode([PacketEvent].self, from: data) { baselineEvents = value }
    }

    func start(name: String, description: String, eventIDs: [UUID]) {
        experiments.insert(
            Experiment(id: UUID(), name: name, description: description, startedAt: Date(),
                       endedAt: nil, eventIDs: eventIDs, confidence: .observed), at: 0)
        save()
    }

    func finish(_ id: UUID) {
        guard let index = experiments.firstIndex(where: { $0.id == id }) else { return }
        experiments[index].endedAt = Date()
        save()
    }

    func addNote(title: String, body: String, confidence: ResearchConfidence) {
        notes.insert(ResearchNote(id: UUID(), date: Date(), title: title, body: body, confidence: confidence), at: 0)
        save()
    }

    func saveBaseline(events: [PacketEvent]) {
        baselineEvents = events
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) { UserDefaults.standard.set(data, forKey: baselineKey) }
    }

    func compareCurrent(_ current: [PacketEvent]) {
        let baselineMap = Dictionary(grouping: baselineEvents, by: { "\($0.uuid)|\($0.hex)" })
        let currentMap = Dictionary(grouping: current, by: { "\($0.uuid)|\($0.hex)" })
        let baselineUUIDs = Set(baselineEvents.map(\.uuid))
        let currentUUIDs = Set(current.map(\.uuid))
        let shared = baselineEvents.filter { baselineUUIDs.contains($0.uuid) && currentUUIDs.contains($0.uuid) }
        let changedUUIDs = Set(current.compactMap { event in
            guard let old = baselineEvents.first(where: { $0.uuid == event.uuid }) else { return nil }
            guard let a = PacketAnalyzer.data(from: old.hex), let b = PacketAnalyzer.data(from: event.hex) else { return nil }
            return PacketAnalyzer.changed(a, b).isEmpty ? nil : event.uuid
        }).sorted()
        lastComparison = SessionComparison(
            baselineCount: baselineEvents.count,
            currentCount: current.count,
            sharedCount: shared.count,
            addedCount: max(0, currentMap.count - baselineMap.count),
            removedCount: max(0, baselineMap.count - currentMap.count),
            changedCount: changedUUIDs.count,
            changedUUIDs: changedUUIDs
        )
    }

    private func save() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(experiments) { UserDefaults.standard.set(data, forKey: experimentsKey) }
        if let data = try? encoder.encode(notes) { UserDefaults.standard.set(data, forKey: notesKey) }
    }
}

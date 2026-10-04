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
        let baselineByUUID = Dictionary(grouping: baselineEvents, by: \.uuid)
        let currentByUUID = Dictionary(grouping: current, by: \.uuid)

        let baselineUUIDs = Set(baselineByUUID.keys)
        let currentUUIDs = Set(currentByUUID.keys)
        let sharedUUIDs = baselineUUIDs.intersection(currentUUIDs)

        let changedUUIDs = sharedUUIDs.filter { uuid in
            let baselinePayloads = Set(baselineByUUID[uuid, default: []].map(\.hex))
            let currentPayloads = Set(currentByUUID[uuid, default: []].map(\.hex))
            return baselinePayloads != currentPayloads
        }.sorted()

        lastComparison = SessionComparison(
            baselineCount: baselineEvents.count,
            currentCount: current.count,
            sharedCount: sharedUUIDs.count,
            addedCount: currentUUIDs.subtracting(baselineUUIDs).count,
            removedCount: baselineUUIDs.subtracting(currentUUIDs).count,
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

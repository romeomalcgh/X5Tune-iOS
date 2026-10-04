import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @StateObject private var store = ResearchStore()
    @State private var tab = 0
    @State private var selectedEvent: PacketEvent?
    @State private var showPalette = false
    @State private var showExperiment = false
    @State private var experimentName = ""
    @State private var experimentDescription = ""
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var replayIndex = 0

    private let bg = Color(red: 0.039, green: 0.039, blue: 0.047)
    private let panel = Color(red: 0.075, green: 0.075, blue: 0.09)
    private let accent = Color.blue

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            TabView(selection: $tab) {
                NavigationStack { dashboard }.tabItem { Label("Home", systemImage: "bolt.fill") }.tag(0)
                NavigationStack { monitor }.tabItem { Label("Monitor", systemImage: "waveform.path.ecg") }.tag(1)
                NavigationStack { sessions }.tabItem { Label("Sessions", systemImage: "clock.arrow.circlepath") }.tag(2)
                NavigationStack { analysis }.tabItem { Label("Analysis", systemImage: "chart.bar.xaxis") }.tag(3)
                NavigationStack { device }.tabItem { Label("Device", systemImage: "dot.radiowaves.left.and.right") }.tag(4)
            }
            .tint(accent)
            .toolbarBackground(bg, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .sheet(item: $selectedEvent) { PacketInspector(event: $0) }
            .sheet(isPresented: $showExperiment) { experimentSheet }
            .sheet(isPresented: $showShare) {
                if let shareURL { ShareSheet(activityItems: [shareURL]) }
            }
            if showPalette {
                CommandPalette(show: $showPalette, tab: $tab) {
                    ble.startObservation("Quick capture")
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            store.load()
            ble.analyzePackets()
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.fill").font(.title2).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("X5Tune").font(.headline)
                Text(ble.connectedPeripheral == nil ? "Not connected" : "Connected")
                    .font(.caption2)
                    .foregroundStyle(ble.connectedPeripheral == nil ? Color.secondary : Color.green)
            }
            Spacer()
            Text("READ ONLY").font(.caption2.bold()).foregroundStyle(.secondary)
            Button { showPalette = true } label: { Image(systemName: "command") }
        }
    }

    var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                VStack(alignment: .leading, spacing: 10) {
                    Text(ble.connectedPeripheral?.name ?? "Xiaomi Electric Scooter 5 Plus").font(.title2.bold())
                    Text(ble.connectedPeripheral?.identifier.uuidString ?? "Connect a scooter to begin research")
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Circle().fill(ble.bluetoothState == .poweredOn ? .green : .orange).frame(width: 8, height: 8)
                        Text(ble.bluetoothState == .poweredOn ? "Bluetooth ready" : "Bluetooth unavailable")
                        Spacer()
                    }
                    Divider()
                    HStack {
                        metric("Packets", "\(ble.packetEvents.count)")
                        metric("Families", "\(ble.packetFamilies.count)")
                        metric("Changed", "\(ble.packetComparisons.count)")
                    }
                }
                .padding(16).background(panel, in: RoundedRectangle(cornerRadius: 20))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick actions").font(.headline)
                    HStack {
                        action("Capture", "record.circle.fill") { ble.startObservation("Quick capture") }
                        action("Analyze", "sparkles") { ble.analyzePackets() }
                        action("Compare", "arrow.left.arrow.right") { ble.comparePackets() }
                    }
                    HStack {
                        action("Experiment", "flask") { showExperiment = true }
                        action("Export", "square.and.arrow.up") { exportSession() }
                        action("Scan", "antenna.radiowaves.left.and.right") { ble.isScanning ? ble.stopScan() : ble.scan() }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Research").font(.headline)
                    infoRow("Characteristics", "\(ble.snapshots.flatMap { $0.characteristics }.count)")
                    infoRow("Saved", ble.sessionSavedAt?.formatted(date: .omitted, time: .shortened) ?? "Not yet")
                    if let active = ble.activeObservation { infoRow("Active", active) }
                    infoRow("Confidence", "Observational")
                }
                .padding(14).background(panel, in: RoundedRectangle(cornerRadius: 16))

                if !ble.packetEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent packets").font(.headline)
                        ForEach(Array(ble.packetEvents.prefix(5))) { event in
                            Button { selectedEvent = event } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(event.uuid).font(.caption.bold())
                                        Spacer()
                                        Text(event.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(event.hex).font(.system(.caption2, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
                                }
                                .padding(10).background(panel, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title3.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func infoRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) }
            .font(.subheadline)
    }

    func action(_ title: String, _ icon: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    var monitor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Characteristic", selection: $ble.monitorUUID) {
                    Text("All").tag("All")
                    ForEach(ble.observedUUIDs, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)

                TextField("Search characteristic, hex or text", text: $ble.monitorFilter)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("\(ble.filteredPacketEvents.count) packets").font(.caption)
                    Spacer()
                    Button("Clear") { ble.monitorFilter = "" }.font(.caption)
                }

                ForEach(Array(ble.filteredPacketEvents.prefix(200))) { event in
                    Button { selectedEvent = event } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(event.uuid).font(.caption.bold())
                                Spacer()
                                Text(event.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                            Text(event.hex).font(.system(.caption, design: .monospaced)).lineLimit(2)
                            if !event.changedBytes.isEmpty {
                                Text("Changed: \(event.changedBytes.map(String.init).joined(separator: ", "))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(12).background(panel, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle("Monitor")
        .navigationBarTitleDisplayMode(.inline)
    }

    var sessions: some View {
        List {
            Section("Current session") {
                Label("\(ble.packetEvents.count) captured packets", systemImage: "waveform")
                Label("\(ble.observationMarkers.count) timeline markers", systemImage: "timeline.selection")
                if let date = ble.sessionSavedAt {
                    Label("Saved \(date, style: .relative)", systemImage: "externaldrive")
                }
                Button("Re-analyze session") { ble.analyzePackets() }
                Button("Compare adjacent packets") { ble.comparePackets() }
                Button("Export .x5session JSON") { exportSession() }
                Button("Export CSV") { exportTextFile(name: "X5Tune-packets.csv", content: csvText()) }
                Button("Export HTML report") { exportTextFile(name: "X5Tune-report.html", content: htmlText()) }
                Button("Save as comparison baseline") { store.saveBaseline(events: ble.packetEvents) }
                Button("Compare with baseline") { store.compareCurrent(ble.packetEvents) }
                if let comparison = store.lastComparison {
                    Label("\(comparison.changedCount) changed characteristics", systemImage: "arrow.left.arrow.right")
                    Text("Baseline \(comparison.baselineCount) • Current \(comparison.currentCount) • Added \(comparison.addedCount) • Removed \(comparison.removedCount)")
                        .font(.caption2).foregroundStyle(.secondary)
                    if !comparison.changedUUIDs.isEmpty {
                        Text(comparison.changedUUIDs.joined(separator: ", "))
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
                Button("Clear current session", role: .destructive) { ble.clearResearchSession() }
            }

            Section("Timeline") {
                if ble.observationMarkers.isEmpty {
                    Text("No observation markers yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(ble.observationMarkers) { marker in
                        HStack {
                            Text(marker.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                            Text(marker.label).font(.caption)
                        }
                    }
                }
            }

            Section("Experiments") {
                if store.experiments.isEmpty {
                    Text("No experiments yet.").foregroundStyle(.secondary)
                }
                ForEach(store.experiments) { experiment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(experiment.name).font(.headline)
                            Spacer()
                            Text(experiment.confidence.rawValue).font(.caption2)
                        }
                        Text(experiment.description).font(.caption).foregroundStyle(.secondary)
                        Text("\(experiment.eventIDs.count) packets").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("New experiment") { showExperiment = true }
            }

            Section("Research notebook") {
                if store.notes.isEmpty {
                    Text("No notes yet.").foregroundStyle(.secondary)
                }
                ForEach(store.notes) { note in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(note.title).font(.headline)
                            Spacer()
                            Text(note.confidence.rawValue).font(.caption2)
                        }
                        Text(note.body).font(.caption)
                        Text(note.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("Add observation note") {
                    store.addNote(title: "Observation", body: "Add your observation here.", confidence: .observed)
                }
            }

            Section("Replay") {
                if ble.packetEvents.isEmpty {
                    Text("Capture packets to replay them.")
                } else {
                    let frames = Array(ble.packetEvents.reversed())
                    Slider(value: Binding(get: { Double(replayIndex) }, set: { replayIndex = Int($0) }),
                           in: 0...Double(max(0, frames.count - 1)), step: 1)
                    Text("Frame \(replayIndex + 1) / \(frames.count)")
                    if frames.indices.contains(replayIndex) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(frames[replayIndex].uuid).font(.caption.bold())
                            Text(frames[replayIndex].hex).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
    }

    var analysis: some View {
        List {
            Section("Overview") {
                Label("\(ble.packetFamilies.count) packet families", systemImage: "square.stack.3d.up")
                Label("\(ble.fieldStats.count) byte fields", systemImage: "rectangle.split.3x3")
                Label("\(PacketAnalyzer.checksumCandidates(ble.packetEvents).count) checksum candidates", systemImage: "checkmark.seal")
                Label("\(PacketAnalyzer.sequenceCandidates(ble.packetEvents).count) sequence candidates", systemImage: "arrow.triangle.2.circlepath")
            }

            Section("Packet families") {
                ForEach(ble.packetFamilies) { family in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(family.uuid).font(.caption.bold())
                            Spacer()
                            Text("\(family.count)x").font(.caption2)
                        }
                        Text("\(family.length) bytes • prefix \(family.prefix)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Field discovery") {
                ForEach(ble.fieldStats.filter { $0.sampleCount >= 3 }.prefix(80)) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("\(field.uuid) • byte \(field.offset)")
                            Spacer()
                            Text(String(format: "%.0f%% stable", field.stabilityPercent))
                        }
                        Text("\(field.distinctValues) distinct • range \(field.minValue)-\(field.maxValue)")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Numeric decoder") {
                if let event = ble.packetEvents.first, let data = PacketAnalyzer.data(from: event.hex) {
                    Text("Latest \(event.uuid)").font(.headline)
                    ForEach(PacketAnalyzer.interpretations(data).prefix(16)) { item in
                        infoRow(item.label, item.value)
                    }
                    Text("Bit flags: byte 0").font(.headline)
                    HStack {
                        ForEach(PacketAnalyzer.bitRows(data.first ?? 0), id: \.0) { bit in
                            VStack {
                                Text("\(bit.0)").font(.caption2)
                                Circle().fill(bit.1 ? accent : .gray).frame(width: 10, height: 10)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Text("Capture a packet to decode it.")
                }
            }

            Section("Checksums and sequence candidates") {
                ForEach(PacketAnalyzer.checksumCandidates(ble.packetEvents)) { candidate in
                    infoRow(candidate.name, "byte \(candidate.offset) • \(String(format: "%.1f", candidate.matchPercent))%")
                }
                ForEach(PacketAnalyzer.sequenceCandidates(ble.packetEvents)) { candidate in
                    infoRow("Possible sequence", "\(candidate.uuid) byte \(candidate.offset) • \(String(format: "%.1f", candidate.matchPercent))%")
                }
            }

            Section("Correlations and confidence") {
                ForEach(PacketAnalyzer.insights(events: ble.packetEvents, fields: ble.fieldStats, families: ble.packetFamilies)) { insight in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(insight.title).font(.headline)
                            Spacer()
                            Text(insight.confidence.rawValue).font(.caption2)
                        }
                        Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Observed → Correlated → Likely → Confirmed")
                    .font(.caption)
                Text("X5Tune does not promote a hypothesis to confirmed causality automatically.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Analysis")
        .navigationBarTitleDisplayMode(.inline)
    }

    var device: some View {
        List {
            Section("Connection") {
                HStack {
                    Circle().fill(ble.connectedPeripheral == nil ? .orange : .green).frame(width: 8, height: 8)
                    Text(ble.connectedPeripheral == nil ? "Disconnected" : "Connected")
                    Spacer()
                    Button(ble.isScanning ? "Stop" : "Scan") {
                        ble.isScanning ? ble.stopScan() : ble.scan()
                    }
                }
                if let peripheral = ble.connectedPeripheral {
                    Text(peripheral.name ?? "Unnamed")
                    Text(peripheral.identifier.uuidString).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Disconnect") { ble.disconnect() }
                }
            }

            Section("GATT") {
                ForEach(ble.snapshots) { service in
                    DisclosureGroup(service.uuid) {
                        ForEach(service.characteristics) { characteristic in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(characteristic.uuid).font(.system(.subheadline, design: .monospaced))
                                    Spacer()
                                    Text(characteristic.isNotifying ? "ON" : "OFF")
                                        .font(.caption2)
                                        .foregroundStyle(characteristic.isNotifying ? .green : .secondary)
                                }
                                Text(characteristic.properties).font(.caption2).foregroundStyle(.secondary)
                                HStack {
                                    if characteristic.properties.contains("NOTIFY") || characteristic.properties.contains("INDICATE") {
                                        Button(characteristic.isNotifying ? "Unsubscribe" : "Subscribe") {
                                            ble.setNotify(!characteristic.isNotifying, for: characteristic.uuid)
                                        }
                                    }
                                    if characteristic.properties.contains("READ") {
                                        Button("Read") { ble.read(characteristic.uuid) }
                                    }
                                }
                                .buttonStyle(.bordered)
                                if let value = characteristic.valueHex {
                                    Text(value).font(.system(.caption2, design: .monospaced)).lineLimit(4).textSelection(.enabled)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            Section("Safety boundary") {
                Text("READ / NOTIFY ONLY").font(.headline)
                Text("X5Tune does not expose BLE writes, firmware updates, controller parameter writes, speed-limit changes, region changes, reset/write flows, or bypass controls.")
            }

            Section("Raw log") {
                ForEach(ble.log.prefix(50)) { entry in
                    Text("\(entry.date, style: .time)  \(entry.message)")
                        .font(.caption2)
                }
            }
        }
        .navigationTitle("Device")
        .navigationBarTitleDisplayMode(.inline)
    }

    var experimentSheet: some View {
        NavigationStack {
            Form {
                Section("Experiment") {
                    TextField("Name", text: $experimentName)
                    TextField("What are you testing?", text: $experimentDescription, axis: .vertical)
                }
                Section {
                    Button("Start passive experiment") {
                        let name = experimentName.isEmpty ? "Experiment" : experimentName
                        store.start(name: name, description: experimentDescription, eventIDs: ble.packetEvents.map { $0.id })
                        ble.startObservation(name)
                        showExperiment = false
                        experimentName = ""
                        experimentDescription = ""
                    }
                    .disabled(ble.connectedPeripheral == nil)
                } footer: {
                    Text("No BLE writes are sent.")
                }
            }
            .navigationTitle("New experiment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showExperiment = false }
                }
            }
        }
    }

    func csvText() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["timestamp,characteristic,length,hex,changed_offsets"]
        for event in ble.packetEvents.reversed() {
            let length = PacketAnalyzer.data(from: event.hex)?.count ?? 0
            let changes = event.changedBytes.map(String.init).joined(separator: "|")
            lines.append("\(formatter.string(from: event.date)),\(event.uuid),\(length),\(event.hex),\(changes)")
        }
        return lines.joined(separator: "\n")
    }

    func htmlText() -> String {
        let rows = ble.packetEvents.reversed().prefix(500).map {
            "<tr><td>\($0.date)</td><td>\($0.uuid)</td><td><code>\($0.hex)</code></td><td>\($0.changedBytes.map(String.init).joined(separator: ", "))</td></tr>"
        }.joined()
        return "<!doctype html><html><head><meta name=\"viewport\" content=\"width=device-width\"><title>X5Tune Research Report</title><style>body{background:#0a0a0c;color:#fff;font:15px -apple-system,sans-serif;padding:24px}table{width:100%;border-collapse:collapse}td,th{padding:8px;border-bottom:1px solid #292930;text-align:left}code{font-family:ui-monospace;color:#bfc3ff}</style></head><body><h1>X5Tune Research Report</h1><p>READ/NOTIFY ONLY. No BLE writes are exposed.</p><table><tr><th>Time</th><th>Characteristic</th><th>Hex</th><th>Changes</th></tr>\(rows)</table></body></html>"
    }

    func exportTextFile(name: String, content: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try content.data(using: .utf8)?.write(to: url)
            shareURL = url
            showShare = true
        } catch {
            ble.addLog("Export failed: \(error.localizedDescription)")
        }
    }

    func exportSession() {
        do {
            shareURL = try ble.exportSessionURL()
            showShare = true
        } catch {
            ble.addLog("Export failed: \(error.localizedDescription)")
        }
    }
}

struct PacketInspector: View {
    let event: PacketEvent

    var body: some View {
        NavigationStack {
            List {
                Section("Packet") {
                    Text(event.uuid).font(.headline)
                    Text(event.date, style: .date)
                    Text(event.date, style: .time)
                }
                Section("Raw hex") {
                    Text(event.hex)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                }
                if let data = PacketAnalyzer.data(from: event.hex) {
                    Section("Byte view") {
                        ForEach(Array(data.enumerated()), id: \.offset) { index, byte in
                            HStack {
                                Text(String(format: "%02d", index)).foregroundStyle(.secondary).frame(width: 28)
                                Text(String(format: "%02X", byte)).font(.system(.body, design: .monospaced))
                                Spacer()
                                Text("\(byte)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Numeric interpretations") {
                        ForEach(PacketAnalyzer.interpretations(data).prefix(20)) { item in
                            Text("\(item.label)  \(item.value)")
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
                if !event.changedBytes.isEmpty {
                    Section("Changed offsets") {
                        Text(event.changedBytes.map(String.init).joined(separator: ", "))
                    }
                }
            }
            .navigationTitle("Packet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CommandPalette: View {
    @Binding var show: Bool
    @Binding var tab: Int
    let startCapture: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quick actions").font(.headline)
                    Spacer()
                    Button("Close") { show = false }
                }
                paletteButton("Dashboard") { tab = 0 }
                paletteButton("Live monitor") { tab = 1 }
                paletteButton("Sessions") { tab = 2 }
                paletteButton("Analysis") { tab = 3 }
                paletteButton("Device") { tab = 4 }
                paletteButton("Start capture") { startCapture(); tab = 1 }
            }
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
        .padding(14)
        .background(Color.black.opacity(0.45))
    }

    func paletteButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            show = false
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

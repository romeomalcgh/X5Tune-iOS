import SwiftUI
import CoreBluetooth
import UIKit

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var guideStep = 0
    @State private var guideRunning = false
    @State private var copied = false
    @State private var selectedScenario: ResearchScenario = .zeroStart
    @State private var selectedProfile: ResearchTestProfile = .brake
    @State private var theoreticalValue: Double = 25

    private let guide: [GuidedStep] = [
        GuidedStep(id: 0, title: "Connected", instruction: "Keep the scooter stationary. Confirm the BLE connection and GATT map are visible.", safety: "Read/notify only.", marker: "Connection confirmed"),
        GuidedStep(id: 1, title: "Start brake observation", instruction: "Tap Next to start the baseline capture, then squeeze and hold the brake normally for a few seconds.", safety: "Do not ride or accelerate.", marker: "Brake observation started"),
        GuidedStep(id: 2, title: "Release brake", instruction: "Release the brake and wait a few seconds. Then tap Next so X5Tune records the observation boundary.", safety: "Keep the scooter stationary.", marker: "Brake observation ended"),
        GuidedStep(id: 3, title: "Passive settling", instruction: "Wait without touching the controls. Tap Next after telemetry has settled.", safety: "No BLE commands are sent.", marker: "Passive settling complete"),
        GuidedStep(id: 4, title: "Finish", instruction: "Review the packet timeline/diffs, then copy the research report and send it back for analysis.", safety: "The report is observational, not proof of causality.", marker: "Guided test finished")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle().fill(ble.bluetoothState == .poweredOn ? .green : .orange).frame(width: 9, height: 9)
                        Text(stateText)
                        Spacer()
                        Text("READ ONLY").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }

                Section("Guided research") {
                    if guideRunning {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Step \(guideStep + 1) of \(guide.count)").font(.caption).foregroundStyle(.secondary)
                            Text(guide[guideStep].title).font(.headline)
                            Text(guide[guideStep].instruction)
                            Text(guide[guideStep].safety).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                if guideStep > 0 {
                                    Button("Back") { guideStep -= 1 }.buttonStyle(.bordered)
                                }
                                Spacer()
                                Button(guideStep == 0 ? "Start observation" : (guideStep == guide.count - 1 ? "Finish" : "Next")) {
                                    let step = guide[guideStep]
                                    if guideStep == 0 {
                                        ble.addLog("Guide: \(step.marker)")
                                        guideStep += 1
                                    } else if guideStep == 1 {
                                        ble.startObservation("Brake press")
                                        ble.addLog("Guide: \(step.marker)")
                                        guideStep += 1
                                    } else if guideStep == 2 {
                                        ble.finishObservation("Brake press")
                                        ble.addLog("Guide: \(step.marker)")
                                        guideStep += 1
                                    } else if guideStep == 3 {
                                        ble.addLog("Guide: \(step.marker)")
                                        guideStep += 1
                                    } else {
                                        ble.addLog("Guide: \(step.marker)")
                                        guideRunning = false
                                    }
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        Text("A step-by-step workflow records action boundaries and correlates received packets against a baseline.")
                        Button("Start guided test") {
                            guideStep = 0
                            guideRunning = true
                            ble.addLog("Guided research started")
                        }.buttonStyle(.borderedProminent)
                    }
                }

                Section("Test profiles") {
                    Picker("Profile", selection: $selectedProfile) {
                        ForEach(ResearchTestProfile.allCases) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    Text(selectedProfile.instruction)
                    Text(selectedProfile.safety).font(.caption).foregroundStyle(.secondary)
                    Button("Start \(selectedProfile.rawValue)") {
                        ble.startObservation(selectedProfile.rawValue)
                    }.buttonStyle(.bordered)
                    if ble.activeObservation != nil {
                        Button("Finish current observation") {
                            ble.finishObservation()
                        }.buttonStyle(.bordered)
                    }
                }

                Section("Theoretical research lab") {
                    Picker("Scenario", selection: $selectedScenario) {
                        ForEach(ResearchScenario.allCases) { scenario in
                            Text(scenario.rawValue).tag(scenario)
                        }
                    }
                    Text(selectedScenario.summary)
                    Slider(value: $theoreticalValue, in: 0...100, step: 1)
                    Text("Hypothetical parameter: \(Int(theoreticalValue)) — simulation display only")
                        .font(.caption)
                    Text(selectedScenario.boundary).font(.caption).foregroundStyle(.secondary)
                    Text("No BLE write exists in this app. These controls cannot alter scooter firmware, controller parameters, speed limits, start behavior, region settings, or safety limits.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Packet analysis") {
                    HStack {
                        Text("Events")
                        Spacer()
                        Text("\(ble.packetEvents.count)")
                    }
                    HStack {
                        Text("Observed diffs")
                        Spacer()
                        Text("\(ble.packetDiffs.count)")
                    }
                    if let active = ble.activeObservation {
                        Text("Active: \(active)").font(.caption).foregroundStyle(.secondary)
                    }
                    if !ble.packetDiffs.isEmpty {
                        ForEach(Array(ble.packetDiffs.prefix(12))) { diff in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(diff.action) • \(diff.uuid)").font(.caption.bold())
                                Text("Bytes changed: \(diff.changedBytes.map(String.init).joined(separator: ", "))").font(.caption2)
                                Text("\(diff.before) → \(diff.after)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        Text("No packet differences recorded yet. Start an observation and perform one safe action.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Research timeline") {
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

                Section("Protocol knowledge base") {
                    if ble.snapshots.isEmpty {
                        Text("Connect to populate the observed characteristic map.").foregroundStyle(.secondary)
                    } else {
                        ForEach(ble.snapshots) { service in
                            DisclosureGroup(service.uuid) {
                                ForEach(service.characteristics) { c in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(c.uuid).font(.system(.body, design: .monospaced))
                                        Text(c.properties).font(.caption).foregroundStyle(.secondary)
                                        Text(knowledgeNote(for: c))
                                            .font(.caption)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }

                Section("Scanner") {
                    HStack {
                        Button(ble.isScanning ? "Stop" : "Scan") {
                            ble.isScanning ? ble.stopScan() : ble.scan()
                        }.buttonStyle(.borderedProminent)
                        Spacer()
                        Text("\(ble.peripherals.count) found").foregroundStyle(.secondary)
                    }
                    ForEach(ble.peripherals, id: \.identifier) { p in
                        Button {
                            ble.connect(p)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(p.name ?? "Unnamed peripheral")
                                Text(p.identifier.uuidString).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Connection") {
                    if let p = ble.connectedPeripheral {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(p.name ?? "Unnamed")
                                Text(p.identifier.uuidString).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Disconnect") { ble.disconnect() }.buttonStyle(.bordered)
                        }
                    } else {
                        Text("No device connected").foregroundStyle(.secondary)
                    }
                }

                Section("GATT map") {
                    if ble.snapshots.isEmpty {
                        Text("Connect to enumerate services and characteristics.").foregroundStyle(.secondary)
                    } else {
                        ForEach(ble.snapshots) { service in
                            DisclosureGroup(service.uuid) {
                                ForEach(service.characteristics) { c in
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack {
                                            Text(c.uuid).font(.system(.body, design: .monospaced))
                                            Spacer()
                                            Text(c.isNotifying ? "NOTIFY ON" : "NOTIFY OFF")
                                                .font(.caption2.bold())
                                                .foregroundStyle(c.isNotifying ? .green : .secondary)
                                        }
                                        Text(c.properties).font(.caption).foregroundStyle(.secondary)
                                        HStack(spacing: 8) {
                                            if c.properties.contains("NOTIFY") || c.properties.contains("INDICATE") {
                                                Button(c.isNotifying ? "Unsubscribe" : "Subscribe") {
                                                    ble.setNotify(!c.isNotifying, for: c.uuid)
                                                }.buttonStyle(.bordered)
                                            }
                                            if c.properties.contains("READ") {
                                                Button("Read") { ble.read(c.uuid) }.buttonStyle(.bordered)
                                            }
                                        }
                                        if let v = c.valueHex {
                                            Text(v).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                        }
                                        if let t = c.valueUTF8, !t.isEmpty {
                                            Text(t).font(.caption).textSelection(.enabled)
                                        }
                                    }.padding(.vertical, 5)
                                }
                            }
                        }
                    }
                }

                Section("Export / send results") {
                    Button(copied ? "Research report copied" : "Copy research report") {
                        UIPasteboard.general.string = ble.copyableReport()
                        copied = true
                        ble.addLog("Research report copied to clipboard")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                    Button("Create research report JSON") {
                        guard let report = ble.researchReport() else {
                            ble.addLog("Report export unavailable: no connected device")
                            return
                        }
                        do {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            let data = try encoder.encode(report)
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("X5Tune-Research-\(Int(Date().timeIntervalSince1970)).json")
                            try data.write(to: url)
                            shareURL = url
                            showShare = true
                        } catch {
                            ble.addLog("Report export failed: \(error.localizedDescription)")
                        }
                    }
                    Button("Create BLE snapshot") {
                        guard let snapshot = ble.exportSnapshot() else {
                            ble.addLog("Snapshot unavailable: no connected device")
                            return
                        }
                        do {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            let data = try encoder.encode(snapshot)
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("X5Tune-BLE-\(Int(Date().timeIntervalSince1970)).json")
                            try data.write(to: url)
                            shareURL = url
                            showShare = true
                        } catch {
                            ble.addLog("Export failed: \(error.localizedDescription)")
                        }
                    }
                    Button("Clear research session", role: .destructive) {
                        ble.clearResearchSession()
                    }
                    Text("The research report is designed to be pasted directly into ChatGPT for packet analysis.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Raw log") {
                    if ble.log.isEmpty {
                        Text("No events yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(ble.log) { e in
                            VStack(alignment: .leading) {
                                Text(e.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                                Text(e.message).font(.caption.monospaced())
                            }
                        }
                    }
                }
            }
            .navigationTitle("X5Tune")
            .sheet(isPresented: $showShare) {
                if let shareURL { ShareSheet(items: [shareURL]) }
            }
        }
    }

    private func knowledgeNote(for c: CharacteristicSnapshot) -> String {
        switch c.uuid {
        case "0004": return "Observed: READ returned APP firmware string 2.7.0_0039 in prior testing. Role is strongly associated with firmware-version reporting."
        case "0005": return "Observed: NOTIFY-capable. No payload meaning assigned yet; correlate with guided tests."
        default: return "Observed GATT property only. Purpose is currently unknown; do not infer a command meaning from the UUID alone."
        }
    }

    private var stateText: String {
        switch ble.bluetoothState {
        case .poweredOn: return "Bluetooth ready"
        case .poweredOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied"
        case .unsupported: return "Bluetooth unsupported"
        case .resetting: return "Bluetooth resetting"
        default: return "Bluetooth starting"
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

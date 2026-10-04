import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var shareURL: URL?
    @State private var showShare=false
    @State private var guideStep=0
    @State private var guideRunning=false
    @State private var selectedScenario: ResearchScenario = .zeroStart
    @State private var copied=false

    private let guide:[GuidedStep] = [
        GuidedStep(id:0,title:"Connected",instruction:"Keep the scooter stationary. Do not touch the throttle. Continue only after the BLE connection and GATT map are visible.",safety:"Research is read-only."),
        GuidedStep(id:1,title:"Press the brake",instruction:"Squeeze and hold the brake lever normally for a few seconds. Keep the scooter stationary.",safety:"Do not ride or accelerate during the test."),
        GuidedStep(id:2,title:"Release the brake",instruction:"Release the brake and wait a few seconds. Then continue.",safety:"Keep the scooter stationary."),
        GuidedStep(id:3,title:"Optional power-state observation",instruction:"If you want a second observation, use only the normal power button. Do not enter a firmware/update/reset flow.",safety:"Stop if the scooter behaves unexpectedly."),
        GuidedStep(id:4,title:"Finish",instruction:"Copy the log and send it back for analysis. The log contains timestamps, GATT discoveries, notification state, and raw received bytes.",safety:"No BLE commands are sent by X5Tune.")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle().fill(ble.bluetoothState == .poweredOn ? .green : .orange).frame(width:9,height:9)
                        Text(stateText); Spacer()
                        Text("READ ONLY").font(.caption2.bold()).foregroundStyle(.secondary)
                    }
                }
                Section("Guided research") {
                    if guideRunning {
                        VStack(alignment:.leading,spacing:10) {
                            Text("Step \(guideStep+1) of \(guide.count)").font(.caption).foregroundStyle(.secondary)
                            Text(guide[guideStep].title).font(.headline)
                            Text(guide[guideStep].instruction)
                            Text(guide[guideStep].safety).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                if guideStep > 0 { Button("Back"){guideStep-=1}.buttonStyle(.bordered) }
                                Spacer()
                                Button(guideStep == guide.count-1 ? "Finish":"Next") {
                                    if guideStep < guide.count-1 {
                                        ble.addLog("Guide step completed: \(guide[guideStep].title)"); guideStep += 1
                                    } else {
                                        ble.addLog("Guided research finished"); guideRunning=false
                                    }
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        Text("A manual step-by-step workflow that records exactly when you performed each safe observation. X5Tune never automatically assumes a physical action happened.")
                        Button("Start guided test"){guideStep=0;guideRunning=true;ble.addLog("Guided research started")}.buttonStyle(.borderedProminent)
                    }
                }
                Section("Theoretical research lab") {
                    Picker("Scenario",selection:$selectedScenario) {
                        ForEach(ResearchScenario.allCases){ scenario in Text(scenario.rawValue).tag(scenario) }
                    }
                    Text(selectedScenario.summary)
                    Text(selectedScenario.boundary).font(.caption).foregroundStyle(.secondary)
                    Text("Model: X5Tune can document hypotheses and observed RX traffic, but it does not write controller parameters or attempt to bypass safety limits.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Scanner") {
                    HStack {
                        Button(ble.isScanning ? "Stop":"Scan"){ble.isScanning ? ble.stopScan() : ble.scan()}.buttonStyle(.borderedProminent)
                        Spacer(); Text("\(ble.peripherals.count) found").foregroundStyle(.secondary)
                    }
                    ForEach(ble.peripherals,id:\.identifier){p in
                        Button{ble.connect(p)}label:{VStack(alignment:.leading){Text(p.name ?? "Unnamed peripheral");Text(p.identifier.uuidString).font(.caption2).foregroundStyle(.secondary)}}
                    }
                }
                Section("Connection") {
                    if let p=ble.connectedPeripheral {
                        HStack { VStack(alignment:.leading){Text(p.name ?? "Unnamed");Text(p.identifier.uuidString).font(.caption2).foregroundStyle(.secondary)};Spacer();Button("Disconnect"){ble.disconnect()}.buttonStyle(.bordered) }
                    } else { Text("No device connected").foregroundStyle(.secondary) }
                }
                Section("GATT map") {
                    if ble.snapshots.isEmpty { Text("Connect to enumerate services and characteristics.").foregroundStyle(.secondary) }
                    else { ForEach(ble.snapshots){s in DisclosureGroup(s.uuid){ForEach(s.characteristics){c in
                        VStack(alignment:.leading,spacing:7) {
                            HStack { Text(c.uuid).font(.system(.body,design:.monospaced));Spacer();Text(c.isNotifying ? "NOTIFY ON":"NOTIFY OFF").font(.caption2.bold()).foregroundStyle(c.isNotifying ? .green:.secondary) }
                            Text(c.properties).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing:8) {
                                if c.properties.contains("NOTIFY") || c.properties.contains("INDICATE") { Button(c.isNotifying ? "Unsubscribe":"Subscribe"){ble.setNotify(!c.isNotifying,for:c.uuid)}.buttonStyle(.bordered) }
                                if c.properties.contains("READ") { Button("Read"){ble.read(c.uuid)}.buttonStyle(.bordered) }
                            }
                            if let v=c.valueHex { Text(v).font(.system(.caption,design:.monospaced)).textSelection(.enabled) }
                            if let t=c.valueUTF8,!t.isEmpty { Text(t).font(.caption).textSelection(.enabled) }
                        }.padding(.vertical,5)
                    }}}}
                }
                Section("Session export") {
                    Button(copied ? "Log copied":"Copy complete log") {
                        UIPasteboard.general.string=ble.copyableLog(); copied=true; ble.addLog("Complete log copied to clipboard")
                        DispatchQueue.main.asyncAfter(deadline:.now()+2){copied=false}
                    }
                    Button("Create BLE snapshot") {
                        if let s=ble.exportSnapshot(){do{
                            let e=JSONEncoder();e.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
                            let d=try e.encode(s);let u=FileManager.default.temporaryDirectory.appendingPathComponent("X5Tune-BLE-\(Int(Date().timeIntervalSince1970)).json")
                            try d.write(to:u);shareURL=u;showShare=true
                        }catch{ble.addLog("Export failed: \(error.localizedDescription)")}}
                    }
                    Text("Use the share sheet to save the snapshot to Files/iCloud or transfer it to another device. The log can be pasted directly into ChatGPT.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Log") {
                    if ble.log.isEmpty { Text("No events yet.").foregroundStyle(.secondary) }
                    else { ForEach(ble.log){e in VStack(alignment:.leading){Text(e.date,style:.time).font(.caption2).foregroundStyle(.secondary);Text(e.message).font(.caption.monospaced())}}
                    }
                }
            }
            .navigationTitle("X5Tune")
            .sheet(isPresented:$showShare){if let shareURL{ShareSheet(items:[shareURL])}}
        }
    }
    private var stateText:String {
        switch ble.bluetoothState { case .poweredOn:return "Bluetooth ready";case .poweredOff:return "Bluetooth is off";case .unauthorized:return "Bluetooth permission denied";case .unsupported:return "Bluetooth unsupported";case .resetting:return "Bluetooth resetting";default:return "Bluetooth starting" }
    }
}
struct ShareSheet:UIViewControllerRepresentable {
    let items:[Any]
    func makeUIViewController(context:Context)->UIActivityViewController { UIActivityViewController(activityItems:items,applicationActivities:nil) }
    func updateUIViewController(_ c:UIActivityViewController,context:Context){}
}

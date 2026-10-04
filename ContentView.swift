import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var shareURL: URL?
    @State private var showShare=false
    var body: some View {
        NavigationStack {
            List {
                Section { HStack { Circle().fill(ble.bluetoothState == .poweredOn ? .green : .orange).frame(width:9,height:9); Text(stateText); Spacer(); Text("READ ONLY").font(.caption2.bold()).foregroundStyle(.secondary) } }
                Section("Scanner") {
                    HStack { Button(ble.isScanning ? "Stop":"Scan") { ble.isScanning ? ble.stopScan() : ble.scan() }.buttonStyle(.borderedProminent); Spacer(); Text("\(ble.peripherals.count) found").foregroundStyle(.secondary) }
                    ForEach(ble.peripherals,id:\.identifier) { p in Button { ble.connect(p) } label:{ VStack(alignment:.leading){ Text(p.name ?? "Unnamed peripheral"); Text(p.identifier.uuidString).font(.caption2).foregroundStyle(.secondary) } } }
                }
                Section("Connection") {
                    if let p=ble.connectedPeripheral { HStack { VStack(alignment:.leading){Text(p.name ?? "Unnamed");Text(p.identifier.uuidString).font(.caption2).foregroundStyle(.secondary)};Spacer();Button("Disconnect"){ble.disconnect()}.buttonStyle(.bordered) } }
                    else { Text("No device connected").foregroundStyle(.secondary) }
                }
                Section("GATT map") {
                    if ble.snapshots.isEmpty { Text("Connect to enumerate services and characteristics.").foregroundStyle(.secondary) }
                    else { ForEach(ble.snapshots) { s in DisclosureGroup(s.uuid) { ForEach(s.characteristics) { c in VStack(alignment:.leading,spacing:3){ Text(c.uuid).font(.system(.body,design:.monospaced)); Text(c.properties).font(.caption).foregroundStyle(.secondary); if let v=c.valueHex{Text(v).font(.system(.caption,design:.monospaced))}; if let t=c.valueUTF8,!t.isEmpty{Text(t).font(.caption)} }.padding(.vertical,3) } } } }
                }
                Section("Snapshot") {
                    Button("Create BLE snapshot") {
                        if let s=ble.exportSnapshot(){ do { let e=JSONEncoder(); e.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]; let d=try e.encode(s); let u=FileManager.default.temporaryDirectory.appendingPathComponent("X5Tune-BLE-\(Int(Date().timeIntervalSince1970)).json"); try d.write(to:u); shareURL=u;showShare=true } catch { ble.addLog("Export failed: \(error.localizedDescription)") } }
                    }
                    Text("BLE/GATT snapshot only. Not a firmware or NVM backup.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Log") { ForEach(ble.log){ e in VStack(alignment:.leading){Text(e.date,style:.time).font(.caption2).foregroundStyle(.secondary);Text(e.message).font(.caption.monospaced())} } }
            }.navigationTitle("X5Tune").sheet(isPresented:$showShare){if let shareURL{ShareSheet(items:[shareURL])}}
        }
    }
    private var stateText:String { switch ble.bluetoothState { case .poweredOn:return "Bluetooth ready";case .poweredOff:return "Bluetooth is off";case .unauthorized:return "Bluetooth permission denied";case .unsupported:return "Bluetooth unsupported";case .resetting:return "Bluetooth resetting";default:return "Bluetooth starting" } }
}
struct ShareSheet:UIViewControllerRepresentable{let items:[Any];func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:items,applicationActivities:nil)};func updateUIViewController(_ c:UIActivityViewController,context:Context){}}

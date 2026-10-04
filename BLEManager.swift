import Foundation
import CoreBluetooth

@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var peripherals: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?
    @Published var services: [CBService] = []
    @Published var snapshots: [ServiceSnapshot] = []
    @Published var log: [LogEntry] = []
    @Published var isScanning = false
    private var central: CBCentralManager!
    private var characteristicMap: [CBUUID: CBCharacteristic] = [:]

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: nil) }

    func scan() {
        guard bluetoothState == .poweredOn else { addLog("Bluetooth is not ready"); return }
        peripherals.removeAll(); isScanning = true
        addLog("Scanning for BLE peripherals…")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func stopScan() { central.stopScan(); isScanning = false; addLog("Scan stopped") }
    func connect(_ peripheral: CBPeripheral) {
        stopScan(); addLog("Connecting to \(peripheral.name ?? "Unnamed")")
        peripheral.delegate = self; central.connect(peripheral, options: nil)
    }
    func disconnect() { if let p = connectedPeripheral { central.cancelPeripheralConnection(p) } }
    func exportSnapshot() -> BLESnapshot? {
        guard let p = connectedPeripheral else { return nil }
        let snapshot = BLESnapshot(createdAt: Date(), peripheralName: p.name ?? "Unnamed", peripheralIdentifier: p.identifier.uuidString, services: snapshots)
        addLog("Snapshot prepared. BLE/GATT data only, not firmware/NVM.")
        return snapshot
    }
    func addLog(_ message: String) {
        log.insert(LogEntry(message: message), at: 0)
        if log.count > 300 { log.removeLast() }
    }
    private func rebuildSnapshots() {
        snapshots = services.map { s in
            ServiceSnapshot(id: s.uuid.uuidString, uuid: s.uuid.uuidString, characteristics: (s.characteristics ?? []).map { c in
                CharacteristicSnapshot(id: c.uuid.uuidString, uuid: c.uuid.uuidString, properties: propertyString(c.properties), valueHex: c.value.map(hex), valueUTF8: c.value.flatMap { String(data: $0, encoding: .utf8) }, isNotifying: c.isNotifying)
            })
        }
    }
    private func propertyString(_ p: CBCharacteristicProperties) -> String {
        var v:[String] = []
        if p.contains(.read) { v.append("READ") }
        if p.contains(.write) { v.append("WRITE") }
        if p.contains(.writeWithoutResponse) { v.append("WRITE_NR") }
        if p.contains(.notify) { v.append("NOTIFY") }
        if p.contains(.indicate) { v.append("INDICATE") }
        if p.contains(.authenticatedSignedWrites) { v.append("SIGNED") }
        return v.joined(separator: " | ")
    }
    private func hex(_ data: Data) -> String { data.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in self.bluetoothState = central.state; self.addLog("Bluetooth state: \(central.state.rawValue)") }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String:Any], rssi RSSI:NSNumber) {
        Task { @MainActor in
            guard !self.peripherals.contains(where: { $0.identifier == peripheral.identifier }) else { return }
            self.peripherals.append(peripheral)
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unnamed"
            self.addLog("Found \(name)  RSSI \(RSSI)")
        }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in self.connectedPeripheral = peripheral; peripheral.delegate = self; self.addLog("Connected. Discovering all GATT services…"); peripheral.discoverServices(nil) }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error:Error?) {
        Task { @MainActor in self.addLog("Connection failed: \(error?.localizedDescription ?? "unknown error")") }
    }
    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error:Error?) {
        Task { @MainActor in self.addLog("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")"); self.connectedPeripheral=nil }
    }
}

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error:Error?) {
        Task { @MainActor in
            if let error { self.addLog("Service discovery error: \(error.localizedDescription)"); return }
            self.services = peripheral.services ?? []
            self.addLog("Discovered \(self.services.count) services")
            for s in self.services { peripheral.discoverCharacteristics(nil, for:s) }
        }
    }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service:CBService, error:Error?) {
        Task { @MainActor in
            if let error { self.addLog("Characteristic discovery error: \(error.localizedDescription)"); return }
            for c in service.characteristics ?? [] {
                self.characteristicMap[c.uuid]=c
                self.addLog("GATT \(service.uuid) / \(c.uuid) [\(self.propertyString(c.properties))]")
                if c.properties.contains(.read) { peripheral.readValue(for:c) }
                if c.properties.contains(.notify) || c.properties.contains(.indicate) { peripheral.setNotifyValue(true, for:c) }
            }
            self.rebuildSnapshots()
        }
    }
    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic:CBCharacteristic, error:Error?) {
        Task { @MainActor in
            if let error { self.addLog("Read/notify error \(characteristic.uuid): \(error.localizedDescription)"); return }
            guard let data=characteristic.value else{return}
            let h=data.map{String(format:"%02X",$0)}.joined(separator:" ")
            let t=String(data:data,encoding:.utf8)?.filter{!$0.isNewline}
            self.addLog("RX \(characteristic.uuid): \(h)\(t.map{" | \($0)"} ?? "")")
            self.rebuildSnapshots()
        }
    }
    nonisolated func peripheral(_ peripheral:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?) {
        Task { @MainActor in
            if let error { self.addLog("Notify setup error \(characteristic.uuid): \(error.localizedDescription)") }
            else { self.addLog("Notify \(characteristic.uuid): \(characteristic.isNotifying ? "ON" : "OFF")") }
            self.rebuildSnapshots()
        }
    }
}

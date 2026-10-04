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
    @Published var packetEvents: [PacketEvent] = []
    @Published var observationMarkers: [ObservationMarker] = []
    @Published var packetDiffs: [PacketDiff] = []
    @Published var isScanning = false
    @Published var activeObservation: String?
    @Published var selectedProfile: ResearchTestProfile = .brake

    private var central: CBCentralManager!
    private var characteristicMap: [CBUUID: CBCharacteristic] = [:]
    private var latestValues: [String: Data] = [:]
    private var observationBaselines: [String: Data] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func scan() {
        guard bluetoothState == .poweredOn else { addLog("Bluetooth is not ready"); return }
        peripherals.removeAll()
        isScanning = true
        addLog("Scanning for BLE peripherals…")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        addLog("Scan stopped")
    }

    func connect(_ peripheral: CBPeripheral) {
        stopScan()
        addLog("Connecting to \(peripheral.name ?? "Unnamed")")
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let p = connectedPeripheral { central.cancelPeripheralConnection(p) }
    }

    func setNotify(_ enabled: Bool, for uuid: String) {
        guard let characteristic = characteristicMap[CBUUID(string: uuid)], let peripheral = connectedPeripheral else {
            addLog("Notify \(uuid): unavailable (not connected or not discovered)")
            return
        }
        guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            addLog("Notify \(uuid): unsupported")
            return
        }
        addLog("\(enabled ? "Subscribing" : "Unsubscribing") \(uuid)…")
        peripheral.setNotifyValue(enabled, for: characteristic)
    }

    func read(_ uuid: String) {
        guard let characteristic = characteristicMap[CBUUID(string: uuid)], let peripheral = connectedPeripheral else {
            addLog("Read \(uuid): unavailable (not connected or not discovered)")
            return
        }
        guard characteristic.properties.contains(.read) else {
            addLog("Read \(uuid): unsupported")
            return
        }
        addLog("Reading \(uuid)…")
        peripheral.readValue(for: characteristic)
    }

    func startObservation(_ label: String) {
        observationBaselines = latestValues
        activeObservation = label
        let marker = ObservationMarker(id: UUID(), date: Date(), label: "START: \(label)")
        observationMarkers.append(marker)
        addLog("OBSERVATION START: \(label) — baseline captured for \(latestValues.count) characteristic(s)")
    }

    func finishObservation(_ label: String? = nil) {
        let name = label ?? activeObservation ?? "Observation"
        let marker = ObservationMarker(id: UUID(), date: Date(), label: "END: \(name)")
        observationMarkers.append(marker)
        addLog("OBSERVATION END: \(name)")
        activeObservation = nil
        observationBaselines.removeAll()
    }

    func recordGuideAction(_ label: String) {
        if activeObservation == nil {
            startObservation(label)
        } else {
            finishObservation(label)
            startObservation(label)
        }
    }

    func clearResearchSession() {
        packetEvents.removeAll()
        observationMarkers.removeAll()
        packetDiffs.removeAll()
        latestValues.removeAll()
        observationBaselines.removeAll()
        activeObservation = nil
        log.removeAll()
        addLog("Research session cleared")
    }

    func exportSnapshot() -> BLESnapshot? {
        guard let p = connectedPeripheral else { return nil }
        let snapshot = BLESnapshot(createdAt: Date(), peripheralName: p.name ?? "Unnamed", peripheralIdentifier: p.identifier.uuidString, services: snapshots)
        addLog("Snapshot prepared. BLE/GATT data only, not firmware/NVM.")
        return snapshot
    }

    func researchReport() -> ResearchReport? {
        guard let p = connectedPeripheral else { return nil }
        return ResearchReport(
            generatedAt: Date(),
            deviceName: p.name ?? "Unnamed",
            deviceIdentifier: p.identifier.uuidString,
            boundary: "READ/NOTIFY ONLY. X5Tune does not expose BLE writes, firmware updates, controller parameter changes, speed-limit bypass, or zero-start enablement.",
            services: snapshots,
            markers: observationMarkers,
            packetEvents: packetEvents,
            diffs: packetDiffs,
            notes: ["Interpret packet meaning from repeated observations; a packet change is not proof of causality."]
        )
    }

    func copyableReport() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [
            "X5Tune RESEARCH REPORT",
            "Device: \(connectedPeripheral?.name ?? "No connected device")",
            "Identifier: \(connectedPeripheral?.identifier.uuidString ?? "n/a")",
            "Generated: \(formatter.string(from: Date()))",
            "BOUNDARY: READ/NOTIFY ONLY — no BLE writes exposed.",
            "",
            "=== GATT ==="
        ]
        for service in snapshots {
            lines.append("SERVICE \(service.uuid)")
            for c in service.characteristics {
                lines.append("  \(c.uuid) [\(c.properties)] notify=\(c.isNotifying) value=\(c.valueHex ?? "n/a")")
            }
        }
        lines += ["", "=== OBSERVATION TIMELINE ==="]
        lines += observationMarkers.map { "[\(formatter.string(from: $0.date))] \($0.label)" }
        lines += ["", "=== PACKET EVENTS ==="]
        lines += packetEvents.map {
            let changes = $0.changedBytes.map(String.init).joined(separator: ",")
            return "[\(formatter.string(from: $0.date))] \($0.uuid): \($0.hex) changedBytes=[\(changes)]"
        }
        lines += ["", "=== PACKET DIFFS ==="]
        lines += packetDiffs.map {
            let changes = $0.changedBytes.map(String.init).joined(separator: ",")
            return "[\(formatter.string(from: $0.date))] \($0.action) / \($0.uuid): \($0.before) -> \($0.after) changedBytes=[\(changes)]"
        }
        lines += ["", "=== RAW APP LOG ==="]
        lines += log.reversed().map { "[\(formatter.string(from: $0.date))] \($0.message)" }
        return lines.joined(separator: "\n")
    }

    func copyableLog() -> String { copyableReport() }

    func addLog(_ message: String) {
        log.insert(LogEntry(message: message), at: 0)
        if log.count > 1000 { log.removeLast() }
    }

    private func rebuildSnapshots() {
        snapshots = services.map { s in
            ServiceSnapshot(id: s.uuid.uuidString, uuid: s.uuid.uuidString, characteristics: (s.characteristics ?? []).map { c in
                CharacteristicSnapshot(id: c.uuid.uuidString, uuid: c.uuid.uuidString, properties: propertyString(c.properties), valueHex: c.value.map(hex), valueUTF8: c.value.flatMap { String(data: $0, encoding: .utf8) }, isNotifying: c.isNotifying)
            })
        }
    }

    private func propertyString(_ p: CBCharacteristicProperties) -> String {
        var v: [String] = []
        if p.contains(.read) { v.append("READ") }
        if p.contains(.write) { v.append("WRITE") }
        if p.contains(.writeWithoutResponse) { v.append("WRITE_NR") }
        if p.contains(.notify) { v.append("NOTIFY") }
        if p.contains(.indicate) { v.append("INDICATE") }
        if p.contains(.authenticatedSignedWrites) { v.append("SIGNED") }
        return v.joined(separator: " | ")
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func changedBytes(_ old: Data?, _ new: Data) -> [Int] {
        guard let old else { return Array(0..<new.count) }
        let count = max(old.count, new.count)
        return (0..<count).filter { i in
            let a = i < old.count ? old[i] : nil
            let b = i < new.count ? new[i] : nil
            return a != b
        }
    }

    private func capturePacket(_ characteristic: CBCharacteristic, data: Data) {
        let uuid = characteristic.uuid.uuidString
        let changes = changedBytes(latestValues[uuid], data)
        latestValues[uuid] = data
        packetEvents.insert(PacketEvent(id: UUID(), date: Date(), uuid: uuid, hex: hex(data), text: String(data: data, encoding: .utf8)?.filter { !$0.isNewline }, changedBytes: changes), at: 0)
        if packetEvents.count > 1000 { packetEvents.removeLast() }

        if let observation = activeObservation {
            let before = observationBaselines[uuid]
            let diff = changedBytes(before, data)
            if !diff.isEmpty {
                let beforeHex = before.map(hex) ?? "<none>"
                packetDiffs.insert(PacketDiff(id: UUID(), date: Date(), action: observation, uuid: uuid, before: beforeHex, after: hex(data), changedBytes: diff), at: 0)
                if packetDiffs.count > 500 { packetDiffs.removeLast() }
                addLog("DIFF \(observation) / \(uuid): bytes \(diff.map(String.init).joined(separator: ",")) changed")
            }
        }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
            self.addLog("Bluetooth state: \(central.state.rawValue)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard !self.peripherals.contains(where: { $0.identifier == peripheral.identifier }) else { return }
            self.peripherals.append(peripheral)
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Unnamed"
            self.addLog("Found \(name)  RSSI \(RSSI)")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            self.addLog("Connected. Discovering all GATT services…")
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.addLog("Connection failed: \(error?.localizedDescription ?? "unknown error")") }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.addLog("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
            self.connectedPeripheral = nil
        }
    }
}

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                self.addLog("Service discovery error: \(error.localizedDescription)")
                return
            }
            self.services = peripheral.services ?? []
            self.addLog("Discovered \(self.services.count) services")
            for s in self.services { peripheral.discoverCharacteristics(nil, for: s) }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.addLog("Characteristic discovery error: \(error.localizedDescription)")
                return
            }
            for c in service.characteristics ?? [] {
                self.characteristicMap[c.uuid] = c
                self.addLog("GATT \(service.uuid) / \(c.uuid) [\(self.propertyString(c.properties))]")
                if c.properties.contains(.read) { peripheral.readValue(for: c) }
            }
            self.rebuildSnapshots()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                self.addLog("Read/notify error \(characteristic.uuid): \(error.localizedDescription)")
                return
            }
            guard let data = characteristic.value else { return }
            let h = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            let t = String(data: data, encoding: .utf8)?.filter { !$0.isNewline }
            self.addLog("RX \(characteristic.uuid): \(h)\(t.map { " | \($0)" } ?? "")")
            self.capturePacket(characteristic, data: data)
            self.rebuildSnapshots()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                self.addLog("Notify setup error \(characteristic.uuid): \(error.localizedDescription)")
            } else {
                self.addLog("Notify \(characteristic.uuid): \(characteristic.isNotifying ? "ON" : "OFF")")
            }
            self.rebuildSnapshots()
        }
    }
}

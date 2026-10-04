import Foundation
import SwiftUI

// MARK: - X5Tune Digital Twin
//
// This is a simulation/calibration model, not a BLE controller.
// Firmware-derived values are tagged with their evidence level. Unknown
// controller semantics are never treated as confirmed physical behavior.

@MainActor
final class VirtualScooterModel: ObservableObject {
    enum Region: String, CaseIterable, Identifiable {
        case germanyEU = "Germany / EU"
        case global = "Global reference"

        var id: String { rawValue }

        var regulatoryReferenceSpeed: Double {
            switch self {
            case .germanyEU: return 20
            case .global: return 25
            }
        }

        var modeSpeeds: [RideMode: Double] {
            switch self {
            case .germanyEU:
                return [.pedestrian: 6, .eco: 15, .drive: 20, .sport: 20]
            case .global:
                return [.pedestrian: 6, .eco: 15, .drive: 20, .sport: 25]
            }
        }
    }

    enum RideMode: String, CaseIterable, Identifiable {
        case pedestrian = "Pedestrian"
        case eco = "Eco"
        case drive = "Drive"
        case sport = "Sport"

        var id: String { rawValue }
    }

    enum Evidence: String {
        case confirmed = "Confirmed"
        case observed = "Observed"
        case strongCandidate = "Strong candidate"
        case inferred = "Inferred"
        case unknown = "Unknown"
    }

    struct Calibration: Identifiable {
        let id = UUID()
        var riderMassKg = 75.0
        var scooterMassKg = 26.6
        var motorPeakW = 900.0
        var batteryNominalV = 46.8
        var batteryCapacityWh = 477.36
        var rollingCoefficient = 0.012
        var aeroCoefficient = 0.55
        var drivetrainEfficiency = 0.86
        var thermalGain = 0.020
        var thermalCooling = 0.035
        var gradePercent = 0.0
        var windKmh = 0.0

        var totalMassKg: Double { riderMassKg + scooterMassKg }
    }

    struct TestResult: Identifiable {
        let id = UUID()
        let name: String
        let duration: Double
        let finalSpeed: Double
        let peakSpeed: Double
        let energyWh: Double
        let peakMotorTemperature: Double
        let reachedTarget: Bool
        let confidence: Evidence
    }

    struct FirmwareBasis {
        let app = "2.7.0_0039"
        let mcu = "0035"
        let hardware = "SZMC-ES-02664"
    }

    let firmwareBasis = FirmwareBasis()

    @Published var speed = 0.0
    @Published var battery = 82.0
    @Published var batteryVoltage = 49.0
    @Published var currentAmps = 0.0
    @Published var motorTemperature = 24.0
    @Published var controllerTemperature = 24.0
    @Published var throttle = 0.0
    @Published var brake = false
    @Published var lights = false
    @Published var locked = false
    @Published var emergency = false
    @Published var tcsEnabled = true
    @Published var zeroStart = true
    @Published var startThreshold = 5.0
    @Published var mode: RideMode = .drive
    @Published var region: Region = .germanyEU
    @Published var gradePercent = 0.0
    @Published var riderMassKg = 75.0
    @Published var windKmh = 0.0
    @Published var isRunning = false
    @Published var elapsed = 0.0
    @Published private(set) var lastTestResults: [TestResult] = []
    @Published private(set) var activeFaults: [String] = []

    // Experimental parameters live only inside the digital twin.
    @Published var experimentalSpeedCap: Double = 20
    @Published var accelerationScale: Double = 1.0
    @Published var throttleCurve: Double = 1.0
    @Published var regenStrength: Double = 0.35

    private var timer: Timer?
    private var distanceKm = 0.0
    private var energyWh = 0.0

    var targetSpeed: Double {
        min(experimentalSpeedCap, region.modeSpeeds[mode] ?? region.regulatoryReferenceSpeed)
    }

    deinit { timer?.invalidate() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.step(0.05) }
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        speed = 0
        battery = 100
        batteryVoltage = 46.8
        currentAmps = 0
        motorTemperature = 24
        controllerTemperature = 24
        throttle = 0
        brake = false
        locked = false
        emergency = false
        elapsed = 0
        distanceKm = 0
        energyWh = 0
        activeFaults = []
    }

    func setThrottle(_ value: Double) {
        throttle = min(max(value, 0), 1)
    }

    func triggerPanic() {
        emergency = true
        throttle = 0
        brake = true
    }

    func clearPanic() {
        emergency = false
        brake = false
    }

    func runStandardTests() {
        let saved = snapshotParameters()
        var results: [TestResult] = []
        let tests: [(String, Double)] = [
            ("0 -> 5 km/h", 5),
            ("0 -> 10 km/h", 10),
            ("0 -> 15 km/h", 15),
            ("15 -> 20 km/h", 20)
        ]

        for (name, target) in tests {
            reset()
            mode = .drive
            experimentalSpeedCap = max(target, region.regulatoryReferenceSpeed)
            zeroStart = true
            setThrottle(1)
            let duration = simulateUntil(speedTarget: target, timeout: 45)
            results.append(makeResult(name: name, duration: duration, target: target))
        }

        reset()
        mode = .drive
        experimentalSpeedCap = region.regulatoryReferenceSpeed
        zeroStart = true
        setThrottle(1)
        gradePercent = 10
        let hillDuration = simulateUntil(speedTarget: 10, timeout: 45)
        results.append(makeResult(name: "10% hill → 10 km/h", duration: hillDuration, target: 10))

        reset()
        mode = .drive
        experimentalSpeedCap = region.regulatoryReferenceSpeed
        zeroStart = true
        speed = 15
        setThrottle(1)
        let rollingDuration = simulateUntil(speedTarget: 20, timeout: 45)
        results.append(makeResult(name: "15 → 20 km/h", duration: rollingDuration, target: 20))

        reset()
        mode = .drive
        experimentalSpeedCap = region.regulatoryReferenceSpeed
        zeroStart = true
        setThrottle(1)
        riderMassKg = 110
        let heavyDuration = simulateUntil(speedTarget: 15, timeout: 45)
        results.append(makeResult(name: "Heavy rider -> 15 km/h", duration: heavyDuration, target: 15))

        restoreParameters(saved)
        lastTestResults = results
    }

    private func simulateUntil(speedTarget: Double, timeout: Double) -> Double {
        var t = 0.0
        while t < timeout && speed < speedTarget {
            step(0.05)
            t += 0.05
        }
        return t
    }

    private func makeResult(name: String, duration: Double, target: Double) -> TestResult {
        TestResult(
            name: name,
            duration: duration,
            finalSpeed: speed,
            peakSpeed: speed,
            energyWh: energyWh,
            peakMotorTemperature: motorTemperature,
            reachedTarget: speed >= target * 0.995,
            confidence: .inferred
        )
    }

    private struct ParameterSnapshot {
        let mode: RideMode
        let region: Region
        let cap: Double
        let acceleration: Double
        let curve: Double
        let regen: Double
        let zeroStart: Bool
        let startThreshold: Double
        let grade: Double
        let mass: Double
        let wind: Double
    }

    private func snapshotParameters() -> ParameterSnapshot {
        ParameterSnapshot(mode: mode, region: region, cap: experimentalSpeedCap,
                          acceleration: accelerationScale, curve: throttleCurve,
                          regen: regenStrength, zeroStart: zeroStart,
                          startThreshold: startThreshold, grade: gradePercent,
                          mass: riderMassKg, wind: windKmh)
    }

    private func restoreParameters(_ s: ParameterSnapshot) {
        mode = s.mode
        region = s.region
        experimentalSpeedCap = s.cap
        accelerationScale = s.acceleration
        throttleCurve = s.curve
        regenStrength = s.regen
        zeroStart = s.zeroStart
        startThreshold = s.startThreshold
        gradePercent = s.grade
        riderMassKg = s.mass
        windKmh = s.wind
    }

    private func step(_ dt: Double) {
        elapsed += dt
        let calibration = Calibration(riderMassKg: riderMassKg, gradePercent: gradePercent, windKmh: windKmh)

        if locked || emergency {
            speed = max(0, speed - 7.0 * dt)
            updateThermals(current: 0, dt: dt, calibration: calibration)
            return
        }

        let launchAllowed = zeroStart || speed >= startThreshold || speed > 0.01
        let shapedThrottle = pow(max(throttle, 0), max(0.45, throttleCurve))
        let cap = targetSpeed

        if !launchAllowed && shapedThrottle > 0 {
            speed = max(0, speed - 1.0 * dt)
            currentAmps = 0
            updateThermals(current: 0, dt: dt, calibration: calibration)
            return
        }

        let speedMps = speed / 3.6
        let grade = atan(calibration.gradePercent / 100.0)
        let rollingForce = calibration.rollingCoefficient * calibration.totalMassKg * 9.81
        let aeroForce = 0.5 * 1.225 * calibration.aeroCoefficient * speedMps * speedMps
        let gradeForce = calibration.totalMassKg * 9.81 * sin(grade)
        let windMps = calibration.windKmh / 3.6
        let relativeSpeed = max(0, speedMps + windMps)
        let aerodynamicForce = 0.5 * 1.225 * calibration.aeroCoefficient * relativeSpeed * relativeSpeed
        let resistance = rollingForce + gradeForce + aerodynamicForce

        let availableForce = calibration.motorPeakW / max(speedMps, 2.0)
        let commandedForce = availableForce * shapedThrottle * accelerationScale * calibration.drivetrainEfficiency

        let controllerCapForce = speed >= cap ? -max(0, (speed - cap) * 8.0) : 0
        let brakeForce = brake ? calibration.totalMassKg * 9.81 * 0.32 : 0
        let regenForce = brake ? calibration.totalMassKg * 9.81 * 0.10 * regenStrength : 0

        var netForce = commandedForce - resistance + controllerCapForce - brakeForce
        if tcsEnabled && speed < 3 && shapedThrottle > 0.92 {
            netForce *= 0.82
        }

        let acceleration = netForce / calibration.totalMassKg
        speed = min(cap + 0.25, max(0, speed + acceleration * dt * 3.6))

        if speed >= cap && cap > 0 {
            speed = min(speed, cap)
        }

        let wheelPowerW = max(0, commandedForce * max(speedMps, 0))
        let regenW = regenForce * max(speedMps, 0)
        let auxiliaryPowerW = lights ? 12.0 : 0.0
        let batteryPowerW = max(0, wheelPowerW - regenW) + auxiliaryPowerW
        currentAmps = batteryPowerW / max(batteryVoltage, 1)
        energyWh += batteryPowerW * dt / 3600.0
        distanceKm += speed * dt / 3600.0

        let batteryEnergyFraction = min(1, energyWh / max(calibration.batteryCapacityWh, 1))
        battery = max(0, 100 - batteryEnergyFraction * 100)
        let sag = min(5.0, currentAmps * 0.045)
        batteryVoltage = max(38, calibration.batteryNominalV - sag - batteryEnergyFraction * 3.0)

        updateThermals(current: currentAmps, dt: dt, calibration: calibration)

        activeFaults.removeAll()
        if motorTemperature >= 80 { activeFaults.append("Motor thermal limit approaching") }
        if controllerTemperature >= 78 { activeFaults.append("Controller thermal limit approaching") }
        if batteryVoltage <= 40 { activeFaults.append("Low battery voltage model") }
    }

    private func updateThermals(current: Double, dt: Double, calibration: Calibration) {
        let heating = current * current * 0.0012 + throttle * 0.25
        motorTemperature += (heating * calibration.thermalGain - calibration.thermalCooling * (motorTemperature - 22)) * dt
        controllerTemperature += (heating * 0.75 * calibration.thermalGain - calibration.thermalCooling * (controllerTemperature - 22)) * dt
        motorTemperature = min(95, max(22, motorTemperature))
        controllerTemperature = min(95, max(22, controllerTemperature))
        currentAmps = current
    }
}

struct VirtualScooterView: View {
    @StateObject private var scooter = VirtualScooterModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showCalibration = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Xiaomi Electric Scooter 5 Plus").font(.headline)
                        HStack(alignment: .firstTextBaseline) {
                            Text(String(format: "%.1f", scooter.speed))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                            Text("km/h").foregroundStyle(.secondary)
                        }
                        Gauge(value: scooter.speed, in: 0...max(scooter.targetSpeed, 1)) { Text("Speed") }
                            .tint(.blue)
                        HStack {
                            Label(String(format: "%.0f%%", scooter.battery), systemImage: "battery.75")
                            Spacer()
                            Label(String(format: "%.1f A", scooter.currentAmps), systemImage: "bolt.fill")
                            Spacer()
                            Label(String(format: "%.0f C", scooter.motorTemperature), systemImage: "thermometer.medium")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                } header: {
                    HStack {
                        Text("Digital Twin")
                        Spacer()
                        Text("SIMULATION").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    }
                }

                Section("Ride") {
                    Picker("Mode", selection: $scooter.mode) {
                        ForEach(VirtualScooterModel.RideMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Region", selection: $scooter.region) {
                        ForEach(VirtualScooterModel.Region.allCases) { Text($0.rawValue).tag($0) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Throttle")
                            Spacer()
                            Text(String(format: "%.0f%%", scooter.throttle * 100)).foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { scooter.throttle }, set: { scooter.setThrottle($0) }), in: 0...1)
                    }
                    Button {
                        scooter.setThrottle(scooter.throttle > 0.99 ? 0 : 1)
                    } label: {
                        Label(scooter.throttle > 0.99 ? "Release throttle" : "Full throttle",
                              systemImage: scooter.throttle > 0.99 ? "hand.raised" : "figure.outdoor.cycle")
                    }
                    Toggle("Brake", isOn: $scooter.brake)
                    Toggle("Lights", isOn: $scooter.lights)
                    Toggle("Locked", isOn: $scooter.locked)
                }

                Section("What-If Tuning") {
                    LabeledContent("Speed ceiling", value: String(format: "%.0f km/h", scooter.experimentalSpeedCap))
                    Slider(value: $scooter.experimentalSpeedCap, in: 6...30, step: 1)
                    LabeledContent("Acceleration", value: String(format: "%.0f%%", scooter.accelerationScale * 100))
                    Slider(value: $scooter.accelerationScale, in: 0.5...1.3, step: 0.05)
                    LabeledContent("Throttle curve", value: String(format: "%.2f", scooter.throttleCurve))
                    Slider(value: $scooter.throttleCurve, in: 0.55...1.6, step: 0.05)
                    Text("Simulation only. These values never generate BLE writes or firmware changes.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Environment") {
                    LabeledContent("Rider", value: String(format: "%.0f kg", scooter.riderMassKg))
                    LabeledContent("Grade", value: String(format: "%.0f%%", scooter.gradePercent))
                    LabeledContent("Wind", value: String(format: "%.0f km/h", scooter.windKmh))
                    Button("Adjust calibration") { showCalibration = true }
                }

                Section("Tests") {
                    Button("Run standard test suite") { scooter.runStandardTests() }
                    if scooter.lastTestResults.isEmpty {
                        Text("No test results yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(scooter.lastTestResults) { result in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(result.name)
                                    Spacer()
                                    Text(result.reachedTarget ? "PASS" : "LIMIT")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(result.reachedTarget ? .green : .orange)
                                }
                                Text(String(format: "%.2fs | %.1f km/h | %.1f Wh | %.0f C",
                                            result.duration, result.finalSpeed, result.energyWh, result.peakMotorTemperature))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Controls") {
                    Button("Reset simulation", role: .destructive) { scooter.reset() }
                    Button(scooter.emergency ? "Clear emergency" : "Emergency stop",
                           role: scooter.emergency ? nil : .destructive) {
                        scooter.emergency ? scooter.clearPanic() : scooter.triggerPanic()
                    }
                }

                Section("Evidence") {
                    LabeledContent("APP firmware", value: scooter.firmwareBasis.app)
                    LabeledContent("MCU", value: scooter.firmwareBasis.mcu)
                    LabeledContent("Hardware", value: scooter.firmwareBasis.hardware)
                    Text("Firmware evidence informs the model, but physical behavior remains inferred until calibrated against controlled measurements.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("X5Tune Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCalibration) {
                NavigationStack {
                    Form {
                        Section("Physical inputs") {
                            SliderRow(title: "Rider mass", value: $scooter.riderMassKg, range: 40...120, step: 1, suffix: " kg")
                            SliderRow(title: "Grade", value: $scooter.gradePercent, range: -15...20, step: 1, suffix: "%")
                            SliderRow(title: "Wind", value: $scooter.windKmh, range: -30...30, step: 1, suffix: " km/h")
                        }
                        Section("Model") {
                            Toggle("Traction control", isOn: $scooter.tcsEnabled)
                            Toggle("Zero-start", isOn: $scooter.zeroStart)
                            SliderRow(title: "Start threshold", value: $scooter.startThreshold, range: 3...5, step: 0.5, suffix: " km/h")
                        }
                        Section {
                            Button("Reset calibration") {
                                scooter.riderMassKg = 75
                                scooter.gradePercent = 0
                                scooter.windKmh = 0
                                scooter.tcsEnabled = true
                                scooter.zeroStart = true
                                scooter.startThreshold = 5
                            }
                        }
                    }
                    .navigationTitle("Calibration")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showCalibration = false }
                        }
                    }
                }
            }
            .onAppear { scooter.start() }
            .onDisappear { scooter.stop() }
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f%@", value, suffix)).foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}


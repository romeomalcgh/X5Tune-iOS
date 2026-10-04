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

        var color: Color {
            switch self {
            case .confirmed: return .green
            case .observed: return .blue
            case .strongCandidate: return .orange
            case .inferred: return .yellow
            case .unknown: return .gray
            }
        }
    }

    struct Calibration: Identifiable {
        let id = UUID()
        var riderMassKg = 75.0
        var scooterMassKg = 26.6
        var wheelRadiusM = 0.152
        var motorRatedW = 400.0
        var motorPeakW = 900.0
        var batteryNominalV = 46.8
        var batteryCapacityWh = 477.36
        var rollingCoefficient = 0.012
        var aeroCoefficient = 0.55
        var drivetrainEfficiency = 0.86
        var controllerResponse = 2.4
        var thermalGain = 0.020
        var thermalCooling = 0.035
        var gradePercent = 0.0
        var windKmh = 0.0

        var totalMassKg: Double { riderMassKg + scooterMassKg }
    }

    struct Profile: Identifiable {
        let id = UUID()
        var name: String
        var mode: RideMode
        var speedCap: Double
        var accelerationScale: Double
        var throttleCurve: Double
        var regenStrength: Double
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
        let mcuSHA256 = "bdcec9c57c53279a19c28e437003e06e11f441170a349f94f7fdb140edd33cf4"
        let knownScale = 17.4
        let driveReference = 348.0
        let sportReference = 435.0
        let modeRAMCandidate = "0x20001E2C"
        let modeCandidateEvidence: Evidence = .strongCandidate
        let physicalSemanticsEvidence: Evidence = .unknown
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
    @Published var zeroStart = false
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

    var firmware = "APP 2.7.0_0039"
    var mcu = "MCU 0035"
    var bms = "012"
    var hardware = "SZMC-ES-02664"

    var targetSpeed: Double {
        min(experimentalSpeedCap, region.modeSpeeds[mode] ?? region.regulatoryReferenceSpeed)
    }

    var massKg: Double { riderMassKg + 26.6 }

    var distanceMeters: Double { distanceKm * 1000 }
    var energyUsedWh: Double { energyWh }

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
        battery = 82
        batteryVoltage = 49
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

    func applyProfile(_ profile: Profile) {
        mode = profile.mode
        experimentalSpeedCap = profile.speedCap
        accelerationScale = profile.accelerationScale
        throttleCurve = profile.throttleCurve
        regenStrength = profile.regenStrength
    }

    func stockProfile(for mode: RideMode? = nil) -> Profile {
        let selected = mode ?? self.mode
        let cap = region.modeSpeeds[selected] ?? region.regulatoryReferenceSpeed
        let acceleration: Double
        switch selected {
        case .pedestrian: acceleration = 0.45
        case .eco: acceleration = 0.68
        case .drive: acceleration = 0.88
        case .sport: acceleration = 1.0
        }
        return Profile(name: "Stock (selected.rawValue)", mode: selected,
                       speedCap: cap, accelerationScale: acceleration,
                       throttleCurve: 1.0, regenStrength: 0.35)
    }

    func runStandardTests() {
        let saved = snapshotParameters()
        var results: [TestResult] = []
        let tests: [(String, Double)] = [
            ("0 → 5 km/h", 5),
            ("0 → 10 km/h", 10),
            ("0 → 15 km/h", 15),
            ("15 → 20 km/h", 20)
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
        setThrottle(1)
        riderMassKg = 110
        let heavyDuration = simulateUntil(speedTarget: 15, timeout: 45)
        results.append(makeResult(name: "Heavy rider → 15 km/h", duration: heavyDuration, target: 15))

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

        let peakForce = calibration.motorPeakW / max(speedMps, 2.0)
        let availableForce = min(peakForce, calibration.motorPeakW / max(speedMps, 2.0))
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
        currentAmps = max(0, (wheelPowerW - regenW) / max(batteryVoltage, 1))
        energyWh += max(0, wheelPowerW - regenW) * dt / 3600.0
        distanceKm += speed * dt / 3600.0

        let batteryEnergyFraction = min(1, energyWh / max(calibration.batteryCapacityWh, 1))
        battery = max(0, 82 - batteryEnergyFraction * 100)
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

    private let panel = Color(red: 0.075, green: 0.075, blue: 0.09)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    heroCard
                    liveTelemetryCard
                    controlsCard
                    testCard
                    tuningCard
                    calibrationCard
                    evidenceCard
                    simulatorNotice
                }
                .padding(16)
            }
            .navigationTitle("X5Tune Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { scooter.start() }
            .onDisappear { scooter.stop() }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Xiaomi Electric Scooter 5 Plus").font(.headline)
                    Text("DIGITAL TWIN • SIMULATION").font(.caption2.bold()).foregroundStyle(.blue)
                }
                Spacer()
                Circle().fill(scooter.activeFaults.isEmpty ? .green : .orange).frame(width: 9, height: 9)
            }
            HStack(spacing: 16) {
                metric("Speed", String(format: "%.1f", scooter.speed), "km/h")
                metric("Battery", String(format: "%.0f", scooter.battery), "%")
                metric("Motor", String(format: "%.0f", scooter.motorTemperature), "°C")
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var liveTelemetryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live model").font(.headline)

            ProgressView(value: scooter.speed, total: max(scooter.targetSpeed, 1))
                .tint(.blue)

            HStack {
                Text(scooter.mode.rawValue)
                Spacer()
                Text(String(format: "%.1f / %.0f km/h", scooter.speed, scooter.targetSpeed))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Picker("Region", selection: $scooter.region) {
                ForEach(VirtualScooterModel.Region.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)

            Picker("Mode", selection: $scooter.mode) {
                ForEach(VirtualScooterModel.RideMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Throttle")
                    Spacer()
                    Text(String(format: "%.0f%%", scooter.throttle * 100)).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { scooter.throttle }, set: scooter.setThrottle))
            }

            HStack {
                metric("Voltage", String(format: "%.1f", scooter.batteryVoltage), "V")
                metric("Current", String(format: "%.1f", scooter.currentAmps), "A")
                metric("Distance", String(format: "%.2f", scooter.distanceMeters), "m")
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Controls").font(.headline)
            HStack(spacing: 10) {
                Button {
                    scooter.brake.toggle()
                } label: {
                    Label(scooter.brake ? "Brake ON" : "Brake", systemImage: "hand.raised.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    scooter.lights.toggle()
                } label: {
                    Label(scooter.lights ? "Lights ON" : "Lights", systemImage: "lightbulb.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    scooter.locked.toggle()
                    if scooter.locked { scooter.setThrottle(0) }
                } label: {
                    Label(scooter.locked ? "Unlock" : "Lock", systemImage: scooter.locked ? "lock.open" : "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    scooter.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button {
                scooter.emergency ? scooter.clearPanic() : scooter.triggerPanic()
            } label: {
                Label(scooter.emergency ? "Clear Panic" : "PANIC", systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(scooter.emergency ? .gray : .red)
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Standard tests").font(.headline)
                Spacer()
                Button("Run suite") { scooter.runStandardTests() }
            }

            Text("The suite compares repeatable virtual conditions instead of inventing a single 'tuning works' score.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if scooter.lastTestResults.isEmpty {
                Text("No test run yet.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(scooter.lastTestResults) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(result.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(result.reachedTarget ? "PASS" : "LIMIT")
                                .font(.caption2.bold())
                                .foregroundStyle(result.reachedTarget ? .green : .orange)
                        }
                        Text(String(format: "%.2fs • %.1f km/h • %.1f Wh • %.0f°C peak", result.duration, result.finalSpeed, result.energyWh, result.peakMotorTemperature))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var tuningCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("What-if tuning").font(.headline)
                Spacer()
                Text("SIM ONLY").font(.caption2.bold()).foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Virtual speed ceiling")
                    Spacer()
                    Text(String(format: "%.0f km/h", scooter.experimentalSpeedCap)).foregroundStyle(.secondary)
                }
                Slider(value: $scooter.experimentalSpeedCap, in: 6...30, step: 1)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Acceleration scale")
                    Spacer()
                    Text(String(format: "%.0f%%", scooter.accelerationScale * 100)).foregroundStyle(.secondary)
                }
                Slider(value: $scooter.accelerationScale, in: 0.5...1.3, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Throttle curve")
                    Spacer()
                    Text(String(format: "%.2f", scooter.throttleCurve)).foregroundStyle(.secondary)
                }
                Slider(value: $scooter.throttleCurve, in: 0.55...1.6, step: 0.05)
            }

            Text("These controls alter only the virtual controller model. They do not produce BLE writes, firmware patches, or real-scooter commands.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calibration").font(.headline)
                Spacer()
                Button("Adjust") { showCalibration = true }
            }
            infoRow("Rider", String(format: "%.0f kg", scooter.riderMassKg))
            infoRow("Grade", String(format: "%.0f%%", scooter.gradePercent))
            infoRow("Wind", String(format: "%.0f km/h", scooter.windKmh))
            infoRow("TCS", scooter.tcsEnabled ? "Enabled" : "Disabled")
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
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
                        SliderRow(title: "Startup threshold", value: $scooter.startThreshold, range: 3...5, step: 0.5, suffix: " km/h")
                    }
                    Section {
                        Button("Reset calibration") {
                            scooter.riderMassKg = 75
                            scooter.gradePercent = 0
                            scooter.windKmh = 0
                            scooter.tcsEnabled = true
                            scooter.zeroStart = false
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
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Firmware evidence").font(.headline)
            evidenceRow("MCU SHA-256", scooter.firmwareBasis.mcuSHA256, .confirmed)
            evidenceRow("Known internal scale", "17.4", .observed)
            evidenceRow("20 km/h reference", "348", .observed)
            evidenceRow("25 km/h reference", "435", .observed)
            evidenceRow("Mode RAM field", scooter.firmwareBasis.modeRAMCandidate, scooter.firmwareBasis.modeCandidateEvidence)
            evidenceRow("Physical parameter semantics", "Not established", scooter.firmwareBasis.physicalSemanticsEvidence)
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var simulatorNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Digital twin, not a proof of physical behavior.", systemImage: "checkmark.shield")
                .font(.subheadline.weight(.semibold))
            Text("A prediction becomes useful only after controlled real-scooter measurements are used to calibrate mass, launch behavior, acceleration, speed telemetry, battery sag and thermal response. Firmware bytes alone cannot validate those physical outputs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value + " " + unit).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func evidenceRow(_ title: String, _ value: String, _ evidence: VirtualScooterModel.Evidence) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(evidence.rawValue).foregroundStyle(evidence.color)
            }
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
                Text(String(format: "%.1f%@", value, suffix))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

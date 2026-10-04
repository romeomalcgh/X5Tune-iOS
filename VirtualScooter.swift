import Foundation
import SwiftUI

@MainActor
final class VirtualScooterModel: ObservableObject {
    enum RideMode: String, CaseIterable, Identifiable {
        case eco = "Eco"
        case drive = "Drive"
        case sport = "Sport"
        var id: String { rawValue }
        var targetSpeed: Double {
            switch self {
            case .eco: return 15
            case .drive: return 20
            case .sport: return 25
            }
        }
        var accelerationFactor: Double {
            switch self {
            case .eco: return 0.65
            case .drive: return 0.85
            case .sport: return 1.0
            }
        }
    }

    @Published var speed = 0.0
    @Published var battery = 82.0
    @Published var motorTemperature = 24.0
    @Published var mode: RideMode = .drive
    @Published var startThreshold = 5.0
    @Published var zeroStart = false
    @Published var throttle = 0.0
    @Published var brake = false
    @Published var lights = false
    @Published var locked = false
    @Published var emergency = false
    @Published var isRunning = false
    @Published var elapsed = 0.0

    private var timer: Timer?

    var firmware = "APP 2.7.0_0039"
    var mcu = "MCU 0035"
    var bms = "012"
    var hardware = "SZMC-ES-02664"

    deinit { timer?.invalidate() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.step(0.1) }
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
        motorTemperature = 24
        throttle = 0
        brake = false
        lights = false
        locked = false
        emergency = false
        elapsed = 0
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

    private func step(_ dt: Double) {
        elapsed += dt
        guard !locked, !emergency else {
            speed = max(0, speed - 4.0 * dt)
            motorTemperature = max(22, motorTemperature - 0.15 * dt)
            return
        }

        let launchAllowed = zeroStart || speed >= startThreshold
        let target = launchAllowed ? mode.targetSpeed * throttle : 0
        let gain = 2.2 * mode.accelerationFactor
        let braking = brake ? 5.5 : 0
        let delta = (target - speed) * gain * dt - braking * dt
        speed = min(max(speed + delta, 0), mode.targetSpeed)

        battery = max(0, battery - (0.00045 + throttle * 0.0025 + speed / 100000) * dt)
        motorTemperature = min(85, max(22, motorTemperature + (throttle * 0.8 + speed * 0.015 - 0.22) * dt))
    }
}

struct VirtualScooterView: View {
    @StateObject private var scooter = VirtualScooterModel()
    @Environment(\.dismiss) private var dismiss

    private let panel = Color(red: 0.075, green: 0.075, blue: 0.09)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    statusCard
                    telemetryCard
                    controlsCard
                    startBehaviorCard
                    firmwareCard
                    simulatorNotice
                }
                .padding(16)
            }
            .navigationTitle("Virtual Scooter")
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

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Xiaomi Electric Scooter 5 Plus").font(.headline)
                    Text("SIMULATED").font(.caption2.bold()).foregroundStyle(.blue)
                }
                Spacer()
                Circle().fill(scooter.emergency ? .red : .green).frame(width: 9, height: 9)
                Text(scooter.emergency ? "PANIC" : "READY").font(.caption.bold())
            }

            HStack(spacing: 10) {
                metric("Speed", String(format: "%.1f km/h", scooter.speed))
                metric("Battery", String(format: "%.0f%%", scooter.battery))
                metric("Motor", String(format: "%.0f°C", scooter.motorTemperature))
            }
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var telemetryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ride simulation").font(.headline)

            ProgressView(value: scooter.speed, total: scooter.mode.targetSpeed)
                .tint(.blue)

            HStack {
                Text(scooter.mode.rawValue)
                Spacer()
                Text("Target (Int(scooter.mode.targetSpeed)) km/h")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            Picker("Mode", selection: $scooter.mode) {
                ForEach(VirtualScooterModel.RideMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Throttle")
                    Spacer()
                    Text(String(format: "%.0f%%", scooter.throttle * 100))
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { scooter.throttle },
                    set: { scooter.setThrottle($0) }
                ))
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

    private var startBehaviorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start behavior").font(.headline)

            Toggle("Zero-start (simulation)", isOn: $scooter.zeroStart)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Kick-start threshold")
                    Spacer()
                    Text(String(format: "%.1f km/h", scooter.startThreshold))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $scooter.startThreshold, in: 3...5, step: 0.5)
            }

            Text(scooter.zeroStart
                 ? "The simulated motor can engage from standstill."
                 : "The simulated motor requires the configured 3–5 km/h threshold before launch.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var firmwareCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Model basis").font(.headline)
            row("Firmware", scooter.firmware)
            row("MCU", scooter.mcu)
            row("BMS", scooter.bms)
            row("Hardware", scooter.hardware)
            row("Model", "DDHBC23LQ / LEQI")
        }
        .padding(16)
        .background(panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var simulatorNotice: some View {
        Label("Virtual model only. No Bluetooth connection and no scooter writes are performed.", systemImage: "desktopcomputer")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

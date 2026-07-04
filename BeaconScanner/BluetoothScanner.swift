//
//  BluetoothScanner.swift
//  BeaconScanner
//

import Combine
import CoreBluetooth
import Foundation

struct DiscoveredDevice: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
}

@MainActor
final class BluetoothScanner: NSObject, ObservableObject {
    @Published var devices: [DiscoveredDevice] = []
    @Published var isScanning = false
    @Published var statusMessage = "Not started"
    @Published var sampleCount = 0
    @Published var lastSessionURL: URL?

    private var centralManager: CBCentralManager!
    // CoreBluetooth delegate callbacks run on this queue, never on main/MainActor.
    private let bleQueue = DispatchQueue(label: "com.beaconscanner.blequeue", qos: .userInitiated)
    private let deviceStore = DeviceStore()
    private let csvLogger = CSVSessionLogger()
    private var uiRefreshTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    func startScanning(label: String) {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth not ready (\(centralManager.state.description))"
            return
        }

        deviceStore.reset()
        devices.removeAll()
        sampleCount = 0
        lastSessionURL = nil

        let url = csvLogger.startSession(label: label)

        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        isScanning = true
        statusMessage = "Scanning... writing to \(url.lastPathComponent)"
        startUIRefreshTimer()
    }

    func stopScanning() {
        centralManager.stopScan()
        csvLogger.endSession()
        stopUIRefreshTimer()
        refreshUI()
        isScanning = false
        lastSessionURL = csvLogger.currentSessionURL
        statusMessage = "Stopped"
    }

    private func startUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        // Use selector-based timer to avoid capturing self in a @Sendable closure.
        let timer = Timer(timeInterval: 0.25,
                          target: self,
                          selector: #selector(handleUIRefreshTimer(_:)),
                          userInfo: nil,
                          repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        uiRefreshTimer = timer
    }

    private func stopUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        uiRefreshTimer = nil
    }

    @objc private func handleUIRefreshTimer(_ timer: Timer) {
        // Ensure MainActor execution for UI state updates.
        Task { @MainActor in
            self.refreshUI()
        }
    }

    private func refreshUI() {
        let snapshot = deviceStore.snapshot()
        devices = snapshot.devices.map {
            DiscoveredDevice(id: $0.id, name: $0.name, rssi: $0.rssi, lastSeen: $0.lastSeen)
        }
        sampleCount = snapshot.sampleCount
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        Task { @MainActor in
            switch state {
            case .poweredOn:
                statusMessage = "Bluetooth ready"
            case .poweredOff:
                statusMessage = "Bluetooth is off"
                isScanning = false
            case .unauthorized:
                statusMessage = "Bluetooth permission denied"
            case .unsupported:
                statusMessage = "Bluetooth not supported on this device"
            default:
                statusMessage = "Bluetooth state: \(state.description)"
            }
        }
    }

    // Fires at very high rates with allowDuplicates: true. Must stay off the main actor:
    // only cheap, thread-safe work here, decoupled from UI via DeviceStore + a 4Hz timer.
    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name
            ?? "Unknown Device"
        let rssiValue = RSSI.intValue
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)

        deviceStore.record(id: id, name: name, rssi: rssiValue)
        csvLogger.log(
            timestampMs: timestampMs,
            peripheralID: id.uuidString,
            name: name,
            rssi: rssiValue
        )
    }
}

private extension CBManagerState {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unrecognized"
        }
    }
}

//
//  WatchScanner.swift
//  BeaconScannerWatch
//

import Combine
import CoreBluetooth
import Foundation

@MainActor
final class WatchScanner: NSObject, ObservableObject {
    @Published var devices: [DeviceSnapshot] = []
    @Published var isScanning = false
    @Published var statusMessage = "Not started"
    @Published var sampleCount = 0

    private var centralManager: CBCentralManager!
    // CoreBluetooth delegate callbacks run on this queue, never on main/MainActor.
    private let bleQueue = DispatchQueue(label: "com.beaconscanner.watch.blequeue", qos: .userInitiated)
    private let deviceStore = DeviceStore()
    private let csvLogger = CSVSessionLogger()
    private let workout = WorkoutSessionController()
    private var connectivity: WatchConnectivityTransfer!
    private var uiRefreshTimer: Timer?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
        connectivity = WatchConnectivityTransfer { [weak self] message in
            guard let self else { return }
            Task { @MainActor in self.statusMessage = message }
        }
        connectivity.activate()
    }

    func startScanning(label: String) {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth not ready"
            return
        }

        deviceStore.reset()
        devices.removeAll()
        sampleCount = 0

        csvLogger.startSession(label: label)
        workout.start { [weak self] message in
            guard let self else { return }
            Task { @MainActor in self.statusMessage = message }
        }

        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        isScanning = true
        statusMessage = "Scanning..."
        startUIRefreshTimer()
    }

    func stopScanning() {
        centralManager.stopScan()
        csvLogger.endSession()
        workout.stop()
        stopUIRefreshTimer()
        refreshUI()
        isScanning = false
        if let url = csvLogger.currentSessionURL {
            connectivity.transfer(fileURL: url)
            statusMessage = "Sending \(url.lastPathComponent)..."
        } else {
            statusMessage = "Stopped"
        }
    }

    private func startUIRefreshTimer() {
        uiRefreshTimer?.invalidate()
        // Selector-based timer avoids capturing self in a @Sendable closure.
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
        Task { @MainActor in
            self.refreshUI()
        }
    }

    private func refreshUI() {
        let snapshot = deviceStore.snapshot()
        devices = snapshot.devices
        sampleCount = snapshot.sampleCount
    }
}

extension WatchScanner: CBCentralManagerDelegate {
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
                statusMessage = "Bluetooth not supported"
            default:
                statusMessage = "Bluetooth state: \(state.rawValue)"
            }
        }
    }

    // Fires at high rates with allowDuplicates: true. Must stay off the main actor:
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

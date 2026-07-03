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

    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth not ready (\(centralManager.state.description))"
            return
        }
        devices.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        isScanning = true
        statusMessage = "Scanning..."
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = "Stopped"
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
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
                statusMessage = "Bluetooth state: \(central.state.description)"
            }
        }
    }

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

        Task { @MainActor in
            if let index = devices.firstIndex(where: { $0.id == id }) {
                devices[index].rssi = rssiValue
                devices[index].name = name
                devices[index].lastSeen = Date()
            } else {
                devices.append(DiscoveredDevice(id: id, name: name, rssi: rssiValue, lastSeen: Date()))
            }
            devices.sort { $0.rssi > $1.rssi }
        }
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

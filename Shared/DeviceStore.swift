//
//  DeviceStore.swift
//  BeaconScanner
//

import Foundation

struct DeviceSnapshot: Identifiable {
    let id: UUID
    var name: String
    var rssi: Int
    var lastSeen: Date
}

/// Thread-safe device table updated at full BLE callback rate and read at UI refresh rate.
/// Isolation is via `lock`, not the main actor, so `didDiscover` never touches @Published state.
nonisolated final class DeviceStore: @unchecked Sendable {
    private let lock = NSLock()
    private var devicesByID: [UUID: DeviceSnapshot] = [:]
    private var sampleCount = 0

    func record(id: UUID, name: String, rssi: Int) {
        lock.lock()
        defer { lock.unlock() }
        sampleCount += 1
        if var existing = devicesByID[id] {
            existing.name = name
            existing.rssi = rssi
            existing.lastSeen = Date()
            devicesByID[id] = existing
        } else {
            devicesByID[id] = DeviceSnapshot(id: id, name: name, rssi: rssi, lastSeen: Date())
        }
    }

    func snapshot() -> (devices: [DeviceSnapshot], sampleCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        let sorted = devicesByID.values.sorted { $0.rssi > $1.rssi }
        return (sorted, sampleCount)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        devicesByID.removeAll()
        sampleCount = 0
    }
}

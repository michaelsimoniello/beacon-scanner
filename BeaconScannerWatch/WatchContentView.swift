//
//  WatchContentView.swift
//  BeaconScannerWatch
//

import SwiftUI

struct WatchContentView: View {
    @StateObject private var scanner = WatchScanner()
    @State private var label = "watch_baseline"

    private static let labelPresets = ["watch_baseline", "watch_pickup_test"]

    private var beacons: [DeviceSnapshot] {
        scanner.devices.filter { $0.name.hasPrefix("BCPro_") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if scanner.isScanning {
                    Text("\(beacons.count) beacons · \(scanner.sampleCount) samples")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Label", selection: $label) {
                        ForEach(Self.labelPresets, id: \.self) { preset in
                            Text(preset.replacingOccurrences(of: "watch_", with: ""))
                        }
                    }
                    .frame(height: 44)
                }

                ForEach(beacons) { device in
                    HStack {
                        Text(device.name.replacingOccurrences(of: "BCPro_", with: ""))
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Text("\(device.rssi)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(device.rssi > -70 ? .green : .yellow)
                    }
                }

                Button(scanner.isScanning ? "Stop" : "Start") {
                    if scanner.isScanning {
                        scanner.stopScanning()
                    } else {
                        scanner.startScanning(label: label)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(scanner.isScanning ? .red : .green)

                Text(scanner.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WatchContentView()
}

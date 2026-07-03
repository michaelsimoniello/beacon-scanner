//
//  ContentView.swift
//  BeaconScanner
//
//  Created by Student on 6/18/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = BluetoothScanner()

    var body: some View {
        NavigationStack {
            List(scanner.devices) { device in
                HStack {
                    VStack(alignment: .leading) {
                        Text(device.name)
                            .font(.headline)
                        Text(device.id.uuidString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(device.rssi) dBm")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(rssiColor(for: device.rssi))
                }
            }
            .overlay {
                if scanner.devices.isEmpty {
                    ContentUnavailableView(
                        scanner.isScanning ? "Scanning for devices..." : "No devices found",
                        systemImage: "dot.radiowaves.left.and.right"
                    )
                }
            }
            .navigationTitle("Nearby Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(scanner.isScanning ? "Stop" : "Start") {
                        scanner.isScanning ? scanner.stopScanning() : scanner.startScanning()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(scanner.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
        .onAppear {
            scanner.startScanning()
        }
    }

    private func rssiColor(for rssi: Int) -> Color {
        switch rssi {
        case -50...0: return .green
        case -70..<(-50): return .yellow
        default: return .red
        }
    }
}

#Preview {
    ContentView()
}

//
//  ContentView.swift
//  BeaconScanner
//
//  Created by Student on 6/18/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = BluetoothScanner()
    @StateObject private var watchInbox = WatchSessionInbox()
    @State private var label = ""
    @State private var beaconsOnly = false
    @State private var isSharePresented = false

    private var filteredDevices: [DiscoveredDevice] {
        beaconsOnly ? scanner.devices.filter { $0.name.hasPrefix("BCPro_") } : scanner.devices
    }

    /// Most recent session CSV: the last one recorded here or received from the watch.
    private var exportURL: URL? {
        let candidates = [scanner.lastSessionURL, watchInbox.lastReceivedURL].compactMap { $0 }
        return candidates.max { modificationDate($0) < modificationDate($1) }
    }

    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Session label", text: $label)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .disabled(scanner.isScanning)

                    Toggle("Show BCPro_ beacons only", isOn: $beaconsOnly)

                    Text("Samples this session: \(scanner.sampleCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()

                List(filteredDevices) { device in
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
                    if filteredDevices.isEmpty {
                        ContentUnavailableView(
                            scanner.isScanning ? "Scanning for devices..." : "No devices found",
                            systemImage: "dot.radiowaves.left.and.right"
                        )
                    }
                }
            }
            .navigationTitle("Nearby Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(scanner.isScanning ? "Stop" : "Start") {
                        if scanner.isScanning {
                            scanner.stopScanning()
                        } else {
                            scanner.startScanning(label: label)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        isSharePresented = true
                    } label: {
                        Label("Export Last Session", systemImage: "square.and.arrow.up")
                    }
                    .disabled(scanner.isScanning || exportURL == nil)

                    Text(scanner.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                .padding(.horizontal)
            }
            .sheet(isPresented: $isSharePresented) {
                if let url = exportURL {
                    ActivityView(activityItems: [url])
                }
            }
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

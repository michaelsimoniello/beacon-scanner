//
//  WatchConnectivityTransfer.swift
//  BeaconScannerWatch
//

import Foundation
import WatchConnectivity

/// Watch-side WCSession wrapper: ships finished session CSVs to the paired
/// iPhone via background file transfer. Delegate callbacks arrive on arbitrary
/// queues; `onStatus` is set once at init and never mutated afterwards.
nonisolated final class WatchConnectivityTransfer: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onStatus: @Sendable (String) -> Void

    init(onStatus: @escaping @Sendable (String) -> Void) {
        self.onStatus = onStatus
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func transfer(fileURL: URL) {
        WCSession.default.transferFile(fileURL, metadata: ["filename": fileURL.lastPathComponent])
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            onStatus("WCSession error: \(error.localizedDescription)")
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        if let error {
            onStatus("Transfer failed: \(error.localizedDescription)")
        } else {
            onStatus("Sent \(name) to iPhone")
        }
    }
}

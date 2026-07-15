//
//  PhoneConnectivityReceiver.swift
//  BeaconScanner
//

import Combine
import Foundation
import WatchConnectivity

/// iOS-side WCSession receiver: saves session CSVs transferred from the watch
/// into Documents so the existing share-sheet export can AirDrop them.
/// Delegate callbacks arrive on arbitrary queues; `onFileReceived` is set once
/// at init and never mutated afterwards.
nonisolated final class PhoneConnectivityReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    private let onFileReceived: @Sendable (URL) -> Void

    init(onFileReceived: @escaping @Sendable (URL) -> Void) {
        self.onFileReceived = onFileReceived
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let filename = (file.metadata?["filename"] as? String) ?? file.fileURL.lastPathComponent
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)
        do {
            // Must move before returning: the system deletes file.fileURL afterwards.
            try FileManager.default.moveItem(at: file.fileURL, to: destination)
            onFileReceived(destination)
        } catch {
            print("Failed to save watch session file: \(error)")
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

/// Main-actor facade the UI observes: exposes the most recent CSV received
/// from the watch and owns the receiver's lifetime.
@MainActor
final class WatchSessionInbox: ObservableObject {
    @Published var lastReceivedURL: URL?

    private var receiver: PhoneConnectivityReceiver!

    init() {
        receiver = PhoneConnectivityReceiver { url in
            Task { @MainActor [weak self] in
                self?.lastReceivedURL = url
            }
        }
        receiver.activate()
    }
}

//
//  CSVSessionLogger.swift
//  BeaconScanner
//

import Foundation

/// Serial-queue-isolated CSV writer. All row construction and file I/O happens on `queue`,
/// off both the main actor and the CoreBluetooth delegate queue, so BLE callbacks never block on disk.
nonisolated final class CSVSessionLogger: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.beaconscanner.csvlogger")
    private var fileHandle: FileHandle?
    private var buffer = Data()
    private var sessionLabel = "unlabeled"
    private let flushThreshold = 16 * 1024

    private let urlLock = NSLock()
    private var _currentSessionURL: URL?

    var currentSessionURL: URL? {
        urlLock.lock()
        defer { urlLock.unlock() }
        return _currentSessionURL
    }

    @discardableResult
    func startSession(label: String) -> URL {
        let sanitized = Self.sanitize(label)
        let timestamp = Self.timestampFormatter.string(from: Date())
        let filename = "session_\(sanitized)_\(timestamp).csv"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try? FileHandle(forWritingTo: url)

        queue.sync {
            fileHandle = handle
            sessionLabel = sanitized
            buffer.removeAll(keepingCapacity: true)
            let header = "timestamp_ms,peripheral_id,name,rssi,session_label\n"
            fileHandle?.write(Data(header.utf8))
        }

        urlLock.lock()
        _currentSessionURL = url
        urlLock.unlock()

        return url
    }

    func log(timestampMs: Int64, peripheralID: String, name: String, rssi: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            let row = "\(timestampMs),\(peripheralID),\(Self.csvEscape(name)),\(rssi),\(Self.csvEscape(self.sessionLabel))\n"
            self.buffer.append(contentsOf: row.utf8)
            if self.buffer.count >= self.flushThreshold {
                self.fileHandle?.write(self.buffer)
                self.buffer.removeAll(keepingCapacity: true)
            }
        }
    }

    func endSession() {
        queue.sync {
            if !buffer.isEmpty {
                fileHandle?.write(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
            try? fileHandle?.close()
            fileHandle = nil
        }
    }

    private static func sanitize(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "unlabeled" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return cleaned.isEmpty ? "unlabeled" : cleaned
    }

    private static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

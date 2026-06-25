import AppKit
import Foundation

enum AppLogger {
    static let logDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("YouTalkingToMe/logs", isDirectory: true)
    }()

    static let logFileURL = logDirectory.appendingPathComponent("youtalkingtome.log")

    private static let queue = DispatchQueue(label: "AppLogger.queue")
    private nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    static func error(_ message: String, error: Error? = nil) {
        if let error {
            write(level: "ERROR", message: "\(message) | \(String(describing: error))")
        } else {
            write(level: "ERROR", message: message)
        }
    }

    static func debug(_ message: String) {
        write(level: "DEBUG", message: message)
    }

    static func revealInFinder() {
        ensureDirectoryExists()
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            try? "You Talking To Me log file\n".data(using: .utf8)?.write(to: logFileURL)
        }
        NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
    }

    private static func write(level: String, message: String) {
        queue.async {
            ensureDirectoryExists()
            let timestamp = dateFormatter.string(from: Date())
            let line = "[\(timestamp)] [\(level)] \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: logFileURL)
            }

            #if DEBUG
            print(line, terminator: "")
            #endif
        }
    }

    private static func ensureDirectoryExists() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }
}

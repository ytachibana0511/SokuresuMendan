import Foundation

final class AppRuntimeLogger {
    static let shared = AppRuntimeLogger()

    let logFileURL: URL
    var logFilePath: String { logFileURL.path }

    private let queue = DispatchQueue(label: "SokuresuMendan.AppRuntimeLogger")
    private let formatter: ISO8601DateFormatter

    private init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let logDir = baseDir
            .appendingPathComponent("SokuresuMendan", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        logFileURL = logDir.appendingPathComponent("runtime.log", isDirectory: false)

        queue.async {
            if !FileManager.default.fileExists(atPath: self.logFilePath) {
                FileManager.default.createFile(atPath: self.logFilePath, contents: nil)
            }
        }
    }

    func log(_ category: String, _ message: String) {
        let timestamp = formatter.string(from: .now)
        let sanitizedMessage = message.replacingOccurrences(of: "\n", with: " ")
        let line = "[\(timestamp)] [\(category)] \(sanitizedMessage)\n"

        queue.async {
            self.rotateIfNeeded(maxBytes: 1_200_000)
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // logging must never crash the app
                }
                return
            }
            try? data.write(to: self.logFileURL)
        }
    }

    func clear() {
        queue.async {
            try? Data().write(to: self.logFileURL)
        }
    }

    private func rotateIfNeeded(maxBytes: UInt64) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFilePath),
              let fileSize = attrs[.size] as? UInt64,
              fileSize > maxBytes
        else {
            return
        }

        let rotated = logFileURL
            .deletingPathExtension()
            .appendingPathExtension("old.log")

        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: logFileURL, to: rotated)
        FileManager.default.createFile(atPath: logFilePath, contents: nil)
    }
}

import CryptoKit
import Foundation

final class ProfileStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport.appendingPathComponent("SokuresuMendan", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        fileURL = folder.appendingPathComponent("profiles.enc")
    }

    func loadProfiles() -> [CandidateProfile] {
        guard let encrypted = try? Data(contentsOf: fileURL) else {
            return []
        }
        do {
            let key = try KeychainHelper.loadOrCreateSymmetricKey()
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let decrypted = try AES.GCM.open(box, using: key)
            return try decoder.decode([CandidateProfile].self, from: decrypted)
        } catch {
            return []
        }
    }

    func saveProfiles(_ profiles: [CandidateProfile]) throws {
        let plaintext = try encoder.encode(profiles)
        let key = try KeychainHelper.loadOrCreateSymmetricKey()
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw NSError(domain: "ProfileStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "暗号化データを構築できませんでした。"
            ])
        }
        try combined.write(to: fileURL, options: .atomic)
    }

    func importProfile(name: String, rawText: String) -> CandidateProfile {
        let normalized = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = buildSummary(from: normalized)
        let keywords = buildKeywords(from: normalized)
        return CandidateProfile(
            id: UUID(),
            name: name,
            rawText: normalized,
            summary: summary,
            keywords: keywords,
            updatedAt: .now
        )
    }

    private func buildSummary(from raw: String) -> String {
        guard !raw.isEmpty else { return "" }
        let lines = raw
            .split(whereSeparator: { $0 == "\n" || $0 == "。" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let summary = lines.prefix(4).joined(separator: "。")
        let clipped = String(summary.prefix(320))
        return clipped
    }

    private func buildKeywords(from raw: String) -> [String] {
        let stopWords = Set(["です", "ます", "こと", "する", "ある", "いる", "そして", "また", "the", "and"])
        let tokens = raw
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }

        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .prefix(20)
            .map { $0.key }
    }
}

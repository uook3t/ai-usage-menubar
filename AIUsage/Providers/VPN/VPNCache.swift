import CryptoKit
import Foundation

struct VPNCache: Codable {
    let fingerprint: String
    let usage: ResourceUsage
    let fetchedAt: Date

    static func fingerprint(_ endpoint: String) -> String {
        SHA256.hash(data: Data(endpoint.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func load(endpoint: String, defaults: UserDefaults = .standard) -> ProviderSnapshot? {
        guard let data = defaults.data(forKey: "vpn.lastGood"),
              let cache = try? JSONDecoder().decode(Self.self, from: data),
              cache.fingerprint == fingerprint(endpoint), cache.usage.isValid else { return nil }
        var snapshot = ProviderSnapshot(provider: .vpn, planName: "JustMySocks", windows: [
            QuotaWindow(kind: .totalUsage, usedPercent: cache.usage.usedPercent, resetsAt: nil)
        ], fetchedAt: cache.fetchedAt)
        snapshot.resourceUsage = cache.usage
        return snapshot
    }
    static func save(_ snapshot: ProviderSnapshot, endpoint: String, defaults: UserDefaults = .standard) {
        guard let usage = snapshot.resourceUsage else { return }
        let cache = Self(fingerprint: fingerprint(endpoint), usage: usage, fetchedAt: snapshot.fetchedAt)
        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: "vpn.lastGood") }
    }
}

import Foundation

/// A bounded resource in its base unit; adapters choose display units.
/// Other resource providers can reuse this without pretending usage is money.
struct ResourceUsage: Codable, Equatable, Sendable {
    let used: Double
    let limit: Double
    let unit: String
    let divisor: Double
    let resetDay: Int?

    var usedPercent: Double { used / limit * 100 }
    var remaining: Double { max(limit - used, 0) }
    var overage: Double { max(used - limit, 0) }
    var fraction: Double { min(max(usedPercent / 100, 0), 1) }
    var isValid: Bool {
        used.isFinite && used >= 0 && limit.isFinite && limit > 0 &&
        divisor.isFinite && divisor > 0 && usedPercent.isFinite &&
        (resetDay == nil || (1...31).contains(resetDay!))
    }
    func formatted(_ value: Double) -> String {
        "\((value / divisor).formatted(.number.precision(.fractionLength(2)))) \(unit)"
    }
}

enum VPNEndpoint {
    static func validate(_ text: String) throws -> URL {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !input.contains(where: { $0.isWhitespace }),
              let url = URL(string: input), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw ProviderFailure(.invalidResponse, "请输入有效的 HTTPS 查询地址。")
        }
        return url
    }
}

struct VPNProvider: UsageProvider {
    let id: ProviderID = .vpn
    var client: any HTTPClient = VPNHTTPClient()
    var readEndpoint: @Sendable () throws -> String? = { UserDefaults.standard.string(forKey: "vpn.url") }

    func fetch() async throws -> ProviderSnapshot {
        guard let endpoint = try readEndpoint(), !endpoint.isEmpty else {
            throw ProviderFailure(.invalidResponse, "请在设置中填写 VPN 查询地址。")
        }
        let response: HTTPResponse
        do {
            response = try await client.send(HTTPRequest(method: .get, url: VPNEndpoint.validate(endpoint)))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // URLSession errors may contain the secret query URL.
            throw ProviderFailure(.transient, "VPN 查询失败，请检查网络和查询地址。")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderFailure(.transient, "VPN 查询失败（HTTP \(response.statusCode)）。")
        }
        return try Self.decode(response.body, fetchedAt: Date())
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> ProviderSnapshot {
        struct Payload: Decodable {
            let monthly_bw_limit_b: Double
            let bw_counter_b: Double
            let bw_reset_day_of_month: Int?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ProviderFailure(.invalidResponse, "VPN 返回的数据格式不正确。")
        }
        let resource = ResourceUsage(used: payload.bw_counter_b, limit: payload.monthly_bw_limit_b,
                                     unit: "GB", divisor: 1_000_000_000, resetDay: payload.bw_reset_day_of_month)
        guard resource.isValid else {
            throw ProviderFailure(.invalidResponse, "VPN 返回的额度或已用量无效。")
        }
        var snapshot = ProviderSnapshot(provider: .vpn, planName: "JustMySocks", windows: [
            QuotaWindow(kind: .totalUsage, usedPercent: resource.usedPercent, resetsAt: nil)
        ], fetchedAt: fetchedAt)
        snapshot.resourceUsage = resource
        return snapshot
    }
}

/// Query credentials never follow a redirect; the URL must be the final endpoint.
final class VPNHTTPClient: NSObject, HTTPClient, URLSessionTaskDelegate, @unchecked Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderFailure(.invalidResponse, "VPN 返回了无效的响应。")
        }
        return HTTPResponse(statusCode: http.statusCode, headers: [:], body: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

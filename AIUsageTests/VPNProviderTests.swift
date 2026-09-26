import Foundation
import XCTest
@testable import AIUsage

final class VPNProviderTests: XCTestCase {
    private let valid = Data(#"{"monthly_bw_limit_b":500000000000,"bw_counter_b":7930000000,"bw_reset_day_of_month":5}"#.utf8)

    func testRealPayloadAndDecimalUnits() throws {
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .distantPast)
        let usage = try XCTUnwrap(snapshot.resourceUsage)
        XCTAssertEqual(usage.usedPercent, 1.586, accuracy: 0.0001)
        XCTAssertEqual(usage.used / usage.divisor, 7.93)
        XCTAssertEqual(usage.resetDay, 5)
        guard case .percentage(let percent) = snapshot.menuBarValue(for: .totalUsage, displayMode: .remaining) else {
            return XCTFail("Expected percentage")
        }
        XCTAssertEqual(percent, 1.586, accuracy: 0.0001)
    }

    func testOverageAndInvalidPayloads() throws {
        let over = try VPNProvider.decode(Data(#"{"monthly_bw_limit_b":100,"bw_counter_b":120}"#.utf8), fetchedAt: .now)
        XCTAssertEqual(over.resourceUsage?.usedPercent, 120)
        XCTAssertEqual(over.resourceUsage?.remaining, 0)
        XCTAssertEqual(over.resourceUsage?.overage, 20)
        XCTAssertEqual(over.resourceUsage?.fraction, 1)
        for json in [#"{"monthly_bw_limit_b":0,"bw_counter_b":0}"#, #"{"monthly_bw_limit_b":100,"bw_counter_b":-1}"#, #"{"monthly_bw_limit_b":100,"bw_counter_b":1,"bw_reset_day_of_month":32}"#, #"{"error":"invalid token"}"#] {
            XCTAssertThrowsError(try VPNProvider.decode(Data(json.utf8), fetchedAt: .now))
        }
    }

    func testURLValidation() throws {
        XCTAssertEqual(try VPNEndpoint.validate(" https://example.com/?id=test \n").host, "example.com")
        for url in ["http://example.com", "file:///etc/passwd", "https://user:pass@example.com", "https://example.com/#fragment", "", "https://example.com/ a"] {
            XCTAssertThrowsError(try VPNEndpoint.validate(url))
        }
    }

    func testFetchAcceptsJSONDespiteHTMLContentType() async throws {
        let client = MockHTTPClient([HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html"], body: valid)])
        let provider = VPNProvider(client: client, readEndpoint: { "https://example.com/usage?id=secret" })
        let result = try await provider.fetch()
        XCTAssertEqual(result.provider, .vpn)
        let requests = await client.capturedRequests()
        XCTAssertEqual(requests.first?.method, .get)
    }

    func testHTTPFailureDoesNotExposeSecret() async {
        let client = MockHTTPClient([HTTPResponse(statusCode: 403, headers: [:], body: Data("secret".utf8))])
        do {
            _ = try await VPNProvider(client: client, readEndpoint: { "https://example.com/?id=secret" }).fetch()
            XCTFail("Expected HTTP failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("secret"))
            XCTAssertTrue(error.localizedDescription.contains("403"))
        }
    }

    func testCacheBoundToEndpointAndContainsNoSecret() throws {
        let suite = "VPNCacheTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .distantPast)
        VPNCache.save(snapshot, endpoint: "https://example.com/?secret=private", defaults: defaults)
        XCTAssertEqual(VPNCache.load(endpoint: "https://example.com/?secret=private", defaults: defaults), snapshot)
        XCTAssertNil(VPNCache.load(endpoint: "https://example.com/?secret=other", defaults: defaults))
        let data = try XCTUnwrap(defaults.data(forKey: "vpn.lastGood"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private"))
    }

    @MainActor
    func testFailurePreservesLastGoodAndMenuShowsUsed() async throws {
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .now)
        let provider = SequencedProvider(id: .vpn, results: [.success(snapshot), .failure(ProviderFailure(.transient, "HTTP 500"))])
        let store = UsageStore(providers: [provider])
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(store.states[.vpn]?.snapshot, snapshot)
        XCTAssertEqual(store.states[.vpn]?.isStale, true)
        let reading = try XCTUnwrap(store.menuBarReading(for: MenuBarItemID(provider: .vpn, metric: .totalUsage), displayMode: .remaining))
        XCTAssertEqual(reading.displayMode, .used)
        XCTAssertEqual(MenuBarPresentation(reading: reading).valueText, "1.6%")
    }

    @MainActor
    func testChangingEndpointClearsSnapshot() async throws {
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .now)
        let store = UsageStore(providers: [SequencedProvider(id: .vpn, results: [.success(snapshot)])])
        await store.refresh()
        store.configureVPN(name: "流量", intervalMinutes: 17, endpoint: "https://example.com/new")
        XCTAssertNil(store.states[.vpn]?.snapshot)
        XCTAssertEqual(store.vpnName, "流量")
        XCTAssertEqual(store.vpnIntervalMinutes, 17)
    }
    @MainActor
    func testLateResponseCannotRestorePreviousEndpointData() async throws {
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .now)
        let provider = SuspendedVPNProvider(snapshot: snapshot)
        let store = UsageStore(providers: [provider], availabilityChecker: FixedProviderAvailabilityChecker())
        let request = Task { await store.refresh() }
        await provider.waitUntilStarted()
        store.configureVPN(name: "VPN", intervalMinutes: 5, endpoint: "https://example.com/new")
        await provider.finish()
        await request.value
        XCTAssertNil(store.states[.vpn]?.snapshot)
        XCTAssertFalse(store.states[.vpn]?.isRefreshing ?? true)
    }

    @MainActor
    func testVPNPreferencesPersistWithOtherSettings() throws {
        let suite = "VPNPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppPreferences(defaults: defaults)
        settings.vpnURL = "https://example.com/?test=value"
        settings.vpnName = "流量"
        settings.vpnIntervalMinutes = 17
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.vpnURL, settings.vpnURL)
        XCTAssertEqual(restored.vpnDisplayName, "流量")
        XCTAssertEqual(restored.vpnIntervalMinutes, 17)
    }

}

private actor SuspendedVPNProvider: UsageProvider {
    nonisolated let id: ProviderID = .vpn
    let snapshot: ProviderSnapshot
    private var continuation: CheckedContinuation<ProviderSnapshot, Never>?
    private var startedWaiter: CheckedContinuation<Void, Never>?
    init(snapshot: ProviderSnapshot) { self.snapshot = snapshot }
    func fetch() async throws -> ProviderSnapshot {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startedWaiter?.resume()
            startedWaiter = nil
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startedWaiter = $0 }
    }
    func finish() {
        continuation?.resume(returning: snapshot)
        continuation = nil
    }
}

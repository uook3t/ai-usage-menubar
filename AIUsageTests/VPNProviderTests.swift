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
        XCTAssertEqual(percent, 98.414, accuracy: 0.0001)
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
    func testFailurePreservesLastGoodAndMenuFollowsDisplayMode() async throws {
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .now)
        let provider = SequencedProvider(id: .vpn, results: [.success(snapshot), .failure(ProviderFailure(.transient, "HTTP 500"))])
        let store = UsageStore(providers: [provider])
        await store.refresh()
        await store.refresh()
        XCTAssertEqual(store.states[.vpn]?.snapshot, snapshot)
        XCTAssertEqual(store.states[.vpn]?.isStale, true)
        let reading = try XCTUnwrap(store.menuBarReading(for: MenuBarItemID(provider: .vpn, metric: .totalUsage), displayMode: .remaining))
        XCTAssertEqual(reading.displayMode, .remaining)
        XCTAssertEqual(MenuBarPresentation(reading: reading).valueText, "98.4%")
        let used = try XCTUnwrap(store.menuBarReading(for: MenuBarItemID(provider: .vpn, metric: .totalUsage), displayMode: .used))
        XCTAssertEqual(MenuBarPresentation(reading: used).valueText, "1.6%")
    }

    @MainActor
    func testChangingEndpointClearsSnapshot() async throws {
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .now)
        let store = UsageStore(providers: [SequencedProvider(id: .vpn, results: [.success(snapshot)])])
        await store.refresh()
        store.configureVPN(name: "流量", endpoint: "https://example.com/new")
        XCTAssertNil(store.states[.vpn]?.snapshot)
        XCTAssertEqual(store.vpnName, "流量")
    }
    @MainActor
    func testLateResponseCannotRestorePreviousEndpointData() async throws {
        let snapshot = try VPNProvider.decode(valid, fetchedAt: .now)
        let provider = SuspendedVPNProvider(snapshot: snapshot)
        let store = UsageStore(providers: [provider], availabilityChecker: FixedProviderAvailabilityChecker())
        let request = Task { await store.refresh() }
        await provider.waitUntilStarted()
        store.configureVPN(name: "VPN", endpoint: "https://example.com/new")
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
        settings.vpnDisplayMode = .used
        settings.usageDisplayMode = .remaining
        settings.refreshInterval = .fifteenMinutes
        XCTAssertEqual(settings.menuBarOuterPadding, 0)
        XCTAssertEqual(settings.menuBarProviderSpacing, 8)
        settings.menuBarOuterPadding = 3
        settings.menuBarProviderSpacing = 12
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.vpnURL, settings.vpnURL)
        XCTAssertEqual(restored.vpnDisplayName, "流量")
        XCTAssertEqual(restored.vpnDisplayMode, .used)
        XCTAssertEqual(restored.usageDisplayMode, .remaining)
        XCTAssertEqual(restored.refreshInterval, .fifteenMinutes)
        XCTAssertEqual(restored.menuBarOuterPadding, 3)
        XCTAssertEqual(restored.menuBarProviderSpacing, 12)
    }

    @MainActor
    func testExistingSharedModeMigratesOnceWithoutChangingRefreshInterval() throws {
        let suite = "VPNMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("used", forKey: "usageDisplayMode")
        defaults.set("thirtyMinutes", forKey: "refreshInterval")
        defaults.set(17, forKey: "vpn.interval")
        let first = AppPreferences(defaults: defaults)
        XCTAssertEqual(first.vpnDisplayMode, .used)
        XCTAssertEqual(first.refreshInterval, .thirtyMinutes)
        XCTAssertNil(defaults.object(forKey: "vpn.interval"))
        first.usageDisplayMode = .remaining
        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.usageDisplayMode, .remaining)
        XCTAssertEqual(restored.vpnDisplayMode, .used)
    }

    @MainActor
    func testMixedAIAndVPNDisplayModesAreIndependent() async throws {
        let vpnSnapshot = try VPNProvider.decode(valid, fetchedAt: .now)
        let codexSnapshot = ProviderSnapshot(provider: .codex, planName: nil,
            windows: [QuotaWindow(kind: .weekly, usedPercent: 40, resetsAt: nil)], fetchedAt: .now)
        let store = UsageStore(providers: [
            SequencedProvider(id: .vpn, results: [.success(vpnSnapshot)]),
            SequencedProvider(id: .codex, results: [.success(codexSnapshot)])
        ], availabilityChecker: FixedProviderAvailabilityChecker())
        await store.refresh()
        let configurations = [MenuBarProviderConfiguration(provider: .codex, metrics: [.weekly]),
                              MenuBarProviderConfiguration(provider: .vpn, metrics: [.totalUsage])]
        let groups = store.menuBarProviderReadings(for: configurations, displayMode: .remaining, vpnDisplayMode: .used)
        XCTAssertEqual(groups[0].readings.first?.value, .percentage(60))
        XCTAssertEqual(groups[0].readings.first?.displayMode, .remaining)
        XCTAssertEqual(groups[1].readings.first?.displayMode, .used)
        XCTAssertEqual(MenuBarPresentation(reading: try XCTUnwrap(groups[1].readings.first)).valueText, "1.6%")
        let reversed = store.menuBarProviderReadings(for: configurations, displayMode: .used, vpnDisplayMode: .remaining)
        XCTAssertEqual(reversed[0].readings.first?.value, .percentage(40))
        XCTAssertEqual(MenuBarPresentation(reading: try XCTUnwrap(reversed[1].readings.first)).valueText, "98.4%")
    }

    @MainActor
    func testOneScheduledTickRefreshesBothAIAndVPN() async throws {
        let gate = RefreshTickGate()
        let vpn = CountingProvider(id: .vpn, result: .success(try VPNProvider.decode(valid, fetchedAt: .now)))
        let codex = CountingProvider(id: .codex, result: .success(ProviderSnapshot(provider: .codex, planName: nil,
            windows: [QuotaWindow(kind: .weekly, usedPercent: 40, resetsAt: nil)], fetchedAt: .now)))
        let store = UsageStore(providers: [codex, vpn], availabilityChecker: FixedProviderAvailabilityChecker(),
            refreshInterval: .fifteenMinutes, trackedProviderIDs: [.codex, .vpn], sleep: { await gate.sleep($0) })
        store.start()
        await gate.waitUntilSleeping()
        let firstVPN = await vpn.fetchCallCount()
        let firstAI = await codex.fetchCallCount()
        XCTAssertEqual(firstVPN, 1)
        XCTAssertEqual(firstAI, 1)
        await gate.advance()
        await gate.waitUntilSleeping()
        let secondVPN = await vpn.fetchCallCount()
        let secondAI = await codex.fetchCallCount()
        let durations = await gate.durations
        XCTAssertEqual(secondVPN, 2)
        XCTAssertEqual(secondAI, 2)
        XCTAssertEqual(durations, [.seconds(900), .seconds(900)])
        store.stop()
        await gate.advance()
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

private actor RefreshTickGate {
    private var sleeper: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var durations: [Duration] = []
    func sleep(_ duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { continuation in
            sleeper = continuation
            observer?.resume()
            observer = nil
        }
    }
    func waitUntilSleeping() async {
        if sleeper != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func advance() {
        sleeper?.resume()
        sleeper = nil
    }
}

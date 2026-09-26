import Foundation
import Observation

struct MenuBarReading: Equatable, Sendable {
    let provider: ProviderID
    let metric: MenuBarMetricID
    let value: MenuBarReadingValue
    let displayMode: UsageDisplayMode
    let isStale: Bool

    init(
        provider: ProviderID,
        metric: MenuBarMetricID,
        value: MenuBarReadingValue,
        displayMode: UsageDisplayMode,
        isStale: Bool
    ) {
        self.provider = provider
        self.metric = metric
        self.value = value
        self.displayMode = displayMode
        self.isStale = isStale
    }
}

struct MenuBarProviderReadings: Equatable, Identifiable, Sendable {
    let provider: ProviderID
    let selectedMetrics: [MenuBarMetricID]
    let readings: [MenuBarReading]

    var id: ProviderID { provider }
    var showsMetricLabels: Bool { selectedMetrics.count > 1 }
}

@MainActor
@Observable
final class UsageStore {
    private(set) var states: [ProviderID: ProviderState]
    private(set) var installedProviderIDs: Set<ProviderID>?
    private(set) var trackedProviderIDs: Set<ProviderID>
    private(set) var lastAttemptAt: Date?
    private(set) var lastSuccessfulRefreshAt: Date?
    private(set) var refreshInterval: RefreshIntervalOption

    var vpnName = "VPN"
    private(set) var vpnIntervalMinutes = 5
    private var vpnTask: Task<Void, Never>?
    private var vpnEndpoint: String?

    func configureVPN(name: String, intervalMinutes: Int, endpoint: String?, restoreCache: Bool = false) {
        vpnName = name
        let changed = vpnEndpoint != endpoint
        let intervalChanged = vpnIntervalMinutes != intervalMinutes
        vpnIntervalMinutes = min(max(intervalMinutes, 1), 60)
        vpnEndpoint = endpoint
        if changed {
            cancelRefresh()
            states[.vpn] = ProviderState(provider: .vpn)
            if restoreCache, let endpoint, let cached = VPNCache.load(endpoint: endpoint) {
                states[.vpn]?.snapshot = cached
                states[.vpn]?.failure = ProviderFailure(.transient, "显示上次成功数据，正在更新。")
            }
        }
        if cadenceTask != nil, changed || intervalChanged {
            vpnTask?.cancel()
            vpnTask = makeVPNTask(refreshImmediately: false)
        }
    }

    func resume() {
        guard cadenceTask == nil else { return }
        let aiStale = trackedProviderIDs.subtracting([.vpn]).contains { id in
            guard let date = states[id]?.snapshot?.fetchedAt else { return true }
            return Date().timeIntervalSince(date) >= Double(refreshInterval.duration.components.seconds)
        }
        cadenceTask = makeCadenceTask(refreshImmediately: aiStale, initialProviderIDs: trackedProviderIDs.subtracting([.vpn]))
        let vpnStale = states[.vpn]?.snapshot.map {
            Date().timeIntervalSince($0.fetchedAt) >= Double(vpnIntervalMinutes * 60)
        } ?? true
        vpnTask = makeVPNTask(refreshImmediately: vpnStale)
    }

    private let providers: [any UsageProvider]
    private let availabilityChecker: any ProviderAvailabilityChecking
    private var cadenceTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        providers: [any UsageProvider] = [
            ClaudeProvider(),
            CodexProvider(),
            CursorProvider(),
            AntigravityProvider(),
            CopilotProvider(),
            DevinProvider(),
            GrokProvider(),
            VPNProvider()
        ],
        availabilityChecker: any ProviderAvailabilityChecking =
            SystemProviderAvailabilityChecker(),
        refreshInterval: RefreshIntervalOption = .fiveMinutes,
        trackedProviderIDs: Set<ProviderID> = Set(ProviderID.allCases)
    ) {
        self.providers = providers
        self.availabilityChecker = availabilityChecker
        self.refreshInterval = refreshInterval
        self.trackedProviderIDs = trackedProviderIDs
        states = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, ProviderState(provider: $0))
        })
    }

    func start() {
        guard cadenceTask == nil else { return }
        LoginShellEnvironment.shared.prewarm()
        cadenceTask = makeCadenceTask(refreshImmediately: true)
        vpnTask = makeVPNTask(refreshImmediately: false)
    }

    func stop() {
        vpnTask?.cancel()
        vpnTask = nil
        cadenceTask?.cancel()
        cadenceTask = nil
        cancelRefresh()
    }

    func setTrackedProviders(_ providers: Set<ProviderID>) {
        guard trackedProviderIDs != providers else { return }

        let newlyEnabled = providers.subtracting(trackedProviderIDs)
        trackedProviderIDs = providers
        for provider in ProviderID.allCases where !providers.contains(provider) {
            states[provider]?.isRefreshing = false
        }

        guard cadenceTask != nil else { return }
        cadenceTask?.cancel()
        cadenceTask = nil
        cancelRefresh()
        cadenceTask = makeCadenceTask(
            refreshImmediately: !newlyEnabled.isEmpty,
            initialProviderIDs: newlyEnabled.isEmpty ? nil : newlyEnabled
        )
    }

    func setRefreshInterval(_ interval: RefreshIntervalOption) {
        guard refreshInterval != interval else { return }
        refreshInterval = interval

        guard cadenceTask != nil else { return }
        cadenceTask?.cancel()
        cadenceTask = makeCadenceTask(refreshImmediately: false)
    }

    func refreshNow() {
        cadenceTask?.cancel()
        cadenceTask = nil
        cancelRefresh()
        cadenceTask = makeCadenceTask(refreshImmediately: true)
    }

    func refresh(providerIDs requestedProviderIDs: Set<ProviderID>? = nil, afterCurrent: Bool = false) async {
        while let activeTask = refreshTask {
            let activeGeneration = refreshGeneration
            await activeTask.value
            guard !Task.isCancelled else { return }
            if !afterCurrent { return }
            if activeGeneration == refreshGeneration { refreshTask = nil }
        }

        refreshGeneration += 1
        let generation = refreshGeneration
        let providers = self.providers
        let trackedProviderIDs = self.trackedProviderIDs
        let availabilityChecker = self.availabilityChecker
        let task = Task { [weak self] in
            let installedProviders =
                await availabilityChecker.installedProviders()
            guard !Task.isCancelled else { return }

            self?.applyInstalledProviders(installedProviders)

            let requested = requestedProviderIDs ?? trackedProviderIDs
            let effectiveProviders = providers.filter { provider in
                trackedProviderIDs.contains(provider.id) &&
                    requested.contains(provider.id) &&
                    (installedProviders?.contains(provider.id) ?? true)
            }

            for provider in effectiveProviders {
                self?.states[provider.id]?.isRefreshing = true
            }

            let fetchResults = await withTaskGroup(
                of: FetchResult.self
            ) { group in
                for provider in effectiveProviders {
                    group.addTask {
                        do {
                            return FetchResult(
                                provider: provider.id,
                                result: .success(try await provider.fetch())
                            )
                        } catch let failure as ProviderFailure {
                            return FetchResult(
                                provider: provider.id,
                                result: .failure(failure)
                            )
                        } catch {
                            return FetchResult(
                                provider: provider.id,
                                result: .failure(ProviderFailure(
                                    .transient,
                                    "\(provider.id.displayName) could not be refreshed."
                                ))
                            )
                        }
                    }
                }

                var results: [FetchResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            guard !Task.isCancelled else { return }
            self?.applyFetchResults(fetchResults)
        }
        refreshTask = task
        await task.value
        if generation == refreshGeneration {
            refreshTask = nil
        }
    }

    func isProviderVisibleInDashboard(_ provider: ProviderID) -> Bool {
        trackedProviderIDs.contains(provider) &&
            states[provider]?.isToolInstalled != false
    }

    func availableMenuBarItems(
        for provider: ProviderID
    ) -> [MenuBarItemID] {
        guard trackedProviderIDs.contains(provider),
              states[provider]?.isToolInstalled != false else {
            return []
        }
        if provider == .vpn { return [MenuBarItemID(provider: .vpn, metric: .totalUsage)] }
        return states[provider]?.snapshot?.availableMenuBarItems ?? []
    }

    var availableMenuBarItemsByProvider:
        [ProviderID: [MenuBarItemID]] {
        Dictionary(uniqueKeysWithValues: ProviderID.allCases.map {
            ($0, availableMenuBarItems(for: $0))
        })
    }

    func isMenuBarItemAvailable(_ item: MenuBarItemID) -> Bool {
        availableMenuBarItems(for: item.provider).contains(item)
    }

    func menuBarReadings(
        for items: [MenuBarItemID],
        displayMode: UsageDisplayMode = .used
    ) -> [MenuBarReading] {
        items.compactMap { item in
            guard trackedProviderIDs.contains(item.provider),
                  let state = states[item.provider],
                  state.isToolInstalled != false,
                  let value = state.snapshot?.menuBarValue(
                    for: item.metric,
                    displayMode: displayMode
                  ) else {
                return nil
            }

            return MenuBarReading(
                provider: item.provider,
                metric: item.metric,
                value: value,
                displayMode: item.provider == .vpn ? .used : displayMode,
                isStale: state.isStale
            )
        }
    }

    func menuBarProviderReadings(
        for configurations: [MenuBarProviderConfiguration],
        displayMode: UsageDisplayMode = .used
    ) -> [MenuBarProviderReadings] {
        configurations.compactMap { configuration in
            guard trackedProviderIDs.contains(configuration.provider),
                  let state = states[configuration.provider],
                  state.isToolInstalled != false else {
                return nil
            }

            let items = configuration.metrics.map {
                MenuBarItemID(
                    provider: configuration.provider,
                    metric: $0
                )
            }
            return MenuBarProviderReadings(
                provider: configuration.provider,
                selectedMetrics: configuration.metrics,
                readings: menuBarReadings(
                    for: items,
                    displayMode: displayMode
                )
            )
        }
    }

    func menuBarReading(
        for item: MenuBarItemID,
        displayMode: UsageDisplayMode = .used
    ) -> MenuBarReading? {
        menuBarReadings(for: [item], displayMode: displayMode).first
    }

    private func applyInstalledProviders(_ installedProviders: Set<ProviderID>?) {
        installedProviderIDs = installedProviders
        guard let installedProviders else { return }

        for provider in ProviderID.allCases {
            states[provider]?.isToolInstalled =
                installedProviders.contains(provider)
            if !installedProviders.contains(provider) {
                states[provider]?.isRefreshing = false
            }
        }
    }

    private func applyFetchResults(_ fetchResults: [FetchResult]) {
        lastAttemptAt = Date()
        var successfulDates: [Date] = []

        for fetchResult in fetchResults {
            guard trackedProviderIDs.contains(fetchResult.provider) else {
                continue
            }

            var state =
                states[fetchResult.provider] ??
                ProviderState(provider: fetchResult.provider)
            state.isRefreshing = false
            switch fetchResult.result {
            case .success(let snapshot):
                state.snapshot = snapshot
                state.failure = nil
                successfulDates.append(snapshot.fetchedAt)
                if snapshot.provider == .vpn, let vpnEndpoint {
                    VPNCache.save(snapshot, endpoint: vpnEndpoint)
                }
            case .failure(let failure):
                if !failure.preservesLastGood {
                    state.snapshot = nil
                }
                state.failure = failure
            }
            states[fetchResult.provider] = state
        }

        if let latest = successfulDates.max() {
            lastSuccessfulRefreshAt = latest
        }
    }

    private func cancelRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        for id in ProviderID.allCases { states[id]?.isRefreshing = false }
    }

    private func makeVPNTask(refreshImmediately: Bool) -> Task<Void, Never> {
        let seconds = vpnIntervalMinutes * 60
        return Task { [weak self] in
            if refreshImmediately { await self?.refresh(providerIDs: [.vpn], afterCurrent: true) }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                guard !Task.isCancelled else { return }
                await self?.refresh(providerIDs: [.vpn], afterCurrent: true)
            }
        }
    }

    private func makeCadenceTask(
        refreshImmediately: Bool,
        initialProviderIDs: Set<ProviderID>? = nil
    ) -> Task<Void, Never> {
        let duration = refreshInterval.duration
        return Task { [weak self, duration] in
            if refreshImmediately {
                await self?.refresh(providerIDs: initialProviderIDs)
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.refresh(providerIDs: self?.trackedProviderIDs.subtracting([.vpn]))
            }
        }
    }
}

private struct FetchResult: Sendable {
    let provider: ProviderID
    let result: Result<ProviderSnapshot, ProviderFailure>
}

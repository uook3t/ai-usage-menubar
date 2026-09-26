import AppKit
import Observation
import SwiftUI

@MainActor
protocol ApplicationActivating: AnyObject {
    func activate()
}

extension NSApplication: ApplicationActivating {}

struct PanelToggleGate {
    private(set) var suppressesNextToggle = false

    mutating func panelDidClose() {
        suppressesNextToggle = true
    }

    mutating func consumeSuppression() -> Bool {
        guard suppressesNextToggle else { return false }
        suppressesNextToggle = false
        return true
    }

    mutating func clearSuppression() {
        suppressesNextToggle = false
    }
}

@MainActor
enum MenuBarStatusImageRenderer {
    private static let iconSize: CGFloat = 15
    private static let iconTextSpacing: CGFloat = 3
    private static let labelValueSpacing: CGFloat = 1
    private static let separatorSpacing: CGFloat = 3
    private static let staleSpacing: CGFloat = 1
    private static let suffixSpacing: CGFloat = 1
    private static let microLabelRaise: CGFloat = 2
    private static let providerSpacing: CGFloat = 9

    private struct TextRun {
        let text: String
        let size: NSSize

        var width: CGFloat { ceil(size.width) }
    }

    private struct MetricRun {
        let label: TextRun?
        let value: TextRun
        let staleIndicator: TextRun?
        let width: CGFloat
    }

    static func image(
        for groups: [MenuBarProviderReadings],
        font: NSFont
    ) -> NSImage {
        let microFont = NSFont.systemFont(
            ofSize: max(8, floor(font.pointSize * 0.62)),
            weight: .semibold
        )
        let separator = textRun("·", font: microFont)
        let entries = groups.map { group in
            let presentation = MenuBarProviderPresentation(group: group)
            let metrics = presentation.metrics.map { metric in
                let label = metric.label.map {
                    textRun($0, font: microFont)
                }
                let value = textRun(metric.valueText, font: font)
                let staleIndicator = metric.showsStaleIndicator
                    ? textRun("⚠︎", font: microFont)
                    : nil
                return MetricRun(
                    label: label,
                    value: value,
                    staleIndicator: staleIndicator,
                    width:
                        (label?.width ?? 0) +
                        (label == nil ? 0 : labelValueSpacing) +
                        value.width +
                        (staleIndicator == nil ? 0 : staleSpacing) +
                        (staleIndicator?.width ?? 0)
                )
            }
            let separatorsWidth =
                (separator.width + separatorSpacing * 2) *
                CGFloat(max(metrics.count - 1, 0))
            let suffix = presentation.sharedSuffix.map {
                textRun($0, font: microFont)
            }
            let valuesWidth =
                metrics.map(\.width).reduce(0, +) +
                separatorsWidth +
                (suffix == nil ? 0 : suffixSpacing) +
                (suffix?.width ?? 0)
            let width = iconSize + (
                metrics.isEmpty ? 0 : iconTextSpacing + ceil(valuesWidth)
            )
            return (
                provider: group.provider,
                metrics: metrics,
                suffix: suffix,
                width: width
            )
        }
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let microAttributes: [NSAttributedString.Key: Any] = [
            .font: microFont,
            .foregroundColor: NSColor.black
        ]
        let width = entries.map(\.width).reduce(0, +) +
            providerSpacing * CGFloat(max(entries.count - 1, 0))
        let height = max(
            iconSize,
            ceil(font.ascender - font.descender + font.leading),
            ceil(
                microFont.ascender -
                    microFont.descender +
                    microFont.leading +
                    microLabelRaise
            )
        )

        let image = NSImage(
            size: NSSize(width: ceil(width), height: ceil(height)),
            flipped: false
        ) { destination in
            var x = destination.minX

            for (index, entry) in entries.enumerated() {
                let icon = icon(for: entry.provider)
                icon.draw(
                    in: NSRect(
                        x: x,
                        y: destination.midY - iconSize / 2,
                        width: iconSize,
                        height: iconSize
                    ),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                x += iconSize

                if !entry.metrics.isEmpty {
                    x += iconTextSpacing
                }
                for (metricIndex, metric) in entry.metrics.enumerated() {
                    if metricIndex > 0 {
                        x += separatorSpacing
                        (separator.text as NSString).draw(
                            at: NSPoint(
                                x: x,
                                y: destination.midY -
                                    separator.size.height / 2
                            ),
                            withAttributes: microAttributes
                        )
                        x += separator.width + separatorSpacing
                    }

                    if let label = metric.label {
                        (label.text as NSString).draw(
                            at: NSPoint(
                                x: x,
                                y: destination.midY -
                                    label.size.height / 2 +
                                    microLabelRaise
                            ),
                            withAttributes: microAttributes
                        )
                        x += label.width + labelValueSpacing
                    }

                    (metric.value.text as NSString).draw(
                        at: NSPoint(
                            x: x,
                            y: destination.midY -
                                metric.value.size.height / 2
                        ),
                        withAttributes: valueAttributes
                    )
                    x += metric.value.width

                    if metricIndex == entry.metrics.count - 1,
                       let suffix = entry.suffix {
                        x += suffixSpacing
                        (suffix.text as NSString).draw(
                            at: NSPoint(
                                x: x,
                                y: destination.midY -
                                    suffix.size.height / 2
                            ),
                            withAttributes: microAttributes
                        )
                        x += suffix.width
                    }

                    if let staleIndicator = metric.staleIndicator {
                        x += staleSpacing
                        (staleIndicator.text as NSString).draw(
                            at: NSPoint(
                                x: x,
                                y: destination.midY -
                                    staleIndicator.size.height / 2
                            ),
                            withAttributes: microAttributes
                        )
                        x += staleIndicator.width
                    }
                }

                if index < entries.count - 1 {
                    x += providerSpacing
                }
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    private static func textRun(_ text: String, font: NSFont) -> TextRun {
        TextRun(
            text: text,
            size: (text as NSString).size(withAttributes: [
                .font: font
            ])
        )
    }

    private static func icon(for provider: ProviderID) -> NSImage {
        ProviderIcon.templateImage(for: provider, size: iconSize)
    }
}

enum MenuBarPanelRoute: Equatable {
    case dashboard

    var width: CGFloat {
        switch self {
        case .dashboard:
            392
        }
    }
}

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let store: UsageStore
    private let preferences: AppPreferences
    private let launchAtLogin: LaunchAtLoginController
    private let updateController: UpdateController
    private let statusBar: NSStatusBar
    private let application: any ApplicationActivating

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private(set) var settingsWindow: NSWindow?
    private var isStarted = false
    private var toggleGate = PanelToggleGate()

    init(
        store: UsageStore,
        preferences: AppPreferences,
        launchAtLogin: LaunchAtLoginController,
        updateController: UpdateController,
        statusBar: NSStatusBar = .system,
        application: any ApplicationActivating = NSApplication.shared
    ) {
        self.store = store
        self.preferences = preferences
        self.launchAtLogin = launchAtLogin
        self.updateController = updateController
        self.statusBar = statusBar
        self.application = application
        super.init()
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            button.font = .monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
        }

        trackMenuBarState()
        store.start()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        store.stop()
        popover?.performClose(nil)
        releasePanel()
        settingsWindow?.close()

        if let statusItem {
            statusBar.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @objc
    private func togglePanel(_ sender: Any?) {
        guard !toggleGate.consumeSuppression() else { return }

        if popover?.isShown == true {
            popover?.performClose(sender)
        } else {
            showPanel()
        }
    }

    func showSettings() {
        guard isStarted else { return }
        preferences.markInitialSetupCompleted()
        popover?.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: SettingsView.windowWidth, height: SettingsView.windowHeight),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AI Usage 设置"
            window.isReleasedWhenClosed = false
            window.backgroundColor = .windowBackgroundColor
            window.isOpaque = true
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: SettingsView(
                store: store, preferences: preferences, launchAtLogin: launchAtLogin
            ))
            window.center()
            settingsWindow = window
        }
        application.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        window.contentViewController = nil
        settingsWindow = nil
    }

    private func showPanel() {
        guard let button = statusItem?.button else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.popover = popover

        // Status-item clicks do not activate an LSUIElement app automatically.
        // Activate first so Liquid Glass resolves its active appearance.
        application.activate()
        installDashboard(in: popover)
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        popover.contentViewController?.view.window?.makeKey()
    }

    private func installDashboard(in popover: NSPopover) {
        let rootView = DashboardRootView(
            store: store,
            launchAtLogin: launchAtLogin,
            preferences: preferences,
            updateController: updateController,
            openSettings: { [weak self] in self?.showSettings() }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]

        let measuredSize = hostingController.sizeThatFits(
            in: NSSize(
                width: MenuBarPanelRoute.dashboard.width,
                height: .greatestFiniteMagnitude
            )
        )
        let contentSize = NSSize(
            width: MenuBarPanelRoute.dashboard.width,
            height: ceil(measuredSize.height)
        )
        hostingController.preferredContentSize = contentSize
        popover.contentViewController = hostingController
        popover.contentSize = contentSize
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover,
              closedPopover === popover else {
            return
        }
        toggleGate.panelDidClose()
        releasePanel()
        DispatchQueue.main.async { [weak self] in
            self?.toggleGate.clearSuppression()
        }
    }

    private func releasePanel() {
        popover?.delegate = nil
        popover?.contentViewController = nil
        popover = nil
    }

    private func trackMenuBarState() {
        guard isStarted else { return }

        store.setTrackedProviders(preferences.trackedProviderIDs)
        let state = withObservationTracking {
            (
                groups: store.menuBarProviderReadings(
                    for: preferences.menuBarProviderConfigurations,
                    displayMode: preferences.usageDisplayMode
                ),
                trackedProviders: preferences.trackedProviderIDs,
                refreshInterval: preferences.refreshInterval,
                stacked: preferences.stackedMenuBar,
                vpnName: preferences.vpnDisplayName,
                vpnFailure: store.states[.vpn]?.failure
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.trackMenuBarState()
            }
        }

        store.setTrackedProviders(state.trackedProviders)
        store.setRefreshInterval(state.refreshInterval)
        updateStatusItem(with: state.groups)
    }

    private func updateStatusItem(with groups: [MenuBarProviderReadings]) {
        guard let button = statusItem?.button else { return }

        let collectionPresentation = MenuBarReadingsPresentation(
            groups: groups
        )
        button.toolTip = collectionPresentation.accessibilityLabel
        button.setAccessibilityLabel(collectionPresentation.accessibilityLabel)

        guard !groups.isEmpty else {
            button.attributedTitle = NSAttributedString()
            button.image = statusImage(for: nil)
            button.title = ""
            return
        }

        button.attributedTitle = NSAttributedString()
        button.image = nil
        button.title = ""
        if preferences.stackedMenuBar {
            button.image = StackedStatusRenderer.image(groups: groups, vpnName: preferences.vpnDisplayName, vpnFailed: store.states[.vpn]?.failure != nil)
            return
        }
        button.image = MenuBarStatusImageRenderer.image(
            for: groups,
            font: button.font ?? NSFont.menuBarFont(ofSize: 0)
        )
    }

    private func statusImage(for provider: ProviderID?) -> NSImage {
        if let provider {
            return ProviderIcon.templateImage(for: provider, size: 15)
        }

        guard let source = NSImage(
            systemSymbolName: "gauge.with.dots.needle.50percent",
            accessibilityDescription: nil
        ), let image = source.copy() as? NSImage else {
            return NSImage(size: NSSize(width: 15, height: 15))
        }
        image.size = NSSize(width: 15, height: 15)
        image.isTemplate = true
        return image
    }
}

private struct DashboardRootView: View {
    let store: UsageStore
    let launchAtLogin: LaunchAtLoginController
    @Bindable var preferences: AppPreferences
    @Bindable var updateController: UpdateController
    let openSettings: @MainActor () -> Void

    var body: some View {
        DashboardView(
            store: store,
            launchAtLogin: launchAtLogin,
            usageDisplayMode: $preferences.usageDisplayMode,
            refreshInterval: $preferences.refreshInterval,
            availableUpdateVersion: updateController.availableVersion,
            isCheckingForUpdates: updateController.isChecking,
            checkForUpdates: updateController.checkForUpdates,
            openSettings: openSettings
        )
    }
}

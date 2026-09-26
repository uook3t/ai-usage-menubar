import AppKit
import SwiftUI

@main
struct AIUsageApp: App {
    @NSApplicationDelegateAdaptor(AIUsageAppDelegate.self)
    private var appDelegate

    init() {
        if CommandLine.arguments.contains("--configure-vpn-stdin") {
            do {
                let input = FileHandle.standardInput.readDataToEndOfFile()
                let url = try VPNEndpoint.validate(String(decoding: input, as: UTF8.self))
                UserDefaults.standard.set(url.absoluteString, forKey: "vpn.url")
                exit(0)
            } catch {
                fputs("VPN configuration failed.\n", stderr)
                exit(1)
            }
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AIUsageAppDelegate: NSObject, NSApplicationDelegate {
    let services: AppServices
    private var menuBarController: MenuBarController?

    override init() {
        services = AppServices(startingUpdater: !Self.isRunningTests)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)

        let services = self.services
        let menuBarController = MenuBarController(
            store: services.store,
            preferences: services.preferences,
            launchAtLogin: services.launchAtLogin,
            updateController: services.updateController
        )
        menuBarController.start()
        self.menuBarController = menuBarController
        installMainMenu()

        Task {
            await services.store.refresh()
            services.preferences.configureDefaultMenuBarProviders(
                availableItemsByProvider:
                    services.store.availableMenuBarItemsByProvider
            )
            if !services.preferences.hasCompletedInitialSetup {
                menuBarController.showSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
        menuBarController = nil
    }

    @objc private func willSleep() { services.store.stop() }
    @objc private func didWake() { services.store.resume() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.showSettings()
        return true
    }

    @objc
    private func openSettings(_ sender: Any?) {
        menuBarController?.showSettings()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "AI Usage")

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "Quit AI Usage",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApplication.shared
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static var isInstalledInApplicationsFolder: Bool {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let homeApplicationsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .standardizedFileURL
            .path

        return bundlePath.hasPrefix("/Applications/") ||
            bundlePath.hasPrefix("\(homeApplicationsPath)/")
    }
}

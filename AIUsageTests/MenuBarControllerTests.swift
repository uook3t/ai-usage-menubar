import XCTest
@testable import AIUsage

@MainActor
final class MenuBarControllerTests: XCTestCase {
    func testCloseSuppressesOnlyTheMatchingToggleEvent() {
        var gate = PanelToggleGate()

        gate.panelDidClose()

        XCTAssertTrue(gate.consumeSuppression())
        XCTAssertFalse(gate.consumeSuppression())
    }

    func testOutsideCloseSuppressionCanExpireBeforeAnotherToggle() {
        var gate = PanelToggleGate()

        gate.panelDidClose()
        gate.clearSuppression()

        XCTAssertFalse(gate.consumeSuppression())
    }

    func testSettingsUsesIndependentWindowAndReleasesItOnClose() {
        let suiteName = "MenuBarControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let application = RecordingApplicationActivator()
        let controller = MenuBarController(
            store: UsageStore(
                providers: [],
                availabilityChecker: FixedProviderAvailabilityChecker(
                    installed: []
                )
            ),
            preferences: AppPreferences(defaults: defaults),
            launchAtLogin: LaunchAtLoginController(
                service: MenuBarControllerLoginService()
            ),
            updateController: UpdateController(startingUpdater: false),
            application: application
        )

        controller.start()
        controller.showSettings()

        XCTAssertEqual(application.activationCount, 1)
        let window = controller.settingsWindow
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.title, "AI Usage 设置")
        XCTAssertEqual(window?.isOpaque, true)
        XCTAssertTrue(window?.styleMask.contains(.titled) ?? false)
        controller.showSettings()
        XCTAssertTrue(controller.settingsWindow === window)
        window?.close()
        XCTAssertNil(controller.settingsWindow)
        controller.showSettings()
        XCTAssertNotNil(controller.settingsWindow)
        XCTAssertFalse(controller.settingsWindow === window)

        controller.stop()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
private final class RecordingApplicationActivator:
    ApplicationActivating
{
    private(set) var activationCount = 0

    func activate() {
        activationCount += 1
    }
}

@MainActor
private struct MenuBarControllerLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus { .notRegistered }

    func register() throws {}
    func unregister() throws {}
}

import XCTest

/// Smoke UI test: launches the app and asserts the root tab bar is on
/// screen. Acts as a tripwire — if the app fails to launch or the root
/// `RootView` stops rendering, this test fails before any feature work
/// catches it.
///
/// `@MainActor` keeps `XCUIApplication` access on the main actor, which
/// is required under `SWIFT_STRICT_CONCURRENCY: complete` (and an
/// outright error under the Swift 6 language mode).
@MainActor
final class ChorezUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTabBarAppears() throws {
        let app = XCUIApplication()
        // `-UITesting` swaps the live CloudKit-backed `ModelContainer`
        // for an in-memory one — necessary in CI where the simulator
        // isn't signed into iCloud and the CloudKit init can stall the
        // first frame past the 5s wait timeout below.
        app.launchArguments.append("-UITesting")
        app.launch()

        let homeTab = app.tabBars.buttons["Home"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5),
                      "Expected the Home tab to appear after launch")
    }
}

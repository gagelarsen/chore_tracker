import XCTest

/// Smoke UI test: launches the app and asserts the welcome label is on screen.
/// Acts as a tripwire — if the app fails to launch or the root view stops
/// rendering, this test fails before any feature work catches it.
///
/// `@MainActor` keeps `XCUIApplication` access on the main actor, which is
/// required under `SWIFT_STRICT_CONCURRENCY: complete` (and an outright error
/// under the Swift 6 language mode).
@MainActor
final class ChorezUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWelcomeLabelAppears() throws {
        let app = XCUIApplication()
        app.launch()

        let welcome = app.staticTexts["welcomeLabel"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 5),
                      "Expected the welcome label to appear after launch")
    }
}

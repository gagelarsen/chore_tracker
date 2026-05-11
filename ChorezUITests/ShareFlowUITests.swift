import XCTest

/// Structural coverage of the share-invite surface that the user sees
/// in Settings once a household exists.
///
/// Phase 1's exit criterion ("two real iPhones, different iCloud
/// accounts, sync within seconds") cannot be exercised from a
/// simulator — CloudKit needs a signed-in iCloud account and a real
/// `CKContainer`, neither of which CI has. This file therefore covers
/// only the bits we *can* verify deterministically:
///
/// 1. The "Invite spouse" button exists and is enabled once a
///    household is set up (proof the flow is reachable from the UI).
/// 2. The pre-bootstrap variant of the same row is disabled.
///
/// Two-account end-to-end verification is on real hardware, by hand.
@MainActor
final class ShareFlowUITests: XCTestCase {
    private let timeout: TimeInterval = 5

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInviteSpouseDisabledBeforeBootstrap() throws {
        let app = launchClean()
        // No family yet — Invite spouse should be a Label, not a Button.
        app.tabBars.buttons["Settings"].tap()
        let inviteButton = app.buttons["inviteSpouseButton"]
        // Wait briefly: if it does appear, the test fails — we expect
        // the disabled label variant before bootstrap.
        XCTAssertFalse(inviteButton.waitForExistence(timeout: 2),
                       "Invite spouse must be disabled until a household exists")
    }

    func testInviteSpouseEnabledAfterBootstrap() throws {
        let app = launchClean()
        try bootstrap(app, family: "Smiths")

        app.tabBars.buttons["Settings"].tap()
        let inviteButton = app.buttons["inviteSpouseButton"]
        XCTAssertTrue(inviteButton.waitForExistence(timeout: timeout),
                      "Expected the Invite spouse button after household creation")
        XCTAssertTrue(inviteButton.isEnabled,
                      "Invite spouse must be enabled once a household exists")

        // Tapping presents UICloudSharingController. We can't drive the
        // real share-sheet UI from the simulator (no iCloud account),
        // so we stop at proving the button is wired up.
        try XCTSkipIf(true,
                      "Real share-sheet verification requires two real iPhones with different iCloud accounts.")
    }

    // MARK: - Helpers

    private func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launch()
        return app
    }

    private func bootstrap(_ app: XCUIApplication, family: String) throws {
        app.tabBars.buttons["Settings"].tap()
        let nameField = app.textFields["familyNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(family)
        app.buttons["createFamilyButton"].tap()
    }
}

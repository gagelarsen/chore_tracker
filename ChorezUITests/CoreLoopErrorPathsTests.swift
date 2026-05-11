import XCTest

/// Critical error-path UI tests required by `00-standards.md`:
/// "Critical error paths get explicit XCUITests."
///
/// CoreLoopTests covers the golden path; this suite drives the two
/// Phase 1 error paths that are reachable from the parent-only UI:
///
/// 1. Insufficient balance for redemption — the Redeem button must
///    stay disabled when `kid.currentDailyBalance < reward.points`.
/// 2. Negative bonus that would-go-negative — the engine refuses and
///    `KidDetailView` surfaces the failure via an alert.
@MainActor
final class CoreLoopErrorPathsTests: XCTestCase {
    private let timeout: TimeInterval = 5

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRedeemButtonDisabledWhenInsufficientBalance() throws {
        let app = launchClean()
        try bootstrap(app, family: "Smiths", kidName: "Anna")
        try addUnaffordableReward(app, named: "Bike", points: 100)
        try openKidDetail(app, kidName: "Anna")

        let redeem = app.buttons["redeemButton_Bike"]
        XCTAssertTrue(redeem.waitForExistence(timeout: timeout),
                      "Expected Redeem button to render even when unaffordable")
        XCTAssertFalse(redeem.isEnabled,
                       "Redeem button must be disabled when balance is below the reward cost")
    }

    func testNegativeBonusBlockedWhenItWouldGoNegative() throws {
        let app = launchClean()
        try bootstrap(app, family: "Smiths", kidName: "Anna")
        try openKidDetail(app, kidName: "Anna")

        // Open the Give bonus sheet
        app.buttons["giveBonusButton"].tap()
        let field = app.textFields["bonusPointsField"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText("-5")
        app.buttons["confirmBonusButton"].tap()

        // The engine refuses (`.wouldGoNegative`) and the alert surfaces
        let alertButton = app.alerts.buttons["OK"]
        XCTAssertTrue(alertButton.waitForExistence(timeout: timeout),
                      "Expected an alert when docking past zero balance")
        // Sanity-check the alert copy matches the engine's intent so a
        // future rewording of `describe(_:)` doesn't silently change
        // user-facing text.
        XCTAssertTrue(app.staticTexts["Balance cannot go below zero."].exists,
                      "Expected the would-go-negative copy in the alert body")
        alertButton.tap()
    }

    // MARK: - Helpers

    private func launchClean() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launch()
        return app
    }

    private func bootstrap(_ app: XCUIApplication, family: String, kidName: String) throws {
        app.tabBars.buttons["Settings"].tap()
        let nameField = app.textFields["familyNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(family)
        app.buttons["createFamilyButton"].tap()

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["addKidButton"].waitForExistence(timeout: timeout))
        app.buttons["addKidButton"].tap()
        let kidField = app.textFields["newKidNameField"]
        XCTAssertTrue(kidField.waitForExistence(timeout: timeout))
        kidField.tap()
        kidField.typeText(kidName)
        app.buttons["confirmAddKidButton"].tap()
    }

    private func addUnaffordableReward(_ app: XCUIApplication, named name: String, points: Int) throws {
        app.tabBars.buttons["Rewards"].tap()
        XCTAssertTrue(app.buttons["addRewardButton"].waitForExistence(timeout: timeout))
        app.buttons["addRewardButton"].tap()
        let nameField = app.textFields["rewardNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(name)
        let pointsField = app.textFields["rewardPointsField"]
        pointsField.tap()
        pointsField.typeText(String(points))
        app.buttons["confirmAddRewardButton"].tap()
    }

    private func openKidDetail(_ app: XCUIApplication, kidName: String) throws {
        app.tabBars.buttons["Home"].tap()
        let kidRow = app.buttons["kidRow_\(kidName)"]
        XCTAssertTrue(kidRow.waitForExistence(timeout: timeout))
        kidRow.tap()
    }
}

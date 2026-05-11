import XCTest

/// End-to-end happy path for the Phase 1 MVP loop.
///
/// Launches the app with `-UITesting` so each run starts against an
/// in-memory SwiftData store, then drives every Phase 1 screen via
/// accessibility identifiers: create family, add kid, add template,
/// mark chore done, add reward, redeem, end the day. If any of those
/// steps regress this test fails before merge.
///
/// `@MainActor` keeps `XCUIApplication` access on the main actor —
/// required under `SWIFT_STRICT_CONCURRENCY: complete`.
@MainActor
final class CoreLoopTests: XCTestCase {
    private let timeout: TimeInterval = 5

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCreateChoreCompleteRedeemEndDay() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launch()

        try createFamily(app, named: "Smiths")
        try addKid(app, named: "Anna")
        try addTemplate(app, kidName: "Anna", choreName: "Dishes", points: 5)
        try verifyAndCompleteChore(app, kidName: "Anna", choreName: "Dishes", expectedBalanceAfter: 5)
        try addReward(app, name: "Sticker", points: 5)
        try redeemReward(app, kidName: "Anna", rewardName: "Sticker", expectedBalanceAfter: 0)
        try endDay(app)
        try verifyDayClosed(app, kidName: "Anna")
    }

    // MARK: - Steps

    private func createFamily(_ app: XCUIApplication, named name: String) throws {
        app.tabBars.buttons["Settings"].tap()
        let field = app.textFields["familyNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText(name)
        app.buttons["createFamilyButton"].tap()
    }

    private func addKid(_ app: XCUIApplication, named name: String) throws {
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["addKidButton"].waitForExistence(timeout: timeout))
        app.buttons["addKidButton"].tap()
        let field = app.textFields["newKidNameField"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.tap()
        field.typeText(name)
        app.buttons["confirmAddKidButton"].tap()
    }

    private func addTemplate(_ app: XCUIApplication,
                             kidName: String,
                             choreName: String,
                             points: Int) throws {
        app.tabBars.buttons["Chores"].tap()
        XCTAssertTrue(app.buttons["addChoreMenu"].waitForExistence(timeout: timeout))
        app.buttons["addChoreMenu"].tap()
        app.buttons["addTemplateButton"].tap()

        let picker = app.buttons["kidPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        picker.tap()
        app.buttons[kidName].tap()

        let nameField = app.textFields["choreNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText(choreName)

        let pointsField = app.textFields["chorePointsField"]
        pointsField.tap()
        pointsField.typeText(String(points))

        app.buttons["confirmAddTemplateButton"].tap()
    }

    private func verifyAndCompleteChore(_ app: XCUIApplication,
                                        kidName: String,
                                        choreName: String,
                                        expectedBalanceAfter: Int) throws {
        app.tabBars.buttons["Home"].tap()
        let kidRow = app.buttons["kidRow_\(kidName)"]
        XCTAssertTrue(kidRow.waitForExistence(timeout: timeout))
        kidRow.tap()

        let checkbox = app.buttons["choreCheckbox_\(choreName)"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: timeout),
                      "Expected today's chore '\(choreName)' on the kid's screen")
        checkbox.tap()

        assertBalance(app, equals: expectedBalanceAfter, context: "after completion")
    }

    private func addReward(_ app: XCUIApplication, name: String, points: Int) throws {
        app.navigationBars.buttons.firstMatch.tap()   // back to Home from KidDetail
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

    private func redeemReward(_ app: XCUIApplication,
                              kidName: String,
                              rewardName: String,
                              expectedBalanceAfter: Int) throws {
        app.tabBars.buttons["Home"].tap()
        let kidRow = app.buttons["kidRow_\(kidName)"]
        XCTAssertTrue(kidRow.waitForExistence(timeout: timeout))
        kidRow.tap()

        let redeem = app.buttons["redeemButton_\(rewardName)"]
        XCTAssertTrue(redeem.waitForExistence(timeout: timeout))
        redeem.tap()

        assertBalance(app, equals: expectedBalanceAfter, context: "after redemption")
    }

    private func endDay(_ app: XCUIApplication) throws {
        app.navigationBars.buttons.firstMatch.tap()   // back to Home
        app.tabBars.buttons["Settings"].tap()

        let endButton = app.buttons["endDayButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: timeout))
        endButton.tap()

        let confirm = app.buttons["End the day"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout))
        confirm.tap()
    }

    private func verifyDayClosed(_ app: XCUIApplication, kidName: String) throws {
        app.tabBars.buttons["Home"].tap()
        let kidRow = app.buttons["kidRow_\(kidName)"]
        XCTAssertTrue(kidRow.waitForExistence(timeout: timeout))
        kidRow.tap()

        assertBalance(app, equals: 0, context: "after end-of-day")
    }

    /// Asserts the kid's daily-balance pill renders the expected
    /// points value. Targets the `dailyBalancePill` identifier
    /// directly so other point pills on the screen (per-chore,
    /// per-reward) can't accidentally satisfy a generic label match.
    private func assertBalance(_ app: XCUIApplication, equals expected: Int, context: String) {
        let pill = app.descendants(matching: .any)["dailyBalancePill"]
        XCTAssertTrue(pill.waitForExistence(timeout: timeout),
                      "Expected daily-balance pill to render \(context)")
        XCTAssertEqual(pill.label, "\(expected) points",
                       "Expected balance pill to read \(expected) points \(context)")
    }
}

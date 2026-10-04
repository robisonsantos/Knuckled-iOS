import XCTest

final class SoloSmokeTests: XCTestCase {
    func testSoloGameBootsAndFirstMove() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 10))

        let nameField = app.textFields["name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Tester")
        app.buttons["single-player-button"].tap()

        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["peer-board"].exists)
        XCTAssertTrue(app.buttons["dice"].waitForExistence(timeout: 5))

        // Wait for our turn (CPU may move first), then roll.
        let dice = app.buttons["dice"]
        XCTAssertTrue(dice.waitForExistence(timeout: 5))
        waitForEnabled(dice, timeout: 30)
        dice.tap()

        // Awaiting placement → scroll own column 0 into view, then place.
        XCTAssertTrue(app.staticTexts["place-hint"].waitForExistence(timeout: 10))
        app.swipeUp()
        app.staticTexts["own column 0"].tap()

        // Game continues (no crash): boards still present.
        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 10))
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "element never became enabled")
    }
}

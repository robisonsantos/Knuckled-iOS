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

    /// Full-game tour: plays an entire solo game to the result overlay.
    /// Human cycles columns 0→1→2 (full columns no-op via the placeable guard);
    /// loop ends when winner/draw overlay appears. Bounded at 60 iterations.
    func testFullGameTour() {
        let app = XCUIApplication()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 10))

        let nameField = app.textFields["name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Tourist")
        app.buttons["single-player-button"].tap()
        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 10))

        var col = 0
        var resultSeen = false
        for _ in 0..<60 {
            if app.staticTexts["winner-overlay"].exists || app.staticTexts["draw-overlay"].exists {
                resultSeen = true
                break
            }
            if app.staticTexts["place-hint"].waitForExistence(timeout: 4) {
                app.swipeUp()
                // firstMatch: filled dice cells inherit the container label,
                // so the query can match more than once mid-game.
                app.staticTexts["own column \(col % 3)"].firstMatch.tap()
                col += 1
                continue
            }
            if isEnabled(app.buttons["dice"], timeout: 4) {
                app.buttons["dice"].tap()
                continue
            }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertTrue(resultSeen, "full game should reach a result overlay")
        Thread.sleep(forTimeInterval: 3)
    }

    private func isEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "enabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

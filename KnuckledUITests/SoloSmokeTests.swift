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
        // (Query by label: the board identifier stamps every child element,
        // so per-column identifiers never surface — labels do.)
        XCTAssertTrue(app.staticTexts["place-hint"].waitForExistence(timeout: 10))
        app.swipeUp()
        app.buttons["own column 0"].tap()

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

        var resultSeen = false
        var ghostChecks = 0
        // Fast loop (~0.5s/iteration) with a ghost check every pass, so the
        // transient ~500ms destroy markers are observed whenever visible.
        // 300 iterations ≈ several minutes of game budget; the loop exits
        // early at the result overlay.
        for _ in 0..<300 {
            if app.staticTexts["winner-overlay"].exists || app.staticTexts["draw-overlay"].exists {
                resultSeen = true
                break
            }
            ghostChecks += checkGhostsOutsideColumns(app)
            if app.staticTexts["place-hint"].exists {
                app.swipeUp()
                // Tap the first enabled column (full columns are disabled).
                // Query by label: the board identifier stamps every child.
                for c in 0..<3 {
                    let button = app.buttons["own column \(c)"]
                    if button.exists && button.isEnabled {
                        button.tap()
                        break
                    }
                }
                // Our placement may have destroyed peer dice: poll tightly
                // while the ~500ms ghost is likely visible.
                let pollEnd = Date().addingTimeInterval(1.5)
                while Date() < pollEnd {
                    ghostChecks += checkGhostsOutsideColumns(app)
                    Thread.sleep(forTimeInterval: 0.2)
                }
                continue
            }
            let dice = app.buttons["dice"]
            if dice.exists && dice.isEnabled {
                dice.tap()
                continue
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(resultSeen, "full game should reach a result overlay")
        print("ghost geometry checks performed: \(ghostChecks)")
        Thread.sleep(forTimeInterval: 3)
    }

    /// Asserts every currently visible destroy ghost lies outside all column
    /// containers. Returns the number of ghosts checked (0 when none visible —
    /// ghosts auto-dismiss after ~500ms).
    @discardableResult
    private func checkGhostsOutsideColumns(_ app: XCUIApplication) -> Int {
        var checked = 0
        let ghosts = app.staticTexts.matching(NSPredicate(format: "label == %@", "destroyed die marker"))
        for i in 0..<ghosts.count {
            let ghost = ghosts.element(boundBy: i)
            guard ghost.exists else { continue }
            let frame = ghost.frame
            guard !frame.isNull && !frame.isEmpty && ghost.exists else { continue }
            checked += 1
            for c in 0..<3 {
                let own = app.buttons["own column \(c)"]
                if own.exists {
                    XCTAssertFalse(own.frame.intersects(frame), "ghost intersects own column \(c)")
                }
                let peer = app.otherElements.matching(NSPredicate(format: "label == %@", "peer column \(c)")).firstMatch
                if peer.exists {
                    XCTAssertFalse(peer.frame.intersects(frame), "ghost intersects peer column \(c)")
                }
            }
        }
        return checked
    }

    /// Waits for an element with the given accessibility label and returns it.
    /// Uses an explicit label predicate evaluated in a poll loop (KVO-based
    /// waiting on XCUIElementQuery is unreliable across query types).
    private func labeledElement(_ query: XCUIElementQuery, _ label: String, timeout: TimeInterval = 10) -> XCUIElement {
        let filtered = query.matching(NSPredicate(format: "label == %@", label))
        let deadline = Date().addingTimeInterval(timeout)
        while filtered.count == 0 {
            if Date() > deadline { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(filtered.count > 0, "element with label '\(label)' never appeared")
        return filtered.firstMatch
    }

    /// Deterministic board geometry: columns share rows left-to-right and
    /// sub-total chips sit outside the bordered boxes (own above, peer below).
    func testBoardGeometry() {
        let app = XCUIApplication()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 10))
        let nameField = app.textFields["name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Geo")
        app.buttons["single-player-button"].tap()
        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 10))

        let ownFrames = (0..<3).map { labeledElement(app.buttons, "own column \($0)").frame }
        XCTAssertLessThan(abs(ownFrames[0].minY - ownFrames[1].minY), 2, "own columns share a row")
        XCTAssertLessThan(abs(ownFrames[1].minY - ownFrames[2].minY), 2, "own columns share a row")
        XCTAssertLessThan(ownFrames[0].maxX, ownFrames[1].minX, "own columns run left to right")
        XCTAssertLessThan(ownFrames[1].maxX, ownFrames[2].minX, "own columns run left to right")

        let peerFrames = (0..<3).map { labeledElement(app.otherElements, "peer column \($0)").frame }
        XCTAssertLessThan(abs(peerFrames[0].minY - peerFrames[1].minY), 2, "peer columns share a row")
        XCTAssertLessThan(abs(peerFrames[1].minY - peerFrames[2].minY), 2, "peer columns share a row")
        XCTAssertLessThan(peerFrames[0].maxX, peerFrames[1].minX, "peer columns run left to right")
        XCTAssertLessThan(peerFrames[1].maxX, peerFrames[2].minX, "peer columns run left to right")

        let ownChip = labeledElement(app.staticTexts, "own chip 0")
        XCTAssertLessThanOrEqual(ownChip.frame.maxY, ownFrames[0].minY + 2, "own chip sits above its box")

        let peerChip = labeledElement(app.staticTexts, "peer chip 0")
        XCTAssertGreaterThanOrEqual(peerChip.frame.minY, peerFrames[0].maxY - 2, "peer chip sits below its box")
    }
}

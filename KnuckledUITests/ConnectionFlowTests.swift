import XCTest

final class ConnectionFlowTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 10))
        return app
    }

    private func typeName(_ app: XCUIApplication, _ name: String = "Tester") {
        let field = app.textFields["name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
    }

    private func openPvP(_ app: XCUIApplication) {
        let pvp = app.buttons["pvp-button"]
        XCTAssertTrue(pvp.waitForExistence(timeout: 5))
        pvp.tap()
        XCTAssertTrue(app.buttons["host-button"].waitForExistence(timeout: 5))
    }

    func testHostFlowShowsPinThenGame() {
        let app = launch()
        openPvP(app)
        typeName(app)
        app.buttons["host-button"].tap()
        XCTAssertTrue(app.staticTexts["pin-display"].waitForExistence(timeout: 10))
        // Fake client connects immediately: game screen follows.
        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 15))
    }

    func testJoinFlowWrongPinShowsError() {
        let app = launch()
        openPvP(app)
        typeName(app)
        app.buttons["join-button"].tap()
        // Fake discover returns instantly so scan-status flashes past;
        // assert the device row directly.
        let row = app.buttons["device-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        // pin-input stamps the digit tiles; the typable element is the
        // hidden TextField (already focused on appear).
        let pin = app.textFields.firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        pin.typeText("0000")
        // Wrong PIN returns to Start with the error banner.
        XCTAssertTrue(app.staticTexts["start-title"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 5))
    }

    func testJoinFlowCorrectPinReachesGame() {
        let app = launch()
        openPvP(app)
        typeName(app)
        app.buttons["join-button"].tap()
        let row = app.buttons["device-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let pin = app.textFields.firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        pin.tap()
        pin.typeText("1234")
        XCTAssertTrue(app.staticTexts["own-board"].waitForExistence(timeout: 15))
    }
}

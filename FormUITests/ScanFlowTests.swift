import XCTest

final class ScanFlowTests: XCTestCase {
    @MainActor
    func testDemoUnitsSaveAndLibrary() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["DEMO · EXAMPLE DATA"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["32.4"].exists)
        app.buttons["Change measurement units"].tap()
        XCTAssertTrue(app.staticTexts["12.8"].exists)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Save measurement"].waitForExistence(timeout: 3))
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Saved"].waitForExistence(timeout: 3))
        app.buttons["Saved measurements"].tap()
        XCTAssertTrue(app.staticTexts["Example box"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'DEMO' AND label CONTAINS 'W × H × D'")).firstMatch.exists)
    }

    @MainActor
    func testResetAndGuide() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        XCTAssertTrue(app.buttons["New measurement"].waitForExistence(timeout: 10))
        app.buttons["New measurement"].tap()
        XCTAssertTrue(app.staticTexts["Give it dimension."].exists)
        XCTAssertFalse(app.buttons["Save"].exists)
        app.buttons["Scanning guide"].tap()
        XCTAssertTrue(app.staticTexts["Find a clear subject"].waitForExistence(timeout: 3))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Give it dimension."].exists)
    }
}

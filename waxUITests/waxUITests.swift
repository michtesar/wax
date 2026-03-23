//
//  waxUITests.swift
//  waxUITests
//
//  Created by Michael Tesař on 23.03.2026.
//

import XCTest

final class waxUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testLaunchPerformance() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testLaunchWithFakeSeedShowsSeededCollection() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--bootstrap-mode=fake-seed",
            "--reset-database",
            "--sqlite-file-name=ui-fake-seed.sqlite"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Fake seed loaded for local development."].waitForExistence(timeout: 5))
    }
}

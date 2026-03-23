//
//  waxUITestsLaunchTests.swift
//  waxUITests
//
//  Created by Michael Tesař on 23.03.2026.
//

import XCTest

final class waxUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
    }
}

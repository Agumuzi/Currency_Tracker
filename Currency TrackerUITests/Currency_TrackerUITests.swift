//
//  Currency_TrackerUITests.swift
//  Currency TrackerUITests
//
//  Created by Thomas Tao on 4/10/26.
//

import AppKit
import XCTest

final class Currency_TrackerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
        terminateExistingAppInstances()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSettingsWindowStartsBlankWithEmptyAPIState() throws {
        let app = XCUIApplication()
        let suiteName = "CurrencyTrackerUITests.\(UUID().uuidString)"
        app.launchEnvironment["CURRENCY_TRACKER_DEFAULTS_SUITE"] = suiteName
        app.launchEnvironment["CURRENCY_TRACKER_RESET_DEFAULTS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_UI_TEST_SHOW_SETTINGS"] = "1"
        app.launchEnvironment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] = "1"
        app.launch()

        XCTAssertTrue(app.staticTexts["settings.empty-pairs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["settings.currency-search"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["settings.api.twelveData.primary"].label, "编辑")
        XCTAssertEqual(app.buttons["settings.api.openExchangeRates.primary"].label, "编辑")
    }

    @MainActor
    func testLaunchPerformance() throws {
        terminateExistingAppInstances()
        let app = XCUIApplication()
        app.launchEnvironment["CURRENCY_TRACKER_USE_IN_MEMORY_SECRETS"] = "1"
        app.launch()
        XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground)
        app.terminate()
    }

    private func terminateExistingAppInstances() {
        let bundleIdentifier = "com.thomas.Currency-Tracker"
        for runningApplication in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            if runningApplication.terminate() == false {
                runningApplication.forceTerminate()
            }
        }
    }
}

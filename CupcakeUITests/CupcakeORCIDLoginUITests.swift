//
//  CupcakeORCIDLoginUITests.swift
//  CupcakeUITests
//

import XCTest

/// Not part of the regular automated suite — this needs a live backend and a real human
/// completing ORCID's actual login page inside the system-presented `ASWebAuthenticationSession`
/// sheet, which XCUITest has no access to script (it's system-owned UI in another process). This
/// test only drives the app up to presenting that sheet, then waits a long time for a
/// post-sign-in element while a person completes the ORCID login by hand.
final class CupcakeORCIDLoginUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInWithORCIDAgainstLiveBackend() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let orcidButton = app.buttons["signInWithOrcidButton"]
        XCTAssertTrue(orcidButton.waitForExistence(timeout: 5), "Login screen should show a Sign in with ORCID button")
        orcidButton.tap()

        // The ASWebAuthenticationSession sheet should now be visible — complete the ORCID login
        // by hand in the window that just appeared. Polling up to 3 minutes for the app to land
        // back on its main tabs afterward (macOS exposes tab items as radio buttons, iOS as
        // plain buttons — matches every other tab-existence check in this UI test target).
        let deadline = Date().addingTimeInterval(180)
        var reachedMainTabs = false
        while Date() < deadline {
            if app.tabBars.buttons["Protocols"].exists || app.buttons["Protocols"].exists || app.radioButtons["Protocols"].exists {
                reachedMainTabs = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(reachedMainTabs, "Should reach the main tabs after completing ORCID sign-in")
    }
}

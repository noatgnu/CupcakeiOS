
import XCTest

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

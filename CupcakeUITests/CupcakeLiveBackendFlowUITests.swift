//
//  CupcakeLiveBackendFlowUITests.swift
//  CupcakeUITests
//

import XCTest

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Exercises the real online-mode create/sync path against a real (local, disposable) backend —
/// distinct from `CupcakeOfflineFlowUITests`, which only covers standalone/offline mode. Requires
/// a local test backend running at `http://127.0.0.1:8002/api/v1/` with a `testuser`/`testuser123`
/// account (see the `local-test-backend` memory for how to stand one up via OrbStack + poetry).
/// ATS exempts loopback addresses by default, so no Info.plist changes are needed to reach plain
/// HTTP on `127.0.0.1`.
final class CupcakeLiveBackendFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSignInAndCreateProtocolSyncsImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 5))
        serverURLField.tap()
        // `typeText` silently drops `:` characters (confirmed: "http://127.0.0.1:8002/api/v1/"
        // came out as "http//127.0.0.18002/api/v1/") — paste via the clipboard instead, which
        // doesn't go through the same per-character key-event synthesis.
        replaceText(in: serverURLField, withPasted: "http://127.0.0.1:8002/api/v1/")

        XCTAssertEqual(serverURLField.value as? String, "http://127.0.0.1:8002/api/v1/", "The server URL field should contain exactly the pasted text, not a mix of old and new")

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()

        // Signing in against a real backend triggers a real sync; wait for the Protocols tab's
        // own content to settle before proceeding.
        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)

        // Unique per run — this backend persists across test runs (it's a real, if disposable,
        // database), so a fixed title would accumulate duplicates and break element uniqueness.
        let protocolTitle = "Live Backend Test Protocol \(Date().timeIntervalSince1970)"

        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(protocolTitle)
        app.buttons["createProtocolButton"].tap()

        // Surface a caught-but-swallowed sync error immediately, rather than only inferring one
        // indirectly later from a stuck "Pending sync" label.
        let errorAlert = app.alerts["Couldn't create protocol"]
        if errorAlert.waitForExistence(timeout: 3) {
            XCTFail("Protocol creation showed an error alert: \(errorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
            errorAlert.buttons["OK"].tap()
        }

        // Exact-label matching against the full (long, timestamped) title is unreliable — the
        // list column is narrow enough that the row's displayed text visually truncates, and
        // that truncation is confirmed to carry into the exposed accessibility label too (not
        // just the on-screen rendering), so an exact match against the untruncated string never
        // finds it. Match on a short prefix instead.
        //
        // A generous timeout: confirmed via screen-recording that the row does appear correctly
        // with no error, just sometimes past 10s in this shared/contended local environment
        // (multiple concurrent xcodebuild/simulator processes) — not a real app-responsiveness
        // problem, just slower SwiftData cross-context propagation under load here.
        let matchingRows = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Live Backend"))
        XCTAssertTrue(matchingRows.firstMatch.waitForExistence(timeout: 30), "The newly-created protocol should appear in the list")
        matchingRows.firstMatch.tap()

        // If this synced online immediately (rather than queuing in the outbox), no "Pending
        // sync"/"Local only" label should appear anywhere near it. `NewProtocolView.save()`
        // awaits the sync call before dismissing, so the serverID is already attached by the
        // time the row exists.
        XCTAssertFalse(elementContaining("Pending sync", in: app).exists, "A protocol created while signed in against a reachable backend should sync immediately, not queue")
        XCTAssertFalse(elementContaining("Local only", in: app).exists, "\"Local only\" is standalone-mode-only phrasing — shouldn't appear when signed in")
    }

    // MARK: - Helpers (mirrors CupcakeOfflineFlowUITests's private helpers, duplicated rather
    // than shared across test targets/files for simplicity)

    /// Paste-based text entry, bypassing `typeText`'s per-character key-event synthesis (which
    /// silently drops `:` — confirmed live, not a theoretical risk).
    private func replaceText(in field: XCUIElement, withPasted newText: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        field.typeKey("a", modifierFlags: .command)
        field.typeKey("v", modifierFlags: .command)
        #else
        UIPasteboard.general.string = newText
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        for _ in 0..<40 {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        field.press(forDuration: 1.0)
        field.buttons["Paste"].tap()
        #endif
    }

    private func tapToolbarButton(_ identifier: String, label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: timeout) {
            direct.tap()
            return
        }

        let overflow = app.popUpButtons["more toolbar items"]
        XCTAssertTrue(overflow.waitForExistence(timeout: timeout), "Neither \"\(identifier)\" nor a toolbar overflow menu was found")
        overflow.tap()

        let itemInOverflow = app.menuItems[label]
        XCTAssertTrue(itemInOverflow.waitForExistence(timeout: timeout), "\"\(label)\" was not found inside the toolbar overflow menu")
        itemInOverflow.tap()
    }

    private func elementContaining(_ substring: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        let staticText = app.staticTexts.matching(predicate).firstMatch
        let button = app.buttons.matching(predicate).firstMatch
        return staticText.exists ? staticText : button
    }
}

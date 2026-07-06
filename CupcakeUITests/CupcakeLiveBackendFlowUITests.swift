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

    /// Exercises the new `MetadataValueEditSheet` against a real job's real metadata column
    /// (both set up ahead of time via direct API calls during this feature's development — this
    /// test just needs *some* job with a metadata table and at least one column to already exist
    /// on the backend, not a specific one, so it signs in and edits whatever the first job's
    /// first metadata column happens to be).
    @MainActor
    func testEditMetadataColumnValueSyncsImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 5))
        serverURLField.tap()
        replaceText(in: serverURLField, withPasted: "http://127.0.0.1:8002/api/v1/")

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()

        // The tab bar itself (unlike its content) doesn't depend on the initial sync completing,
        // but confirmed live it can still take longer than `tapTab`'s 5s default to actually
        // settle in this shared/contended local environment — a generous explicit timeout here
        // rather than waiting on unrelated protocol content first.
        tapTab("Jobs", in: app, timeout: 30)

        let jobRow = waitForMatch(NSPredicate(format: "label CONTAINS %@", "test job"), in: app.staticTexts, timeout: 60)
        XCTAssertTrue(jobRow.exists, "The existing 'test job' should appear once synced")
        jobRow.tap()

        let columnRow = app.buttons["metadataColumnRow_Serial Number"]
        XCTAssertTrue(columnRow.waitForExistence(timeout: 10), "The job's 'Serial Number' metadata column should be listed")
        columnRow.tap()

        let valueField = app.textFields["metadataValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 5))
        let newValue = "SN-\(Int(Date().timeIntervalSince1970))"
        replaceText(in: valueField, withPasted: newValue)

        app.buttons["saveMetadataValueButton"].tap()

        let errorAlert = app.alerts["Couldn't save value"]
        XCTAssertFalse(errorAlert.waitForExistence(timeout: 3), "Saving a metadata value against a reachable backend shouldn't show an error")

        let updatedValueElement = waitForMatch(NSPredicate(format: "label CONTAINS %@", newValue), in: app.staticTexts, timeout: 10)
        XCTAssertTrue(updatedValueElement.exists, "The updated value should appear in the column list after saving")
    }

    // MARK: - Helpers (mirrors CupcakeOfflineFlowUITests's private helpers, duplicated rather
    // than shared across test targets/files for simplicity)

    /// Unlike `CupcakeOfflineFlowUITests`'s identifier-based `tapTab`, this matches by **label**
    /// explicitly via an `NSPredicate` — confirmed live via an accessibility-hierarchy dump that
    /// on macOS, a `.tabItem { Label(name, systemImage:) }` radio button's `identifier` is the SF
    /// Symbol name (e.g. `"list.clipboard"`), not the label text, so the plain `app.radioButtons[
    /// "Jobs"]` subscript (which matches by identifier) silently never finds it.
    ///
    /// Polls manually with a fresh query each iteration rather than a single
    /// `.matching(predicate).firstMatch.waitForExistence(...)` — confirmed live that the element
    /// is genuinely present (per accessibility-hierarchy dumps taken during the exact failure),
    /// yet `waitForExistence` on that compound query form never detects it appearing, even with
    /// a 30s timeout; re-issuing the query fresh each poll avoids whatever staleness that form
    /// has.
    private func tapTab(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let predicate = NSPredicate(format: "label == %@", label)
            let match = firstExisting(
                app.tabBars.buttons.matching(predicate).firstMatch,
                app.buttons.matching(predicate).firstMatch,
                app.radioButtons.matching(predicate).firstMatch
            )
            if match.exists {
                match.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: timeout), "Neither \"\(label)\" nor a \"More\" tab overflow was found")
        more.tap()

        let itemInMore = firstExisting(app.staticTexts[label], app.buttons[label], app.cells[label])
        XCTAssertTrue(itemInMore.waitForExistence(timeout: timeout), "\"\(label)\" was not found inside the tab bar's More list")
        itemInMore.tap()
    }

    /// Same manual re-query-each-poll workaround as `tapTab`, generalized for any
    /// `.matching(predicate)` query — `.firstMatch.waitForExistence(...)` on a compound predicate
    /// query is confirmed live to sometimes never detect an element appearing even when it's
    /// genuinely present (per accessibility-hierarchy dumps taken during the exact failure),
    /// while a fresh query issued each poll does.
    private func waitForMatch(_ predicate: NSPredicate, in query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var match = query.matching(predicate).firstMatch
        while Date() < deadline {
            match = query.matching(predicate).firstMatch
            if match.exists { return match }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return match
    }

    private func firstExisting(_ candidates: XCUIElement...) -> XCUIElement {
        for candidate in candidates where candidate.exists {
            return candidate
        }
        return candidates[0]
    }

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

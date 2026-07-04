//
//  CupcakeOfflineFlowUITests.swift
//  CupcakeUITests
//

import XCTest

/// Exercises the entire standalone/offline flow end-to-end through the real UI, with no backend
/// or credentials involved: Continue Offline -> create a bare local protocol -> add a section ->
/// rename it -> add a step (with duration) within it -> attach a reagent -> start a session ->
/// add a text annotation. This is the flow the app's offline mode exists to make testable
/// without a live server (see AppSession's doc comment), and its shape (section always created
/// before a step, protocol created bare with no forced first step, session creation via a
/// name/enabled form) is verified against the reference web app, not invented.
final class CupcakeOfflineFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOfflineProtocolSessionAndAnnotationFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        // 1. Login screen appears with a clean, signed-out/non-standalone state.
        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5), "Login screen should show a Continue Offline button")

        continueOfflineButton.tap()

        // 2. Standalone mode shows the protocol list (empty at first) instead of the login form.
        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)

        // 3. Create a bare protocol — title only, matching the reference web app's
        // protocol-create-modal.ts (no section/step created alongside it).
        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Sample Prep")
        app.buttons["createProtocolButton"].tap()

        // 4. The new protocol appears in the list; select it.
        let protocolRow = app.staticTexts["Sample Prep"]
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 5))
        protocolRow.tap()

        // 5. Add a section — created instantly with a default name, matching the reference web
        // app's createSection() (no dialog), then rename it.
        tapToolbarButton("addSectionButton", label: "Add Section", in: app)

        let defaultSectionHeader = app.staticTexts["New Section 1"]
        XCTAssertTrue(defaultSectionHeader.waitForExistence(timeout: 5), "A new section should appear instantly with a default name")

        app.buttons["renameSectionButton"].firstMatch.tap()

        let renameField = firstExisting(app.textViews["addTextSheetField"], app.textFields["addTextSheetField"])
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.tap()
        selectAllAndReplace(renameField, with: "Analysis")
        app.buttons["addTextSheetSaveButton"].tap()

        XCTAssertTrue(app.staticTexts["Analysis"].waitForExistence(timeout: 5), "The section should show its new name")

        // 6. Add a step within that section — a section must exist before a step can be added
        // to it, which is exactly what this exercises.
        //
        // A plain `.tap()` here can report "not hittable" even though the element exists with a
        // valid on-screen frame — the accessibility dump shows a second full-screen window at
        // the same bounds as the main one immediately after the rename sheet's dismissal,
        // confusing XCUITest's hit-test gate (waiting for `isHittable` didn't help; it appears
        // to stay stuck rather than flip once the transition settles). Tap the element's own
        // resolved coordinate directly instead, which bypasses that gate.
        let addStepButton = app.buttons["addStepButton"].firstMatch
        XCTAssertTrue(addStepButton.waitForExistence(timeout: 5))
        addStepButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let stepField = firstExisting(app.textViews["addTextSheetField"], app.textFields["addTextSheetField"])
        XCTAssertTrue(stepField.waitForExistence(timeout: 5))
        stepField.tap()
        stepField.typeText("Run the assay")

        let stepDurationField = app.textFields["stepDurationField"]
        XCTAssertTrue(stepDurationField.waitForExistence(timeout: 5))
        stepDurationField.tap()
        stepDurationField.typeText("15")

        app.buttons["addTextSheetSaveButton"].tap()

        let newStepRow = app.staticTexts["Run the assay (15 min)"]
        XCTAssertTrue(newStepRow.waitForExistence(timeout: 5), "The manually-added step should show its entered duration")
        XCTAssertTrue(app.staticTexts["Analysis (15 min)"].waitForExistence(timeout: 5), "The section's duration should auto-update to the sum of its steps' durations")

        // 7. Attach a (newly-created) reagent to that step — completes the
        // Protocol -> Section -> Step -> StepReagent authoring hierarchy. Name is a typeahead
        // (no existing reagents yet, so no suggestions appear) and unit is a fixed-list dropdown
        // — both verified against the reference web app's step-reagent-modal.ts, not invented.
        app.buttons["attachReagentButton"].firstMatch.tap()

        let reagentNameField = app.textFields["reagentNameField"]
        XCTAssertTrue(reagentNameField.waitForExistence(timeout: 5))
        reagentNameField.tap()
        reagentNameField.typeText("NaOH")

        selectPickerOption("reagentUnitPicker", option: "mL", in: app)

        let reagentQuantityField = app.textFields["reagentQuantityField"]
        reagentQuantityField.tap()
        reagentQuantityField.typeText("10")

        app.buttons["saveReagentButton"].tap()

        let attachedReagent = app.staticTexts["NaOH: 10 mL"]
        XCTAssertTrue(attachedReagent.waitForExistence(timeout: 5), "The attached reagent should appear under its step")

        // 8. Start a session — via a name/enabled form, matching session-create-modal.ts.
        tapToolbarButton("newSessionButton", label: "New Session", in: app)

        let startSessionButton = app.buttons["startSessionButton"]
        XCTAssertTrue(startSessionButton.waitForExistence(timeout: 5))
        startSessionButton.tap()

        // 9. Add a text annotation to the step.
        let addNoteButton = app.buttons["addNoteButton"].firstMatch
        XCTAssertTrue(addNoteButton.waitForExistence(timeout: 5))
        addNoteButton.tap()

        let noteField = firstExisting(app.textViews["noteTextField"], app.textFields["noteTextField"])
        XCTAssertTrue(noteField.waitForExistence(timeout: 5))
        noteField.tap()
        noteField.typeText("Gloves are on.")

        app.buttons["saveNoteButton"].tap()

        // 10. The annotation shows up in the step's list, entirely offline.
        let savedAnnotation = app.staticTexts["Gloves are on."]
        XCTAssertTrue(savedAnnotation.waitForExistence(timeout: 5), "The locally-created annotation should appear without any network access")
    }

    /// Selects an option from a SwiftUI `Picker` in a `Form` — on iOS this pushes a new list
    /// screen (tapping an option auto-pops back); on macOS it opens a pull-down menu.
    @MainActor
    private func selectPickerOption(_ identifier: String, option: String, in app: XCUIApplication) {
        let picker = firstExisting(app.popUpButtons[identifier], app.buttons[identifier], app.otherElements[identifier])
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Picker \"\(identifier)\" not found")
        picker.tap()

        let optionElement = firstExisting(app.buttons[option], app.staticTexts[option], app.menuItems[option])
        XCTAssertTrue(optionElement.waitForExistence(timeout: 5), "Picker option \"\(option)\" not found")
        optionElement.tap()
    }

    private func firstExisting(_ candidates: XCUIElement...) -> XCUIElement {
        for candidate in candidates where candidate.exists {
            return candidate
        }
        return candidates[0]
    }

    /// Selects all existing text in a field and replaces it — used for renaming a
    /// pre-filled field (e.g. the default "New Section N" name) rather than appending to it.
    private func selectAllAndReplace(_ field: XCUIElement, with newText: String) {
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(newText)
        #else
        // Tapping a TextField with existing content places the cursor at the *start* on iOS,
        // not the end (confirmed: backspaces after a plain `.tap()` deleted nothing, and the
        // new text got prepended instead of replacing anything). Tap near the trailing edge to
        // put the cursor at the end first, then backspace more than enough times to clear it.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        for _ in 0..<40 {
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        field.typeText(newText)
        #endif
    }

    /// On macOS, SwiftUI can collapse secondary `ToolbarItem`s into an overflow "more toolbar
    /// items" popup regardless of available window width (reproduced against this app even at
    /// 1200pt wide) — a macOS toolbar-customization behavior, not a window-sizing problem. Falls
    /// back to opening that popup and tapping the item inside it by its visible label when the
    /// button isn't directly visible: overflow menu items expose their label as `title`, not the
    /// SwiftUI accessibility identifier (confirmed via the failed run's accessibility dump — the
    /// item shows up as `identifier: '_simpleOverflowMenuItemClicked:', title: 'New Protocol'`).
    /// On iOS there's no such overflow, so the direct-tap path is all that ever runs there.
    @MainActor
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
}

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

    /// Storage/Instruments are read-only lookup tabs — in standalone mode there's no server to
    /// sync from, so both should render their empty state cleanly rather than crash or show
    /// nothing at all.
    @MainActor
    func testStorageAndInstrumentTabsShowEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapTab("Storage", in: app)
        XCTAssertTrue(app.staticTexts["Empty"].waitForExistence(timeout: 5), "Storage tab should show its empty state with no synced data")

        tapTab("Instruments", in: app)
        XCTAssertTrue(app.staticTexts["No Instruments"].waitForExistence(timeout: 5), "Instruments tab should show its empty state with no synced data")
    }

    /// Hits the real, live `noatgnu/cupcake-webgui` GitHub release from inside the actual app
    /// sandbox — not just the package test target — since network access, temp-file writes, and
    /// the SQLite C API can all behave differently under the app's entitlements/sandbox than in
    /// a plain `swift test` process.
    @MainActor
    func testOfflineOntologyDataImportsTissueTable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapTab("Settings", in: app)

        let ontologyLink = elementContaining("Offline Ontology Data", in: app)
        XCTAssertTrue(ontologyLink.waitForExistence(timeout: 5))
        ontologyLink.tap()

        let tissueImportButton = app.buttons["importOntologyButton_tissue"]
        XCTAssertTrue(tissueImportButton.waitForExistence(timeout: 15), "The live manifest should load and show a Tissue row")
        tissueImportButton.tap()

        XCTAssertTrue(elementContaining("Imported", in: app).waitForExistence(timeout: 20), "Tissue import should complete and show an 'Imported' timestamp")
    }

    /// `submit`/`cancel` require the job to already have a `serverID` (a live-synced job), so
    /// standalone mode can't exercise those — this covers what standalone mode *can* verify:
    /// creating a project inline alongside a new job, and both showing up correctly offline.
    @MainActor
    func testCreateJobWithNewProjectOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapTab("Jobs", in: app)

        tapToolbarButton("newJobButton", label: "New Job", in: app)

        let jobNameField = app.textFields["newJobNameField"]
        XCTAssertTrue(jobNameField.waitForExistence(timeout: 5))
        jobNameField.tap()
        jobNameField.typeText("LC-MS Run 1")

        let createProjectToggle = app.switches["newJobCreateProjectToggle"]
        XCTAssertTrue(createProjectToggle.waitForExistence(timeout: 5))
        createProjectToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        let newProjectNameField = app.textFields["newJobNewProjectNameField"]
        XCTAssertTrue(newProjectNameField.waitForExistence(timeout: 5))
        newProjectNameField.tap()
        newProjectNameField.typeText("Proteomics Study")

        app.buttons["createJobButton"].tap()

        let jobRow = elementContaining("LC-MS Run 1", in: app)
        XCTAssertTrue(jobRow.waitForExistence(timeout: 5), "The newly-created job should appear in the Jobs list")
        XCTAssertTrue(elementContaining("Proteomics Study", in: app).waitForExistence(timeout: 5), "The job's row should show its new project's name")

        jobRow.tap()
        XCTAssertTrue(elementContaining("Pending sync", in: app).waitForExistence(timeout: 5), "A standalone-mode job has no serverID, so it should show as pending sync")

        let submitButton = app.buttons["submitJobButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        XCTAssertFalse(submitButton.isEnabled, "Submit should stay disabled until the job has actually synced to the server")
    }

    /// `CachedStorageObject`/`CachedInstrument` are read-only server data (never
    /// offline-createable), so exercising `AddStoredReagentSheet`/`BookInstrumentSheet` in
    /// standalone mode needs a fake "already synced" location/instrument seeded ahead of time —
    /// see `--ui-testing-seed-storage-instrument` in `CupcakeApp.init()`.
    @MainActor
    func testAddStoredReagentAndBookInstrumentOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state", "--ui-testing-seed-storage-instrument"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        // 1. Drill into the seeded storage location and add a reagent.
        let storageTab = firstExisting(app.tabBars.buttons["Storage"], app.buttons["Storage"], app.radioButtons["Storage"])
        XCTAssertTrue(storageTab.waitForExistence(timeout: 5))
        storageTab.tap()

        // NavigationLink rows can expose as a single Button (macOS) or nested StaticTexts (iOS)
        // depending on their content — matches the earlier tab-bar discovery, same reasoning.
        let shelfRow = firstExisting(app.staticTexts["Test Shelf"], app.buttons["Test Shelf"])
        XCTAssertTrue(shelfRow.waitForExistence(timeout: 5))
        shelfRow.tap()

        tapToolbarButton("addStoredReagentButton", label: "Add Reagent", in: app)

        let reagentNameField = app.textFields["newStoredReagentNameField"]
        XCTAssertTrue(reagentNameField.waitForExistence(timeout: 5))
        reagentNameField.tap()
        reagentNameField.typeText("NaCl")

        selectPickerOption("newStoredReagentUnitPicker", option: "g", in: app)

        let quantityField = app.textFields["newStoredReagentQuantityField"]
        quantityField.tap()
        quantityField.typeText("500")

        app.buttons["saveStoredReagentButton"].tap()

        // A NavigationLink row's multi-line VStack collapses into one comma-joined accessibility
        // label on macOS (confirmed via the accessibility dump: "NaCl, 500 g", not just "NaCl"),
        // so match by substring rather than an exact label.
        let reagentRow = elementContaining("NaCl", in: app)
        XCTAssertTrue(reagentRow.waitForExistence(timeout: 5), "The newly-added reagent should appear in the location's list")

        // 2. Open it and record a "reserve" action against it.
        reagentRow.tap()

        app.buttons["recordActionButton"].tap()

        // `.pickerStyle(.segmented)` exposes as a RadioGroup of RadioButtons on macOS, and as
        // plain Buttons in an OtherElement group on iOS — neither matches the menu-style
        // `selectPickerOption` helper (which expects a PopUpButton/pushed list), so select the
        // segment directly instead.
        let reserveSegment = firstExisting(app.radioButtons["Reserve"], app.buttons["Reserve"])
        XCTAssertTrue(reserveSegment.waitForExistence(timeout: 5), "\"Reserve\" segment not found")
        reserveSegment.tap()

        let actionQuantityField = app.textFields["reagentActionQuantityField"]
        XCTAssertTrue(actionQuantityField.waitForExistence(timeout: 5))
        actionQuantityField.tap()
        actionQuantityField.typeText("50")

        app.buttons["saveReagentActionButton"].tap()

        XCTAssertTrue(elementContaining("Reserve 50", in: app).waitForExistence(timeout: 5), "The recorded action should appear in the reagent's history")
        XCTAssertTrue(elementContaining("450", in: app).waitForExistence(timeout: 5), "Current Quantity should reflect the reserve action immediately, offline")

        // 3. Book the seeded instrument.
        let instrumentsTab = firstExisting(app.tabBars.buttons["Instruments"], app.buttons["Instruments"], app.radioButtons["Instruments"])
        instrumentsTab.tap()

        let instrumentRow = elementContaining("Test Centrifuge", in: app)
        XCTAssertTrue(instrumentRow.waitForExistence(timeout: 5))
        instrumentRow.tap()

        tapToolbarButton("bookInstrumentButton", label: "Book", in: app)

        let descriptionField = app.textFields["bookingDescriptionField"]
        XCTAssertTrue(descriptionField.waitForExistence(timeout: 5))
        descriptionField.tap()
        descriptionField.typeText("Spin down samples")

        app.buttons["saveBookingButton"].tap()

        XCTAssertTrue(app.staticTexts["Spin down samples"].waitForExistence(timeout: 5), "The newly-created booking should appear in the instrument's Bookings section")
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

    /// A multi-`Text` `VStack` inside a `NavigationLink` row collapses into one comma-joined
    /// accessibility label on macOS (confirmed via the accessibility dump: a row showing
    /// "NaCl" + "500 g" on two lines exposes as a single Button labeled "NaCl, 500 g") — matches
    /// by substring across both `staticTexts` and `buttons`, since which element type wins
    /// depends on the row's exact content and isn't worth predicting up front. Also checks
    /// `value`, not just `label` — a plain `Text` exposes its content via AX `value`.
    private func elementContaining(_ substring: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        return firstExisting(app.staticTexts.matching(predicate).firstMatch, app.buttons.matching(predicate).firstMatch)
    }

    /// Taps a tab by its label, falling back to iOS's "More" overflow tab when there are more
    /// than 4 tabs (confirmed via the accessibility dump: a 6th tab like "Jobs"/"Settings" pushes
    /// both into a `TabBar`'s "More" button, exposing the rest in a pushed list) — a different
    /// overflow mechanism from macOS's toolbar "more toolbar items" popup, and from the
    /// RadioGroup/Button distinction `firstExisting` already handles for a directly-visible tab.
    @MainActor
    private func tapTab(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let direct = firstExisting(app.tabBars.buttons[label], app.buttons[label], app.radioButtons[label])
        if direct.waitForExistence(timeout: timeout) {
            direct.tap()
            return
        }

        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: timeout), "Neither \"\(label)\" nor a \"More\" tab overflow was found")
        more.tap()

        let itemInMore = firstExisting(app.staticTexts[label], app.buttons[label], app.cells[label])
        XCTAssertTrue(itemInMore.waitForExistence(timeout: timeout), "\"\(label)\" was not found inside the tab bar's More list")
        itemInMore.tap()
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

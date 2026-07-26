import XCTest

#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class CupcakeAppStoreScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let instrumentNames = [
        "Probe Sonicator (Cell Disruptor)",
        "Beckman Avanti Centrifuge",
        "Roller Mixer",
        "ÄKTA Pure (Chromatography System)",
        "Infors Shaker-Incubator",
    ]

    private static let protocolTitle = "Expression and purification of Rab10 (1-181)"
    private static let sessionName = "Rab10 Prep, Batch 12"

    @MainActor
    func testAppStoreDemoScreenshotTour() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        signIn(app)

        guard let protocolRow = waitForMatch(containing: Self.protocolTitle, in: app, timeout: 30) else {
            XCTFail("The seeded protocol should appear once synced")
            return
        }
        captureScreenshot("01_protocols_list", in: app)

        protocolRow.tap()
        XCTAssertTrue(waitForTextAppearing("Overnight culture", in: app, timeout: 15), "The protocol's first section should be visible")
        captureScreenshot("02_protocol_detail", in: app)

        XCTAssertTrue(tapFirstMatch(identifierPrefix: "sectionRow_", in: app, timeout: 10, untilIdentifierPrefixAppears: "stepRow_"), "The Overnight culture section's steps should appear")
        XCTAssertTrue(tapFirstMatch(identifierPrefix: "stepRow_", in: app, timeout: 10, untilIdentifierPrefixAppears: "editReagentButton_"), "The step detail's Reagents section should appear")
        captureScreenshot("03_step_detail_reagent", in: app)
        navigateToRoot(untilStaticTextHittable: "All Protocols", in: app)

        tapTab("Inventory", in: app, timeout: 15)
        tapSegment("Storage", in: app)
        XCTAssertTrue(waitForTextAppearing("Cold Room Shelf A", in: app, timeout: 15), "The seeded storage locations should appear once synced")
        captureScreenshot("04_storage_list", in: app)

        tapSegment("Instruments", in: app)
        XCTAssertTrue(waitForTextAppearing("Accepts Bookings", in: app, timeout: 15), "The seeded instruments should appear once synced")
        captureScreenshot("05_instruments_list", in: app)

        XCTAssertTrue(tapFirstMatch(labelContainsAnyOf: Self.instrumentNames, in: app, timeout: 15), "An instrument row should be tappable")
        XCTAssertTrue(waitForTextAppearing("Bookings", in: app, timeout: 10), "The instrument detail's Bookings section should appear")
        captureScreenshot("06_instrument_detail_booking", in: app)

        tapSegment("Storage", in: app, timeout: 15)
        tapTab("Sessions", in: app, timeout: 15)
        guard let sessionRow = waitForMatch(containing: Self.sessionName, in: app, timeout: 15) else {
            XCTFail("The seeded session should appear once synced")
            return
        }
        captureScreenshot("07_sessions_list", in: app)

        sessionRow.tap()
        XCTAssertTrue(waitForTextAppearing("pipette tip", in: app, timeout: 15), "The session detail should show its attached protocol's steps")
        captureScreenshot("08_session_detail", in: app)
    }

    @MainActor
    func testAnnotationExamplesScreenshotFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        signIn(app)

        guard let protocolRow = waitForMatch(containing: Self.protocolTitle, in: app, timeout: 30) else {
            XCTFail("The seeded protocol should appear once synced")
            return
        }
        protocolRow.tap()
        XCTAssertTrue(waitForTextAppearing("Overnight culture", in: app, timeout: 15), "The protocol's first section should be visible")
        navigateToRoot(untilStaticTextHittable: "All Protocols", in: app)

        tapTab("Sessions", in: app, timeout: 15)
        guard let sessionRow = waitForMatch(containing: Self.sessionName, in: app, timeout: 15) else {
            XCTFail("The seeded session should appear once synced")
            return
        }
        sessionRow.tap()
        XCTAssertTrue(waitForTextAppearing("pipette tip", in: app, timeout: 15), "The session detail should show its attached protocol's steps")

        let addAnnotationButton = app.buttons["addStepAnnotationButton"].firstMatch
        scrollDownUntilVisible(addAnnotationButton, in: app)
        XCTAssertTrue(addAnnotationButton.waitForExistence(timeout: 10), "The step's Add annotation button should appear")
        addAnnotationButton.tap()

        let textKind = app.buttons["annotationKind_text"]
        XCTAssertTrue(textKind.waitForExistence(timeout: 10), "The annotation type picker should offer a text note")
        textKind.tap()

        let noteField = app.textFields["noteTextField"]
        XCTAssertTrue(noteField.waitForExistence(timeout: 10), "The note text field should appear")
        noteField.tap()
        noteField.typeText("Colonies picked from plate 3 look healthy, proceeding with overnight culture.")

        let saveNoteButton = app.buttons["saveNoteButton"]
        XCTAssertTrue(saveNoteButton.isEnabled, "Save should be enabled once the note has text")
        saveNoteButton.tap()

        XCTAssertTrue(waitForTextAppearing("Colonies picked from plate 3", in: app, timeout: 15), "The saved text note should appear in the session")
        captureScreenshot("13_text_annotation", in: app)

        let addAnnotationButtonAgain = app.buttons["addStepAnnotationButton"].firstMatch
        scrollDownUntilVisible(addAnnotationButtonAgain, in: app)
        XCTAssertTrue(addAnnotationButtonAgain.waitForExistence(timeout: 10))
        addAnnotationButtonAgain.tap()

        let calculatorKind = app.buttons["annotationKind_calculator"]
        XCTAssertTrue(calculatorKind.waitForExistence(timeout: 10), "The annotation type picker should offer a calculator")
        calculatorKind.tap()

        app.buttons["calcButton_7"].tap()
        app.buttons["calcButton_+"].tap()
        app.buttons["calcButton_3"].tap()
        app.buttons["calcButton_="].tap()

        let saveCalculatorButton = app.buttons["saveCalculatorButton"]
        XCTAssertTrue(saveCalculatorButton.waitForExistence(timeout: 10) && saveCalculatorButton.isEnabled, "Save should be enabled once a calculation has been completed")
        captureScreenshot("14_calculator_annotation", in: app)
        saveCalculatorButton.tap()

        XCTAssertTrue(waitForTextAppearing("7 + 3 = 10", in: app, timeout: 15), "The saved calculator note should appear in the session")
        captureScreenshot("15_calculator_annotation_saved", in: app)
    }

    @MainActor
    func testCreateReusableMetadataTemplateFromSchemaScreenshotFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        signIn(app)
        importSDRFSchemaOntologyData(app)

        let jobSearchField = app.textFields["jobSearchField"]
        var didReachJobsTab = false
        for _ in 0..<3 {
            tapTab("Jobs", in: app, timeout: 15)
            if jobSearchField.waitForExistence(timeout: 8) {
                didReachJobsTab = true
                break
            }
        }
        XCTAssertTrue(didReachJobsTab, "Switching to the Jobs tab should reach the job list")
        tapToolbarButton("manageMetadataTableTemplatesButton", label: "Table Templates", in: app, timeout: 15)
        XCTAssertTrue(app.buttons["newMetadataTableTemplateButton"].waitForExistence(timeout: 10), "Table Template Management should open")
        app.buttons["newMetadataTableTemplateButton"].tap()

        let fromSchemaSegment = firstExisting(app.radioButtons["From Schema"], app.buttons["From Schema"])
        XCTAssertTrue(fromSchemaSegment.waitForExistence(timeout: 10), "\"From Schema\" mode should be selectable")
        fromSchemaSegment.tap()

        let nameField = app.textFields["newTemplateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Rab10 Proteomics QC Template")

        let searchField = app.textFields["schemaSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "A schema list appropriate to the protocol should be searchable")

        searchField.tap()
        searchField.typeText("human")
        let humanRow = app.buttons["schemaRow_human"]
        XCTAssertTrue(humanRow.waitForExistence(timeout: 10), "The \"human\" schema should appear")
        humanRow.tap()

        clearAndType(in: searchField, with: "ms-proteomics", in: app)
        let msProteomicsRow = app.buttons["schemaRow_ms-proteomics"]
        XCTAssertTrue(msProteomicsRow.waitForExistence(timeout: 10), "The \"ms-proteomics\" schema should appear")
        msProteomicsRow.tap()

        captureScreenshot("09_create_template_from_schema", in: app)

        let createButton = app.buttons["createTemplateButton"]
        XCTAssertTrue(createButton.isEnabled, "Create should be enabled once a name and at least one schema are selected")
        createButton.tap()

        XCTAssertTrue(waitForTextAppearing("Rab10 Proteomics QC Template", in: app, timeout: 10), "The new reusable template should appear in the template list")
        captureScreenshot("10_template_created", in: app)
    }

    @MainActor
    func testOrganismTypeaheadFavouriteDisplayNameScreenshotFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        signIn(app)

        let jobSearchField = app.textFields["jobSearchField"]
        var didReachJobsTab = false
        for _ in 0..<3 {
            tapTab("Jobs", in: app, timeout: 15)
            if jobSearchField.waitForExistence(timeout: 8) {
                didReachJobsTab = true
                break
            }
        }
        XCTAssertTrue(didReachJobsTab, "Switching to the Jobs tab should reach the job list")
        jobSearchField.tap()
        jobSearchField.typeText("QC Metadata Review")
        guard let jobRow = waitForMatch(containing: "QC Metadata Review", in: app, timeout: 30) else {
            XCTFail("The seeded QC job should appear once synced")
            return
        }
        jobRow.tap()

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        let organismRow = app.buttons["metadataColumnRow_characteristics[organism]"]
        gentleScrollUntilEitherVisible(createFromTemplateButton, organismRow, in: app)

        if createFromTemplateButton.exists, createFromTemplateButton.isHittable {
            createFromTemplateButton.tap()

            let templateRow = app.buttons["metadataTemplateRow_QC Metadata Review Template"]
            XCTAssertTrue(templateRow.waitForExistence(timeout: 10), "The reusable template shared with this job's lab group should appear")
            templateRow.tap()

            let sampleCountField = app.textFields["metadataSampleCountField"]
            if sampleCountField.waitForExistence(timeout: 5), (sampleCountField.value as? String)?.isEmpty != false {
                sampleCountField.tap()
                sampleCountField.typeText("4")
            }

            app.buttons["createMetadataTableButton"].tap()
            gentleScrollUntilVisible(organismRow, in: app)
        }

        XCTAssertTrue(organismRow.waitForExistence(timeout: 15), "The characteristics[organism] column row should appear")

        let valueField = app.textFields["metadataValueField"]
        var openedEditor = false
        for _ in 0..<3 {
            organismRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if valueField.waitForExistence(timeout: 8) {
                openedEditor = true
                break
            }
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.exists, cancelButton.isHittable {
                cancelButton.tap()
            }
            Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(openedEditor, "The Edit Value sheet should open")

        let startsWithSegment = firstExisting(app.radioButtons["Starts With"], app.buttons["Starts With"])
        XCTAssertTrue(startsWithSegment.waitForExistence(timeout: 10), "The Contains/Starts With match-type control should appear once the column has an ontology type")
        startsWithSegment.tap()

        clearAndType(in: valueField, with: "Homo sap", in: app)

        let suggestionRow = app.buttons["ontologySuggestionRow_Homo sapiens"]
        XCTAssertTrue(suggestionRow.waitForExistence(timeout: 15), "A live \"Homo sapiens\" ontology suggestion should appear alongside other \"Homo sap...\" matches")
        captureScreenshot("11_organism_typeahead", in: app)

        suggestionRow.tap()

        let displayNameField = app.textFields["favouriteDisplayNameField"]
        scrollDownUntilVisible(displayNameField, in: app)
        XCTAssertTrue(displayNameField.waitForExistence(timeout: 10))
        displayNameField.tap()
        displayNameField.typeText("Human")

        let addFavouriteButton = app.buttons["addFavourite_Personal"]
        scrollDownUntilVisible(addFavouriteButton, in: app)
        XCTAssertTrue(addFavouriteButton.waitForExistence(timeout: 5))
        addFavouriteButton.tap()

        XCTAssertTrue(waitForTextAppearing("Human", in: app, timeout: 10), "The new favourite should be listed with its custom display name")
        captureScreenshot("12_favourite_custom_display_name", in: app)

        let saveButton = app.buttons["saveMetadataValueButton"]
        if saveButton.exists, saveButton.isEnabled {
            saveButton.tap()
        }

        dismissKeyboardIfPresent(in: app)
    }

    @MainActor
    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.count > 0 else { return }
        let navigationBar = app.navigationBars.firstMatch
        if navigationBar.exists {
            navigationBar.tap()
        }
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)
    }

    @MainActor
    private func captureScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 5))
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/")

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("appstoredemo")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("AppStoreDemo123!")

        app.buttons["signInButton"].tap()
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with newText: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        field.tap()
        for _ in 0..<3 {
            field.typeKey("a", modifierFlags: .command)
            field.typeKey("v", modifierFlags: .command)
            if field.value as? String == newText { return }
        }
        XCTAssertEqual(field.value as? String, newText, "Failed to replace field text after multiple attempts")
        #else
        field.tap()
        for _ in 0..<6 {
            if field.value as? String == newText { return }
            field.typeKey("a", modifierFlags: .command)
            field.typeText(newText)
        }
        XCTAssertEqual(field.value as? String, newText, "Failed to replace field text after multiple attempts")
        #endif
    }

    @MainActor
    private func clearAndType(in field: XCUIElement, with newText: String, in app: XCUIApplication) {
        field.tap()
        for _ in 0..<6 {
            if field.value as? String == newText { return }
            field.typeKey("a", modifierFlags: .command)
            field.typeText(newText)
        }
        XCTAssertEqual(field.value as? String, newText, "Failed to clear and type field text after multiple attempts")
    }

    @MainActor
    private func tapTab(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let predicate = NSPredicate(format: "label == %@", label)
            let match = firstExisting(
                app.buttons.matching(predicate).firstMatch,
                app.radioButtons.matching(predicate).firstMatch
            )
            if match.exists, match.isHittable {
                match.tap()
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("Tab \"\(label)\" not found")
    }

    @MainActor
    private func tapSegment(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let segment = firstExisting(app.radioButtons[label], app.buttons[label])
        XCTAssertTrue(segment.waitForExistence(timeout: timeout), "\"\(label)\" segment not found")
        segment.tap()
    }

    @MainActor
    private func tapToolbarButton(_ identifier: String, label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: timeout) {
            direct.tap()
            return
        }

        let overflow = firstExisting(
            app.popUpButtons["more toolbar items"],
            app.buttons["more toolbar items"],
            app.buttons["More"]
        )
        guard overflow.waitForExistence(timeout: timeout) else {
            XCTFail("Neither \"\(identifier)\" nor a toolbar overflow menu was found")
            return
        }
        overflow.tap()

        let itemInOverflow = firstExisting(app.menuItems[label], app.buttons[label])
        XCTAssertTrue(itemInOverflow.waitForExistence(timeout: timeout), "\"\(label)\" was not found inside the toolbar overflow menu")
        itemInOverflow.tap()
    }

    @MainActor
    private func scrollDownUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 15) {
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxAttempts {
            app.swipeUp(velocity: .fast)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    @MainActor
    private func gentleScrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 8) {
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxAttempts {
            app.swipeUp(velocity: .slow)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    @MainActor
    private func gentleScrollUntilEitherVisible(_ first: XCUIElement, _ second: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 8) {
        var attempts = 0
        while attempts < maxAttempts {
            if (first.exists && first.isHittable) || (second.exists && second.isHittable) {
                return
            }
            app.swipeUp(velocity: .slow)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    @MainActor
    private func importSDRFSchemaOntologyData(_ app: XCUIApplication) {
        tapTab("Protocols", in: app, timeout: 15)
        tapToolbarButton("settingsButton", label: "Settings", in: app, timeout: 15)

        guard let offlineOntologyRow = waitForMatch(containing: "Offline Ontology Data", in: app, timeout: 10) else {
            XCTFail("The Offline Ontology Data settings section should appear")
            return
        }
        offlineOntologyRow.tap()

        let importButton = app.buttons["importOntologyButton_sdrf"]
        scrollDownUntilVisible(importButton, in: app)
        XCTAssertTrue(importButton.waitForExistence(timeout: 10), "The SDRF Schemas import row should appear")
        importButton.tap()
        XCTAssertTrue(waitForTextAppearing("Imported", in: app, timeout: 120), "The SDRF schema bundle should finish importing")

        app.buttons["Done"].tap()
    }

    private func firstExisting(_ candidates: XCUIElement...) -> XCUIElement {
        for candidate in candidates where candidate.exists {
            return candidate
        }
        return candidates[0]
    }

    @MainActor
    @discardableResult
    private func tapFirstMatch(identifierPrefix: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in [app.buttons, app.cells, app.staticTexts] {
                let match = query.matching(predicate).firstMatch
                if match.exists, match.isHittable {
                    match.tap()
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    @MainActor
    private func waitForIdentifierPrefix(_ prefix: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for query in [app.buttons, app.cells, app.staticTexts] {
                if query.matching(predicate).firstMatch.exists { return true }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    @MainActor
    @discardableResult
    private func tapFirstMatch(identifierPrefix: String, in app: XCUIApplication, timeout: TimeInterval, untilIdentifierPrefixAppears expectedPrefix: String, attempts: Int = 3) -> Bool {
        for _ in 0..<attempts {
            guard tapFirstMatch(identifierPrefix: identifierPrefix, in: app, timeout: timeout) else { continue }
            if waitForIdentifierPrefix(expectedPrefix, in: app, timeout: 4) {
                return true
            }
        }
        return false
    }

    @MainActor
    @discardableResult
    private func tapFirstMatch(labelContainsAnyOf substrings: [String], in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for substring in substrings {
                let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
                for query in [app.buttons, app.staticTexts, app.cells] {
                    let match = query.matching(predicate).firstMatch
                    if match.exists, match.isHittable {
                        match.tap()
                        return true
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    @MainActor
    private func navigateToRoot(untilStaticTextHittable marker: String, in app: XCUIApplication, maxAttempts: Int = 6) {
        for _ in 0..<maxAttempts {
            if app.staticTexts[marker].isHittable {
                return
            }
            navigateBack(in: app)
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let breadcrumbBack = app.buttons["breadcrumbBackButton"]
        if breadcrumbBack.exists, breadcrumbBack.isHittable {
            breadcrumbBack.tap()
            return
        }
        for button in app.navigationBars.buttons.allElementsBoundByIndex {
            if !button.identifier.isEmpty || button.label == "More" {
                continue
            }
            if button.isHittable {
                button.tap()
                return
            }
        }
    }

    @MainActor
    private func waitForMatch(containing substring: String, in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let staticText = app.staticTexts.matching(predicate).firstMatch
            if staticText.exists { return staticText }
            let button = app.buttons.matching(predicate).firstMatch
            if button.exists { return button }
            let cell = app.cells.matching(predicate).firstMatch
            if cell.exists { return cell }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
    }

    @MainActor
    private func waitForTextAppearing(_ substring: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.staticTexts.matching(predicate).firstMatch.exists { return true }
            if app.buttons.matching(predicate).firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }
}

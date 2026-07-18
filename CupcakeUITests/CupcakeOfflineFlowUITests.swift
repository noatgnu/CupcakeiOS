
import XCTest

#if os(iOS)
import UIKit
#endif

final class CupcakeOfflineFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testReenteringSameProtocolAfterBackNavigatesCorrectly() throws {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("This regression is specific to compact width's push navigation — regular width (iPad/Mac) shows detail inline with nothing to pop.")
        }
        #else
        throw XCTSkip("This regression is specific to compact width's push navigation — regular width (iPad/Mac) shows detail inline with nothing to pop.")
        #endif
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)
        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Reentry Test")
        app.buttons["createProtocolButton"].tap()

        let protocolRow = app.staticTexts["Reentry Test"]
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 5))
        protocolRow.tap()

        XCTAssertTrue(app.navigationBars["Reentry Test"].waitForExistence(timeout: 5), "Should navigate into the protocol on first tap")

        navigateBack(in: app)
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 5), "Should be back at the protocol list")

        protocolRow.tap()
        XCTAssertTrue(app.navigationBars["Reentry Test"].waitForExistence(timeout: 5), "Re-entering the same protocol after backing out should navigate in again, not freeze")
    }

    @MainActor
    func testOfflineProtocolSessionAndAnnotationFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5), "Login screen should show a Continue Offline button")

        continueOfflineButton.tap()

        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)

        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Sample Prep")
        app.buttons["createProtocolButton"].tap()

        let protocolRow = app.staticTexts["Sample Prep"]
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 5))
        protocolRow.tap()

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

        let addStepButton = app.buttons["addStepButton"].firstMatch
        XCTAssertTrue(addStepButton.waitForExistence(timeout: 5))
        let stepField = openAddStepSheet(tapping: addStepButton, in: app)
        stepField.tap()
        stepField.typeText("Run the assay")

        let stepDurationField = app.textFields["stepDurationField"]
        XCTAssertTrue(stepDurationField.waitForExistence(timeout: 5))
        stepDurationField.tap()
        stepDurationField.typeText("15")

        app.buttons["addTextSheetSaveButton"].tap()

        XCTAssertTrue(elementContaining("Run the assay", in: app).waitForExistence(timeout: 5), "The manually-added step should show its description")
        XCTAssertTrue(elementContaining("15m", in: app).waitForExistence(timeout: 5), "The manually-added step should show its entered duration")
        XCTAssertTrue(app.staticTexts["Analysis (15m)"].waitForExistence(timeout: 5), "The section's duration should auto-update to the sum of its steps' durations")

        elementContaining("Run the assay", in: app).tap()
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

        XCTAssertTrue(elementContaining("NaOH: 10 mL", in: app).waitForExistence(timeout: 5), "The attached reagent should appear in the step's own detail screen")
        navigateBack(in: app)

        openStartSessionSheet(in: app)
        app.buttons["startSessionButton"].tap()

        let addStepAnnotationButton = app.buttons["addStepAnnotationButton"].firstMatch
        XCTAssertTrue(addStepAnnotationButton.waitForExistence(timeout: 5))
        addStepAnnotationButton.tap()

        let textKindButton = app.buttons["annotationKind_text"].firstMatch
        XCTAssertTrue(textKindButton.waitForExistence(timeout: 5))
        textKindButton.tap()

        let noteField = firstExisting(app.textViews["noteTextField"], app.textFields["noteTextField"])
        XCTAssertTrue(noteField.waitForExistence(timeout: 5))
        noteField.tap()
        noteField.typeText("Gloves are on.")

        app.buttons["saveNoteButton"].tap()

        let savedAnnotation = app.staticTexts["Gloves are on."]
        XCTAssertTrue(savedAnnotation.waitForExistence(timeout: 5), "The locally-created annotation should appear without any network access")
    }

    @MainActor
    func testStorageAndInstrumentTabsShowEmptyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapTab("Inventory", in: app)
        XCTAssertTrue(app.staticTexts["No Sublocations"].waitForExistence(timeout: 5), "Storage section should show its empty state with no synced data")

        tapSegment("Instruments", in: app)
        XCTAssertTrue(app.staticTexts["No Instruments"].waitForExistence(timeout: 5), "Instruments section should show its empty state with no synced data")
    }

    @MainActor
    func testOfflineOntologyDataImportsTissueTable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapTab("Protocols", in: app)
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        tapToolbarButton("settingsButton", label: "Settings", in: app)
        #endif

        let ontologyLink = elementContaining("Offline Ontology Data", in: app)
        XCTAssertTrue(ontologyLink.waitForExistence(timeout: 5))
        ontologyLink.tap()

        let tissueImportButton = app.buttons["importOntologyButton_tissue"]
        XCTAssertTrue(tissueImportButton.waitForExistence(timeout: 15), "The live manifest should load and show a Tissue row")
        tissueImportButton.tap()

        XCTAssertTrue(elementContaining("Imported", in: app).waitForExistence(timeout: 20), "Tissue import should complete and show an 'Imported' timestamp")
    }

    @MainActor
    func testCreateProjectOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapTab("Jobs", in: app)
        tapToolbarButton("projectsLink", label: "Projects", in: app)
        tapToolbarButton("newProjectButton", label: "New Project", in: app)

        let projectNameField = app.textFields["newProjectNameField"]
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 5))
        projectNameField.tap()
        projectNameField.typeText("Proteomics Study")
        app.buttons["createProjectButton"].tap()

        XCTAssertTrue(elementContaining("Proteomics Study", in: app).waitForExistence(timeout: 5), "The new project should appear in the Projects list")
    }

    @MainActor
    func testCreateJobOffline() throws {
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

        app.buttons["createJobButton"].tap()

        let jobRow = elementContaining("LC-MS Run 1", in: app)
        XCTAssertTrue(jobRow.waitForExistence(timeout: 5), "The newly-created job should appear in the Jobs list")

        jobRow.tap()
        XCTAssertTrue(elementContaining("Pending sync", in: app).waitForExistence(timeout: 5), "A standalone-mode job has no serverID, so it should show as pending sync")

        let submitButton = app.buttons["submitJobButton"]
        XCTAssertTrue(submitButton.waitForExistence(timeout: 5))
        XCTAssertFalse(submitButton.isEnabled, "Submit should stay disabled until the job has actually synced to the server")

        let createMetadataButton = app.buttons["createMetadataFromTemplateButton"]
        XCTAssertTrue(createMetadataButton.waitForExistence(timeout: 5))
        XCTAssertFalse(createMetadataButton.isEnabled, "Creating a metadata table needs a synced job serverID too")

        XCTAssertFalse(app.descendants(matching: .any)["jobLabGroupPicker"].exists, "Lab group assignment needs a serverID, so its whole section shouldn't render for an unsynced job")

        let bookInstrumentButton = app.buttons["bookInstrumentForJobButton"]
        XCTAssertTrue(bookInstrumentButton.waitForExistence(timeout: 5))
        XCTAssertFalse(bookInstrumentButton.isEnabled, "Booking an instrument needs both a synced job serverID and an existing metadata table")
    }

    @MainActor
    func testAddStoredReagentAndBookInstrumentOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state", "--ui-testing-seed-storage-instrument"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapTab("Inventory", in: app)

        let shelfRow = app.buttons["storageLocationRow_Test Shelf"]
        XCTAssertTrue(shelfRow.waitForExistence(timeout: 5))
        shelfRow.tap()

        tapMenuItem("storageAddMenu", item: "Add Reagent", in: app)

        let reagentNameField = app.textFields["newStoredReagentNameField"]
        XCTAssertTrue(reagentNameField.waitForExistence(timeout: 5))
        reagentNameField.tap()
        reagentNameField.typeText("NaCl")

        selectPickerOption("newStoredReagentUnitPicker", option: "g", in: app)

        let quantityField = app.textFields["newStoredReagentQuantityField"]
        quantityField.tap()
        quantityField.typeText("500")

        app.buttons["saveStoredReagentButton"].tap()

        let reagentRow = elementContaining("NaCl", in: app)
        XCTAssertTrue(reagentRow.waitForExistence(timeout: 5), "The newly-added reagent should appear in the location's list")

        reagentRow.tap()

        app.buttons["recordActionButton"].tap()

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

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        #endif
        tapSegment("Instruments", in: app)

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

    @MainActor
    func testCalculatorMolarityAndSketchAnnotationsOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)
        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Annotation Types Test")
        app.buttons["createProtocolButton"].tap()

        let protocolRow = app.staticTexts["Annotation Types Test"]
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 5))
        protocolRow.tap()

        tapToolbarButton("addSectionButton", label: "Add Section", in: app)
        let defaultSectionHeader = app.staticTexts["New Section 1"]
        XCTAssertTrue(defaultSectionHeader.waitForExistence(timeout: 5))

        app.buttons["renameSectionButton"].firstMatch.tap()
        let renameField = firstExisting(app.textViews["addTextSheetField"], app.textFields["addTextSheetField"])
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.tap()
        selectAllAndReplace(renameField, with: "Analysis")
        app.buttons["addTextSheetSaveButton"].tap()
        XCTAssertTrue(app.staticTexts["Analysis"].waitForExistence(timeout: 5))

        let addStepButton = app.buttons["addStepButton"].firstMatch
        XCTAssertTrue(addStepButton.waitForExistence(timeout: 5))
        let stepField = openAddStepSheet(tapping: addStepButton, in: app)
        stepField.tap()
        stepField.typeText("Mix reagents")

        let stepDurationField = app.textFields["stepDurationField"]
        XCTAssertTrue(stepDurationField.waitForExistence(timeout: 5))
        stepDurationField.tap()
        stepDurationField.typeText("15")

        app.buttons["addTextSheetSaveButton"].tap()
        XCTAssertTrue(elementContaining("Mix reagents", in: app).waitForExistence(timeout: 5))

        elementContaining("Mix reagents", in: app).tap()
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
        XCTAssertTrue(elementContaining("NaOH: 10 mL", in: app).waitForExistence(timeout: 5))
        navigateBack(in: app)

        openStartSessionSheet(in: app)
        app.buttons["startSessionButton"].tap()

        let addStepAnnotationButton = app.buttons["addStepAnnotationButton"].firstMatch
        XCTAssertTrue(addStepAnnotationButton.waitForExistence(timeout: 5))
        addStepAnnotationButton.tap()
        let molarityKindButton = app.buttons["annotationKind_molarityCalculator"].firstMatch
        XCTAssertTrue(molarityKindButton.waitForExistence(timeout: 5))
        molarityKindButton.tap()

        let concentrationField = app.textFields["molarityConcentrationField"]
        XCTAssertTrue(concentrationField.waitForExistence(timeout: 5))
        concentrationField.tap()
        concentrationField.typeText("1")

        let volumeField = app.textFields["molarityVolumeField"]
        volumeField.tap()
        volumeField.typeText("1")

        let mwField = app.textFields["molarityMolecularWeightField"]
        mwField.tap()
        mwField.typeText("100")

        app.buttons["calculateMolarityButton"].tap()

        let saveMolarityButton = app.buttons["saveMolarityButton"]
        XCTAssertTrue(saveMolarityButton.waitForExistence(timeout: 5))
        let calculateSucceeded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: saveMolarityButton)
        XCTAssertEqual(XCTWaiter().wait(for: [calculateSucceeded], timeout: 5), .completed, "Calculating should add a history entry, enabling Save")
        saveMolarityButton.tap()
        XCTAssertTrue(elementContaining("Molarity calculator note", in: app).waitForExistence(timeout: 5), "The saved molarity calculation should appear as a local annotation row immediately, offline")

        XCTAssertTrue(addStepAnnotationButton.waitForExistence(timeout: 5))
        addStepAnnotationButton.tap()
        let calculatorKindButton = app.buttons["annotationKind_calculator"].firstMatch
        XCTAssertTrue(calculatorKindButton.waitForExistence(timeout: 5))
        calculatorKindButton.tap()

        let sevenButton = app.buttons["calcButton_7"]
        XCTAssertTrue(sevenButton.waitForExistence(timeout: 5))
        sevenButton.tap()
        app.buttons["calcButton_+"].tap()
        app.buttons["calcButton_3"].tap()
        app.buttons["calcButton_="].tap()

        let display = app.staticTexts["calculatorDisplay"]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        let displayText = (display.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? display.label
        XCTAssertEqual(displayText, "10", "7 + 3 should compute to 10")

        app.buttons["saveCalculatorButton"].tap()
        XCTAssertTrue(elementContaining("Calculator note", in: app).waitForExistence(timeout: 5), "The saved calculator history should appear as a local annotation row immediately, offline")

        XCTAssertTrue(addStepAnnotationButton.waitForExistence(timeout: 5))
        addStepAnnotationButton.tap()
        let photoKindButton = app.buttons["annotationKind_photo"].firstMatch
        XCTAssertTrue(photoKindButton.waitForExistence(timeout: 5))
        XCTAssertTrue(photoKindButton.isEnabled)
        let videoKindButton = app.buttons["annotationKind_video"].firstMatch
        XCTAssertTrue(videoKindButton.waitForExistence(timeout: 5))
        XCTAssertTrue(videoKindButton.isEnabled)

        let sketchKindButton = app.buttons["annotationKind_sketch"].firstMatch
        XCTAssertTrue(sketchKindButton.waitForExistence(timeout: 5))
        sketchKindButton.tap()

        let sketchCanvas = firstExisting(app.otherElements["sketchCanvas"], app.images["sketchCanvas"])
        XCTAssertTrue(sketchCanvas.waitForExistence(timeout: 5), "The sketch canvas should be reachable from the step's \"Add Sketch…\" action")
        XCTAssertTrue(app.buttons["sketchClearButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sketchUndoButton"].waitForExistence(timeout: 5))
        let saveSketchButton = app.buttons["saveSketchButton"]
        XCTAssertTrue(saveSketchButton.waitForExistence(timeout: 5))
        XCTAssertFalse(saveSketchButton.isEnabled, "Save should stay disabled with no strokes drawn yet")

        firstExisting(app.navigationBars.buttons["Cancel"], app.buttons["Cancel"]).tap()
    }

    @MainActor
    func testAudioAndVideoRecordingAnnotationsOffline() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        addUIInterruptionMonitor(withDescription: "Microphone/Camera permission") { alert in
            let allowButton = alert.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'allow' OR label CONTAINS[c] 'ok'")).firstMatch
            guard allowButton.exists else { return false }
            allowButton.tap()
            return true
        }

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)
        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Recording Types Test")
        app.buttons["createProtocolButton"].tap()

        let protocolRow = app.staticTexts["Recording Types Test"]
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 5))
        protocolRow.tap()

        tapToolbarButton("addSectionButton", label: "Add Section", in: app)
        XCTAssertTrue(app.staticTexts["New Section 1"].waitForExistence(timeout: 5))

        let addStepButton = app.buttons["addStepButton"].firstMatch
        XCTAssertTrue(addStepButton.waitForExistence(timeout: 5))
        let stepField = openAddStepSheet(tapping: addStepButton, in: app)
        stepField.tap()
        stepField.typeText("Record observations")
        app.buttons["addTextSheetSaveButton"].tap()
        XCTAssertTrue(elementContaining("Record observations", in: app).waitForExistence(timeout: 5))

        #if os(iOS)
        navigateBack(in: app)
        #endif
        openStartSessionSheet(in: app)
        app.buttons["startSessionButton"].tap()

        let addStepAnnotationButton = app.buttons["addStepAnnotationButton"].firstMatch
        XCTAssertTrue(addStepAnnotationButton.waitForExistence(timeout: 5))

        addStepAnnotationButton.tap()
        app.buttons["annotationKind_audio"].firstMatch.tap()

        let modePicker = firstExisting(app.radioGroups["recordingModePicker"], app.segmentedControls["recordingModePicker"])
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5), "The recorder should show a Mode picker, since audio/video are two modes of one function")

        tapSegment("Video", in: app)
        XCTAssertTrue(firstExisting(app.otherElements["cameraPreview"], app.images["cameraPreview"]).waitForExistence(timeout: 5), "Switching to Video mode should show the camera preview")
        tapSegment("Audio", in: app)

        recordTranscribeTranslateAndSave(in: app, expectedRowText: "Audio note")

        addStepAnnotationButton.tap()
        app.buttons["annotationKind_video"].firstMatch.tap()
        let recordVideoButton = app.buttons["recordVideoButton"]
        XCTAssertTrue(recordVideoButton.waitForExistence(timeout: 5))
        recordVideoButton.tap()

        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))
        XCTAssertTrue(firstExisting(app.otherElements["cameraPreview"], app.images["cameraPreview"]).waitForExistence(timeout: 5), "Video mode should show a live camera preview")

        recordTranscribeTranslateAndSave(in: app, expectedRowText: "Video note")
    }

    @MainActor
    private func recordTranscribeTranslateAndSave(in app: XCUIApplication, expectedRowText: String) {
        let startButton = app.buttons["startRecordingButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let stopButton = app.buttons["stopRecordingButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Tapping Start should flip the button to Stop")
        Thread.sleep(forTimeInterval: 2)
        stopButton.tap()

        let saveButton = app.buttons["saveMediaAnnotationButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        let transcriptionSettled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: saveButton)
        XCTAssertEqual(XCTWaiter().wait(for: [transcriptionSettled], timeout: 15), .completed, "Save should become enabled once the recording (and any on-device transcription attempt) settles")
        saveButton.tap()

        XCTAssertTrue(elementContaining(expectedRowText, in: app).waitForExistence(timeout: 5), "The saved \(expectedRowText) should appear as a local annotation row immediately, offline")
    }



    @MainActor
    func testSessionModeToggleAndProtocolLessSession() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        for title in ["Protocol A", "Protocol B"] {
            tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)
            let titleField = app.textFields["newProtocolTitleField"]
            XCTAssertTrue(titleField.waitForExistence(timeout: 5))
            titleField.tap()
            titleField.typeText(title)
            app.buttons["createProtocolButton"].tap()
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        }

        tapTab("Sessions", in: app)
        tapToolbarButton("newSessionButton", label: "New Session", in: app)

        let sessionNameField = app.textFields["newSessionNameField"]
        XCTAssertTrue(sessionNameField.waitForExistence(timeout: 5))
        sessionNameField.tap()
        sessionNameField.typeText("Multi-Protocol Run")

        for title in ["Protocol A", "Protocol B"] {
            let row = app.buttons["newSessionProtocolRow_\(title)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
        }
        app.buttons["createSessionButton"].tap()

        let multiProtocolSessionRow = elementContaining("Multi-Protocol Run", in: app)
        if multiProtocolSessionRow.waitForExistence(timeout: 5) {
            multiProtocolSessionRow.tap()
        }

        let notesSegment = firstExisting(app.radioButtons["Notes"], app.buttons["Notes"])
        XCTAssertTrue(notesSegment.waitForExistence(timeout: 5), "A session with attached protocols should show a Protocol/Notes mode toggle")
        XCTAssertTrue(
            firstExisting(
                app.buttons["Protocol A"], app.buttons["Protocol B"], app.buttons["More"],
                app.otherElements["sessionProtocolPicker"], app.popUpButtons["sessionProtocolPicker"]
            ).waitForExistence(timeout: 5),
            "A session with two attached protocols should show a protocol switcher"
        )

        notesSegment.tap()
        XCTAssertTrue(app.buttons["addSessionAnnotationButton"].waitForExistence(timeout: 5), "Notes mode should show the session-level Add Annotation entry point")
        XCTAssertFalse(app.buttons["addStepAnnotationButton"].exists, "Session-level notes should never show step content while in Notes mode")

        let protocolSegment = firstExisting(app.radioButtons["Protocol"], app.buttons["Protocol"])
        protocolSegment.tap()
        XCTAssertFalse(app.buttons["addSessionAnnotationButton"].exists, "Session notes must never show while in Protocol Mode")

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        #endif

        tapTab("Sessions", in: app)
        tapToolbarButton("newSessionButton", label: "New Session", in: app)
        let secondSessionNameField = app.textFields["newSessionNameField"]
        XCTAssertTrue(secondSessionNameField.waitForExistence(timeout: 5))
        secondSessionNameField.tap()
        secondSessionNameField.typeText("Protocol-less Run")
        app.buttons["createSessionButton"].tap()

        let protocolLessSessionRow = elementContaining("Protocol-less Run", in: app)
        if protocolLessSessionRow.waitForExistence(timeout: 5) {
            protocolLessSessionRow.tap()
        }

        XCTAssertFalse(app.segmentedControls["sessionModePicker"].exists, "A protocol-less session has nothing to toggle, so no mode picker should show")
        XCTAssertTrue(app.buttons["addSessionAnnotationButton"].waitForExistence(timeout: 5), "A protocol-less session should open directly in Notes mode")
    }


    @MainActor
    func testScrollingRealProtocolFixtureDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state", "--ui-testing-seed-real-protocol"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        let protocolRow = elementContaining("Expression and purification of Rab10", in: app)
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 5), "The seeded real protocol should appear")
        protocolRow.tap()

        let largestSectionRow = elementContaining("Preparation of cell lysate", in: app)
        XCTAssertTrue(largestSectionRow.waitForExistence(timeout: 5), "The section-jump sidebar should list the real sections")
        largestSectionRow.tap()

        let stepList = firstExisting(app.tables["stepList"], app.outlines["stepList"], app.collectionViews["stepList"], app.scrollViews["stepList"])
        XCTAssertTrue(stepList.exists, "The selected section's step list should render")

        let diagnosticShot = XCTAttachment(screenshot: app.screenshot())
        diagnosticShot.lifetime = .keepAlways
        add(diagnosticShot)

        for _ in 0..<10 {
            stepList.swipeUp(velocity: .fast)
        }
        for _ in 0..<10 {
            stepList.swipeDown(velocity: .fast)
        }
        for _ in 0..<10 {
            stepList.swipeUp(velocity: .fast)
        }

        XCTAssertEqual(app.state, .runningForeground, "The app should still be running after scrolling through the real 70-step protocol")
    }

    @MainActor
    private func selectPickerOption(_ identifier: String, option: String, in app: XCUIApplication) {
        let picker = firstExisting(app.popUpButtons[identifier], app.buttons[identifier], app.otherElements[identifier])
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Picker \"\(identifier)\" not found")
        picker.tap()

        let optionElement = firstExisting(app.buttons[option], app.staticTexts[option], app.menuItems[option])
        XCTAssertTrue(optionElement.waitForExistence(timeout: 5), "Picker option \"\(option)\" not found")
        optionElement.tap()
    }

    @MainActor
    private func openAddStepSheet(tapping button: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let durationField = app.textFields["stepDurationField"]
        var stepField = firstExisting(app.textViews["addTextSheetField"], app.textFields["addTextSheetField"], timeout: 0)
        for _ in 0..<3 {
            if stepField.exists && durationField.exists { break }
            if stepField.exists && !durationField.exists {
                firstExisting(app.navigationBars.buttons["Cancel"], app.buttons["Cancel"]).tap()
            }
            button.tap()
            stepField = firstExisting(app.textViews["addTextSheetField"], app.textFields["addTextSheetField"], timeout: 3)
        }
        XCTAssertTrue(stepField.exists && durationField.exists, "The Add Step sheet (not Rename Section) should be open")
        return stepField
    }

    @MainActor
    private func openStartSessionSheet(in app: XCUIApplication) {
        let startSessionButton = app.buttons["startSessionButton"]
        for _ in 0..<3 {
            if startSessionButton.exists { break }
            let strayCancel = firstExisting(app.navigationBars.buttons["Cancel"], app.buttons["Cancel"], timeout: 0)
            if strayCancel.exists {
                strayCancel.tap()
            }
            tapToolbarButton("newSessionButton", label: "New Session", in: app)
            _ = startSessionButton.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(startSessionButton.exists, "\"New Session\" never opened the start-session sheet after repeated taps")
    }

    private func firstExisting(_ candidates: XCUIElement..., timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.waitForExistence(timeout: 0.5) {
                return candidate
            }
        } while Date() < deadline
        return candidates[0]
    }

    private func elementContaining(_ substring: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        return firstExisting(app.staticTexts.matching(predicate).firstMatch, app.buttons.matching(predicate).firstMatch)
    }

    @MainActor
    private func tapTab(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let direct = firstExisting(app.tabBars.buttons[label], app.buttons[label], app.radioButtons[label], app.cells[label], app.cells.staticTexts[label])
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

    @MainActor
    private func tapMenuItem(_ menuIdentifier: String, item label: String, in app: XCUIApplication) {
        let menuButton = firstExisting(app.buttons[menuIdentifier], app.menuButtons[menuIdentifier])
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5), "\"\(menuIdentifier)\" menu button not found")
        menuButton.tap()
        let menuItem = firstExisting(app.menuItems[label], app.buttons[label])
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "\"\(label)\" not found in the \"\(menuIdentifier)\" menu")
        menuItem.tap()
    }

    @MainActor
    private func navigateBack(in app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            for bar in app.navigationBars.allElementsBoundByIndex.reversed() {
                let buttons = bar.buttons.allElementsBoundByIndex
                if let backButton = buttons.first(where: {
                    !$0.label.isEmpty
                        && !$0.label.localizedCaseInsensitiveContains("sidebar")
                        && !$0.label.localizedCaseInsensitiveContains("more")
                }) {
                    backButton.tap()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        let macBack = firstExisting(app.buttons["chevron.backward"], app.buttons["Back"], timeout: 0)
        guard macBack.exists else { return }
        macBack.tap()
    }

    private func tapSegment(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let segment = firstExisting(app.radioButtons[label], app.buttons[label])
        XCTAssertTrue(segment.waitForExistence(timeout: timeout), "\"\(label)\" segment not found")
        segment.tap()
    }

    private func selectAllAndReplace(_ field: XCUIElement, with newText: String) {
        field.tap()
        for _ in 0..<5 {
            if field.value as? String == newText { return }
            let existing = (field.value as? String) ?? ""
            if !existing.isEmpty {
                field.typeKey("a", modifierFlags: .command)
                for _ in existing {
                    field.typeKey(.delete, modifierFlags: [])
                }
                for _ in existing {
                    field.typeKey(.forwardDelete, modifierFlags: [])
                }
            }
            field.typeText(newText)
            if field.value as? String == newText { return }
            field.tap()
        }
        XCTAssertEqual(field.value as? String, newText, "Failed to replace field text after multiple attempts")
    }

    @MainActor
    private func tapToolbarButton(_ identifier: String, label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: timeout) {
            direct.tap()
            return
        }

        let macOverflow = app.popUpButtons["more toolbar items"]
        let iPadOverflow = app.buttons["More"]
        let overflow = firstExisting(macOverflow, iPadOverflow)
        XCTAssertTrue(overflow.waitForExistence(timeout: timeout), "Neither \"\(identifier)\" nor a toolbar overflow control was found")
        overflow.tap()

        let itemInOverflow = firstExisting(app.menuItems[label], app.buttons[label], app.staticTexts[label], app.cells[label])
        XCTAssertTrue(itemInOverflow.waitForExistence(timeout: timeout), "\"\(label)\" was not found inside the toolbar overflow menu")
        itemInOverflow.tap()
    }
}

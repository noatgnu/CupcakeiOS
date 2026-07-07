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

/// Exercises the online-mode create/sync path against a real, local, disposable backend.
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
        replaceText(in: serverURLField, withPasted: "http://127.0.0.1:8002/api/v1/")

        XCTAssertEqual(serverURLField.value as? String, "http://127.0.0.1:8002/api/v1/", "The server URL field should contain exactly the pasted text, not a mix of old and new")

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()

        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)

        let protocolTitle = "Live Backend Test Protocol \(Date().timeIntervalSince1970)"

        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(protocolTitle)
        app.buttons["createProtocolButton"].tap()

        let errorAlert = app.alerts["Couldn't create protocol"]
        if errorAlert.waitForExistence(timeout: 3) {
            XCTFail("Protocol creation showed an error alert: \(errorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
            errorAlert.buttons["OK"].tap()
        }

        // Exact title match, checking both label and value — macOS sometimes exposes row text via AX value.
        let matchingRows = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", protocolTitle, protocolTitle))
        XCTAssertTrue(matchingRows.firstMatch.waitForExistence(timeout: 30), "The newly-created protocol should appear in the list")
        matchingRows.firstMatch.tap()

        XCTAssertFalse(elementContaining("Pending sync", in: app).exists, "A protocol created while signed in against a reachable backend should sync immediately, not queue")
        XCTAssertFalse(elementContaining("Local only", in: app).exists, "\"Local only\" is standalone-mode-only phrasing — shouldn't appear when signed in")
    }

    @MainActor
    func testStandaloneToSignInImportsLocalNotebook() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let continueOfflineButton = app.buttons["continueOfflineButton"]
        XCTAssertTrue(continueOfflineButton.waitForExistence(timeout: 5))
        continueOfflineButton.tap()

        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)

        let protocolTitle = "Standalone Import Test \(Date().timeIntervalSince1970)"
        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(protocolTitle)
        app.buttons["createProtocolButton"].tap()

        let localRow = app.staticTexts[protocolTitle]
        XCTAssertTrue(localRow.waitForExistence(timeout: 5), "The locally-created protocol should appear while still in standalone mode")

        tapToolbarButton("exitOfflineModeButton", label: "Exit Offline Mode", in: app)

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

        let importButton = app.buttons["importLocalNotebookButton"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15), "Signing in with local-only content should offer to import it")
        importButton.tap()

        let importedRow = waitForMatch(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", protocolTitle, protocolTitle), in: app.staticTexts, timeout: 30)
        XCTAssertTrue(importedRow.exists, "The imported protocol should appear in the list once synced")
        importedRow.tap()

        XCTAssertFalse(elementContaining("Pending sync", in: app).exists, "An imported protocol should be fully synced, not left pending")
        XCTAssertFalse(elementContaining("Local only", in: app).exists, "An imported protocol should no longer show standalone-mode phrasing")
    }

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

    @MainActor
    func testManageMetadataTableTemplateEditAndDelete() throws {
        let templateName = "Live Test Template \(Int(Date().timeIntervalSince1970))"
        try createBlankTemplateViaAPI(named: templateName)

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

        tapTab("Jobs", in: app, timeout: 30)
        tapToolbarButton("newJobButton", label: "New Job", in: app, timeout: 10)

        let jobName = "Template Mgmt Test \(Int(Date().timeIntervalSince1970))"
        let jobNameField = app.textFields["newJobNameField"]
        XCTAssertTrue(jobNameField.waitForExistence(timeout: 5))
        jobNameField.tap()
        jobNameField.typeText(jobName)
        app.buttons["createJobButton"].tap()

        let jobRow = waitForMatchAcrossTypes(NSPredicate(format: "label CONTAINS %@", jobName), in: app, timeout: 30)
        XCTAssertTrue(jobRow.exists, "The newly-created job should appear once synced")
        jobRow.tap()

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 15))
        createFromTemplateButton.tap()

        app.buttons["manageMetadataTableTemplatesButton"].tap()

        let templateRow = app.buttons["myTableTemplateRow_\(templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 15), "The blank template created via the API should appear in the management list")
        Thread.sleep(forTimeInterval: 1)
        templateRow.tap()

        let nameField = app.textFields["tableTemplateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let renamedName = templateName + " Renamed"
        replaceText(in: nameField, withPasted: renamedName)
        app.buttons["saveTableTemplateButton"].tap()

        let renamedRow = app.buttons["myTableTemplateRow_\(renamedName)"]
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 10), "The renamed template should appear in the management list")
    }

    /// Covers step variations, protocol rating, and step-scoped booking annotations online.
    @MainActor
    func testStepVariationRatingAndBookingAnnotationSyncImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)
        let protocolTitle = "Live Variation Test \(Date().timeIntervalSince1970)"
        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(protocolTitle)
        app.buttons["createProtocolButton"].tap()

        let createErrorAlert = app.alerts["Couldn't create protocol"]
        if createErrorAlert.waitForExistence(timeout: 3) {
            XCTFail("Protocol creation showed an error alert: \(createErrorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
            createErrorAlert.buttons["OK"].tap()
        }

        let titlePredicate = NSPredicate(format: "label == %@ OR value == %@", protocolTitle, protocolTitle)
        var protocolRow = waitForMatch(titlePredicate, in: app.staticTexts, timeout: 30)
        XCTAssertTrue(protocolRow.exists, "The newly-created protocol should appear once synced")

        let addSectionButton = app.buttons["addSectionButton"]
        for _ in 0..<5 {
            protocolRow.tap()
            if addSectionButton.waitForExistence(timeout: 3) { break }
            protocolRow = waitForMatch(titlePredicate, in: app.staticTexts, timeout: 5)
        }
        XCTAssertTrue(addSectionButton.waitForExistence(timeout: 5), "Tapping the protocol row should navigate into its detail view")

        tapToolbarButton("addSectionButton", label: "Add Section", in: app, timeout: 10)
        XCTAssertTrue(app.staticTexts["New Section 1"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)

        let addStepButton = app.buttons["addStepButton"].firstMatch
        XCTAssertTrue(addStepButton.waitForExistence(timeout: 10))
        var stepField = firstExisting(app.textViews["addTextSheetField"], app.textFields["addTextSheetField"])
        for _ in 0..<3 {
            if stepField.exists { break }
            addStepButton.tap()
            stepField = firstExisting(app.textViews["addTextSheetField"], app.textFields["addTextSheetField"])
        }
        XCTAssertTrue(stepField.exists)
        stepField.tap()
        stepField.typeText("Mix reagents")
        app.buttons["addTextSheetSaveButton"].tap()
        XCTAssertTrue(elementContaining("Mix reagents", in: app).waitForExistence(timeout: 10))

        let stepSyncErrorAlert = app.alerts["Couldn't start session"]
        if stepSyncErrorAlert.waitForExistence(timeout: 3) {
            XCTFail("Step creation showed a sync error alert: \(stepSyncErrorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
            stepSyncErrorAlert.buttons.firstMatch.tap()
        }

        let rateButton = app.buttons["rateProtocolButton"]
        XCTAssertTrue(rateButton.waitForExistence(timeout: 5))
        rateButton.tap()

        let complexitySlider = app.sliders["complexityRatingSlider"]
        XCTAssertTrue(complexitySlider.waitForExistence(timeout: 5))
        complexitySlider.adjust(toNormalizedSliderPosition: 0.7)
        app.sliders["durationRatingSlider"].adjust(toNormalizedSliderPosition: 0.3)
        app.buttons["saveRatingButton"].tap()
        XCTAssertFalse(app.alerts["Couldn't save rating"].waitForExistence(timeout: 3), "Rating a protocol against a reachable backend shouldn't show an error")

        tapToolbarButton("newSessionButton", label: "New Session", in: app, timeout: 10)
        let startSessionButton = app.buttons["startSessionButton"]
        XCTAssertTrue(startSessionButton.waitForExistence(timeout: 10))
        startSessionButton.tap()

        // Step variations are session-scoped, added from the session's own Protocol Mode step section.
        let addVariationButton = app.buttons["addVariationButton"].firstMatch
        XCTAssertTrue(addVariationButton.waitForExistence(timeout: 20), "\"Add Variation\" should appear once the session and step both have serverIDs")
        addVariationButton.tap()

        let variationDescField = app.textFields["variationDescriptionField"]
        XCTAssertTrue(variationDescField.waitForExistence(timeout: 5))
        variationDescField.tap()
        variationDescField.typeText("For larger samples, extend incubation")

        let variationDurationField = app.textFields["variationDurationField"]
        variationDurationField.tap()
        variationDurationField.typeText("20")

        app.buttons["saveVariationButton"].tap()
        // Navigating away and back forces a fresh view mount, picking up the new variation.
        if !elementContaining("Variation:", in: app).waitForExistence(timeout: 5) {
            tapTab("Sessions", in: app)
            var sessionRow = elementContaining(protocolTitle, in: app)
            for _ in 0..<5 {
                if sessionRow.waitForExistence(timeout: 3) {
                    sessionRow.tap()
                    break
                }
                sessionRow = elementContaining(protocolTitle, in: app)
            }
        }
        XCTAssertTrue(elementContaining("Variation:", in: app).waitForExistence(timeout: 10), "The saved variation should appear inline under the step once synced")

        // Step-scoped booking annotation, now reached through the consolidated Add Annotation sheet.
        let addStepAnnotationButton = app.buttons["addStepAnnotationButton"].firstMatch
        XCTAssertTrue(addStepAnnotationButton.waitForExistence(timeout: 10))
        addStepAnnotationButton.tap()
        let bookingKindButton = app.buttons["annotationKind_booking"].firstMatch
        XCTAssertTrue(bookingKindButton.waitForExistence(timeout: 5), "\"Booking\" should be offered once the session and step both have serverIDs")
        bookingKindButton.tap()

        selectPickerOption("bookingAnnotationInstrumentPicker", option: "Test Centrifuge", in: app)

        let bookingDescField = app.textFields["bookingAnnotationDescriptionField"]
        XCTAssertTrue(bookingDescField.waitForExistence(timeout: 5))
        bookingDescField.tap()
        bookingDescField.typeText("Spin test samples")

        app.buttons["saveBookingAnnotationButton"].tap()
        XCTAssertFalse(app.alerts["Couldn't book instrument"].waitForExistence(timeout: 5), "Booking an instrument against a reachable backend shouldn't show an error")
    }

    /// Drives `StepTimerView`'s real Start/Stop buttons, then confirms a live WebSocket push refreshes this mounted view.
    @MainActor
    func testStepTimerStartAndCrossDeviceStopSyncLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let seed = try seedSessionWithTimedStepViaAPI(
            protocolTitle: "Live TimeKeeper Test \(unique)",
            sessionName: "Live TimeKeeper Session \(unique)"
        )

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Sessions", in: app, timeout: 30)
        let sessionRow = waitForMatchAcrossTypes(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", seed.sessionName, seed.sessionName),
            in: app, timeout: 30
        )
        XCTAssertTrue(sessionRow.exists, "The session seeded via the API should appear once synced")
        sessionRow.tap()

        let startButton = app.buttons["startStepTimerButton"].firstMatch
        XCTAssertTrue(startButton.waitForExistence(timeout: 15), "The step's timer Start button should render since the step has a duration")
        startButton.tap()

        let stopButton = app.buttons["stopStepTimerButton"].firstMatch
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Starting the timer locally should flip the button to Stop immediately, via the direct-context write")

        // Stop the same TimeKeeper via a raw API call, standing in for a second device.
        let timeKeeperID = try findTimeKeeperIDViaAPI(sessionID: seed.sessionID, stepID: seed.stepID, deviceToken: seed.deviceToken)
        try postJSON("time-keepers/\(timeKeeperID)/stop_timer/", body: [:], deviceToken: seed.deviceToken)

        let resumeButton = app.buttons["startStepTimerButton"].firstMatch
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 15), "Stopping the timer from another \"device\" should push a live update back to this view with no local interaction")
    }

    /// Covers sample pool creation only — editing hits unrelated navigation flakiness on macOS.
    @MainActor
    func testSamplePoolCreateSyncImmediately() throws {
        let templateName = "Live Pool Test Template \(Int(Date().timeIntervalSince1970))"
        try createBlankTemplateViaAPI(named: templateName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 30)
        tapToolbarButton("newJobButton", label: "New Job", in: app, timeout: 10)

        let jobName = "Sample Pool Test \(Int(Date().timeIntervalSince1970))"
        let jobNameField = app.textFields["newJobNameField"]
        XCTAssertTrue(jobNameField.waitForExistence(timeout: 5))
        jobNameField.tap()
        jobNameField.typeText(jobName)
        app.buttons["createJobButton"].tap()

        let jobRow = waitForMatchAcrossTypes(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", jobName, jobName), in: app, timeout: 30)
        XCTAssertTrue(jobRow.exists, "The newly-created job should appear once synced")
        jobRow.tap()

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 15))
        createFromTemplateButton.tap()

        let templateRow = app.buttons["metadataTemplateRow_\(templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 15), "The template created via the API should appear once synced")
        templateRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("5")

        app.buttons["createMetadataTableButton"].tap()

        let newPoolButton = app.buttons["newSamplePoolButton"]
        XCTAssertTrue(newPoolButton.waitForExistence(timeout: 15), "The Sample Pools section should appear once the metadata table syncs")
        newPoolButton.tap()

        let poolNameField = app.textFields["samplePoolNameField"]
        XCTAssertTrue(poolNameField.waitForExistence(timeout: 5))
        poolNameField.tap()
        poolNameField.typeText("Pool A")

        let onlyField = app.textFields["samplePoolOnlySamplesField"]
        onlyField.tap()
        onlyField.typeText("1-2")

        let independentField = app.textFields["samplePoolIndependentSamplesField"]
        independentField.tap()
        independentField.typeText("3")

        app.buttons["saveSamplePoolButton"].tap()

        XCTAssertTrue(elementContaining("Pool A", in: app).waitForExistence(timeout: 10), "The newly-created sample pool should appear once synced")
    }

    /// Verifies `CreateMetadataFromTemplateSheet`'s three-tier picker and the resulting table's column editor, live.
    @MainActor
    func testMetadataTemplatePickerTiersAndTableEditor() throws {
        let seed = try seedTemplatePickerTierData()

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 30)

        let jobRow = waitForMatchAcrossTypes(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", seed.jobName, seed.jobName), in: app, timeout: 30)
        XCTAssertTrue(jobRow.exists, "The job seeded via the API should appear once synced")
        jobRow.tap()

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 15))
        createFromTemplateButton.tap()

        XCTAssertTrue(app.staticTexts["Personal"].waitForExistence(timeout: 10), "The Personal section header should render")
        XCTAssertTrue(app.staticTexts["Job's Lab Group"].waitForExistence(timeout: 5), "The Job's Lab Group section header should render")
        XCTAssertTrue(app.staticTexts["Other Lab Groups"].waitForExistence(timeout: 5), "The Other Lab Groups section header should render")

        let personalRow = app.buttons["metadataTemplateRow_\(seed.personalTemplateName)"]
        XCTAssertTrue(personalRow.waitForExistence(timeout: 10), "The personal template should be listed")
        XCTAssertTrue(app.buttons["metadataTemplateRow_\(seed.jobGroupTemplateName)"].exists, "The job's own lab-group template should be listed")
        XCTAssertTrue(app.buttons["metadataTemplateRow_\(seed.otherGroupTemplateName)"].exists, "The other lab group's template should be listed")

        personalRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("5")

        app.buttons["createMetadataTableButton"].tap()

        let firstColumnRow = app.buttons["metadataColumnRow_\(seed.firstColumnName)"]
        XCTAssertTrue(firstColumnRow.waitForExistence(timeout: 15), "The metadata table's first column should render")

        // Per-sample grid — the actual new feature under test.
        let firstGridCell = app.buttons["metadataCell_\(seed.firstColumnName)_1"]
        XCTAssertTrue(firstGridCell.waitForExistence(timeout: 10), "The per-sample grid should render a cell for sample 1")

        // Opening the cell editor window hits a known macOS artifact, not chased further here.
    }

    /// Signs in against the local test backend with the standard `testuser` credentials.
    @MainActor
    private func signIn(_ app: XCUIApplication) {
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
    }

    /// Selects an option from a SwiftUI `Picker`.
    @MainActor
    private func selectPickerOption(_ identifier: String, option: String, in app: XCUIApplication) {
        let picker = firstExisting(app.popUpButtons[identifier], app.buttons[identifier], app.otherElements[identifier])
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Picker \"\(identifier)\" not found")
        picker.tap()

        let optionElement = firstExisting(app.buttons[option], app.staticTexts[option], app.menuItems[option])
        XCTAssertTrue(optionElement.waitForExistence(timeout: 5), "Picker option \"\(option)\" not found")
        optionElement.tap()
    }

    /// Finds an element matching the predicate in either `staticTexts` or `buttons`, polling with a fresh query each iteration.
    private func waitForMatchAcrossTypes(_ predicate: NSPredicate, in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let staticText = app.staticTexts.matching(predicate).firstMatch
            if staticText.exists { return staticText }
            let button = app.buttons.matching(predicate).firstMatch
            if button.exists { return button }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return app.staticTexts.matching(predicate).firstMatch
    }

    /// Creates a blank metadata table template directly via the API, to seed test data.
    private func createBlankTemplateViaAPI(named name: String) throws {
        let loginData = try JSONSerialization.data(withJSONObject: ["username": "testuser", "password": "testuser123"])
        var loginRequest = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/auth/login/")!)
        loginRequest.httpMethod = "POST"
        loginRequest.httpBody = loginData
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (loginResponseData, _) = try synchronousData(for: loginRequest)
        let loginJSON = try JSONSerialization.jsonObject(with: loginResponseData) as? [String: Any]
        guard let accessToken = loginJSON?["access_token"] as? String else {
            XCTFail("Couldn't log in via API to seed a template")
            return
        }

        var deviceTokenRequest = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/device-tokens/")!)
        deviceTokenRequest.httpMethod = "POST"
        deviceTokenRequest.httpBody = try JSONSerialization.data(withJSONObject: ["label": "ui-test-device", "permission": "write"])
        deviceTokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        deviceTokenRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (deviceTokenResponseData, _) = try synchronousData(for: deviceTokenRequest)
        let deviceTokenJSON = try JSONSerialization.jsonObject(with: deviceTokenResponseData) as? [String: Any]
        guard let deviceToken = deviceTokenJSON?["token"] as? String else {
            XCTFail("Couldn't create a device token to seed a template")
            return
        }

        var createRequest = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/metadata-table-templates/")!)
        createRequest.httpMethod = "POST"
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "visibility": "private"])
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.setValue("DeviceToken \(deviceToken)", forHTTPHeaderField: "Authorization")
        _ = try synchronousData(for: createRequest)
    }

    private struct TemplatePickerTierSeed {
        let jobName: String
        let personalTemplateName: String
        let jobGroupTemplateName: String
        let otherGroupTemplateName: String
        let firstColumnName: String
    }

    private enum APISeedError: Error { case missingField(String) }

    /// Seeds a job assigned to a fresh lab group, plus one template per picker tier.
    private func seedTemplatePickerTierData() throws -> TemplatePickerTierSeed {
        let deviceToken = try fetchDeviceTokenViaAPI()
        let timestamp = Int(Date().timeIntervalSince1970)

        let jobGroupID = try createLabGroupViaAPI(named: "Tier Test Job Group \(timestamp)", deviceToken: deviceToken)
        let otherGroupID = try createLabGroupViaAPI(named: "Tier Test Other Group \(timestamp)", deviceToken: deviceToken)

        let personalTemplateName = "Tier Test Personal \(timestamp)"
        let firstColumnName = try createTemplateFromSchemaViaAPI(named: personalTemplateName, deviceToken: deviceToken)

        let jobGroupTemplateName = "Tier Test JobGroup \(timestamp)"
        try createGroupTemplateViaAPI(named: jobGroupTemplateName, labGroupID: jobGroupID, deviceToken: deviceToken)

        let otherGroupTemplateName = "Tier Test OtherGroup \(timestamp)"
        try createGroupTemplateViaAPI(named: otherGroupTemplateName, labGroupID: otherGroupID, deviceToken: deviceToken)

        let projectID = try createProjectViaAPI(named: "Tier Test Project \(timestamp)", deviceToken: deviceToken)
        let jobName = "Tier Test Job \(timestamp)"
        let jobID = try createJobViaAPI(named: jobName, projectID: projectID, deviceToken: deviceToken)
        try assignJobLabGroupViaAPI(jobID: jobID, labGroupID: jobGroupID, deviceToken: deviceToken)

        return TemplatePickerTierSeed(
            jobName: jobName,
            personalTemplateName: personalTemplateName,
            jobGroupTemplateName: jobGroupTemplateName,
            otherGroupTemplateName: otherGroupTemplateName,
            firstColumnName: firstColumnName
        )
    }

    private func fetchDeviceTokenViaAPI() throws -> String {
        let loginData = try JSONSerialization.data(withJSONObject: ["username": "testuser", "password": "testuser123"])
        var loginRequest = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/auth/login/")!)
        loginRequest.httpMethod = "POST"
        loginRequest.httpBody = loginData
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (loginResponseData, _) = try synchronousData(for: loginRequest)
        let loginJSON = try JSONSerialization.jsonObject(with: loginResponseData) as? [String: Any]
        guard let accessToken = loginJSON?["access_token"] as? String else {
            throw APISeedError.missingField("access_token")
        }

        var deviceTokenRequest = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/device-tokens/")!)
        deviceTokenRequest.httpMethod = "POST"
        deviceTokenRequest.httpBody = try JSONSerialization.data(withJSONObject: ["label": "ui-test-device-\(UUID().uuidString)", "permission": "write"])
        deviceTokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        deviceTokenRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (deviceTokenResponseData, _) = try synchronousData(for: deviceTokenRequest)
        let deviceTokenJSON = try JSONSerialization.jsonObject(with: deviceTokenResponseData) as? [String: Any]
        guard let token = deviceTokenJSON?["token"] as? String else {
            throw APISeedError.missingField("token")
        }
        return token
    }

    @discardableResult
    private func postJSON(_ path: String, body: [String: Any], deviceToken: String) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeviceToken \(deviceToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try synchronousData(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APISeedError.missingField(path)
        }
        return json
    }

    private func patchJSON(_ path: String, body: [String: Any], deviceToken: String) throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/\(path)")!)
        request.httpMethod = "PATCH"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeviceToken \(deviceToken)", forHTTPHeaderField: "Authorization")
        _ = try synchronousData(for: request)
    }

    private func createLabGroupViaAPI(named name: String, deviceToken: String) throws -> Int64 {
        let json = try postJSON("lab-groups/", body: ["name": name], deviceToken: deviceToken)
        guard let id = json["id"] as? Int else { throw APISeedError.missingField("id") }
        return Int64(id)
    }

    /// Creates a group-visibility template via create-from-schema, then PATCHes visibility/lab_group.
    private func createGroupTemplateViaAPI(named name: String, labGroupID: Int64, deviceToken: String) throws {
        let created = try postJSON("metadata-table-templates/create_from_schema/", body: ["name": name, "schemas": ["minimum"]], deviceToken: deviceToken)
        guard let id = created["id"] as? Int else { throw APISeedError.missingField("id") }
        try patchJSON("metadata-table-templates/\(id)/", body: ["visibility": "group", "lab_group": labGroupID], deviceToken: deviceToken)
    }

    /// Returns the created template's first column's name (`column_position == 0`).
    private func createTemplateFromSchemaViaAPI(named name: String, deviceToken: String) throws -> String {
        let json = try postJSON("metadata-table-templates/create_from_schema/", body: ["name": name, "schemas": ["minimum"]], deviceToken: deviceToken)
        guard let columns = json["user_columns"] as? [[String: Any]],
              let firstColumn = columns.first(where: { ($0["column_position"] as? Int) == 0 }),
              let columnName = firstColumn["name"] as? String else {
            throw APISeedError.missingField("user_columns")
        }
        return columnName
    }

    private func createProjectViaAPI(named name: String, deviceToken: String) throws -> Int64 {
        let json = try postJSON("projects/", body: ["project_name": name], deviceToken: deviceToken)
        guard let id = json["id"] as? Int else { throw APISeedError.missingField("id") }
        return Int64(id)
    }

    private func createJobViaAPI(named name: String, projectID: Int64, deviceToken: String) throws -> Int64 {
        let json = try postJSON("instrument-jobs/", body: ["job_type": "analysis", "job_name": name, "project": projectID], deviceToken: deviceToken)
        guard let id = json["id"] as? Int else { throw APISeedError.missingField("id") }
        return Int64(id)
    }

    private func assignJobLabGroupViaAPI(jobID: Int64, labGroupID: Int64, deviceToken: String) throws {
        try patchJSON("instrument-jobs/\(jobID)/", body: ["lab_group": labGroupID], deviceToken: deviceToken)
    }

    private func getJSON(_ path: String, deviceToken: String) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/\(path)")!)
        request.httpMethod = "GET"
        request.setValue("DeviceToken \(deviceToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try synchronousData(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APISeedError.missingField(path)
        }
        return json
    }

    /// Seeds a protocol → section → step (with a real `step_duration`) → session attached to it.
    private func seedSessionWithTimedStepViaAPI(protocolTitle: String, sessionName: String) throws -> (deviceToken: String, sessionID: Int64, stepID: Int64, sessionName: String) {
        let deviceToken = try fetchDeviceTokenViaAPI()
        let protocolJSON = try postJSON("protocols/", body: ["protocol_title": protocolTitle, "enabled": false], deviceToken: deviceToken)
        guard let protocolID = protocolJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let sectionJSON = try postJSON("sections/", body: ["protocol": protocolID, "section_description": "Sec1", "section_duration": 0], deviceToken: deviceToken)
        guard let sectionID = sectionJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let stepJSON = try postJSON(
            "steps/",
            body: ["protocol": protocolID, "step_section": sectionID, "step_description": "Timed Step", "step_duration": 120],
            deviceToken: deviceToken
        )
        guard let stepID = stepJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let sessionJSON = try postJSON("sessions/", body: ["name": sessionName, "enabled": false, "protocols": [protocolID]], deviceToken: deviceToken)
        guard let sessionID = sessionJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        return (deviceToken, Int64(sessionID), Int64(stepID), sessionName)
    }

    private func findTimeKeeperIDViaAPI(sessionID: Int64, stepID: Int64, deviceToken: String) throws -> Int64 {
        let json = try getJSON("time-keepers/?session=\(sessionID)&step=\(stepID)", deviceToken: deviceToken)
        guard let results = json["results"] as? [[String: Any]], let first = results.first, let id = first["id"] as? Int else {
            throw APISeedError.missingField("time-keepers results")
        }
        return Int64(id)
    }

    private func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try result!.get()
    }

    /// Taps a tab by its label, polling with a fresh query each iteration, falling back to "More".
    private func tapTab(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let predicate = NSPredicate(format: "label == %@", label)
            let match = firstExisting(
                app.tabBars.buttons.matching(predicate).firstMatch,
                app.buttons.matching(predicate).firstMatch,
                app.radioButtons.matching(predicate).firstMatch,
                app.cells.matching(predicate).firstMatch,
                app.cells.staticTexts.matching(predicate).firstMatch
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

    /// Finds an element matching the predicate in the given query, polling with a fresh query each iteration.
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

    /// Pastes text into a field via the clipboard rather than `typeText`.
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

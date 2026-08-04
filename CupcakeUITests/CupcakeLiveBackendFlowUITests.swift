
import CryptoKit
import XCTest

#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class CupcakeLiveBackendFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDown() {
        XCUIApplication(bundleIdentifier: "info.proteo.cupcake").terminate()
        super.tearDown()
    }

    @MainActor
    func testSignInAndCreateProtocolSyncsImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 10))
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/", in: app)

        XCTAssertEqual(serverURLField.value as? String, "http://127.0.0.1:8002/api/v1/", "The server URL field should contain exactly the pasted text, not a mix of old and new")

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()
        dismissSavePasswordPromptIfPresent()

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

        let matchingRows = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", protocolTitle, protocolTitle))
        XCTAssertTrue(matchingRows.firstMatch.waitForExistence(timeout: 10), "The newly-created protocol should appear in the list")
        matchingRows.firstMatch.tap()

        XCTAssertFalse(elementContaining("Pending sync", in: app).exists, "A protocol created while signed in against a reachable backend should sync immediately, not queue")
        XCTAssertFalse(elementContaining("Local only", in: app).exists, "\"Local only\" is standalone-mode-only phrasing, shouldn't appear when signed in")
    }

    @MainActor
    func testSelectingExistingProtocolRowShowsCorrectDetail() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Protocols", in: app, timeout: 10)

        let titlePredicate = NSPredicate(format: "label CONTAINS %@", "Test")
        var candidateTitle: String?
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, candidateTitle == nil {
            let matches = app.staticTexts.matching(titlePredicate)
            for index in 0..<min(matches.count, 10) {
                let element = matches.element(boundBy: index)
                if element.exists, element.label.count > 5 {
                    candidateTitle = element.label
                    break
                }
            }
            if candidateTitle == nil { Thread.sleep(forTimeInterval: 0.3) }
        }

        XCTAssertNotNil(candidateTitle, "There should be at least one existing protocol row already visible in the list without needing to create one")
        guard let candidateTitle else { return }

        let existingRow = app.staticTexts[candidateTitle]
        XCTAssertTrue(existingRow.exists, "The chosen existing row should be tappable")
        existingRow.tap()

        let detailTitleShown = waitForTextAppearing(candidateTitle, in: app, timeout: 10)
        XCTAssertTrue(detailTitleShown, "Tapping an existing (not-just-created) protocol row \"\(candidateTitle)\" should show its own detail, not stay blank or show a different protocol")
    }

    @MainActor
    func testSyncProgressBannerShowsPullDuringSignInSync() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        let bannerPredicate = NSPredicate(format: "identifier == %@", "syncProgressBanner")
        var sawPullBanner = false
        var sawPullLabel = ""
        let bannerQuery = app.staticTexts.matching(bannerPredicate)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let element = bannerQuery.firstMatch
            if element.exists {
                let valueText = (element.value as? String) ?? ""
                let text = !valueText.isEmpty ? valueText : element.label
                if text.hasPrefix("Pulling") {
                    sawPullBanner = true
                    sawPullLabel = text
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        XCTAssertTrue(sawPullBanner, "The sync-progress banner should show a \"Pulling …\" label at some point during the automatic sign-in sync against a real backend with real data to pull")
        if sawPullBanner {
            XCTAssertTrue(sawPullLabel.hasSuffix("…"), "The pull label should end with an ellipsis, e.g. \"Pulling protocols…\" — got \"\(sawPullLabel)\"")
        }

        let bannerDeadline = Date().addingTimeInterval(30)
        while Date() < bannerDeadline, bannerQuery.firstMatch.exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(bannerQuery.firstMatch.exists, "The banner should disappear once syncAll() finishes, not stay stuck")
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

        tapToolbarButton("exitOfflineModeButton", label: "Exit Offline Mode", in: app, overflowIndex: 0)

        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 10))
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/", in: app)

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()
        dismissSavePasswordPromptIfPresent()

        let importButton = app.buttons.matching(identifier: "importLocalNotebookButton").firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 10), "Signing in with local-only content should offer to import it")
        importButton.tap()
        waitForSignInSyncToFinish(in: app)

        let importedRow = waitForMatch(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", protocolTitle, protocolTitle), in: app.staticTexts, timeout: 10)
        XCTAssertTrue(importedRow.exists, "The imported protocol should appear in the list once synced")
        importedRow.tap()

        XCTAssertFalse(elementContaining("Pending sync", in: app).exists, "An imported protocol should be fully synced, not left pending")
        XCTAssertFalse(elementContaining("Local only", in: app).exists, "An imported protocol should no longer show standalone-mode phrasing")
    }

    @MainActor
    func testEditMetadataColumnValueSyncsImmediately() throws {
        let jobName = "Edit Value Test Job \(Int(Date().timeIntervalSince1970))"
        let seed = try seedJobWithEditableColumnViaAPI(jobName: jobName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 10)

        findAndTapJobRow(named: jobName, in: app, timeout: 10)

        let createFromTemplateButtonForEdit = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButtonForEdit, in: app)
        XCTAssertTrue(createFromTemplateButtonForEdit.waitForExistence(timeout: 10), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButtonForEdit.tap()

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        let templateSearchFieldForEdit = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForEdit.waitForExistence(timeout: 10))
        templateSearchFieldForEdit.tap()
        templateSearchFieldForEdit.typeText(seed.templateName)

        let templateRowForEdit = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRowForEdit.waitForExistence(timeout: 10), "The template created via the API should appear once synced and filtered by search")
        templateRowForEdit.tap()

        let sampleCountFieldForEdit = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountFieldForEdit.waitForExistence(timeout: 5))
        sampleCountFieldForEdit.tap()
        sampleCountFieldForEdit.typeText("1")
        app.buttons["createMetadataTableButton"].tap()

        let columnRow = app.buttons["metadataColumnRow_\(seed.columnName)"]
        scrollDownUntilVisible(columnRow, in: app)
        XCTAssertTrue(columnRow.waitForExistence(timeout: 10), "The job's editable metadata column should be listed")
        columnRow.tap()

        let valueField = app.textFields["metadataValueField"]
        XCTAssertTrue(valueField.waitForExistence(timeout: 5))
        let newValue = "SN-\(Int(Date().timeIntervalSince1970))"
        replaceText(in: valueField, with: newValue, in: app)

        tapToolbarButton("saveMetadataValueButton", label: "Save", in: app, window: "metadata-value-editor", overflowIndex: 1, timeout: 10)

        let errorAlert = waitForAlertOrSheet(in: app, timeout: 3)
        if errorAlert.exists {
            XCTFail("Saving a metadata value against a reachable backend shouldn't show an error: \(errorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
        }

        let editorWindow = app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", "metadata-value-editor")).firstMatch
        let editorDeadline = Date().addingTimeInterval(10)
        while editorWindow.exists, Date() < editorDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(editorWindow.exists, "The Edit Value window should close on its own once the save genuinely completes")

        scrollDownUntilVisible(columnRow, in: app, window: "main-AppWindow")
        XCTAssertTrue(waitForTextAppearing(newValue, in: app, timeout: 10), "The updated value should appear in the column list after saving")
    }

    @MainActor
    func testModificationParametersColumnUnimodSpecificationSyncsLive() throws {
        let jobName = "Modification Test Job \(Int(Date().timeIntervalSince1970))"
        let seed = try seedJobWithModificationColumnViaAPI(jobName: jobName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 10)
        findAndTapJobRow(named: jobName, in: app, timeout: 10)

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 10), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButton.tap()
        waitForSignInSyncToFinish(in: app)

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        let templateSearchField = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchField.waitForExistence(timeout: 10))
        templateSearchField.tap()
        templateSearchField.typeText(seed.templateName)

        let templateRow = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10), "The template created via the API should appear once synced and filtered by search")
        templateRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("1")
        app.buttons["createMetadataTableButton"].tap()

        let columnRow = app.buttons["metadataColumnRow_\(seed.columnName)"]
        scrollDownUntilVisible(columnRow, in: app)
        XCTAssertTrue(columnRow.waitForExistence(timeout: 10), "The seeded modification-parameters column should be listed")
        columnRow.tap()

        let ntField = app.textFields["sdrfField_NT"]
        XCTAssertTrue(ntField.waitForExistence(timeout: 5), "A comment[modification parameters] column should render the SDRF key-value editor, not a plain text field")
        ntField.tap()
        ntField.typeText("Phospho")

        let suggestionRow = app.buttons["ontologySuggestionRow_Phospho"]
        XCTAssertTrue(suggestionRow.waitForExistence(timeout: 10), "A real Unimod suggestion for \"Phospho\" should appear from the live ontology typeahead")

        ntField.typeText("\n")
        Thread.sleep(forTimeInterval: 0.5)

        let acField = app.textFields["sdrfField_AC"]
        var selectedSuggestion = false
        for _ in 0..<3 {
            scrollDownUntilVisible(suggestionRow, in: app)
            Thread.sleep(forTimeInterval: 0.5)
            suggestionRow.tap()
            scrollUpUntilVisible(acField, in: app)
            Thread.sleep(forTimeInterval: 0.5)
            if acField.exists, let acValue = acField.value as? String, acValue == "UNIMOD:21" {
                selectedSuggestion = true
                break
            }
        }
        XCTAssertTrue(selectedSuggestion, "Selecting the suggestion should fill AC with the real Unimod accession")
        XCTAssertEqual(ntField.value as? String, "Phospho", "Selecting the suggestion should fill NT")

        let combinedSpecRow = app.buttons["specificationRow_1"]
        scrollDownUntilVisible(combinedSpecRow, in: app)
        XCTAssertTrue(combinedSpecRow.waitForExistence(timeout: 5), "The real, non-hidden Threonine/Serine specification should be listed")
        let tyrosineSpecRow = app.buttons["specificationRow_2"]
        XCTAssertTrue(tyrosineSpecRow.exists, "The real, non-hidden Tyrosine specification should be listed")

        Thread.sleep(forTimeInterval: 0.5)
        combinedSpecRow.tap()

        let taField = app.textFields["sdrfField_TA"]
        scrollUpUntilVisible(taField, in: app)
        XCTAssertTrue(taField.waitForExistence(timeout: 5))
        XCTAssertEqual(taField.value as? String, "T,S", "Applying the combined specification should fill TA with both real residues, comma-joined")

        tapToolbarButton("saveMetadataValueButton", label: "Save", in: app, window: "metadata-value-editor", overflowIndex: 1, timeout: 5)

        let errorAlert = waitForAlertOrSheet(in: app, timeout: 3)
        if errorAlert.exists {
            XCTFail("Saving a modification-parameters value against a reachable backend shouldn't show an error: \(errorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
        }

        let editorWindow = app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", "metadata-value-editor")).firstMatch
        let editorDeadline = Date().addingTimeInterval(10)
        while editorWindow.exists, Date() < editorDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(editorWindow.exists, "The Edit Value window should close on its own once the save genuinely completes")

        scrollDownUntilVisible(columnRow, in: app, window: "main-AppWindow")
        XCTAssertTrue(waitForTextAppearing("NT=Phospho", in: app, timeout: 10), "The saved NT=Phospho;AC=UNIMOD:21;...;TA=T,S;... value should appear in the column list after saving")
        XCTAssertTrue(waitForTextAppearing("TA=T,S", in: app, timeout: 5), "The saved value should include the applied specification's target amino acids")
    }

    @MainActor
    func testManageMetadataTableTemplateEditAndDelete() throws {
        let templateName = "Live Test Template \(Int(Date().timeIntervalSince1970))"
        try createBlankTemplateViaAPI(named: templateName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 10))
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/", in: app)

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()
        dismissSavePasswordPromptIfPresent()
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)
        tapToolbarButton("manageMetadataTableTemplatesButton", label: "Table Templates", in: app, timeout: 10)
        waitForSignInSyncToFinish(in: app)

        let searchField = app.textFields.matching(identifier: "myTableTemplateSearchField").firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(templateName)

        let templateRow = app.buttons.matching(identifier: "myTableTemplateRow_\(templateName)").firstMatch
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10), "The blank template created via the API should appear in the management list")
        Thread.sleep(forTimeInterval: 1)
        templateRow.tap()

        let editTemplateButtonForRename = app.buttons["editTableTemplateButton"]
        XCTAssertTrue(editTemplateButtonForRename.waitForExistence(timeout: 10), "The template preview should offer an Edit button")
        editTemplateButtonForRename.tap()

        let nameField = app.textFields["tableTemplateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let renamedName = templateName + " Renamed"
        replaceText(in: nameField, with: renamedName, in: app)
        app.buttons["saveTableTemplateButton"].tap()
        XCTAssertTrue(waitForElementDestroyed(identifier: "tableTemplateNameField", in: app, timeout: 10), "Tapping Save should trigger the async save and dismiss the edit sheet")

        #if os(iOS)
        let templatesBackButton = app.navigationBars.buttons["Templates"]
        XCTAssertTrue(templatesBackButton.waitForExistence(timeout: 5), "Should be back on the template detail page with a Templates back button after saving")
        for _ in 0..<4 {
            if templatesBackButton.isHittable { templatesBackButton.tap() }
            if searchField.waitForExistence(timeout: 3) { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        #endif
        replaceText(in: searchField, with: renamedName, in: app)
        let renamedRow = app.buttons.matching(identifier: "myTableTemplateRow_\(renamedName)").firstMatch
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 10), "The renamed template should appear in the management list")
    }

    @MainActor
    func testColumnAndTableTemplateManagementFlow() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Protocols", in: app, timeout: 10)
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        tapToolbarButton("settingsButton", label: "Settings", in: app, verify: { self.waitForTextAppearing("Offline Ontology Data", in: app, timeout: 3) })
        #endif
        XCTAssertTrue(waitForTextAppearing("Offline Ontology Data", in: app, timeout: 10))
        firstExisting(app.buttons["settingsSidebarItem_offlineOntologyData"], app.staticTexts["settingsSidebarItem_offlineOntologyData"], app.cells["settingsSidebarItem_offlineOntologyData"]).tap()
        let schemaImportButton = app.buttons["importOntologyButton_sdrf"]
        scrollDownUntilVisible(schemaImportButton, in: app)
        XCTAssertTrue(schemaImportButton.waitForExistence(timeout: 10))
        if schemaImportButton.label != "Re-import" {
            schemaImportButton.tap()
            let deadline = Date().addingTimeInterval(120)
            while schemaImportButton.label != "Re-import", Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }
        XCTAssertEqual(schemaImportButton.label, "Re-import", "The sdrf schema dataset should finish importing (button relabels itself once its own importedAt state is set)")
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        tapToolbarButton("doneButton", label: "Done", in: app, timeout: 3)
        #endif

        tapTab("Jobs", in: app, timeout: 10)
        let newJobOverflowIndex = dynamicOverflowIndex(precedingIdentifiers: ["projectsLink", "manageMetadataTableTemplatesButton", "columnTemplatesToolbarButton", "metadataTablesBrowserButton", "labGroupsButton"], in: app)
        tapToolbarButton("newJobButton", label: "New Job", in: app, overflowIndex: newJobOverflowIndex, timeout: 10)
        let jobName = "Template Flow Job \(timestamp)"
        let jobNameField = app.textFields["newJobNameField"]
        XCTAssertTrue(jobNameField.waitForExistence(timeout: 5))
        jobNameField.tap()
        jobNameField.typeText(jobName)
        tapCreateJobButtonReliably(in: app)
        XCTAssertTrue(waitForElementDestroyed(identifier: "newJobNameField", in: app, timeout: 10), "Tapping Create should trigger the async create and dismiss the New Job sheet")

        findAndTapJobRow(named: jobName, in: app)

        let labGroupSearchField = app.textFields["jobLabGroupSearchField"]
        XCTAssertTrue(labGroupSearchField.waitForExistence(timeout: 10))
        labGroupSearchField.tap()
        labGroupSearchField.typeText("Test Lab Group")
        app.buttons["jobLabGroupRow_Test Lab Group"].tap()

        let assignStaffButton = app.buttons["assignStaffButton"]
        XCTAssertTrue(assignStaffButton.waitForExistence(timeout: 10), "Assigning staff should become available once a lab group is set")
        assignStaffButton.tap()
        let staffRow = app.buttons["staffMemberRow_testuser"]
        XCTAssertTrue(staffRow.waitForExistence(timeout: 10))
        staffRow.tap()
        tapToolbarButton("saveStaffAssignmentButton", label: "Save", in: app)

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let jobsBackButtonBeforeTemplates = app.navigationBars.buttons["Jobs"]
            XCTAssertTrue(jobsBackButtonBeforeTemplates.waitForExistence(timeout: 5), "Should be back on the job detail page with a Jobs back button before reaching list-level Table Templates management")
            for _ in 0..<4 {
                if jobsBackButtonBeforeTemplates.isHittable { jobsBackButtonBeforeTemplates.tap() }
                if app.navigationBars["Jobs"].waitForExistence(timeout: 3) { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        #endif
        tapToolbarButton("manageMetadataTableTemplatesButton", label: "Table Templates", in: app, timeout: 10)
        app.buttons["newMetadataTableTemplateButton"].tap()
        tapSegment("From Schema", in: app)

        let tableTemplateName = "Template Flow Table Template \(timestamp)"
        let newTemplateNameField = app.textFields["newTemplateNameField"]
        XCTAssertTrue(newTemplateNameField.waitForExistence(timeout: 5))
        newTemplateNameField.tap()
        newTemplateNameField.typeText(tableTemplateName)

        let schemaSearchField = app.textFields["schemaSearchField"]
        XCTAssertTrue(schemaSearchField.waitForExistence(timeout: 10))

        schemaSearchField.tap()
        schemaSearchField.typeText("ms-proteomics")
        let msProteomicsRow = app.buttons["schemaRow_ms-proteomics"]
        XCTAssertTrue(msProteomicsRow.waitForExistence(timeout: 10), "ms-proteomics should be selectable since the sdrf dataset was just imported")
        msProteomicsRow.tap()

        replaceText(in: schemaSearchField, with: "human", in: app)
        let humanRow = app.buttons["schemaRow_human"]
        XCTAssertTrue(humanRow.waitForExistence(timeout: 10), "human should be selectable since the sdrf dataset was just imported")
        humanRow.tap()

        let createTemplateButton = app.buttons["createTemplateButton"]
        XCTAssertTrue(createTemplateButton.waitForExistence(timeout: 5), "The Create button should be reachable once a schema is selected")
        createTemplateButton.tap()

        let createTemplateErrorAlert = app.alerts.firstMatch
        if createTemplateErrorAlert.waitForExistence(timeout: 3) {
            XCTFail("Creating the table template shouldn't show an error: \(createTemplateErrorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
        }
        XCTAssertTrue(
            waitForElementDestroyed(identifier: "createTemplateButton", in: app, timeout: 10),
            "The create-template sheet should dismiss itself once its async create call finishes, before we try to close the parent window"
        )

        #if os(macOS)
        closeWindow(matching: "table-template-manager", in: app, timeout: 10)
        #else
        Thread.sleep(forTimeInterval: 1.0)
        dismissTableTemplateManagementSheet(in: app)
        if UIDevice.current.userInterfaceIdiom == .phone {
            findAndTapJobRow(named: jobName, in: app)
        }
        #endif

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 10))
        createFromTemplateButton.tap()
        waitForSignInSyncToFinish(in: app)

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        let templateSearchField = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchField.waitForExistence(timeout: 10), "The template picker should offer a search field given how many templates have accumulated on this long-lived test backend")
        templateSearchField.tap()
        templateSearchField.typeText(tableTemplateName)

        let newTemplateRow = app.buttons["metadataTemplateRow_\(tableTemplateName)"]
        XCTAssertTrue(newTemplateRow.waitForExistence(timeout: 10), "The just-created template should appear in the picker once filtered by its unique name")
        newTemplateRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 10))
        sampleCountField.tap()
        sampleCountField.typeText("3")
        app.buttons["createMetadataTableButton"].tap()

        let addMetadataColumnButton = app.buttons["addMetadataColumnButton"]
        scrollDownUntilVisible(addMetadataColumnButton, in: app)
        XCTAssertTrue(addMetadataColumnButton.waitForExistence(timeout: 10), "The Metadata Table section should appear once created")

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let jobsBackButtonBeforeSecondTemplatesVisit = app.navigationBars.buttons["Jobs"]
            XCTAssertTrue(jobsBackButtonBeforeSecondTemplatesVisit.waitForExistence(timeout: 5), "Should be back on the job detail page with a Jobs back button before reaching list-level Table Templates management a second time")
            for _ in 0..<4 {
                if jobsBackButtonBeforeSecondTemplatesVisit.isHittable { jobsBackButtonBeforeSecondTemplatesVisit.tap() }
                if app.navigationBars["Jobs"].waitForExistence(timeout: 3) { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        #endif
        tapToolbarButton("manageMetadataTableTemplatesButton", label: "Table Templates", in: app, timeout: 10)
        waitForSignInSyncToFinish(in: app)
        let managementSearchField = app.textFields.matching(identifier: "myTableTemplateSearchField").firstMatch
        XCTAssertTrue(managementSearchField.waitForExistence(timeout: 10))
        managementSearchField.tap()
        managementSearchField.typeText(tableTemplateName)

        let tableTemplateRow = app.buttons.matching(identifier: "myTableTemplateRow_\(tableTemplateName)").firstMatch
        XCTAssertTrue(tableTemplateRow.waitForExistence(timeout: 10), "The newly-created table template should appear in the management list")
        XCTAssertFalse(tableTemplateRow.label.contains("0 columns"), "Combining ms-proteomics + human should produce real columns, not an empty (Blank-equivalent) template: \(tableTemplateRow.label)")
        tableTemplateRow.tap()

        tapToolbarButton("editTableTemplateButton", label: "Edit…", in: app, window: "table-template-manager", timeout: 10)
        let tableTemplateNameField = app.textFields["tableTemplateNameField"]
        XCTAssertTrue(tableTemplateNameField.waitForExistence(timeout: 10), "The template edit sheet should open")

        let templateColumnSearchField = app.textFields["templateColumnSearchField"]
        func filterTemplateColumns(to term: String) {
            guard templateColumnSearchField.waitForExistence(timeout: 3) else { return }
            replaceText(in: templateColumnSearchField, with: term, in: app)
        }

        let column1Name = "characteristics[flow test a]"
        let addTemplateColumnButton = app.buttons["addTemplateColumnButton"]
        filterTemplateColumns(to: "zzznomatchingcolumn")
        XCTAssertTrue(addTemplateColumnButton.waitForExistence(timeout: 10))
        addTemplateColumnButton.tap()
        let addColumnNameField = app.textFields["addTemplateColumnNameField"]
        XCTAssertTrue(addColumnNameField.waitForExistence(timeout: 5))
        addColumnNameField.tap()
        addColumnNameField.typeText(column1Name)
        app.buttons["confirmAddTemplateColumnButton"].tap()
        filterTemplateColumns(to: column1Name)
        XCTAssertTrue(app.buttons["templateColumnRow_\(column1Name)"].waitForExistence(timeout: 10), "The first added column should appear")

        let column2Name = "characteristics[flow test b]"
        filterTemplateColumns(to: "zzznomatchingcolumn")
        XCTAssertTrue(addTemplateColumnButton.waitForExistence(timeout: 10))
        addTemplateColumnButton.tap()
        let addColumnNameField2 = app.textFields["addTemplateColumnNameField"]
        XCTAssertTrue(addColumnNameField2.waitForExistence(timeout: 5))
        addColumnNameField2.tap()
        addColumnNameField2.typeText(column2Name)
        app.buttons["confirmAddTemplateColumnButton"].tap()
        filterTemplateColumns(to: column2Name)
        XCTAssertTrue(app.buttons["templateColumnRow_\(column2Name)"].waitForExistence(timeout: 10), "The second added column should appear")

        let selectModeButton = app.buttons["templateColumnSelectModeButton"]
        XCTAssertTrue(selectModeButton.waitForExistence(timeout: 10))
        selectModeButton.tap()
        let column1Row = app.buttons["templateColumnRow_\(column1Name)"]
        filterTemplateColumns(to: column1Name)
        XCTAssertTrue(column1Row.waitForExistence(timeout: 10))
        column1Row.tap()
        let column2Row = app.buttons["templateColumnRow_\(column2Name)"]
        filterTemplateColumns(to: column2Name)
        XCTAssertTrue(column2Row.waitForExistence(timeout: 10))
        column2Row.tap()
        filterTemplateColumns(to: "")
        let bulkStaffOnlyButton = app.buttons["templateColumnBulkStaffOnlyButton"]
        XCTAssertTrue(bulkStaffOnlyButton.waitForExistence(timeout: 10))
        bulkStaffOnlyButton.tap()
        XCTAssertFalse(app.alerts["Couldn't save template"].waitForExistence(timeout: 3), "Bulk staff-only update against a reachable backend shouldn't show an error")
        Thread.sleep(forTimeInterval: 3.0)

        if selectModeButton.label == "Select" {
            selectModeButton.tap()
        }
        filterTemplateColumns(to: column1Name)
        XCTAssertTrue(column1Row.waitForExistence(timeout: 10))
        column1Row.tap()
        filterTemplateColumns(to: column2Name)
        XCTAssertTrue(column2Row.waitForExistence(timeout: 10))
        column2Row.tap()
        filterTemplateColumns(to: "")
        let bulkDeleteButton = app.buttons["templateColumnBulkDeleteButton"]
        XCTAssertTrue(bulkDeleteButton.waitForExistence(timeout: 10))
        bulkDeleteButton.tap()
        XCTAssertFalse(app.buttons["templateColumnRow_\(column1Name)"].waitForExistence(timeout: 5), "Bulk-deleted columns should no longer appear")
        selectModeButton.tap()

        filterTemplateColumns(to: "zzznomatchingcolumn")
        XCTAssertTrue(addTemplateColumnButton.waitForExistence(timeout: 10))
        addTemplateColumnButton.tap()
        let seedColumnNameField = app.textFields["addTemplateColumnNameField"]
        XCTAssertTrue(seedColumnNameField.waitForExistence(timeout: 5))
        seedColumnNameField.tap()
        seedColumnNameField.typeText("characteristics[flow seed col]")
        app.buttons["confirmAddTemplateColumnButton"].tap()
        filterTemplateColumns(to: "characteristics[flow seed col]")
        XCTAssertTrue(app.buttons["templateColumnRow_characteristics[flow seed col]"].waitForExistence(timeout: 10))

        let saveTableTemplateButton = app.buttons["saveTableTemplateButton"]
        saveTableTemplateButton.tap()
        XCTAssertTrue(
            waitForElementDestroyed(identifier: "tableTemplateNameField", in: app, timeout: 10),
            "The edit-template sheet should dismiss itself once its async save call finishes, before we try to close the parent window. Waiting on the stable name field rather than the Save button itself, since Save's label swaps to a ProgressView mid-save and can falsely register as destroyed before the sheet actually closes."
        )
        #if os(macOS)
        closeWindow(matching: "table-template-manager", in: app, timeout: 10)
        #else
        Thread.sleep(forTimeInterval: 1.0)
        dismissTableTemplateManagementSheet(in: app)
        if UIDevice.current.userInterfaceIdiom == .phone {
            findAndTapJobRow(named: jobName, in: app)
        }
        #endif
        let mainWindow = frontmostWindow(in: app, matching: "main-AppWindow")
        let addMetadataColumnButtonAgain = mainWindow.buttons["addMetadataColumnButton"]
        let manageMyColumnTemplatesButton = mainWindow.buttons["manageMyColumnTemplatesButton"]
        let jobMetadataColumnSearchField = mainWindow.textFields["jobMetadataColumnSearchField"]
        if jobMetadataColumnSearchField.waitForExistence(timeout: 3) {
            jobMetadataColumnSearchField.tap()
            jobMetadataColumnSearchField.typeText("zzznomatchingcolumn")
        }
        XCTAssertTrue(addMetadataColumnButtonAgain.waitForExistence(timeout: 10))
        addMetadataColumnButtonAgain.tap()
        XCTAssertTrue(manageMyColumnTemplatesButton.waitForExistence(timeout: 10), "The Add Metadata Field sheet should open")
        manageMyColumnTemplatesButton.tap()

        tapSegment("Grouped", in: app)
        XCTAssertTrue(
            firstExisting(app.staticTexts["No matching columns found."], app.staticTexts["Type at least 3 characters to search across every schema."]).waitForExistence(timeout: 5),
            "Grouped mode should render its own empty state without crashing"
        )
        tapSegment("My Templates", in: app)

        app.buttons["newColumnTemplateButton"].tap()
        let columnTemplateName = "Flow Column Template \(timestamp)"
        let columnTemplateNameField = app.textFields["columnTemplateNameField"]
        XCTAssertTrue(columnTemplateNameField.waitForExistence(timeout: 5))
        replaceText(in: columnTemplateNameField, with: columnTemplateName, in: app)

        let columnTemplateColumnNameField = app.textFields["columnTemplateColumnNameField"]
        replaceText(in: columnTemplateColumnNameField, with: "characteristics[flow column template]", in: app)

        let tagsField = app.textFields["columnTemplateTagsField"]
        replaceText(in: tagsField, with: "flowtest, verify", in: app)

        let defaultPositionField = app.textFields["columnTemplateDefaultPositionField"]
        replaceText(in: defaultPositionField, with: "2", in: app)

        app.buttons["saveColumnTemplateButton"].tap()

        let columnTemplateSearchField = app.textFields["columnTemplateSearchField"]
        XCTAssertTrue(columnTemplateSearchField.waitForExistence(timeout: 10))
        columnTemplateSearchField.tap()
        columnTemplateSearchField.typeText(columnTemplateName)

        let columnTemplateRow = app.buttons["myColumnTemplateRow_\(columnTemplateName)"]
        XCTAssertTrue(columnTemplateRow.waitForExistence(timeout: 10), "The newly-created column template should appear in the flat list once filtered by its unique name")

        columnTemplateRow.tap()
        let reopenedDefaultPositionField = app.textFields["columnTemplateDefaultPositionField"]
        XCTAssertTrue(reopenedDefaultPositionField.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedDefaultPositionField.value as? String, "2", "The default position should round-trip through save/reload")
        let reopenedTagsField = app.textFields["columnTemplateTagsField"]
        XCTAssertEqual(reopenedTagsField.value as? String, "flowtest, verify", "Tags should round-trip through save/reload")
    }

    @MainActor
    func testMetadataTableGridBrowserAndAutofillFlow() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let jobName = "Grid Flow Job \(timestamp)"
        let seed = try seedJobWithMetadataTableViaAPI(jobName: jobName)

        let browserTableName = "Browser Flow Table \(timestamp)"
        let browserDeviceToken = try fetchDeviceTokenViaAPI()
        try seedStandaloneMetadataTableViaAPI(named: browserTableName, deviceToken: browserDeviceToken)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)
        findAndTapJobRow(named: jobName, in: app)

        let createFromTemplateButtonForGrid = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButtonForGrid, in: app)
        XCTAssertTrue(createFromTemplateButtonForGrid.waitForExistence(timeout: 10), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButtonForGrid.tap()
        waitForSignInSyncToFinish(in: app)

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        let templateSearchFieldForGrid = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForGrid.waitForExistence(timeout: 10))
        templateSearchFieldForGrid.tap()
        templateSearchFieldForGrid.typeText(seed.templateName)

        let templateRowForGrid = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRowForGrid.waitForExistence(timeout: 10), "The template created via the API should appear once synced and filtered by search")
        templateRowForGrid.tap()

        let sampleCountFieldForGrid = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountFieldForGrid.waitForExistence(timeout: 5))
        sampleCountFieldForGrid.tap()
        sampleCountFieldForGrid.typeText("\(seed.sampleCount)")
        app.buttons["createMetadataTableButton"].tap()

        let openFullTableViewButton = app.buttons["openFullMetadataTableViewButton"]
        XCTAssertTrue(openFullTableViewButton.waitForExistence(timeout: 10))
        scrollDownUntilVisible(openFullTableViewButton, in: app)
        openFullTableViewButton.tap()

        tapSegment("List", within: "metadataTableViewModePicker", in: app)
        let seededColumnRow = waitForMatchAcrossTypes(
            NSPredicate(format: "label CONTAINS %@", seed.column1Name),
            in: app, timeout: 10
        )
        XCTAssertTrue(seededColumnRow.exists, "List mode should show the seeded columns")

        tapSegment("Table", within: "metadataTableViewModePicker", in: app)
        let firstCell = app.buttons["metadataTableCell_\(seed.column1Name)_1"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "Table mode should show a grid cell for sample 1")
        firstCell.tap()

        let valueField = firstExisting(app.textFields["metadataValueField"], app.textViews["metadataValueField"])
        XCTAssertTrue(valueField.waitForExistence(timeout: 5))
        valueField.tap()
        valueField.typeText("42.0")
        tapToolbarButton("saveMetadataValueButton", label: "Save", in: app, window: "metadata-value-editor", overflowIndex: 1)
        XCTAssertTrue(waitForElementDisappearing(valueField, timeout: 10), "The edit-value window should close itself once its save call finishes")
        let metadataTableDetailWindow = frontmostWindow(in: app, matching: "metadata-table-detail")
        let updatedCellPredicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "42.0", "42.0")
        var sawUpdatedCell = false
        let updatedCellDeadline = Date().addingTimeInterval(10)
        while Date() < updatedCellDeadline {
            if metadataTableDetailWindow.staticTexts.matching(updatedCellPredicate).firstMatch.exists
                || metadataTableDetailWindow.buttons.matching(updatedCellPredicate).firstMatch.exists {
                sawUpdatedCell = true
                break
            }
        }
        XCTAssertTrue(sawUpdatedCell, "The edited cell value should appear once synced")

        tapSegment("List", within: "metadataTableViewModePicker", in: app)
        let columnFilterField = app.textFields["metadataTableColumnFilterField"]
        XCTAssertTrue(columnFilterField.waitForExistence(timeout: 10))
        columnFilterField.tap()
        columnFilterField.typeText(seed.column2Name)
        tapMenuItem("metadataTableColumnMenu_\(seed.column2Name)", item: "metadataTableColumnAutofillMenuItem_\(seed.column2Name)", in: app)

        let templateField = app.textFields["basicAutofillTemplateField"]
        XCTAssertTrue(templateField.waitForExistence(timeout: 5), "Basic mode should be selected by default")
        app.buttons["applyAutofillButton"].tap()
        let autofillCompleteAlert = waitForAlertOrSheet(in: app, timeout: 10)
        XCTAssertTrue(autofillCompleteAlert.exists, "Basic autofill against a reachable backend should report success")
        autofillCompleteAlert.buttons["OK"].tap()

        tapMenuItem("metadataTableColumnMenu_\(seed.column2Name)", item: "metadataTableColumnAutofillMenuItem_\(seed.column2Name)", in: app)
        tapSegment("Advanced", in: app)

        let templateSamplesField = app.textFields["advancedAutofillTemplateSamplesField"]
        XCTAssertTrue(templateSamplesField.waitForExistence(timeout: 5))
        replaceText(in: templateSamplesField, with: "1", in: app)

        let targetCountField = app.textFields["advancedAutofillTargetSampleCountField"]
        targetCountField.tap()
        targetCountField.typeText("\(seed.sampleCount)")
        targetCountField.typeText("\n")
        Thread.sleep(forTimeInterval: 0.5)

        let addVariationButton = app.buttons["addAutofillVariationButton"]
        scrollDownUntilVisible(addVariationButton, in: app)
        Thread.sleep(forTimeInterval: 0.5)
        addVariationButton.tap()
        selectPickerOption("autofillVariationColumnPicker_0", option: seed.column2Name, in: app, menuItemCount: 2, optionIndex: 1)
        tapSegment("List", within: "autofillVariationTypePicker_0", in: app)

        let valuesField = app.textFields["autofillVariationValuesField_0"]
        scrollDownUntilVisible(valuesField, in: app)
        XCTAssertTrue(valuesField.waitForExistence(timeout: 5))
        valuesField.tap()
        valuesField.typeText("A,B,C,D,E")
        valuesField.typeText("\n")
        Thread.sleep(forTimeInterval: 0.5)

        let applyAutofillButton = app.buttons["applyAutofillButton"]
        scrollDownUntilVisible(applyAutofillButton, in: app)
        applyAutofillButton.tap()
        let advancedAutofillCompleteAlert = waitForAlertOrSheet(in: app, timeout: 10)
        XCTAssertTrue(advancedAutofillCompleteAlert.exists, "Advanced autofill against a reachable backend should report success")
        advancedAutofillCompleteAlert.buttons["OK"].tap()
        Thread.sleep(forTimeInterval: 0.5)

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let jobsBackButton = app.navigationBars.buttons["Jobs"]
            var reachedJobDetail = false
            for _ in 0..<3 {
                app.buttons["Done"].tap()
                if jobsBackButton.waitForExistence(timeout: 3) {
                    reachedJobDetail = true
                    break
                }
            }
            XCTAssertTrue(reachedJobDetail, "Should be back on the job detail page with a Jobs back button after dismissing the full table view")
            for _ in 0..<4 {
                if jobsBackButton.isHittable { jobsBackButton.tap() }
                if app.navigationBars["Jobs"].waitForExistence(timeout: 3) { break }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        #else
        closeWindow(matching: "metadata-table-detail", in: app, timeout: 10)
        #endif
        tapToolbarButton("metadataTablesBrowserButton", label: "Metadata Tables", in: app, window: "main-AppWindow", overflowIndex: 1)

        let searchField = app.textFields["metadataTablesBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(browserTableName)
        searchField.typeText("\n")

        let browserTableRow = app.buttons["metadataTableRow_\(browserTableName)"]
        XCTAssertTrue(browserTableRow.waitForExistence(timeout: 10), "The ccv-native standalone table should appear in the browser, unlike a job-created (ccm-owned) table")

        browserTableRow.swipeRight()
        let editSwipeAction = app.buttons["Edit"]
        XCTAssertTrue(editSwipeAction.waitForExistence(timeout: 5), "The row's leading Edit swipe action should appear")
        editSwipeAction.tap()

        let sampleCountField = app.textFields["metadataTableEditSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        replaceText(in: sampleCountField, with: "1", in: app)
        app.buttons["saveMetadataTableEditButton"].tap()

        let reduceSampleCountAlert = waitForAlertOrSheet(in: app, timeout: 10)
        XCTAssertTrue(reduceSampleCountAlert.exists, "Reducing an already-populated sample count should ask for confirmation, not silently apply")
        app.buttons["confirmSampleCountReductionButton"].tap()
        XCTAssertFalse(app.alerts["Couldn't save table"].waitForExistence(timeout: 5) || app.sheets["Couldn't save table"].waitForExistence(timeout: 5), "Confirming the reduction should let the save go through")
    }

    @MainActor
    func testOntologyBrowserSearchesOnlineAcrossEnabledDatabases() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Protocols", in: app, timeout: 10)
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        tapToolbarButton("settingsButton", label: "Settings", in: app, verify: { self.waitForTextAppearing("Ontology Browser", in: app, timeout: 3) })
        #endif
        XCTAssertTrue(waitForTextAppearing("Ontology Browser", in: app, timeout: 10))
        let ontologyBrowserSidebarItem = firstExisting(app.buttons["settingsSidebarItem_ontologyBrowser"], app.staticTexts["settingsSidebarItem_ontologyBrowser"], app.cells["settingsSidebarItem_ontologyBrowser"])
        #if !os(macOS)
        scrollDownUntilVisible(ontologyBrowserSidebarItem, within: "settingsSidebarList", in: app)
        #endif
        XCTAssertTrue(ontologyBrowserSidebarItem.waitForExistence(timeout: 5), "The Ontology Browser sidebar item should carry its real accessibility identifier")
        ontologyBrowserSidebarItem.tap()

        tapSegment("Online", within: "ontologyBrowserModePicker", in: app, timeout: 10)

        let searchField = app.textFields["ontologyBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("Phospho")

        let unimodPhosphoRow = firstExisting(
            app.buttons["ontologyResultRow_unimod:UNIMOD:21"],
            app.staticTexts["ontologyResultRow_unimod:UNIMOD:21"],
            app.otherElements["ontologyResultRow_unimod:UNIMOD:21"]
        )
        let humanDiseasePhosphoRow = firstExisting(
            app.buttons["ontologyResultRow_human_disease:DI-01188"],
            app.staticTexts["ontologyResultRow_human_disease:DI-01188"],
            app.otherElements["ontologyResultRow_human_disease:DI-01188"]
        )
        XCTAssertTrue(humanDiseasePhosphoRow.waitForExistence(timeout: 10), "With every online database enabled, a Human Disease match should appear, proving results span multiple databases")

        tapToolbarButton("ontologyBrowserDatabasesButton", label: "Databases", in: app)
        let nonUnimodTypeKeys = ["tissue", "species", "human_disease", "subcellular_location", "ms_unique_vocabularies", "ncbi_taxonomy", "chebi", "mondo", "uberon", "cell_ontology", "psi_ms", "bto", "doid"]
        for typeKey in nonUnimodTypeKeys {
            let toggle = firstExisting(
                app.switches["ontologyDatabaseToggle_\(typeKey)"],
                app.checkBoxes["ontologyDatabaseToggle_\(typeKey)"],
                app.buttons["ontologyDatabaseToggle_\(typeKey)"]
            )
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "The \"\(typeKey)\" database toggle should exist in the filter sheet")
            #if !os(macOS)
            scrollDownUntilVisible(toggle, within: "ontologyDatabaseFilterList", in: app)
            Thread.sleep(forTimeInterval: 0.3)
            #endif
            func currentValue() -> Int? { toggle.value as? Int ?? (toggle.value as? String).flatMap(Int.init) }
            let valueBeforeTap = currentValue()
            for _ in 0..<3 {
                if currentValue() != valueBeforeTap { break }
                let deadline = Date().addingTimeInterval(3)
                while Date() < deadline, !toggle.isHittable {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                Thread.sleep(forTimeInterval: 0.3)
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
                Thread.sleep(forTimeInterval: 0.3)
            }
            XCTAssertNotEqual(currentValue(), valueBeforeTap, "Tapping the \"\(typeKey)\" toggle's trailing switch control should flip its value (was \(String(describing: valueBeforeTap)))")
        }
        let filterDoneButton = app.buttons["ontologyDatabaseFilterDoneButton"]
        XCTAssertTrue(filterDoneButton.waitForExistence(timeout: 5))
        filterDoneButton.tap()

        let filterAppliedDeadline = Date().addingTimeInterval(10)
        while humanDiseasePhosphoRow.exists, Date() < filterAppliedDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(humanDiseasePhosphoRow.exists, "After disabling every database except Unimod, the Human Disease result should disappear from the still-active Phospho search")

        XCTAssertTrue(unimodPhosphoRow.waitForExistence(timeout: 10), "The specific real Phospho (UNIMOD:21) result row should still exist, now as the sole database's top result")
        unimodPhosphoRow.tap()

        XCTAssertTrue(waitForTextAppearing("Delta Mono Mass", in: app, timeout: 10), "The Unimod detail view should show mass/composition fields, not the generic Simple Term layout")
        XCTAssertTrue(waitForTextAppearing("79.966331", in: app, timeout: 5), "The real Phospho delta mono mass should be shown")
    }

    @MainActor
    func testOntologyBrowserOnlineSubcellularLocationShowsRichFullData() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Protocols", in: app, timeout: 10)
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        tapToolbarButton("settingsButton", label: "Settings", in: app, verify: { self.waitForTextAppearing("Ontology Browser", in: app, timeout: 3) })
        #endif
        XCTAssertTrue(waitForTextAppearing("Ontology Browser", in: app, timeout: 10))
        let ontologyBrowserSidebarItem = firstExisting(app.buttons["settingsSidebarItem_ontologyBrowser"], app.staticTexts["settingsSidebarItem_ontologyBrowser"], app.cells["settingsSidebarItem_ontologyBrowser"])
        #if !os(macOS)
        scrollDownUntilVisible(ontologyBrowserSidebarItem, within: "settingsSidebarList", in: app)
        #endif
        XCTAssertTrue(ontologyBrowserSidebarItem.waitForExistence(timeout: 5), "The Ontology Browser sidebar item should carry its real accessibility identifier")
        ontologyBrowserSidebarItem.tap()

        tapSegment("Online", within: "ontologyBrowserModePicker", in: app, timeout: 10)

        let searchField = app.textFields["ontologyBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText("Acrosomal vesicle")

        let acrosomeResultRow = firstExisting(
            app.buttons["ontologyResultRow_subcellular_location:SL-0007"],
            app.staticTexts["ontologyResultRow_subcellular_location:SL-0007"],
            app.otherElements["ontologyResultRow_subcellular_location:SL-0007"]
        )
        XCTAssertTrue(acrosomeResultRow.waitForExistence(timeout: 10), "The specific Acrosome result row should appear for an 'Acrosomal vesicle' synonym search")
        let rowText = acrosomeResultRow.label.isEmpty ? (acrosomeResultRow.value as? String ?? "") : acrosomeResultRow.label
        XCTAssertTrue(
            rowText.contains("Acrosomal vesicle"),
            "The real Acrosome synonym should render in that specific result row (row text: '\(rowText)'), proving the online path now decodes subcellular_location's own full_data instead of only the generic id/value/description fields"
        )
    }

    @MainActor
    func testColumnTemplateShareGrantsAccessRoleLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let deviceToken = try fetchDeviceTokenViaAPI()

        let usersJSON = try getJSON("users/?search=importtestuser", deviceToken: deviceToken)
        guard let userResults = usersJSON["results"] as? [[String: Any]],
              let importTestUserID = userResults.first(where: { ($0["username"] as? String) == "importtestuser" })?["id"] as? Int else {
            XCTFail("Couldn't find importtestuser's real id via the API")
            return
        }

        let templateName = "Share Test Template \(unique)"
        let templateJSON = try postJSON(
            "column-templates/",
            body: ["name": templateName, "column_name": "share_test_col_\(unique)", "column_type": "characteristics", "visibility": "private"],
            deviceToken: deviceToken
        )
        guard let templateID = templateJSON["id"] as? Int else {
            XCTFail("Creating a column template should return an id")
            return
        }

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 10)
        tapToolbarButton("columnTemplatesToolbarButton", label: "Column Templates", in: app, overflowIndex: 0, timeout: 10)

        let searchField = app.textFields["columnTemplateSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(templateName)

        let templateRow = app.buttons["myColumnTemplateRow_\(templateName)"].firstMatch
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10), "The freshly created column template should appear once synced")
        #if os(macOS)
        templateRow.rightClick()
        #else
        templateRow.press(forDuration: 1.0)
        #endif

        let shareMenuButton = firstExisting(
            app.buttons["shareColumnTemplateMenuButton_\(templateName)"],
            app.menuItems["shareColumnTemplateMenuButton_\(templateName)"]
        )
        XCTAssertTrue(shareMenuButton.waitForExistence(timeout: 5), "A Share context-menu action should appear for a template this user owns")
        shareMenuButton.tap()

        let shareSearchField = app.textFields["templateShareSearchUsersField"]
        XCTAssertTrue(shareSearchField.waitForExistence(timeout: 10))
        shareSearchField.tap()
        shareSearchField.typeText("importtestuser")

        let editButton = app.buttons["shareTemplateAsEditButton_importtestuser"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 10), "The user search should find importtestuser and offer an Edit share button")
        editButton.tap()

        XCTAssertTrue(waitForTextAppearing("importtestuser", in: app, timeout: 10), "The new share should appear in the Shared With list")
        XCTAssertTrue(waitForTextAppearing("Edit", in: app, timeout: 5), "The new share should show its Edit permission level")

        let shares = try getJSON("template-shares/?template_id=\(templateID)", deviceToken: deviceToken)
        guard let shareResults = shares["results"] as? [[String: Any]],
              let share = shareResults.first(where: { ($0["user"] as? Int) == importTestUserID }) else {
            XCTFail("The real backend should record a share for importtestuser on this template")
            return
        }
        XCTAssertEqual(share["permission_level"] as? String, "edit", "The share should have been created at Edit permission level, matching the button tapped")
    }

    @MainActor
    func testColumnFindReplaceUpdatesValueLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let deviceToken = try fetchDeviceTokenViaAPI()
        let tableName = "Find Replace Table \(unique)"
        let tableID = try seedStandaloneMetadataTableViaAPI(named: tableName, deviceToken: deviceToken)

        let columnJSON = try postJSON(
            "metadata-tables/\(tableID)/add_column_with_auto_reorder/",
            body: ["column_data": ["name": "organism", "type": "characteristics", "value": "human"]],
            deviceToken: deviceToken
        )
        guard let columnID = (columnJSON["column"] as? [String: Any])?["id"] as? Int else {
            XCTFail("Adding a column should return the created column")
            return
        }
        _ = try postJSON(
            "metadata-columns/\(columnID)/bulk_update_sample_values/",
            body: ["updates": [["sample_index": 2, "value": "mouse"]]],
            deviceToken: deviceToken
        )

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)
        tapToolbarButton("metadataTablesBrowserButton", label: "Metadata Tables", in: app, overflowIndex: 1)

        let searchField = app.textFields["metadataTablesBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(tableName)
        searchField.typeText("\n")

        let tableRow = app.buttons["metadataTableRow_\(tableName)"]
        XCTAssertTrue(tableRow.waitForExistence(timeout: 10), "The freshly seeded table should appear in the browser")
        tableRow.tap()

        tapSegment("List", within: "metadataTableViewModePicker", in: app)

        tapMenuItem("metadataTableColumnMenu_organism", item: "metadataTableColumnFindReplaceMenuItem_organism", in: app)

        let oldValueField = app.textFields["findReplaceOldValueField"]
        XCTAssertTrue(oldValueField.waitForExistence(timeout: 10))
        oldValueField.tap()
        oldValueField.typeText("human")

        let newValueField = app.textFields["findReplaceNewValueField"]
        newValueField.tap()
        newValueField.typeText("rat")

        app.buttons["applyFindReplaceButton"].tap()
        let replaceCompleteAlert = waitForAlertOrSheet(in: app, timeout: 10)
        XCTAssertTrue(replaceCompleteAlert.exists, "The replace should complete against a reachable backend")
        replaceCompleteAlert.buttons["OK"].tap()

        let updatedColumn = try getJSON("metadata-columns/\(columnID)/", deviceToken: deviceToken)
        XCTAssertEqual(updatedColumn["value"] as? String, "rat", "The column's default value should be updated by the real replace_value endpoint")
        let modifiers = updatedColumn["modifiers"] as? [[String: Any]]
        XCTAssertEqual(modifiers?.first?["value"] as? String, "mouse", "The unrelated mouse override for sample 2 should be preserved, not touched by the replacement")
    }

    @MainActor
    func testAsyncTaskCenterButtonShowsPendingCountLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let deviceToken = try fetchDeviceTokenViaAPI()
        let tableName = "Badge Count Table \(unique)"
        let tableID = try seedStandaloneMetadataTableViaAPI(named: tableName, deviceToken: deviceToken)
        _ = try postJSON(
            "metadata-tables/\(tableID)/add_column_with_auto_reorder/",
            body: ["column_data": ["name": "organism", "type": "characteristics", "value": "human"]],
            deviceToken: deviceToken
        )

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)
        tapToolbarButton("metadataTablesBrowserButton", label: "Metadata Tables", in: app, overflowIndex: 1)

        let searchField = app.textFields["metadataTablesBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(tableName)
        searchField.typeText("\n")

        let tableRow = app.buttons["metadataTableRow_\(tableName)"]
        XCTAssertTrue(tableRow.waitForExistence(timeout: 10), "The freshly seeded table should appear in the browser")
        tableRow.tap()

        let pendingCountLabel = app.staticTexts["pendingAsyncTaskCount"]
        XCTAssertTrue(pendingCountLabel.waitForExistence(timeout: 10))
        let baselineCount = readPendingAsyncTaskCount(pendingCountLabel)

        tapToolbarButton("exportMenu", label: "Export", in: app, window: "metadata-tables-browser", overflowIndex: 1, timeout: 10)
        let exportSDRFButton = firstExisting(app.buttons["exportSDRFButton"], app.menuItems["exportSDRFButton"])
        XCTAssertTrue(exportSDRFButton.waitForExistence(timeout: 5), "The Export submenu should be open")
        exportSDRFButton.tap()

        let exportQueuedAlert = waitForAlertOrSheet(in: app, timeout: 10)
        XCTAssertTrue(exportQueuedAlert.waitForExistence(timeout: 5), "The export should be accepted and queued against a reachable backend")
        exportQueuedAlert.buttons["OK"].tap()

        var updatedCount = baselineCount
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            updatedCount = readPendingAsyncTaskCount(pendingCountLabel)
            if updatedCount > baselineCount { break }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertGreaterThan(updatedCount, baselineCount, "The Async Tasks button should show an incremented pending count after queuing a real export, was \(baselineCount), now \(updatedCount)")
    }

    private func readPendingAsyncTaskCount(_ element: XCUIElement) -> Int {
        if let fromLabel = Int(element.label) { return fromLabel }
        if let valueString = element.value as? String, let fromValue = Int(valueString) { return fromValue }
        return 0
    }

    @MainActor
    func testRetryFailedAsyncTaskResubmitsLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let deviceToken = try fetchDeviceTokenViaAPI()
        let tableName = "Retry Fail Table \(unique)"
        let tableID = try seedStandaloneMetadataTableViaAPI(named: tableName, deviceToken: deviceToken)

        let columnJSON = try postJSON(
            "metadata-tables/\(tableID)/add_column_with_auto_reorder/",
            body: ["column_data": ["name": "badvalue", "type": "characteristics", "value": "placeholder"]],
            deviceToken: deviceToken
        )
        guard let columnID = (columnJSON["column"] as? [String: Any])?["id"] as? Int else {
            XCTFail("Adding a column should return the created column")
            return
        }
        try patchJSON("metadata-columns/\(columnID)/", body: ["value": "bad\u{000B}value\u{000C}here"], deviceToken: deviceToken)

        let beforeTasks = try getJSON("async-tasks/?metadata_table=\(tableID)&ordering=-created_at&limit=10", deviceToken: deviceToken)
        let beforeCount = beforeTasks["count"] as? Int ?? 0

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)
        tapToolbarButton("metadataTablesBrowserButton", label: "Metadata Tables", in: app, overflowIndex: 1)

        let searchField = app.textFields["metadataTablesBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(tableName)
        searchField.typeText("\n")

        let tableRow = app.buttons["metadataTableRow_\(tableName)"]
        XCTAssertTrue(tableRow.waitForExistence(timeout: 10), "The freshly seeded table should appear in the browser")
        tableRow.tap()

        let exportOverflowIndex = dynamicOverflowIndex(precedingIdentifiers: ["editMetadataTableButton"], in: app, window: "metadata-tables-browser")
        tapToolbarButton("exportMenu", label: "Export", in: app, window: "metadata-tables-browser", overflowIndex: exportOverflowIndex, timeout: 10)
        let exportExcelButton = firstExisting(app.buttons["exportExcelButton"], app.menuItems["exportExcelButton"])
        XCTAssertTrue(exportExcelButton.waitForExistence(timeout: 5))
        exportExcelButton.tap()

        let exportQueuedAlert2 = waitForAlertOrSheet(in: app, timeout: 10)
        XCTAssertTrue(exportQueuedAlert2.waitForExistence(timeout: 5), "The export should be accepted and queued against a reachable backend")
        exportQueuedAlert2.buttons["OK"].tap()

        var originalTaskID: String?
        let queuedDeadline = Date().addingTimeInterval(20)
        while Date() < queuedDeadline {
            let page = try getJSON("async-tasks/?metadata_table=\(tableID)&ordering=-created_at&limit=1", deviceToken: deviceToken)
            if let results = page["results"] as? [[String: Any]], let first = results.first, let id = first["id"] as? String {
                originalTaskID = id
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        guard let originalTaskID else {
            XCTFail("The queued export task should be discoverable via the real API")
            return
        }

        var reachedFailure = false
        let failureDeadline = Date().addingTimeInterval(90)
        while Date() < failureDeadline {
            let taskJSON = try getJSON("async-tasks/\(originalTaskID)/", deviceToken: deviceToken)
            if taskJSON["status"] as? String == "FAILURE" {
                reachedFailure = true
                break
            }
            Thread.sleep(forTimeInterval: 2)
        }
        XCTAssertTrue(reachedFailure, "The export task should genuinely fail server-side once a worker processes the illegal-character column value (openpyxl's IllegalCharacterError)")

        let asyncTaskCenterOverflowIndex = dynamicOverflowIndex(
            precedingIdentifiers: ["editMetadataTableButton", "exportMenu", "importMenu"],
            in: app, window: "metadata-tables-browser"
        )
        tapToolbarButton("openAsyncTaskCenterButton", label: "Async Tasks", in: app, window: "metadata-tables-browser", overflowIndex: asyncTaskCenterOverflowIndex, timeout: 10)

        let taskRow = waitForFirstExisting(
            timeout: 10,
            app.otherElements["asyncTaskRow_\(originalTaskID)"],
            app.staticTexts["asyncTaskRow_\(originalTaskID)"],
            app.cells["asyncTaskRow_\(originalTaskID)"]
        )
        XCTAssertTrue(taskRow.exists, "The real failed task this session submitted should appear in the task center")
        #if os(macOS)
        taskRow.rightClick()
        #else
        taskRow.press(forDuration: 1.0)
        #endif

        let retryMenuButton = firstExisting(
            app.buttons["retryAsyncTaskMenuButton_\(originalTaskID)"],
            app.menuItems["retryAsyncTaskMenuButton_\(originalTaskID)"]
        ).firstMatch
        XCTAssertTrue(retryMenuButton.waitForExistence(timeout: 5), "A Retry context-menu action should appear for a real failed task")
        retryMenuButton.tap()

        var newTaskAppeared = false
        let retryDeadline = Date().addingTimeInterval(20)
        while Date() < retryDeadline {
            let afterTasks = try getJSON("async-tasks/?metadata_table=\(tableID)&ordering=-created_at&limit=10", deviceToken: deviceToken)
            let afterCount = afterTasks["count"] as? Int ?? 0
            if afterCount > beforeCount + 1 {
                newTaskAppeared = true
                break
            }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertTrue(newTaskAppeared, "Tapping Retry should resubmit the same export request as a genuinely new async task")
    }

    @MainActor
    func testStepVariationRatingAndBookingAnnotationSyncImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

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
        var protocolRow = waitForMatch(titlePredicate, in: app.staticTexts, timeout: 10)
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
        var stepField = firstExisting(app.textViews["stepDescriptionField"], app.textFields["stepDescriptionField"])
        for _ in 0..<3 {
            if stepField.exists { break }
            addStepButton.tap()
            stepField = firstExisting(app.textViews["stepDescriptionField"], app.textFields["stepDescriptionField"])
        }
        XCTAssertTrue(stepField.exists)
        stepField.tap()
        stepField.typeText("Mix reagents")
        app.buttons["addStepSaveButton"].tap()
        XCTAssertTrue(waitForTextAppearing("Mix reagents", in: app, timeout: 10))

        let stepSyncErrorAlert = app.alerts["Couldn't start session"]
        if stepSyncErrorAlert.waitForExistence(timeout: 3) {
            XCTFail("Step creation showed a sync error alert: \(stepSyncErrorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
            stepSyncErrorAlert.buttons.firstMatch.tap()
        }

        let backToProtocolButton = app.navigationBars.buttons.element(boundBy: 0)
        if backToProtocolButton.waitForExistence(timeout: 5), backToProtocolButton.isHittable {
            backToProtocolButton.tap()
        }
        tapToolbarButton("rateProtocolButton", label: "Rate Protocol", in: app, timeout: 10)

        let complexitySlider = app.sliders["complexityRatingSlider"]
        XCTAssertTrue(complexitySlider.waitForExistence(timeout: 5))
        complexitySlider.adjust(toNormalizedSliderPosition: 0.7)
        app.sliders["durationRatingSlider"].adjust(toNormalizedSliderPosition: 0.3)
        app.buttons["saveRatingButton"].tap()
        XCTAssertFalse(app.alerts["Couldn't save rating"].waitForExistence(timeout: 3), "Rating a protocol against a reachable backend shouldn't show an error")

        tapToolbarButton("startProtocolSessionButton", label: "New Session", in: app, timeout: 10)
        let startSessionButton = app.buttons["startSessionButton"]
        XCTAssertTrue(startSessionButton.waitForExistence(timeout: 10))
        startSessionButton.tap()

        let addVariationButton = app.buttons["addVariationButton"].firstMatch
        XCTAssertTrue(addVariationButton.waitForExistence(timeout: 10), "\"Add Variation\" should appear once the session and step both have serverIDs")
        addVariationButton.tap()

        let variationDescField = app.textFields["variationDescriptionField"]
        XCTAssertTrue(variationDescField.waitForExistence(timeout: 5))
        variationDescField.tap()
        variationDescField.typeText("For larger samples, extend incubation")

        let variationDurationField = app.textFields["variationDurationField"]
        variationDurationField.tap()
        variationDurationField.typeText("20")

        app.buttons["saveVariationButton"].tap()
        if !waitForTextAppearing("Variation:", in: app, timeout: 5) {
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
        XCTAssertTrue(waitForTextAppearing("Variation:", in: app, timeout: 10), "The saved variation should appear inline under the step once synced")

        let addStepAnnotationButton = app.buttons["addStepAnnotationButton"].firstMatch
        XCTAssertTrue(addStepAnnotationButton.waitForExistence(timeout: 10))
        addStepAnnotationButton.tap()
        let bookingKindButton = app.buttons["annotationKind_booking"].firstMatch
        XCTAssertTrue(bookingKindButton.waitForExistence(timeout: 5), "\"Booking\" should be offered once the session and step both have serverIDs")
        bookingKindButton.tap()

        let instrumentSearchField = app.textFields["bookingAnnotationInstrumentSearchField"]
        XCTAssertTrue(instrumentSearchField.waitForExistence(timeout: 10))
        instrumentSearchField.tap()
        instrumentSearchField.typeText("Test Centrifuge")

        let instrumentRow = app.buttons["bookingAnnotationInstrumentRow_Test Centrifuge"]
        XCTAssertTrue(instrumentRow.waitForExistence(timeout: 10))
        instrumentRow.tap()

        let bookingDescField = app.textFields["bookingAnnotationDescriptionField"]
        scrollDownUntilVisible(bookingDescField, in: app)
        XCTAssertTrue(bookingDescField.waitForExistence(timeout: 5))
        bookingDescField.tap()
        bookingDescField.typeText("Spin test samples")

        app.buttons["saveBookingAnnotationButton"].tap()
        XCTAssertFalse(app.alerts["Couldn't book instrument"].waitForExistence(timeout: 5), "Booking an instrument against a reachable backend shouldn't show an error")
    }

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

        tapTab("Sessions", in: app, timeout: 10)
        let sessionRow = waitForMatchAcrossTypes(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", seed.sessionName, seed.sessionName),
            in: app, timeout: 10
        )
        XCTAssertTrue(sessionRow.exists, "The session seeded via the API should appear once synced")
        sessionRow.tap()

        let startButton = app.buttons["startStepTimerButton_\(seed.stepID)"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "The step's timer Start button should render since the step has a duration")
        startButton.tap()

        let stopButton = app.buttons["stopStepTimerButton_\(seed.stepID)"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Starting the timer locally should flip the button to Stop immediately, via the direct-context write")

        let timeKeeperID = try findTimeKeeperIDViaAPI(sessionID: seed.sessionID, stepID: seed.stepID, deviceToken: seed.deviceToken)
        try postJSON("time-keepers/\(timeKeeperID)/stop_timer/", body: [:], deviceToken: seed.deviceToken)

        let resumeButton = app.buttons["startStepTimerButton_\(seed.stepID)"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 10), "Stopping the timer from another \"device\" should push a live update back to this view with no local interaction")
    }

    @MainActor
    func testRunningStepTimerShowsPulsingIndicator() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let seed = try seedSessionWithTimedStepViaAPI(
            protocolTitle: "Live Pulse Test \(unique)",
            sessionName: "Live Pulse Session \(unique)"
        )

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Sessions", in: app, timeout: 10)
        let sessionRow = waitForMatchAcrossTypes(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", seed.sessionName, seed.sessionName),
            in: app, timeout: 10
        )
        XCTAssertTrue(sessionRow.exists, "The session seeded via the API should appear once synced")
        sessionRow.tap()

        XCTAssertFalse(app.otherElements["pulsingTimerIndicator"].exists, "No pulsing indicator should show before the timer is started")

        let startButton = app.buttons["startStepTimerButton_\(seed.stepID)"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "The step's timer Start button should render since the step has a duration")
        startButton.tap()

        XCTAssertTrue(app.otherElements["pulsingTimerIndicator"].firstMatch.waitForExistence(timeout: 10), "Starting the timer should show a pulsing indicator")
        XCTAssertGreaterThanOrEqual(
            app.otherElements.matching(identifier: "pulsingTimerIndicator").count, 2,
            "A running timer should pulse both on the section header and on the step itself"
        )

        let stopButton = app.buttons["stopStepTimerButton_\(seed.stepID)"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10))
        stopButton.tap()

        XCTAssertFalse(app.otherElements["pulsingTimerIndicator"].waitForExistence(timeout: 5), "Stopping the timer should remove the pulsing indicator")

        let resumeButton = app.buttons["startStepTimerButton_\(seed.stepID)"]
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 10))
        resumeButton.tap()
        XCTAssertTrue(app.otherElements["pulsingTimerIndicator"].firstMatch.waitForExistence(timeout: 10), "Resuming the timer should show the pulsing indicator again")

        let timeKeeperID = try findTimeKeeperIDViaAPI(sessionID: seed.sessionID, stepID: seed.stepID, deviceToken: seed.deviceToken)
        try postJSON("time-keepers/\(timeKeeperID)/stop_timer/", body: [:], deviceToken: seed.deviceToken)

        XCTAssertFalse(app.otherElements["pulsingTimerIndicator"].waitForExistence(timeout: 10), "Stopping the timer from another \"device\" should push a live update that removes the pulsing indicator, with no local interaction")
    }

    @MainActor
    func testSamplePoolCreateSyncImmediately() throws {
        let templateName = "Live Pool Test Template \(Int(Date().timeIntervalSince1970))"
        try createBlankTemplateViaAPI(named: templateName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 10)
        let newJobOverflowIndex = dynamicOverflowIndex(precedingIdentifiers: ["projectsLink", "manageMetadataTableTemplatesButton", "columnTemplatesToolbarButton", "metadataTablesBrowserButton", "labGroupsButton"], in: app)
        tapToolbarButton("newJobButton", label: "New Job", in: app, overflowIndex: newJobOverflowIndex, timeout: 10)

        let jobName = "Sample Pool Test \(Int(Date().timeIntervalSince1970))"
        let jobNameField = app.textFields["newJobNameField"]
        XCTAssertTrue(jobNameField.waitForExistence(timeout: 5))
        jobNameField.tap()
        jobNameField.typeText(jobName)
        tapCreateJobButtonReliably(in: app)
        XCTAssertTrue(waitForElementDestroyed(identifier: "newJobNameField", in: app, timeout: 10), "Tapping Create should trigger the async create and dismiss the New Job sheet")

        findAndTapJobRow(named: jobName, in: app)

        let labGroupSearchFieldForPool = app.textFields["jobLabGroupSearchField"]
        XCTAssertTrue(labGroupSearchFieldForPool.waitForExistence(timeout: 10))
        labGroupSearchFieldForPool.tap()
        labGroupSearchFieldForPool.typeText("Test Lab Group")
        app.buttons["jobLabGroupRow_Test Lab Group"].tap()

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 10), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButton.tap()
        waitForSignInSyncToFinish(in: app)

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        let templateSearchFieldForPool = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForPool.waitForExistence(timeout: 10))
        templateSearchFieldForPool.tap()
        templateSearchFieldForPool.typeText(templateName)

        let templateRow = app.buttons["metadataTemplateRow_\(templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10), "The template created via the API should appear once synced and filtered by search")
        templateRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("5")

        app.buttons["createMetadataTableButton"].tap()

        let newPoolButton = app.buttons["newSamplePoolButton"]
        scrollDownUntilVisible(newPoolButton, in: app)
        XCTAssertTrue(newPoolButton.waitForExistence(timeout: 10), "The Sample Pools section should appear once the metadata table syncs")
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

        XCTAssertTrue(waitForTextAppearing("Pool A", in: app, timeout: 10), "The newly-created sample pool should appear once synced")
    }

    @MainActor
    func testInstrumentAndStoredReagentMetadataAddAndEditFieldSyncsLive() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let templateName = "salinity"
        let columnName = "characteristics[salinity]"

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Inventory", in: app, timeout: 10)
        tapSegment("Instruments", in: app, timeout: 10)

        tapToolbarButton("newInstrumentButton", label: "New Instrument", in: app, timeout: 10)
        let instrumentName = "Live Metadata Instrument \(timestamp)"
        let instrumentNameField = app.textFields["instrumentNameField"]
        XCTAssertTrue(instrumentNameField.waitForExistence(timeout: 5))
        instrumentNameField.tap()
        instrumentNameField.typeText(instrumentName)
        app.buttons["saveInstrumentButton"].tap()

        let instrumentSearchField = app.textFields["instrumentSearchField"]
        XCTAssertTrue(instrumentSearchField.waitForExistence(timeout: 10))
        instrumentSearchField.tap()
        instrumentSearchField.typeText(instrumentName)

        let instrumentRow = waitForMatchAcrossTypes(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", instrumentName, instrumentName), in: app, timeout: 10)
        XCTAssertTrue(instrumentRow.exists, "The newly-created instrument should appear once synced")
        instrumentRow.tap()

        let addInstrumentMetadataButton = app.buttons["addMetadataFieldButton"]
        XCTAssertTrue(addInstrumentMetadataButton.waitForExistence(timeout: 10), "The Metadata section should appear once the instrument's auto-created metadata table syncs")
        scrollDownUntilVisible(addInstrumentMetadataButton, in: app)
        addInstrumentMetadataButton.tap()

        let templateSearchField = app.textFields["addColumnSearchField"]
        XCTAssertTrue(templateSearchField.waitForExistence(timeout: 5))
        templateSearchField.tap()
        templateSearchField.typeText(templateName)

        let templateRow = app.buttons["addColumnGroupRow_\(columnName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10), "The already-seeded \"salinity\" column template should appear in the search results")
        templateRow.tap()

        let instrumentFieldRow = app.buttons["metadataColumnRow_\(columnName)"]
        XCTAssertTrue(instrumentFieldRow.waitForExistence(timeout: 10), "The newly-added metadata field should appear once synced")
        scrollDownUntilVisible(instrumentFieldRow, in: app)
        instrumentFieldRow.tap()

        let instrumentValueField = firstExisting(app.textFields["metadataValueField"], app.textViews["metadataValueField"])
        XCTAssertTrue(instrumentValueField.waitForExistence(timeout: 5))
        instrumentValueField.tap()
        instrumentValueField.typeText("42.5")
        tapToolbarButton("saveMetadataValueButton", label: "Save", in: app, window: "metadata-value-editor", overflowIndex: 1)

        let instrumentSaveErrorAlert = waitForAlertOrSheet(in: app, timeout: 3)
        if instrumentSaveErrorAlert.exists {
            XCTFail("Saving the instrument metadata value shouldn't show an error: \(instrumentSaveErrorAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
        }

        let editorWindow = app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", "metadata-value-editor")).firstMatch
        let editorDeadline = Date().addingTimeInterval(10)
        while editorWindow.exists, Date() < editorDeadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertFalse(editorWindow.exists, "The Edit Value window should close on its own once the save genuinely completes")

        scrollDownUntilVisible(instrumentFieldRow, in: app, window: "main-AppWindow")
        XCTAssertTrue(instrumentFieldRow.waitForExistence(timeout: 10), "The edited metadata field row should still be listed once synced")
        XCTAssertTrue(waitForTextAppearing("42.5", in: app, timeout: 10), "The edited metadata value should appear once synced")

        tapSegment("Storage", in: app)

        tapMenuItem("storageAddMenu", item: "New Location", in: app)
        let locationName = "Live Metadata Shelf \(timestamp)"
        let locationNameField = app.textFields["storageLocationNameField"]
        XCTAssertTrue(locationNameField.waitForExistence(timeout: 5))
        locationNameField.tap()
        locationNameField.typeText(locationName)
        app.buttons["saveStorageLocationButton"].tap()

        let locationSearchField = app.textFields["storageLocationSearchField"]
        XCTAssertTrue(locationSearchField.waitForExistence(timeout: 10))
        locationSearchField.tap()
        locationSearchField.typeText(locationName)

        let locationRow = app.buttons["storageLocationRow_\(locationName)"]
        XCTAssertTrue(locationRow.waitForExistence(timeout: 10), "The newly-created location should appear once synced")
        locationRow.tap()

        tapMenuItem("storageAddMenu", item: "Add Reagent", in: app)
        let reagentName = "Live Metadata Reagent \(timestamp)"
        let reagentNameField = app.textFields["newStoredReagentNameField"]
        XCTAssertTrue(reagentNameField.waitForExistence(timeout: 5))
        reagentNameField.tap()
        reagentNameField.typeText(reagentName)
        selectPickerOption("newStoredReagentUnitPicker", option: "g", in: app, menuItemCount: 17, optionIndex: 8)
        let reagentQuantityField = app.textFields["newStoredReagentQuantityField"]
        reagentQuantityField.tap()
        reagentQuantityField.typeText("100")
        app.buttons["saveStoredReagentButton"].tap()

        let reagentSearchField = app.textFields["reagentSearchField"]
        XCTAssertTrue(reagentSearchField.waitForExistence(timeout: 10))
        reagentSearchField.tap()
        reagentSearchField.typeText(reagentName)

        let reagentRow = app.buttons["storedReagentRow_\(reagentName)"]
        XCTAssertTrue(reagentRow.waitForExistence(timeout: 10), "The newly-added reagent should appear once synced")
        reagentRow.tap()

        let addReagentMetadataButton = app.buttons["addMetadataFieldButton"]
        XCTAssertTrue(addReagentMetadataButton.waitForExistence(timeout: 10), "The Metadata section should appear once the reagent's auto-created metadata table syncs")
        addReagentMetadataButton.tap()

        let reagentTemplateSearchField = app.textFields["addColumnSearchField"]
        XCTAssertTrue(reagentTemplateSearchField.waitForExistence(timeout: 5))
        reagentTemplateSearchField.tap()
        reagentTemplateSearchField.typeText(templateName)

        let reagentTemplateRow = app.buttons["addColumnGroupRow_\(columnName)"]
        XCTAssertTrue(reagentTemplateRow.waitForExistence(timeout: 10), "The already-seeded \"salinity\" column template should appear in the search results")

        let reagentFieldRow = app.buttons["metadataColumnRow_\(columnName)"]
        for _ in 0..<3 {
            guard reagentTemplateRow.exists else { break }
            reagentTemplateRow.tap()
            if reagentFieldRow.waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(reagentFieldRow.waitForExistence(timeout: 10), "The newly-added metadata field should appear on the stored reagent once synced")
    }

    @MainActor
    func testMetadataTemplatePickerTiersAndTableEditor() throws {
        let seed = try seedTemplatePickerTierData()

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)

        findAndTapJobRow(named: seed.jobName, in: app)

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 10))
        createFromTemplateButton.tap()
        waitForSignInSyncToFinish(in: app)

        let templateSearchFieldForTiers = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForTiers.waitForExistence(timeout: 10))

        selectPickerOption("templateCategoryFilterPicker", option: "Personal", in: app, menuItemCount: 4, optionIndex: 1)
        templateSearchFieldForTiers.tap()
        templateSearchFieldForTiers.typeText(seed.personalTemplateName)
        let personalRow = app.buttons["metadataTemplateRow_\(seed.personalTemplateName)"]
        XCTAssertTrue(personalRow.waitForExistence(timeout: 10), "The personal template should be listed under the Personal category")

        replaceText(in: templateSearchFieldForTiers, with: seed.jobGroupTemplateName, in: app)
        selectPickerOption("templateCategoryFilterPicker", option: "Job's Lab Group", in: app, menuItemCount: 4, optionIndex: 2)
        XCTAssertTrue(app.buttons["metadataTemplateRow_\(seed.jobGroupTemplateName)"].waitForExistence(timeout: 10), "The job's own lab-group template should be listed under Job's Lab Group")

        replaceText(in: templateSearchFieldForTiers, with: seed.otherGroupTemplateName, in: app)
        selectPickerOption("templateCategoryFilterPicker", option: "Shared With Me", in: app, menuItemCount: 4, optionIndex: 3)
        XCTAssertTrue(app.buttons["metadataTemplateRow_\(seed.otherGroupTemplateName)"].waitForExistence(timeout: 10), "The other lab group's template should be listed under Shared With Me")

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        replaceText(in: templateSearchFieldForTiers, with: seed.personalTemplateName, in: app)
        XCTAssertTrue(personalRow.waitForExistence(timeout: 10))
        personalRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("5")

        app.buttons["createMetadataTableButton"].tap()

        let firstColumnRow = app.buttons["metadataColumnRow_\(seed.firstColumnName)"]
        XCTAssertTrue(firstColumnRow.waitForExistence(timeout: 10), "The metadata table's first column should render")

        let firstGridCell = app.buttons["metadataCell_\(seed.firstColumnName)_1"]
        scrollDownUntilVisible(firstGridCell, in: app)
        XCTAssertTrue(firstGridCell.waitForExistence(timeout: 10), "The per-sample grid should render a cell for sample 1")

    }

    @MainActor
    func testMetadataTablesBrowserOpensAsRealWindowOnRegularWidth() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 10)

        #if os(macOS)
        let windowCountBefore = app.windows.count
        #endif

        tapToolbarButton("metadataTablesBrowserButton", label: "Metadata Tables", in: app, overflowIndex: 1, timeout: 10)

        let searchField = app.textFields["metadataTablesBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "The Metadata Tables browser's own content should be reachable")

        #if os(macOS)
        XCTAssertGreaterThan(app.windows.count, windowCountBefore, "On macOS, Metadata Tables should open in a genuinely separate window, not a sheet")
        #endif
    }

    @MainActor
    func testWorkOfflineToggleQueuesThenSyncsBackOnReconnect() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Protocols", in: app, timeout: 10)
        openConnectionSettings(in: app)

        tapWorkOfflineToggle(in: app)

        closeSettings(in: app)

        tapTab("Protocols", in: app, timeout: 10)
        tapToolbarButton("newProtocolButton", label: "New Protocol", in: app)

        let protocolTitle = "Work Offline Test Protocol \(Date().timeIntervalSince1970)"
        let titleField = app.textFields["newProtocolTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText(protocolTitle)
        app.buttons["createProtocolButton"].tap()

        let matchingRows = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", protocolTitle, protocolTitle))
        XCTAssertTrue(matchingRows.firstMatch.waitForExistence(timeout: 10), "The protocol should still be created locally while Work Offline is on")

        XCTAssertTrue(
            waitForTextAppearing("Pending sync", in: app, timeout: 10),
            "A protocol created while Work Offline is on should queue instead of syncing immediately, exactly like a genuine transport failure would"
        )

        openConnectionSettings(in: app)

        tapWorkOfflineToggle(in: app)

        closeSettings(in: app)

        tapTab("Protocols", in: app, timeout: 10)

        XCTAssertTrue(
            waitForTextDisappearing("Pending sync", in: app, timeout: 10),
            "Turning Work Offline back off should automatically replay the outbox and sync the queued protocol"
        )
    }

    @MainActor
    func testEditCaptionsOnAudioAnnotationSyncsLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let seed = try seedStepAudioAnnotationWithTranscriptionViaAPI(
            protocolTitle: "Caption Editor Test Protocol \(unique)",
            sessionName: "Caption Editor Test Session \(unique)"
        )

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app, baseURL: "https://127.0.0.1:8080/api/v1/")

        tapTab("Sessions", in: app, timeout: 10)
        let sessionRow = waitForMatchAcrossTypes(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", seed.sessionName, seed.sessionName),
            in: app, timeout: 10
        )
        XCTAssertTrue(sessionRow.exists, "The session seeded via the API should appear once synced")
        sessionRow.tap()

        let editCaptionsButton = app.buttons["editCaptionsButton"].firstMatch
        scrollDownUntilVisible(editCaptionsButton, in: app)
        XCTAssertTrue(editCaptionsButton.waitForExistence(timeout: 10), "The seeded audio annotation already has a transcription, so Edit Captions should be reachable")
        editCaptionsButton.tap()

        let firstCue = app.textViews["captionCueTextField_0"].firstMatch
        let firstCueField = firstExisting(firstCue, app.textFields["captionCueTextField_0"])
        XCTAssertTrue(firstCueField.waitForExistence(timeout: 10), "The seeded WebVTT should parse into at least one editable cue")
        XCTAssertTrue((firstCueField.value as? String)?.contains("This is a caption") ?? false, "The first cue's real seeded text should display")

        let secondCue = firstExisting(app.textViews["captionCueTextField_1"], app.textFields["captionCueTextField_1"])
        XCTAssertTrue(secondCue.waitForExistence(timeout: 10), "The seeded WebVTT has two cues")
        replaceText(in: secondCue, with: "editor test recording, hand-edited.", in: app)

        let saveButton = app.buttons["saveCaptionsButton"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(waitForTextDisappearing("Edit Captions", in: app, timeout: 10) || !app.buttons["saveCaptionsButton"].exists, "Saving should dismiss the caption editor")

        let readback = try getJSON("step-annotations/\(seed.stepAnnotationID)/", deviceToken: seed.deviceToken)
        let transcription = readback["transcription"] as? String ?? ""
        XCTAssertTrue(transcription.contains("This is a caption"), "The unedited first cue should round-trip unchanged")
        XCTAssertTrue(transcription.contains("hand-edited"), "The hand-edited second cue should have persisted through the real PATCH round-trip")
    }

    @MainActor
    func testLabGroupCreateAndInviteSyncsLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let groupName = "Live Lab Group Test \(unique)"

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 10)
        tapToolbarButton("labGroupsButton", label: "Lab Groups", in: app, overflowIndex: 2, timeout: 10)

        let newLabGroupButton = app.buttons["newLabGroupButton"].firstMatch
        XCTAssertTrue(newLabGroupButton.waitForExistence(timeout: 10))
        newLabGroupButton.tap()

        let nameField = app.textFields["labGroupNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        replaceText(in: nameField, with: groupName, in: app)

        let saveButton = app.buttons["saveLabGroupButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let groupRow = waitForMatchAcrossTypes(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", groupName, groupName),
            in: app, timeout: 10
        )
        XCTAssertTrue(groupRow.exists, "The newly-created lab group should appear in the list once synced")
        groupRow.tap()

        let inviteButton = app.buttons["inviteMemberButton"]
        XCTAssertTrue(inviteButton.waitForExistence(timeout: 10), "The creator should be able to invite, since invite defaults to true for a new group")
        inviteButton.tap()

        let emailField = app.textFields["inviteEmailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 5))
        emailField.tap()
        let inviteEmail = "livetest-\(unique)@example.com"
        replaceText(in: emailField, with: inviteEmail, in: app)

        let sendInviteButton = app.buttons["sendInviteButton"]
        XCTAssertTrue(sendInviteButton.waitForExistence(timeout: 5))
        sendInviteButton.tap()

        XCTAssertTrue(waitForTextDisappearing("Invite Member", in: app, timeout: 10) || !app.buttons["sendInviteButton"].exists, "Sending the invite should dismiss the sheet")

        let deviceToken = try fetchDeviceTokenViaAPI()
        let groups = try getJSON("lab-groups/my_groups/?limit=500", deviceToken: deviceToken)
        let results = groups["results"] as? [[String: Any]] ?? []
        XCTAssertTrue(results.contains { ($0["name"] as? String) == groupName }, "The lab group created via the real UI should exist server-side")
    }

    @MainActor
    func testProtocolAccessManagementGrantsEditorAccessLive() throws {
        let protocolTitle = "Live Access Test \(Date().timeIntervalSince1970)"
        let deviceTokenForSeed = try fetchDeviceTokenViaAPI()
        _ = try postJSON("protocols/", body: ["protocol_title": protocolTitle, "enabled": false], deviceToken: deviceTokenForSeed)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Protocols", in: app, timeout: 10)
        let protocolSearchField = app.textFields["protocolSearchField"]
        XCTAssertTrue(protocolSearchField.waitForExistence(timeout: 10))
        protocolSearchField.tap()
        protocolSearchField.typeText(protocolTitle)

        let protocolRow = elementContaining(protocolTitle, in: app)
        XCTAssertTrue(protocolRow.waitForExistence(timeout: 10), "The API-created protocol should appear once synced and filtered by search")
        protocolRow.tap()

        let manageAccessButton = app.buttons["manageProtocolAccessButton"]
        XCTAssertTrue(manageAccessButton.waitForExistence(timeout: 10), "Manage Access should be immediately available since the protocol's ownership was already established server-side before the app ever pulled it")
        let beforeTapAttachment = XCTAttachment(screenshot: app.screenshot())
        beforeTapAttachment.name = "before-manage-access-tap"
        beforeTapAttachment.lifetime = .keepAlways
        add(beforeTapAttachment)
        manageAccessButton.tap()
        let afterTapAttachment = XCTAttachment(screenshot: app.screenshot())
        afterTapAttachment.name = "after-manage-access-tap"
        afterTapAttachment.lifetime = .keepAlways
        add(afterTapAttachment)

        let searchField = app.textFields["accessSearchUsersField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Manage Access should open the access management screen")
        searchField.tap()
        searchField.typeText("importtestuser")

        let addEditorButton = app.buttons["addAsEditorButton_importtestuser"]
        XCTAssertTrue(addEditorButton.waitForExistence(timeout: 10), "Searching should find the real importtestuser account")
        addEditorButton.tap()

        XCTAssertTrue(app.staticTexts["editorRow_importtestuser"].waitForExistence(timeout: 10), "importtestuser should now appear in the Editors list")

        let encodedTitle = protocolTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? protocolTitle
        let protocolsJSON = try getJSON("protocols/?search=\(encodedTitle)", deviceToken: deviceTokenForSeed)
        let matches = protocolsJSON["results"] as? [[String: Any]] ?? []
        guard let match = matches.first(where: { ($0["protocol_title"] as? String) == protocolTitle }) else {
            XCTFail("Couldn't find the created protocol via the real API to verify its editors array")
            return
        }
        let editors = match["editors"] as? [Int] ?? []
        let editorsUsernames = match["editors_usernames"] as? [String] ?? []
        XCTAssertTrue(editorsUsernames.contains("importtestuser"), "The real server-side editors array should include importtestuser after granting access through the UI")
        XCTAssertFalse(editors.isEmpty)
    }

    @MainActor
    func testSessionAccessManagementGrantsEditorAccessLive() throws {
        let sessionName = "Live Session Access Test \(Date().timeIntervalSince1970)"
        let deviceTokenForSeed = try fetchDeviceTokenViaAPI()
        _ = try postJSON("sessions/", body: ["name": sessionName, "enabled": false, "protocols": []], deviceToken: deviceTokenForSeed)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Sessions", in: app, timeout: 10)
        let sessionRow = elementContaining(sessionName, in: app)
        XCTAssertTrue(sessionRow.waitForExistence(timeout: 10), "The API-created session should appear once synced")
        sessionRow.tap()

        let beforeTapAttachment = XCTAttachment(screenshot: app.screenshot())
        beforeTapAttachment.name = "before-session-manage-access-tap"
        beforeTapAttachment.lifetime = .keepAlways
        add(beforeTapAttachment)
        tapToolbarButton("manageSessionAccessButton", label: "Manage Access", in: app, timeout: 10)
        let afterTapAttachment = XCTAttachment(screenshot: app.screenshot())
        afterTapAttachment.name = "after-session-manage-access-tap"
        afterTapAttachment.lifetime = .keepAlways
        add(afterTapAttachment)

        let searchField = app.textFields["accessSearchUsersField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10), "Manage Access should open the access management screen")
        searchField.tap()
        searchField.typeText("importtestuser")

        let addEditorButton = app.buttons["addAsEditorButton_importtestuser"]
        XCTAssertTrue(addEditorButton.waitForExistence(timeout: 10), "Searching should find the real importtestuser account")
        addEditorButton.tap()

        XCTAssertTrue(app.staticTexts["editorRow_importtestuser"].waitForExistence(timeout: 10), "importtestuser should now appear in the Editors list")

        let encodedName = sessionName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sessionName
        let sessionsJSON = try getJSON("sessions/?search=\(encodedName)", deviceToken: deviceTokenForSeed)
        let matches = sessionsJSON["results"] as? [[String: Any]] ?? []
        guard let match = matches.first(where: { ($0["name"] as? String) == sessionName }) else {
            XCTFail("Couldn't find the created session via the real API to verify its editors array")
            return
        }
        let editors = match["editors"] as? [Int] ?? []
        let editorsUsernames = match["editors_usernames"] as? [String] ?? []
        XCTAssertTrue(editorsUsernames.contains("importtestuser"), "The real server-side editors array should include importtestuser after granting access through the UI")
        XCTAssertFalse(editors.isEmpty)
    }

    @MainActor
    func testSharedWithMeShowsAccessRoleBadgeForProtocolAndSession() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let deviceToken = try fetchDeviceTokenViaAPI()

        let usersJSON = try getJSON("users/?search=importtestuser", deviceToken: deviceToken)
        guard let userResults = usersJSON["results"] as? [[String: Any]],
              let importTestUserID = userResults.first(where: { ($0["username"] as? String) == "importtestuser" })?["id"] as? Int else {
            XCTFail("Couldn't find importtestuser's real id via the API")
            return
        }

        let protocolTitle = "Shared Badge Protocol \(unique)"
        let protocolJSON = try postJSON("protocols/", body: ["protocol_title": protocolTitle, "enabled": false], deviceToken: deviceToken)
        guard let protocolID = protocolJSON["id"] as? Int else {
            XCTFail("Creating a protocol should return an id")
            return
        }
        try patchJSON("protocols/\(protocolID)/", body: ["editors": [importTestUserID]], deviceToken: deviceToken)

        let sessionName = "Shared Badge Session \(unique)"
        let sessionJSON = try postJSON("sessions/", body: ["name": sessionName, "enabled": false, "protocols": []], deviceToken: deviceToken)
        guard let sessionID = sessionJSON["id"] as? Int else {
            XCTFail("Creating a session should return an id")
            return
        }
        try patchJSON("sessions/\(sessionID)/", body: ["viewers": [importTestUserID]], deviceToken: deviceToken)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app, username: "importtestuser", password: "importtestuser123")

        tapTab("Protocols", in: app, timeout: 10)
        tapToolbarButton("protocolFilterMenu", label: "Filter", in: app, timeout: 10)
        #if os(macOS)
        let protocolSharedItem = openMenuItem(itemCount: 5, at: 2, in: app)
        #else
        let protocolSharedItem = firstExisting(app.buttons["Shared With Me"], app.menuItems["Shared With Me"])
        #endif
        XCTAssertTrue(protocolSharedItem.waitForExistence(timeout: 5))
        protocolSharedItem.tap()

        let anyAlert = app.alerts.firstMatch
        if anyAlert.waitForExistence(timeout: 3) {
            XCTFail("Unexpected alert after applying the filter: \(anyAlert.staticTexts.allElementsBoundByIndex.map(\.label))")
        }

        XCTAssertTrue(elementContaining(protocolTitle, in: app).waitForExistence(timeout: 10), "The protocol shared as editor should appear under Shared With Me")
        XCTAssertTrue(
            firstExisting(app.staticTexts["protocolAccessRoleBadge_\(protocolTitle)"], elementContaining("Editor", in: app)).waitForExistence(timeout: 5),
            "The protocol row should show an Editor access-role badge"
        )

        tapTab("Sessions", in: app, timeout: 10)
        tapToolbarButton("sessionFilterMenu", label: "Filter", in: app, timeout: 10)
        #if os(macOS)
        let sessionSharedItem = openMenuItem(itemCount: 3, at: 2, in: app)
        #else
        let sessionSharedItem = firstExisting(app.buttons["Shared With Me"], app.menuItems["Shared With Me"])
        #endif
        XCTAssertTrue(sessionSharedItem.waitForExistence(timeout: 5))
        sessionSharedItem.tap()

        XCTAssertTrue(elementContaining(sessionName, in: app).waitForExistence(timeout: 10), "The session shared as viewer should appear under Shared With Me")
        XCTAssertTrue(
            firstExisting(app.staticTexts["sessionAccessRoleBadge_\(sessionName)"], elementContaining("Viewer", in: app)).waitForExistence(timeout: 5),
            "The session row should show a Viewer access-role badge"
        )
    }

    #if !os(macOS)
    @MainActor
    func testSettingsAndAccountReachableFromNonProtocolsTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Sessions", in: app, timeout: 10)

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Settings should be reachable from the Sessions tab, not just Protocols")
        settingsButton.tap()
        XCTAssertTrue(waitForTextAppearing("Appearance", in: app, timeout: 10) || waitForTextAppearing("Connection", in: app, timeout: 10), "Settings should open correctly from a non-Protocols tab")
        let doneButton = app.buttons["Done"].firstMatch
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        }

        tapTab("Sessions", in: app, timeout: 10)
        let accountMenu = app.buttons["accountMenu"]
        XCTAssertTrue(accountMenu.waitForExistence(timeout: 10), "Account should be reachable from the Sessions tab, not just Protocols")
        let switchInstanceItem = openAccountMenuAndFindSwitchInstance(in: app)
        XCTAssertTrue(switchInstanceItem.exists, "The Account menu should list Switch Instance and Sign Out")
    }

    @MainActor
    func testAccountProfileEditSyncsLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let lastName = "TestEdit\(unique)"

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let accountRow = elementContaining("Account", in: app)
        XCTAssertTrue(accountRow.waitForExistence(timeout: 10))
        accountRow.tap()

        let editButton = app.buttons["editAccountProfileButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 10), "Account should show the signed-in user's profile with an edit entry point")
        editButton.tap()

        let lastNameField = app.textFields["accountLastNameField"]
        XCTAssertTrue(lastNameField.waitForExistence(timeout: 5))
        replaceText(in: lastNameField, with: lastName, in: app)

        let saveButton = app.buttons["saveAccountProfileButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let editButtonReturned = app.buttons["editAccountProfileButton"]
        XCTAssertTrue(editButtonReturned.waitForExistence(timeout: 10), "Saving should return to the read-only profile view")

        let deviceToken = try fetchDeviceTokenViaAPI()
        let profile = try getJSON("users/1/", deviceToken: deviceToken)
        XCTAssertEqual(profile["last_name"] as? String, lastName, "The profile edit made through the real UI should persist server-side")

        try patchJSON("users/1/", body: ["last_name": ""], deviceToken: deviceToken)
    }

    @MainActor
    func testChangePasswordSurfacesWrongCurrentPasswordError() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let accountRow = elementContaining("Account", in: app)
        XCTAssertTrue(accountRow.waitForExistence(timeout: 10))
        accountRow.tap()

        let currentPasswordField = app.secureTextFields["accountCurrentPasswordField"]
        XCTAssertTrue(currentPasswordField.waitForExistence(timeout: 10))
        currentPasswordField.tap()
        Thread.sleep(forTimeInterval: 0.3)
        currentPasswordField.typeText("definitely-the-wrong-password\n")
        Thread.sleep(forTimeInterval: 0.3)

        let newPasswordField = app.secureTextFields["accountNewPasswordField"]
        newPasswordField.tap()
        Thread.sleep(forTimeInterval: 0.3)
        newPasswordField.typeText("SomeNewPassword123\n")
        Thread.sleep(forTimeInterval: 0.3)

        let confirmPasswordField = app.secureTextFields["accountConfirmPasswordField"]
        confirmPasswordField.tap()
        Thread.sleep(forTimeInterval: 0.3)
        confirmPasswordField.typeText("SomeNewPassword123")

        app.buttons["changePasswordButton"].tap()

        XCTAssertTrue(waitForTextAppearing("current_password", in: app, timeout: 10), "A wrong current password should surface the real server-side validation error")
        XCTAssertFalse(app.staticTexts["Password changed successfully."].exists, "The change must not have gone through")

        XCTAssertNoThrow(try fetchDeviceTokenViaAPI(), "The real password must still work afterward — this test must never actually change it")
    }

    @MainActor
    func testKnownInstanceSwitchSignsBackInWithoutCredentials() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Protocols", in: app, timeout: 10)
        let accountMenu = app.buttons["accountMenu"]
        XCTAssertTrue(accountMenu.waitForExistence(timeout: 10))
        let switchInstanceItem = openAccountMenuAndFindSwitchInstance(in: app)
        XCTAssertTrue(switchInstanceItem.exists)
        switchInstanceItem.tap()

        let knownInstanceRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "knownInstanceRow_")).firstMatch
        XCTAssertTrue(knownInstanceRow.waitForExistence(timeout: 10), "Leaving an active instance should list it under Known Instances on the login screen")
        knownInstanceRow.tap()

        XCTAssertTrue(
            firstExisting(app.buttons["accountMenu"], app.buttons["settingsButton"]).waitForExistence(timeout: 10),
            "Tapping a known instance should sign back in directly using its stored credentials, with nothing retyped"
        )
    }

    @MainActor
    func testDeviceTokenCreateAndDeleteSyncsLive() throws {
        let unique = Int(Date().timeIntervalSince1970)
        let label = "Live Token Test \(unique)"

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        let settingsButton = app.buttons["settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let tokensRow = elementContaining("API Tokens", in: app)
        XCTAssertTrue(tokensRow.waitForExistence(timeout: 10))
        tokensRow.tap()

        let newTokenButton = app.buttons["newDeviceTokenButton"]
        XCTAssertTrue(newTokenButton.waitForExistence(timeout: 10))
        newTokenButton.tap()

        let labelField = app.textFields["newDeviceTokenLabelField"]
        XCTAssertTrue(labelField.waitForExistence(timeout: 5))
        labelField.tap()
        replaceText(in: labelField, with: label, in: app)

        let createButton = app.buttons["createDeviceTokenButton"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        XCTAssertTrue(waitForTextAppearing("TOKEN CREATED", in: app, timeout: 10), "Creating a token through the real UI should show the one-time reveal")

        let doneButton = app.buttons["Done"].firstMatch
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()

        let createdRow = elementContaining(label, in: app)
        XCTAssertTrue(createdRow.waitForExistence(timeout: 10), "The newly-created token should appear in the list once synced")

        let deviceToken = try fetchDeviceTokenViaAPI()
        let listing = try getJSON("device-tokens/?limit=1000", deviceToken: deviceToken)
        let results = listing["results"] as? [[String: Any]] ?? []
        guard let created = results.first(where: { ($0["label"] as? String) == label }) else {
            XCTFail("The token created via the real UI should exist server-side")
            return
        }
        let createdID = created["id"] as! Int
        try deleteResource("device-tokens/\(createdID)/", deviceToken: deviceToken)
    }
    #endif

    @MainActor
    func testAsyncTaskExportSDRFQueuesAndAppearsInTaskCenter() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let jobName = "Async Task Job \(timestamp)"
        let seed = try seedJobWithMetadataTableViaAPI(jobName: jobName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)
        findAndTapJobRow(named: jobName, in: app)

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 10))
        createFromTemplateButton.tap()
        waitForSignInSyncToFinish(in: app)

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        let templateSearchField = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchField.waitForExistence(timeout: 10))
        templateSearchField.tap()
        templateSearchField.typeText(seed.templateName)

        let templateRow = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10))
        templateRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("\(seed.sampleCount)")
        app.buttons["createMetadataTableButton"].tap()

        let openFullTableViewButton = app.buttons["openFullMetadataTableViewButton"]
        XCTAssertTrue(openFullTableViewButton.waitForExistence(timeout: 10))
        scrollDownUntilVisible(openFullTableViewButton, in: app)
        openFullTableViewButton.tap()

        tapToolbarButton("exportMenu", label: "Export", in: app, window: "metadata-table-detail", timeout: 10)

        let exportSDRFButton = firstExisting(app.buttons["exportSDRFButton"], app.menuItems["exportSDRFButton"])
        XCTAssertTrue(exportSDRFButton.waitForExistence(timeout: 5))
        exportSDRFButton.tap()

        let exportQueuedAlert = waitForAlertOrSheet(in: app, timeout: 10)
        XCTAssertTrue(exportQueuedAlert.waitForExistence(timeout: 5), "Submitting an SDRF export should queue a real async task server-side")
        exportQueuedAlert.buttons["OK"].tap()

        tapToolbarButton("openAsyncTaskCenterButton", label: "Async Tasks", in: app, window: "metadata-table-detail", timeout: 10)

        let taskRowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "asyncTaskRow_")
        let asButton = app.buttons.matching(taskRowPredicate).firstMatch
        let asStaticText = app.staticTexts.matching(taskRowPredicate).firstMatch
        let asOtherElement = app.otherElements.matching(taskRowPredicate).firstMatch
        let deadline = Date().addingTimeInterval(15)
        var taskRow = asOtherElement
        while Date() < deadline {
            if asButton.exists { taskRow = asButton; break }
            if asStaticText.exists { taskRow = asStaticText; break }
            if asOtherElement.exists { taskRow = asOtherElement; break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(taskRow.exists, "The just-submitted export task should appear in the Async Tasks list")

        let deviceToken = try fetchDeviceTokenViaAPI()
        let listing = try getJSON("async-tasks/?task_type=EXPORT_SDRF&limit=1", deviceToken: deviceToken)
        let results = listing["results"] as? [[String: Any]] ?? []
        guard let task = results.first else {
            XCTFail("The export task submitted via the real UI should exist server-side (list is ordered most-recent-first)")
            return
        }
        let taskID = task["id"] as! String
        try deleteResource("async-tasks/\(taskID)/cancel/", deviceToken: deviceToken)
    }

    @MainActor
    func testAsyncTaskImportSDRFReachableAndScopedToTableEditors() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let jobName = "Async Import Job \(timestamp)"
        let seed = try seedJobWithEditableColumnViaAPI(jobName: jobName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)
        waitForSignInSyncToFinish(in: app)

        tapTab("Jobs", in: app, timeout: 10)
        findAndTapJobRow(named: jobName, in: app)

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 10))
        createFromTemplateButton.tap()
        waitForSignInSyncToFinish(in: app)

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app, menuItemCount: 4, optionIndex: 0)
        let templateSearchField = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchField.waitForExistence(timeout: 10))
        templateSearchField.tap()
        templateSearchField.typeText(seed.templateName)

        let templateRow = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10))
        templateRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("1")
        app.buttons["createMetadataTableButton"].tap()

        let openFullTableViewButton = app.buttons["openFullMetadataTableViewButton"]
        XCTAssertTrue(openFullTableViewButton.waitForExistence(timeout: 10))
        scrollDownUntilVisible(openFullTableViewButton, in: app)
        openFullTableViewButton.tap()

        tapToolbarButton("importMenu", label: "Import", in: app, window: "metadata-table-detail", timeout: 10)
        let importButton = firstExisting(app.buttons["importSDRFButton"], app.menuItems["importSDRFButton"])
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Choose SDRF File should be reachable inside the Import menu")
        XCTAssertTrue(importButton.isEnabled, "The import trigger should be enabled for the table's owner/editor")

        let deviceToken = try fetchDeviceTokenViaAPI()
        let jobJSON = try getJSON("instrument-jobs/\(seed.jobID)/", deviceToken: deviceToken)
        guard let metadataTableID = jobJSON["metadata_table"] as? Int else {
            XCTFail("The job created through the real UI should have a metadata table by now")
            return
        }

        let sdrfContent = "source name\tcharacteristics[organism]\nHCC-001\thomo sapiens\n"

        let ownerResult = try postSDRFImportViaAPI(metadataTableID: Int64(metadataTableID), fileContent: sdrfContent, replaceExisting: true, deviceToken: deviceToken)
        XCTAssertEqual(ownerResult.statusCode, 202, "The table's owner (also staff on this backend) should be able to queue a real import")
        guard let ownerTaskID = ownerResult.json["task_id"] as? String else {
            XCTFail("A successful import should return a task_id")
            return
        }
        try deleteResource("async-tasks/\(ownerTaskID)/cancel/", deviceToken: deviceToken)

        let nonStaffDeviceToken = try fetchDeviceTokenViaAPI(username: "importtestuser", password: "importtestuser123")
        let nonOwnerResult = try postSDRFImportViaAPI(metadataTableID: Int64(metadataTableID), fileContent: sdrfContent, replaceExisting: true, deviceToken: nonStaffDeviceToken)
        XCTAssertEqual(nonOwnerResult.statusCode, 403, "A non-owner, non-staff user must be denied editing another user's table")
        XCTAssertEqual(nonOwnerResult.json["error"] as? String, "Permission denied: cannot edit this metadata table")

        let ownTableID = try seedStandaloneMetadataTableViaAPI(named: "Non-Staff Scope Table \(timestamp)", deviceToken: nonStaffDeviceToken)
        let scopedResult = try postSDRFImportViaAPI(metadataTableID: ownTableID, fileContent: sdrfContent, replaceExisting: false, importType: "both", deviceToken: nonStaffDeviceToken)
        XCTAssertEqual(scopedResult.statusCode, 202, "A non-staff user should still be able to import into their own table")
        guard let scopedTaskID = scopedResult.json["task_id"] as? String else {
            XCTFail("A successful scoped import should return a task_id")
            return
        }
        let scopedTaskJSON = try getJSON("async-tasks/\(scopedTaskID)/", deviceToken: nonStaffDeviceToken)
        let recordedParameters = scopedTaskJSON["parameters"] as? [String: Any]
        XCTAssertEqual(recordedParameters?["import_type"] as? String, "user_metadata", "A non-staff user's requested 'both' scope must be recorded as the downgraded 'user_metadata' scope, not the raw request")
        try deleteResource("async-tasks/\(scopedTaskID)/cancel/", deviceToken: nonStaffDeviceToken)
    }

    @MainActor
    func testImportRealSDRFFixtureIsAcceptedWithCorrectRequestShape() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let deviceToken = try fetchDeviceTokenViaAPI()

        let templateJSON = try postJSON("metadata-table-templates/", body: ["name": "Real SDRF Fixture Template \(timestamp)", "visibility": "private"], deviceToken: deviceToken)
        guard let templateID = templateJSON["id"] as? Int else {
            XCTFail("Creating a table template should return an id")
            return
        }
        let tableJSON = try postJSON(
            "metadata-table-templates/create_table_from_template/",
            body: ["template_id": templateID, "name": "Real SDRF Fixture Table \(timestamp)", "sample_count": 13],
            deviceToken: deviceToken
        )
        guard let tableID = tableJSON["id"] as? Int else {
            XCTFail("Creating a table from a template should return an id")
            return
        }

        let staffColumnJSON = try postJSON(
            "metadata-tables/\(tableID)/add_column_with_auto_reorder/",
            body: ["column_data": ["name": "comment[internal lab notes]", "type": "comment", "value": "pre-import staff note"]],
            deviceToken: deviceToken
        )
        guard let staffColumnID = (staffColumnJSON["column"] as? [String: Any])?["id"] as? Int else {
            XCTFail("Adding a column should return the created column")
            return
        }
        try patchJSON("metadata-columns/\(staffColumnID)/", body: ["staff_only": true], deviceToken: deviceToken)

        let result = try postSDRFImportViaAPI(
            metadataTableID: Int64(tableID), fileContent: Self.realSDRFFixtureContent, replaceExisting: false, deviceToken: deviceToken
        )
        XCTAssertEqual(result.statusCode, 202, "A real, 13-sample/38-column SDRF fixture (PXD019185_PXD018883.sdrf.tsv) should be accepted by the real async-import endpoint")
        guard let taskID = result.json["task_id"] as? String else {
            XCTFail("A successful import of the real fixture should return a task_id")
            return
        }

        let taskJSON = try getJSON("async-tasks/\(taskID)/", deviceToken: deviceToken)
        let parameters = taskJSON["parameters"] as? [String: Any]
        XCTAssertEqual(taskJSON["task_type"] as? String, "IMPORT_SDRF")
        XCTAssertEqual(parameters?["file_name"] as? String, "import_test.sdrf.tsv")
        XCTAssertEqual(parameters?["replace_existing"] as? Bool, false, "replace_existing:false must be recorded as a real bool, not the truthy literal string \"false\" (the bug fixed in MetadataChunkedUploadView applies to the sibling chunked-upload path, not this serializer-validated one, which was already correct - this locks that in)")
        try deleteResource("async-tasks/\(taskID)/cancel/", deviceToken: deviceToken)
    }

    @MainActor
    private func openConnectionSettings(in app: XCUIApplication) {
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        tapToolbarButton("settingsButton", label: "Settings", in: app, verify: { self.waitForTextAppearing("Connection", in: app, timeout: 3) })
        #endif
        XCTAssertTrue(waitForTextAppearing("Connection", in: app, timeout: 10))
        firstExisting(app.buttons["settingsSidebarItem_connection"], app.staticTexts["settingsSidebarItem_connection"], app.cells["settingsSidebarItem_connection"]).tap()
    }

    @MainActor
    private func closeSettings(in app: XCUIApplication) {
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        tapToolbarButton("doneButton", label: "Done", in: app, timeout: 3)
        #endif
    }

    @MainActor
    private func tapWorkOfflineToggle(in app: XCUIApplication) {
        let toggle = firstExisting(app.switches["forceOfflineToggle"], app.checkBoxes["forceOfflineToggle"])
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "The Work Offline toggle should be reachable from Settings > Connection")
        func describeValue() -> String { "\(toggle.value ?? "nil")" }
        let valueBeforeTap = describeValue()
        var valueAfterTap = valueBeforeTap
        for _ in 0..<3 {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.5)
            valueAfterTap = describeValue()
            if valueAfterTap != valueBeforeTap { break }
        }
        XCTAssertNotEqual(valueBeforeTap, valueAfterTap, "Tapping the Work Offline toggle should flip its reported value (before: \(valueBeforeTap), after: \(valueAfterTap))")
    }

    private func openAccountMenuAndFindSwitchInstance(in app: XCUIApplication) -> XCUIElement {
        let accountMenu = app.buttons["accountMenu"]
        guard accountMenu.waitForExistence(timeout: 10) else {
            return app.buttons["switchInstanceButton"]
        }
        waitUntilHittableAndTap(accountMenu, timeout: 10)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let realMenus = app.menus.allElementsBoundByIndex.filter { $0.frame.width > 0 && $0.frame.height > 0 }
            if let openMenu = realMenus.last {
                let item = firstExisting(openMenu.menuItems["switchInstanceButton"], openMenu.buttons["switchInstanceButton"])
                if item.waitForExistence(timeout: 2) { return item }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return firstExisting(app.menuItems["switchInstanceButton"], app.buttons["switchInstanceButton"])
    }

    private func ensureSignedOut(in app: XCUIApplication, timeout: TimeInterval = 20) {
        let serverURLField = app.textFields["serverURLField"]
        if serverURLField.waitForExistence(timeout: 5) {
            return
        }

        #if os(macOS)
        let accountMenu = app.buttons["accountMenu"]
        guard accountMenu.waitForExistence(timeout: 5) else { return }
        accountMenu.tap()
        let signOutMenuItem = firstExisting(app.menuItems["signOutButton"], app.buttons["signOutButton"])
        guard signOutMenuItem.waitForExistence(timeout: 5) else { return }
        signOutMenuItem.tap()
        #else
        tapToolbarButton("settingsButton", label: "Settings", in: app, verify: { self.waitForTextAppearing("Account", in: app, timeout: 3) })
        let accountSidebarItem = firstExisting(app.buttons["settingsSidebarItem_account"], app.staticTexts["settingsSidebarItem_account"], app.cells["settingsSidebarItem_account"])
        scrollDownUntilVisible(accountSidebarItem, in: app)
        guard accountSidebarItem.waitForExistence(timeout: 5) else { return }
        accountSidebarItem.tap()
        let signOutButton = app.buttons["signOutButton"]
        guard signOutButton.waitForExistence(timeout: 5) else { return }
        signOutButton.tap()
        #endif

        XCTAssertTrue(serverURLField.waitForExistence(timeout: timeout), "Should return to the sign-in screen after signing out a pre-existing session")
        #if os(iOS)
        let doneButton = app.buttons["doneButton"]
        if doneButton.exists { doneButton.tap() }
        #endif
    }

    private func signIn(_ app: XCUIApplication, baseURL: String = "http://127.0.0.1:8002/api/v1/", username: String = "testuser", password: String = "testuser123") {
        ensureSignedOut(in: app)
        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 10))
        replaceText(in: serverURLField, with: baseURL, in: app)

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText(username)

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["signInButton"].tap()
        dismissSavePasswordPromptIfPresent()
    }

    private func dismissSavePasswordPromptIfPresent() {
        #if !os(macOS)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
        }
        #endif
    }

    @MainActor
    private func waitForSignInSyncToFinish(in app: XCUIApplication, timeout: TimeInterval = 30, stallTimeout: TimeInterval = 15) {
        let bannerQuery = app.staticTexts.matching(NSPredicate(format: "identifier == %@", "syncProgressBanner"))
        let deadline = Date().addingTimeInterval(timeout)
        var consecutiveAbsences = 0
        var lastText: String?
        var lastChangeTime = Date()
        while Date() < deadline {
            let element = bannerQuery.firstMatch
            if element.exists {
                consecutiveAbsences = 0
                let valueText = (element.value as? String) ?? ""
                let text = !valueText.isEmpty ? valueText : element.label
                if text != lastText {
                    lastText = text
                    lastChangeTime = Date()
                } else if Date().timeIntervalSince(lastChangeTime) > stallTimeout {
                    XCTFail("Sign-in sync appears stalled: the sync banner has shown \"\(text)\" unchanged for more than \(Int(stallTimeout))s")
                    return
                }
            } else {
                if lastText != nil {
                    lastText = nil
                    lastChangeTime = Date()
                }
                consecutiveAbsences += 1
                if consecutiveAbsences >= 40 { return }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    @MainActor
    private func selectPickerOption(_ identifier: String, option: String, in app: XCUIApplication, menuItemCount: Int? = nil, optionIndex: Int? = nil) {
        let picker = waitForFirstExisting(timeout: 10, app.popUpButtons[identifier], app.buttons[identifier], app.otherElements[identifier])
        XCTAssertTrue(picker.exists, "Picker \"\(identifier)\" not found")
        picker.tap()

        #if os(macOS)
        if let menuItemCount, let optionIndex {
            let optionElement = openMenuItem(itemCount: menuItemCount, at: optionIndex, in: app)
            XCTAssertTrue(optionElement.waitForExistence(timeout: 5), "Picker option \"\(option)\" not found")
            optionElement.tap()
            return
        }
        #endif

        let predicate = NSPredicate(format: "label == %@", option)
        let queries = [app.buttons.matching(predicate), app.staticTexts.matching(predicate), app.menuItems.matching(predicate)]
        let deadline = Date().addingTimeInterval(5)
        var optionElement: XCUIElement?
        while optionElement == nil, Date() < deadline {
            for query in queries {
                for index in 0..<query.count {
                    let candidate = query.element(boundBy: index)
                    if candidate.exists, candidate.isHittable {
                        optionElement = candidate
                        break
                    }
                }
                if optionElement != nil { break }
            }
            if optionElement == nil { Thread.sleep(forTimeInterval: 0.3) }
        }
        guard let optionElement else {
            XCTFail("Picker option \"\(option)\" not found")
            return
        }
        optionElement.tap()
    }

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

    private func fetchDeviceTokenViaAPI(username: String = "testuser", password: String = "testuser123") throws -> String {
        let loginData = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
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

    private func deleteResource(_ path: String, deviceToken: String) throws {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/\(path)")!)
        request.httpMethod = "DELETE"
        request.setValue("DeviceToken \(deviceToken)", forHTTPHeaderField: "Authorization")
        _ = try synchronousData(for: request)
    }

    private func createLabGroupViaAPI(named name: String, deviceToken: String) throws -> Int64 {
        let json = try postJSON("lab-groups/", body: ["name": name], deviceToken: deviceToken)
        guard let id = json["id"] as? Int else { throw APISeedError.missingField("id") }
        return Int64(id)
    }

    private func createGroupTemplateViaAPI(named name: String, labGroupID: Int64, deviceToken: String) throws {
        let created = try postJSON("metadata-table-templates/create_from_schema/", body: ["name": name, "schemas": ["minimum"]], deviceToken: deviceToken)
        guard let id = created["id"] as? Int else { throw APISeedError.missingField("id") }
        try patchJSON("metadata-table-templates/\(id)/", body: ["visibility": "group", "lab_group": labGroupID], deviceToken: deviceToken)
    }

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

    private struct MetadataGridSeed {
        let templateName: String
        let column1Name: String
        let column2Name: String
        let sampleCount: Int
    }

    private func seedJobWithMetadataTableViaAPI(jobName: String) throws -> MetadataGridSeed {
        let deviceToken = try fetchDeviceTokenViaAPI()
        let timestamp = Int(Date().timeIntervalSince1970)
        let projectID = try createProjectViaAPI(named: "Grid Flow Project \(timestamp)", deviceToken: deviceToken)
        let jobID = try createJobViaAPI(named: jobName, projectID: projectID, deviceToken: deviceToken)
        let labGroupID = try createLabGroupViaAPI(named: "Grid Flow Lab Group \(timestamp)", deviceToken: deviceToken)
        try assignJobLabGroupViaAPI(jobID: jobID, labGroupID: labGroupID, deviceToken: deviceToken)

        let templateName = "Grid Flow Template \(timestamp)"
        let templateJSON = try postJSON("metadata-table-templates/", body: ["name": templateName, "visibility": "private"], deviceToken: deviceToken)
        guard let templateID = templateJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let column1Name = "characteristics[grid col a]"
        let column2Name = "characteristics[grid col b]"
        try postJSON("metadata-table-templates/\(templateID)/add_column/", body: ["column_data": ["name": column1Name, "type": "characteristics"]], deviceToken: deviceToken)
        try postJSON("metadata-table-templates/\(templateID)/add_column/", body: ["column_data": ["name": column2Name, "type": "characteristics"]], deviceToken: deviceToken)

        return MetadataGridSeed(templateName: templateName, column1Name: column1Name, column2Name: column2Name, sampleCount: 5)
    }

    private struct EditableColumnSeed {
        let jobID: Int64
        let templateName: String
        let columnName: String
    }

    private func seedJobWithEditableColumnViaAPI(jobName: String) throws -> EditableColumnSeed {
        let deviceToken = try fetchDeviceTokenViaAPI()
        let timestamp = Int(Date().timeIntervalSince1970)
        let projectID = try createProjectViaAPI(named: "Edit Value Test Project \(timestamp)", deviceToken: deviceToken)
        let jobID = try createJobViaAPI(named: jobName, projectID: projectID, deviceToken: deviceToken)
        let labGroupID = try createLabGroupViaAPI(named: "Edit Value Test Lab Group \(timestamp)", deviceToken: deviceToken)
        try assignJobLabGroupViaAPI(jobID: jobID, labGroupID: labGroupID, deviceToken: deviceToken)

        let templateName = "Edit Value Test Template \(timestamp)"
        let templateJSON = try postJSON("metadata-table-templates/", body: ["name": templateName, "visibility": "private"], deviceToken: deviceToken)
        guard let templateID = templateJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let columnName = "characteristics[edit test value]"
        try postJSON("metadata-table-templates/\(templateID)/add_column/", body: ["column_data": ["name": columnName, "type": "characteristics"]], deviceToken: deviceToken)

        return EditableColumnSeed(jobID: jobID, templateName: templateName, columnName: columnName)
    }

    private struct ModificationColumnSeed {
        let jobID: Int64
        let templateName: String
        let columnName: String
    }

    private func seedJobWithModificationColumnViaAPI(jobName: String) throws -> ModificationColumnSeed {
        let deviceToken = try fetchDeviceTokenViaAPI()
        let timestamp = Int(Date().timeIntervalSince1970)
        let projectID = try createProjectViaAPI(named: "Modification Test Project \(timestamp)", deviceToken: deviceToken)
        let jobID = try createJobViaAPI(named: jobName, projectID: projectID, deviceToken: deviceToken)
        let labGroupID = try createLabGroupViaAPI(named: "Modification Test Lab Group \(timestamp)", deviceToken: deviceToken)
        try assignJobLabGroupViaAPI(jobID: jobID, labGroupID: labGroupID, deviceToken: deviceToken)

        let templateName = "Modification Test Template \(timestamp)"
        let templateJSON = try postJSON("metadata-table-templates/", body: ["name": templateName, "visibility": "private"], deviceToken: deviceToken)
        guard let templateID = templateJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let columnName = "comment[modification parameters]"
        try postJSON(
            "metadata-table-templates/\(templateID)/add_column/",
            body: ["column_data": ["name": columnName, "type": "comment", "ontology_type": "unimod"]],
            deviceToken: deviceToken
        )

        return ModificationColumnSeed(jobID: jobID, templateName: templateName, columnName: columnName)
    }

    private func seedStandaloneMetadataTableViaAPI(named name: String, deviceToken: String) throws -> Int64 {
        let templateJSON = try postJSON("metadata-table-templates/", body: ["name": "\(name) Template", "visibility": "private"], deviceToken: deviceToken)
        guard let templateID = templateJSON["id"] as? Int else { throw APISeedError.missingField("id") }
        let tableJSON = try postJSON("metadata-table-templates/create_table_from_template/", body: ["template_id": templateID, "name": name, "sample_count": 4], deviceToken: deviceToken)
        guard let tableID = tableJSON["id"] as? Int else { throw APISeedError.missingField("id") }
        return Int64(tableID)
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

    @discardableResult
    private func postSDRFImportViaAPI(metadataTableID: Int64, fileContent: String, replaceExisting: Bool, importType: String? = nil, deviceToken: String) throws -> (statusCode: Int, json: [String: Any]) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/async-import/sdrf_file/")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("DeviceToken \(deviceToken)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        addField("metadata_table_id", String(metadataTableID))
        addField("replace_existing", replaceExisting ? "true" : "false")
        if let importType {
            addField("import_type", importType)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"import_test.sdrf.tsv\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/tab-separated-values\r\n\r\n".data(using: .utf8)!)
        body.append(fileContent.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try synchronousData(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (statusCode, json ?? [:])
    }

    private func uploadStepAudioAnnotationViaAPI(sessionID: Int, stepID: Int, fileData: Data, deviceToken: String) throws -> Int64 {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/api/v1/upload/step-annotation-chunks/")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("DeviceToken \(deviceToken)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        let sha256 = SHA256.hash(data: fileData).map { String(format: "%02x", $0) }.joined()
        addField("filename", "caption_test_audio.m4a")
        addField("sha256", sha256)
        addField("session_id", String(sessionID))
        addField("step_id", String(stepID))
        addField("annotation_type", "audio")
        addField("auto_transcribe", "false")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"caption_test_audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, _) = try synchronousData(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let stepAnnotationID = json["step_annotation_id"] as? Int else {
            throw APISeedError.missingField("step_annotation_id")
        }
        return Int64(stepAnnotationID)
    }

    private func seedStepAudioAnnotationWithTranscriptionViaAPI(
        protocolTitle: String,
        sessionName: String
    ) throws -> (deviceToken: String, sessionID: Int64, stepID: Int64, stepAnnotationID: Int64, sessionName: String) {
        let deviceToken = try fetchDeviceTokenViaAPI()
        let protocolJSON = try postJSON("protocols/", body: ["protocol_title": protocolTitle, "enabled": false], deviceToken: deviceToken)
        guard let protocolID = protocolJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let sectionJSON = try postJSON("sections/", body: ["protocol": protocolID, "section_description": "Caption Test Section", "section_duration": 0], deviceToken: deviceToken)
        guard let sectionID = sectionJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let stepJSON = try postJSON(
            "steps/",
            body: ["protocol": protocolID, "step_section": sectionID, "step_description": "Caption Test Step", "order": 0],
            deviceToken: deviceToken
        )
        guard let stepID = stepJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let sessionJSON = try postJSON("sessions/", body: ["name": sessionName, "enabled": false, "protocols": [protocolID]], deviceToken: deviceToken)
        guard let sessionID = sessionJSON["id"] as? Int else { throw APISeedError.missingField("id") }

        let audioData = Data(base64Encoded: Self.captionTestAudioFixtureBase64)!
        let stepAnnotationID = try uploadStepAudioAnnotationViaAPI(sessionID: sessionID, stepID: stepID, fileData: audioData, deviceToken: deviceToken)

        let seedVTT = "WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nThis is a caption\n\n00:00:02.000 --> 00:00:04.000\neditor test recording."
        try patchJSON("step-annotations/\(stepAnnotationID)/", body: ["transcription": seedVTT, "language": "en"], deviceToken: deviceToken)

        return (deviceToken, Int64(sessionID), Int64(stepID), stepAnnotationID, sessionName)
    }

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

    private func scrollDownUntilVisible(_ element: XCUIElement, in app: XCUIApplication, window windowIdentifierSubstring: String? = nil, maxAttempts: Int = 15) {
        #if os(macOS)
        let window = frontmostWindow(in: app, matching: windowIdentifierSubstring)
        var attempts = 0
        while attempts < 6 {
            if element.exists, element.isHittable, element.frame.width > 0, element.frame.height > 0, window.frame.contains(element.frame) {
                return
            }
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.15))
            let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.95))
            start.press(forDuration: 0.05, thenDragTo: end)
            attempts += 1
        }
        #else
        var scopedWindow: XCUIElement?
        if let windowIdentifierSubstring, UIDevice.current.userInterfaceIdiom == .pad {
            let match = app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", windowIdentifierSubstring)).firstMatch
            if match.exists { scopedWindow = match }
        }
        var attempts = 0
        while attempts < maxAttempts {
            if element.exists, element.isHittable, element.frame.width > 0, element.frame.height > 0, app.frame.contains(element.frame) {
                return
            }
            if let scopedWindow {
                scopedWindow.swipeUp(velocity: .fast)
            } else {
                app.swipeUp(velocity: .fast)
            }
            attempts += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
        #endif
    }

    private func scrollDownUntilVisible(_ element: XCUIElement, within containerIdentifier: String, in app: XCUIApplication, maxAttempts: Int = 15) {
        func container() -> XCUIElement {
            firstExisting(app.collectionViews[containerIdentifier], app.tables[containerIdentifier], app.otherElements[containerIdentifier], app.scrollViews[containerIdentifier])
        }
        #if os(macOS)
        return
        #else
        var attempts = 0
        while attempts < maxAttempts {
            if element.exists, element.isHittable, element.frame.width > 0, element.frame.height > 0 {
                return
            }
            container().swipeUp(velocity: .fast)
            attempts += 1
        }
        #endif
    }

    private func scrollUpUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 15) {
        var attempts = 0
        while !element.exists, attempts < maxAttempts {
            app.swipeDown(velocity: .fast)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func scrollUpUntilVisible(_ element: XCUIElement, within containerIdentifier: String, in app: XCUIApplication, maxAttempts: Int = 15) {
        func container() -> XCUIElement {
            firstExisting(app.collectionViews[containerIdentifier], app.tables[containerIdentifier], app.otherElements[containerIdentifier], app.scrollViews[containerIdentifier])
        }
        #if os(macOS)
        return
        #else
        var attempts = 0
        while !element.exists, attempts < maxAttempts {
            container().swipeDown(velocity: .fast)
            attempts += 1
        }
        #endif
    }

    private func scrollUpUntilVisible(_ element: XCUIElement, orAtTop topAnchor: XCUIElement, within containerIdentifier: String, in app: XCUIApplication, maxAttempts: Int = 15) {
        func container() -> XCUIElement {
            firstExisting(app.collectionViews[containerIdentifier], app.tables[containerIdentifier], app.otherElements[containerIdentifier], app.scrollViews[containerIdentifier])
        }
        #if os(macOS)
        return
        #else
        var attempts = 0
        while !element.exists, !topAnchor.exists, attempts < maxAttempts {
            container().swipeDown(velocity: .fast)
            attempts += 1
        }
        #endif
    }

    private func tapCreateJobButtonReliably(in app: XCUIApplication) {
        let button = app.buttons["createJobButton"]
        let sheetField = app.textFields["newJobNameField"]
        for _ in 0..<8 {
            guard sheetField.exists else { return }
            if button.exists, button.isEnabled, button.isHittable {
                button.tap()
            }
            Thread.sleep(forTimeInterval: 1.0)
            if !sheetField.exists { return }
        }
    }

    private func findAndTapJobRow(named jobName: String, in app: XCUIApplication, timeout: TimeInterval = 30) {
        let searchField = app.textFields["jobSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        replaceText(in: searchField, with: jobName, in: app)

        let asButton = app.buttons["jobRow_\(jobName)"]
        let asStaticText = app.staticTexts["jobRow_\(jobName)"]
        let asOtherElement = app.otherElements["jobRow_\(jobName)"]
        let deadline = Date().addingTimeInterval(timeout)
        var jobRow = asButton
        while Date() < deadline {
            if asButton.exists { jobRow = asButton; break }
            if asStaticText.exists { jobRow = asStaticText; break }
            if asOtherElement.exists { jobRow = asOtherElement; break }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(jobRow.exists, "The job \"\(jobName)\" should appear once filtered by name")
        jobRow.tap()
    }

    private func closeWindow(matching identifierSubstring: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        #if os(macOS)
        func freshWindowExists() -> Bool {
            app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", identifierSubstring)).firstMatch.exists
        }
        let window = app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", identifierSubstring)).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: timeout), "Expected a window matching \"\(identifierSubstring)\" to close")
        func attemptClose() {
            app.activate()
            let closeButton = window.buttons["_XCUI:CloseWindow"]
            if closeButton.waitForExistence(timeout: 3) {
                closeButton.tap()
            }
        }
        attemptClose()
        #else
        let doneButton = app.buttons["doneButton_\(identifierSubstring)"].firstMatch
        if doneButton.waitForExistence(timeout: timeout) {
            doneButton.tap()
        }
        #endif
        #if os(macOS)
        let deadline = Date().addingTimeInterval(timeout)
        while freshWindowExists(), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        if freshWindowExists() {
            attemptClose()
            let retryDeadline = Date().addingTimeInterval(5)
            while freshWindowExists(), Date() < retryDeadline {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        if freshWindowExists() {
            app.activate()
            app.typeKey("w", modifierFlags: .command)
            let fallbackDeadline = Date().addingTimeInterval(5)
            while freshWindowExists(), Date() < fallbackDeadline {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        XCTAssertFalse(freshWindowExists(), "Window matching \"\(identifierSubstring)\" should have closed")
        #endif
    }

    private func tapTab(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        #if !os(macOS)
        if app.navigationBars[label].exists { return }
        #endif
        let findDeadline = Date().addingTimeInterval(timeout)
        var match: XCUIElement?
        while Date() < findDeadline {
            let predicate = NSPredicate(format: "label == %@", label)
            let candidate = firstExisting(
                app.tabBars.buttons.matching(predicate).firstMatch,
                app.buttons.matching(predicate).firstMatch,
                app.radioButtons.matching(predicate).firstMatch,
                app.cells.matching(predicate).firstMatch,
                app.cells.staticTexts.matching(predicate).firstMatch
            )
            if candidate.exists { match = candidate; break }
            Thread.sleep(forTimeInterval: 0.5)
        }

        if let match {
            #if !os(macOS)
            for _ in 0..<4 {
                waitUntilHittableAndTap(match, timeout: 2)
                if app.navigationBars[label].waitForExistence(timeout: 3) { return }
                if !match.exists || match.isSelected { return }
            }
            return
            #else
            waitUntilHittableAndTap(match, timeout: timeout)
            return
            #endif
        }

        let more = app.tabBars.buttons["More"]
        XCTAssertTrue(more.waitForExistence(timeout: timeout), "Neither \"\(label)\" nor a \"More\" tab overflow was found")
        waitUntilHittableAndTap(more, timeout: timeout)

        let itemInMore = firstExisting(app.staticTexts[label], app.buttons[label], app.cells[label])
        XCTAssertTrue(itemInMore.waitForExistence(timeout: timeout), "\"\(label)\" was not found inside the tab bar's More list")
        itemInMore.tap()
    }

    private func waitForAlertOrSheet(in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement {
        let asAlert = app.alerts.firstMatch
        if asAlert.waitForExistence(timeout: timeout) { return asAlert }
        return app.sheets.firstMatch
    }

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

    private func waitForFirstExisting(timeout: TimeInterval, _ candidates: XCUIElement...) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for candidate in candidates where candidate.exists {
                return candidate
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return candidates[0]
    }

    private func waitUntilHittableAndTap(_ element: XCUIElement, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !element.isHittable {
            Thread.sleep(forTimeInterval: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.3)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func tapSegment(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let segment = firstExisting(app.radioButtons[label], app.buttons[label])
        XCTAssertTrue(segment.waitForExistence(timeout: timeout), "\"\(label)\" segment not found")
        segment.tap()
    }

    private func tapSegment(_ label: String, within pickerIdentifier: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let picker = firstExisting(app.segmentedControls[pickerIdentifier], app.radioGroups[pickerIdentifier], app.otherElements[pickerIdentifier])
        if picker.waitForExistence(timeout: 3) {
            let segment = firstExisting(picker.radioButtons[label], picker.buttons[label])
            XCTAssertTrue(segment.waitForExistence(timeout: timeout), "\"\(label)\" segment not found within \"\(pickerIdentifier)\"")
            segment.tap()
            return
        }

        let window = frontmostWindow(in: app)
        let overflow = firstExisting(
            window.popUpButtons["more toolbar items"],
            window.buttons["more toolbar items"],
            window.buttons["More"]
        )
        XCTAssertTrue(overflow.waitForExistence(timeout: timeout), "Neither \"\(pickerIdentifier)\" nor a toolbar overflow menu was found")
        waitUntilHittableAndTap(overflow, timeout: timeout)

        #if os(macOS)
        let overflowSearchRoot = overflow
        #else
        let overflowSearchRoot = window
        #endif
        let modeMenuItem = overflowItem(labeled: label, in: overflowSearchRoot, timeout: timeout)
        if modeMenuItem.exists {
            modeMenuItem.tap()
            return
        }

        let modeToggle = overflowItem(labeled: "Mode", in: overflowSearchRoot, timeout: timeout)
        XCTAssertTrue(modeToggle.exists, "Neither \"\(label)\" nor a \"Mode\" control was found inside the toolbar overflow menu")
        modeToggle.tap()
        let segmentInOverflow = overflowItem(labeled: label, in: overflowSearchRoot, timeout: timeout)
        XCTAssertTrue(segmentInOverflow.exists, "\"\(label)\" was not found inside the \"Mode\" overflow control")
        segmentInOverflow.tap()
    }

    private func tapMenuItem(_ menuIdentifier: String, item label: String, in app: XCUIApplication) {
        let menuButton = firstExisting(app.buttons[menuIdentifier], app.menuButtons[menuIdentifier])
        if menuButton.waitForExistence(timeout: 3) {
            menuButton.tap()
            let menuItem = firstExisting(app.menuItems[label], app.buttons[label])
            XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "\"\(label)\" not found in the \"\(menuIdentifier)\" menu")
            menuItem.tap()
            return
        }

        let overflow = app.popUpButtons["more toolbar items"]
        XCTAssertTrue(overflow.waitForExistence(timeout: 5), "Neither \"\(menuIdentifier)\" nor a toolbar overflow menu was found")
        overflow.tap()

        let overflowMenuButton = firstExisting(app.menuItems[menuIdentifier], app.buttons[menuIdentifier])
        let menuItem = firstExisting(app.menuItems[label], app.buttons[label])
        for _ in 0..<3 {
            if menuItem.waitForExistence(timeout: 2) { break }
            if overflowMenuButton.exists { overflowMenuButton.tap() }
        }
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "\"\(label)\" not found in the \"\(menuIdentifier)\" menu (including toolbar overflow)")
        menuItem.tap()
    }

    private func replaceText(in field: XCUIElement, with newText: String, in app: XCUIApplication) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        for _ in 0..<3 {
            field.tap()
            field.typeKey("a", modifierFlags: .command)
            field.typeKey("v", modifierFlags: .command)
            if field.value as? String == newText { return }
        }
        XCTAssertEqual(field.value as? String, newText, "Failed to replace field text after multiple attempts")
        #else
        let placeholder = field.placeholderValue
        func matchesTarget() -> Bool {
            let current = field.value as? String
            if newText.isEmpty { return current == nil || current == "" || current == placeholder }
            return current == newText
        }
        let priorValue = field.value as? String
        let hasRealPriorContent = priorValue.map { !$0.isEmpty && $0 != newText && $0 != placeholder } ?? false
        if !hasRealPriorContent {
            waitUntilHittableAndTap(field)
            field.typeText(newText)
            if matchesTarget() { return }
        }

        for _ in 0..<5 {
            if matchesTarget() { return }
            waitUntilHittableAndTap(field)
            Thread.sleep(forTimeInterval: 0.5)
            waitUntilHittableAndTap(field)
            Thread.sleep(forTimeInterval: 0.3)
            waitUntilHittableAndTap(field)
            let selectAllItem = app.menuItems["Select All"]
            let cutItem = app.menuItems["Cut"]
            let alreadySelected = firstExisting(selectAllItem, cutItem)
            guard alreadySelected.waitForExistence(timeout: 3) else { continue }
            if selectAllItem.exists { selectAllItem.tap() }
            if newText.isEmpty {
                field.typeText("\u{8}")
            } else {
                field.typeText(newText)
            }
            if matchesTarget() { return }
        }
        XCTAssertTrue(matchesTarget(), "Failed to replace field text after multiple attempts")
        #endif
    }

    private func frontmostWindow(in app: XCUIApplication, matching identifierSubstring: String? = nil) -> XCUIElement {
        #if os(macOS)
        if let identifierSubstring {
            return app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", identifierSubstring)).firstMatch
        }
        return app.windows.firstMatch
        #elseif os(iOS)
        if let identifierSubstring, UIDevice.current.userInterfaceIdiom == .pad {
            let match = app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", identifierSubstring)).firstMatch
            if match.exists { return match }
        }
        return app
        #else
        return app
        #endif
    }

    private func directToolbarElement(_ identifier: String, in window: XCUIElement, timeout: TimeInterval) -> XCUIElement? {
        let asButton = window.buttons[identifier]
        if asButton.waitForExistence(timeout: timeout) { return asButton }
        let asMenuButton = window.menuButtons[identifier]
        if asMenuButton.waitForExistence(timeout: 1) { return asMenuButton }
        return nil
    }

    private func toolbarButtonLabel(_ identifier: String, label: String, in app: XCUIApplication, window windowIdentifierSubstring: String? = nil, overflowIndex: Int? = nil, timeout: TimeInterval = 5) -> String {
        let window = frontmostWindow(in: app, matching: windowIdentifierSubstring)
        if let direct = directToolbarElement(identifier, in: window, timeout: timeout) {
            return direct.label
        }

        let overflow = firstExisting(
            window.popUpButtons["more toolbar items"],
            window.buttons["more toolbar items"],
            window.buttons["More"]
        )
        guard overflow.waitForExistence(timeout: timeout) else {
            XCTFail("Neither \"\(identifier)\" nor a toolbar overflow menu was found")
            return ""
        }
        overflow.tap()

        #if os(macOS)
        let overflowSearchRoot = overflow
        #else
        let overflowSearchRoot = window
        #endif
        let itemInOverflow = overflowItem(labeled: label, overflowIndex: overflowIndex, in: overflowSearchRoot, timeout: timeout)
        XCTAssertTrue(itemInOverflow.exists, "\"\(label)\" was not found inside the toolbar overflow menu")
        let resolvedLabel = itemInOverflow.label
        overflow.tap()
        return resolvedLabel
    }

    private func dynamicOverflowIndex(precedingIdentifiers: [String], in app: XCUIApplication, window windowIdentifierSubstring: String? = nil) -> Int {
        let window = frontmostWindow(in: app, matching: windowIdentifierSubstring)
        return precedingIdentifiers.filter { directToolbarElement($0, in: window, timeout: 1) == nil }.count
    }

    private func openMenuItem(itemCount: Int? = nil, at index: Int, in app: XCUIApplication, timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var matchedMenu: XCUIElement?
        while Date() < deadline {
            let realMenus = app.menus.allElementsBoundByIndex.filter { $0.frame.width > 0 && $0.frame.height > 0 }
            if let itemCount, let found = realMenus.first(where: { $0.menuItems.count == itemCount }) {
                matchedMenu = found
                break
            } else if itemCount == nil, let found = realMenus.last {
                matchedMenu = found
                break
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        guard let matchedMenu else {
            XCTFail("No open menu was found within \(timeout)s")
            return app.menus.firstMatch.menuItems.element(boundBy: index)
        }
        return matchedMenu.menuItems.element(boundBy: index)
    }

    private func overflowItem(labeled label: String, overflowIndex: Int? = nil, in overflow: XCUIElement, timeout: TimeInterval) -> XCUIElement {
        #if os(macOS)
        if let overflowIndex {
            let element = overflow.menuItems.element(boundBy: overflowIndex)
            _ = element.waitForExistence(timeout: timeout)
            return element
        }
        #endif
        let predicate = NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label)
        let menuItem = overflow.menuItems.matching(predicate).firstMatch
        if menuItem.waitForExistence(timeout: timeout) {
            return menuItem
        }
        let button = overflow.buttons.matching(predicate).firstMatch
        _ = button.waitForExistence(timeout: 1)
        return button
    }

    private func tapToolbarButton(_ identifier: String, label: String, in app: XCUIApplication, window windowIdentifierSubstring: String? = nil, overflowIndex: Int? = nil, timeout: TimeInterval = 5, verify: (() -> Bool)? = nil) {
        let window = frontmostWindow(in: app, matching: windowIdentifierSubstring)
        if let direct = directToolbarElement(identifier, in: window, timeout: timeout) {
            if let verify {
                for _ in 0..<4 {
                    waitUntilHittableAndTap(direct, timeout: timeout)
                    if verify() { return }
                }
                return
            }
            waitUntilHittableAndTap(direct, timeout: timeout)
            return
        }

        let overflow = firstExisting(
            window.popUpButtons["more toolbar items"],
            window.buttons["more toolbar items"],
            window.buttons["More"]
        )
        guard overflow.waitForExistence(timeout: timeout) else {
            XCTFail("Neither \"\(identifier)\" nor a toolbar overflow menu was found")
            return
        }
        waitUntilHittableAndTap(overflow, timeout: timeout)

        #if os(macOS)
        let overflowSearchRoot = overflow
        #else
        let overflowSearchRoot = window
        #endif
        let itemInOverflow = overflowItem(labeled: label, overflowIndex: overflowIndex, in: overflowSearchRoot, timeout: timeout)
        XCTAssertTrue(itemInOverflow.exists, "\"\(label)\" was not found inside the toolbar overflow menu")
        itemInOverflow.tap()
    }

    private func dismissTableTemplateManagementSheet(in app: XCUIApplication, maxAttempts: Int = 3) {
        let backToTemplatesButton = app.buttons["Templates"]
        if backToTemplatesButton.waitForExistence(timeout: 3) {
            backToTemplatesButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        #if os(macOS)
        let usesSeparateWindow = true
        #elseif os(iOS)
        let usesSeparateWindow = UIDevice.current.userInterfaceIdiom == .pad
        #else
        let usesSeparateWindow = false
        #endif
        if usesSeparateWindow {
            closeWindow(matching: "table-template-manager", in: app)
            return
        }
        let stillOpenMarker = app.buttons["newMetadataTableTemplateButton"]
        for _ in 0..<maxAttempts {
            tapToolbarButton("tableTemplateManagementSheetDoneButton", label: "Done", in: app, timeout: 3)
            Thread.sleep(forTimeInterval: 0.5)
            if !stillOpenMarker.exists {
                return
            }
        }
        XCTFail("Table Template Management sheet did not dismiss after \(maxAttempts) attempts at \"tableTemplateManagementSheetDoneButton\"")
    }

    private func elementContaining(_ substring: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        return app.staticTexts.matching(predicate).firstMatch.exists
            ? app.staticTexts.matching(predicate).firstMatch
            : app.buttons.matching(predicate).firstMatch
    }

    private func waitForTextAppearing(_ substring: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        if app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout) {
            return true
        }
        return app.buttons.matching(predicate).firstMatch.exists
    }

    private func waitForElementDisappearing(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !element.exists
    }

    private func waitForElementDestroyed(identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        #if os(macOS)
        if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "info.proteo.cupcake").first?.processIdentifier {
            return AXEventWaiter(pid: pid).waitForDestruction(ofIdentifier: identifier, timeout: timeout)
        }
        #endif
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
        return !app.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists
    }

    private func waitForTextDisappearing(_ substring: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        let staticText = app.staticTexts.matching(predicate).firstMatch
        let button = app.buttons.matching(predicate).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let stillPresent = staticText.exists || button.exists
            if !stillPresent { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private static let realSDRFFixtureContent: String = #"""
source name	characteristics[biological replicate]	characteristics[organism]	characteristics[organism part]	characteristics[age]	characteristics[ancestry category]	characteristics[cell type]	characteristics[disease]	characteristics[cell line]	characteristics[phenotype]	characteristics[genetic modification]	characteristics[individual]	characteristics[sex]	characteristics[pooled sample]	characteristics[xenograft]	characteristics[enrichment process]	assay name	technology type	comment[proteomexchange accession number]	comment[cleavage agent details]	comment[cleavage agent details]	comment[cleavage agent details]	comment[fraction identifier]	comment[fragment mass tolerance]	comment[instrument]	comment[label]	comment[modification parameters]	comment[modification parameters]	comment[modification parameters]	comment[modification parameters]	comment[modification parameters]	comment[modification parameters]	comment[precursor mass tolerance]	comment[technical replicate]	comment[tool metadata]	comment[data file]	factor value[genetic modification]	factor value[phenotype]
D-HEp3 #1	1	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	not applicable	not applicable	not available	pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 1	proteomic profiling by mass spectrometry	PXD036453 	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.015 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M', 'K', 'P	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N,Q	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	NT=Carbamyl;AC=Unimod:5;MT=Variable;PP=Any N-term;TA=Y', 'S', 'T	not applicable	10 ppm	1	lesSDRF v0.1.0	180615_554_AN_D1.raw	not applicable	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 #2	2	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	not applicable	not applicable	not available	pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 2	proteomic profiling by mass spectrometry	PXD036453 	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.015 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M', 'K', 'P	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N,Q	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	NT=Carbamyl;AC=Unimod:5;MT=Variable;PP=Any N-term;TA=Y', 'S', 'T	not applicable	10 ppm	1	lesSDRF v0.1.0	180615_554_AN_D2.raw	not applicable	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
T-HEp3 #1	1	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=proliferating cells;AC=CMPO:0000241	not applicable	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 3	proteomic profiling by mass spectrometry	PXD036453	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.015 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M', 'K', 'P	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N,Q	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	NT=Carbamyl;AC=Unimod:5;MT=Variable;PP=Any N-term;TA=Y', 'S', 'T	not applicable	10 ppm	1	lesSDRF v0.1.0	180615_554_AN_T1.raw	not applicable	NT=proliferating cells;AC=CMPO:0000241
T-HEp3 #2	2	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=proliferating cells;AC=CMPO:0000241	not applicable	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 4	proteomic profiling by mass spectrometry	PXD036453	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.015 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M', 'K', 'P	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N,Q	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	NT=Carbamyl;AC=Unimod:5;MT=Variable;PP=Any N-term;TA=Y', 'S', 'T	not applicable	10 ppm	1	lesSDRF v0.1.0	180615_554_AN_T2.raw	not applicable	NT=proliferating cells;AC=CMPO:0000241
T-HEp3 #4	3	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=proliferating cells;AC=CMPO:0000241	not applicable	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 5	proteomic profiling by mass spectrometry	PXD036453	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.015 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M', 'K', 'P	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N,Q	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	NT=Carbamyl;AC=Unimod:5;MT=Variable;PP=Any N-term;TA=Y', 'S', 'T	not applicable	10 ppm	1	lesSDRF v0.1.0	180615_554_AN_T4.raw	not applicable	NT=proliferating cells;AC=CMPO:0000241
D-HEp3 shCTRL #1	1	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	not applicable	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 6	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	NabaC0-2-10X.raw	not applicable	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 shCTRL #2	2	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	not applicable	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 7	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	NabaC1-1-10X.raw	not applicable	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 shCTRL #3	3	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	not applicable	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 8	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	Naba-1-10x_180123194318.raw	not applicable	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 shCTRL #4	4	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	not applicable	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 9	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	Naba-2-10x.raw	not applicable	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 shDDR1 #1	1	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	NT=gene knockdown;AC=OBI:0002625	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 10	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	NabaSh2-4-10X.raw	NT=gene knockdown;AC=OBI:0002625	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 shDDR1 #2	2	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	NT=gene knockdown;AC=OBI:0002625	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 11	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	NabaSh3-2-10X.raw	NT=gene knockdown;AC=OBI:0002625	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 shDDR1 #3	3	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	NT=gene knockdown;AC=OBI:0002625	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 12	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	Naba-3-10x.raw	NT=gene knockdown;AC=OBI:0002625	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
D-HEp3 shDDR1 #4	4	homo sapiens	NT=head and neck;AC=MA:0000006	62Y	african american	squamous epitheliel cells	squamous cell carcinoma	NT=HEp-3 cell;AC=BTO:0005139	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445	NT=gene knockdown;AC=OBI:0002625	not applicable	not available	not pooled	cancer cell line grown in mice	NT=Extraction purification;AC=NCIT:C113061	run 13	proteomic profiling by mass spectrometry	PXD018883	NT=Trypsin;AC=MS:1001251	NT=Lys-C;AC=MS:1001309	NT=N-glycosidase F;AC=CHMO:0002922	not applicable	0.1 Da	NT=LTQ Orbitrap Velos;AC=MS:1001742	label free sample	NT=Carbamidomethyl;AC=Unimod:4;MT=Fixed;PP=Anywhere;TA=C	NT=Oxidation;AC=Unimod:35;MT=Variable;PP=Anywhere;TA=M	NT=Deamidated;AC=Unimod:7;MT=Variable;PP=Anywhere;TA=N	NT=Gln->pyro-Glu;AC=Unimod:28;MT=Variable;PP=Any N-term;TA=N	not applicable	NT=Hydroxylation;AC=MOP:0000673;MT=Variable;PP=Anywhere;TA=K,P	10 ppm	1	lesSDRF v0.1.0	Naba-4-10x.raw	NT=gene knockdown;AC=OBI:0002625	NT=cell cycle arrest in mitotic G1 phase;AC=FYPO:0000445
"""#

    private static let captionTestAudioFixtureBase64: String = [
        "AAAAHGZ0eXBNNEEgAAAAAE00QSBtcDQyaXNvbQAABBptb292AAAAbG12aGQAAAAA5op1z+aKdc8AAFYiAADMAAABAAABAAAA",
        "AAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAC",
        "AAACrHRyYWsAAABcdGtoZAAAAAfminXP5op1zwAAAAEAAAAAAADMAAAAAAAAAAAAAAAAAAEAAAAAAQAAAAAAAAAAAAAAAAAA",
        "AAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAkhtZGlhAAAAIG1kaGQAAAAA5op1z+aKdc8AAFYiAADMAAAAAAAAAAAi",
        "aGRscgAAAAAAAAAAc291bgAAAAAAAAAAAAAAAAAAAAAB/m1pbmYAAAAQc21oZAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAA",
        "AAAAAAABAAAADHVybCAAAAABAAABwnN0YmwAAAB2c3RzZAAAAAAAAAABAAAAZm1wNGEAAAAAAAAAAQAAAAAAAAAAAAIAEAAA",
        "AABWIgAAAAAAM2VzZHMAAAAAA4CAgCIAAAAEgICAFEAUABgAAACVWAAAfQAFgICAAhOIBoCAgAECAAAAD3NidGQAAAAASTE2",
        "AAAAGHN0dHMAAAAAAAAAAQAAADMAAAQAAAAAKHN0c2MAAAAAAAAAAgAAAAEAAAALAAAAAQAAAAUAAAAHAAAAAQAAAOBzdHN6",
        "AAAAAAAAAAAAAAAzAAAABAAAAMoAAADqAAABCwAAAO4AAAEHAAAA0wAAAP4AAADBAAAA9QAAAPEAAAC5AAAAtgAAAIEAAAEZ",
        "AAAAvwAAAM4AAAC6AAAAuQAAALAAAAFOAAAAyQAAAIUAAAFbAAABDwAAAU4AAAEmAAAAtAAAAIEAAAE7AAAAsAAAAJkAAADD",
        "AAAA2AAAAPcAAAEqAAAAhQAAAK8AAAB9AAAA+AAAALoAAACbAAAAlgAAAKEAAAExAAAAkQAAAJwAAACTAAAAlwAAAJEAAAA6",
        "AAAAJHN0Y28AAAAAAAAABQAAEAAAABkwAAAiAAAAK98AADQNAAAA+nVkdGEAAADybWV0YQAAAAAAAAAiaGRscgAAAAAAAAAA",
        "bWRpcmFwcGwAAAAAAAAAAAAAAAAAxGlsc3QAAAC8LS0tLQAAABxtZWFuAAAAAGNvbS5hcHBsZS5pVHVuZXMAAAAUbmFtZQAA",
        "AABpVHVuU01QQgAAAIRkYXRhAAAAAQAAAAAgMDAwMDAwMDAgMDAwMDA4NDAgMDAwMDAxQjcgMDAwMDAwMDAwMDAwQzIwOSAw",
        "MDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMCAwMDAwMDAwMAAA",
        "C8JmcmVlAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAChobWRhdADQQAcA9J/M",
        "Pzf4E2kjNE7Au/z4+jiWsf/XHBt7ZrW+EcP7/FsTgE23qCeIFy5DWTScaXbyWnqTix8YvANr8p50NKoNY6q6oT+mXq+n5xnG",
        "zgMU1aE2Xckk6r1f+3svceHdUUu4sQkCJuNBC8Xh69m60S75giaJz68LMgVgpsNjp6PZ6IZwpXDcqdCtNxWaW5y72BiCAQDL",
        "ppBHqJCz6Xqvbofi8gvhdFi3e0+7/8fQfK67429OvjvxIGjqa3JxnPkt9plaKgORcYCBNgA4ATKe+tNyZgsgNooxQmRiETbT",
        "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",
    ].joined()
}

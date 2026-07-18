
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

    @MainActor
    func testSignInAndCreateProtocolSyncsImmediately() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()

        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 5))
        serverURLField.tap()
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/")

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
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/")

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
        let jobName = "Edit Value Test Job \(Int(Date().timeIntervalSince1970))"
        let seed = try seedJobWithEditableColumnViaAPI(jobName: jobName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 30)

        findAndTapJobRow(named: jobName, in: app, timeout: 60)

        let createFromTemplateButtonForEdit = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButtonForEdit, in: app)
        XCTAssertTrue(createFromTemplateButtonForEdit.waitForExistence(timeout: 15), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButtonForEdit.tap()

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app)
        let templateSearchFieldForEdit = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForEdit.waitForExistence(timeout: 10))
        templateSearchFieldForEdit.tap()
        templateSearchFieldForEdit.typeText(seed.templateName)

        let templateRowForEdit = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRowForEdit.waitForExistence(timeout: 15), "The template created via the API should appear once synced and filtered by search")
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
        replaceText(in: valueField, with: newValue)

        let saveMetadataValueButton = app.buttons["saveMetadataValueButton"]
        XCTAssertTrue(saveMetadataValueButton.waitForExistence(timeout: 10))
        saveMetadataValueButton.tap()

        let errorAlert = app.alerts["Couldn't save value"]
        XCTAssertFalse(errorAlert.waitForExistence(timeout: 3), "Saving a metadata value against a reachable backend shouldn't show an error")

        let updatedValueElement = waitForMatch(NSPredicate(format: "label CONTAINS %@", newValue), in: app.staticTexts, timeout: 10)
        XCTAssertTrue(updatedValueElement.exists, "The updated value should appear in the column list after saving")
    }

    @MainActor
    func testModificationParametersColumnUnimodSpecificationSyncsLive() throws {
        let jobName = "Modification Test Job \(Int(Date().timeIntervalSince1970))"
        let seed = try seedJobWithModificationColumnViaAPI(jobName: jobName)

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 30)
        findAndTapJobRow(named: jobName, in: app, timeout: 60)

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 15), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButton.tap()

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app)
        let templateSearchField = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchField.waitForExistence(timeout: 10))
        templateSearchField.tap()
        templateSearchField.typeText(seed.templateName)

        let templateRow = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 15), "The template created via the API should appear once synced and filtered by search")
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

        let saveButton = app.buttons["saveMetadataValueButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let errorAlert = app.alerts["Couldn't save value"]
        XCTAssertFalse(errorAlert.waitForExistence(timeout: 3), "Saving a modification-parameters value against a reachable backend shouldn't show an error")

        let savedValueElement = waitForMatch(NSPredicate(format: "label CONTAINS %@", "NT=Phospho"), in: app.staticTexts, timeout: 10)
        XCTAssertTrue(savedValueElement.exists, "The saved NT=Phospho;AC=UNIMOD:21;...;TA=T,S;... value should appear in the column list after saving")
        XCTAssertTrue(savedValueElement.label.contains("TA=T,S"), "The saved value should include the applied specification's target amino acids")
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
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/")

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()

        tapTab("Jobs", in: app, timeout: 30)
        tapToolbarButton("manageMetadataTableTemplatesButton", label: "Table Templates", in: app, timeout: 10)

        let searchField = app.textFields.matching(identifier: "myTableTemplateSearchField").firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(templateName)

        let templateRow = app.buttons.matching(identifier: "myTableTemplateRow_\(templateName)").firstMatch
        XCTAssertTrue(templateRow.waitForExistence(timeout: 15), "The blank template created via the API should appear in the management list")
        Thread.sleep(forTimeInterval: 1)
        templateRow.tap()

        let editTemplateButtonForRename = app.buttons["editTableTemplateButton"]
        XCTAssertTrue(editTemplateButtonForRename.waitForExistence(timeout: 10), "The template preview should offer an Edit button")
        editTemplateButtonForRename.tap()

        let nameField = app.textFields["tableTemplateNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        let renamedName = templateName + " Renamed"
        nameField.tap()
        replaceText(in: nameField, with: renamedName)
        app.buttons["saveTableTemplateButton"].tap()

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let templatesBackButton = app.navigationBars.buttons["Templates"]
            XCTAssertTrue(templatesBackButton.waitForExistence(timeout: 5), "Should be back on the template detail page with a Templates back button after saving")
            templatesBackButton.tap()
        }
        #endif
        searchField.tap()
        replaceText(in: searchField, with: renamedName)
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

        tapTab("Protocols", in: app, timeout: 30)
        #if os(macOS)
        app.typeKey(",", modifierFlags: .command)
        #else
        tapToolbarButton("settingsButton", label: "Settings", in: app)
        #endif
        XCTAssertTrue(waitForTextAppearing("Offline Ontology Data", in: app, timeout: 10))
        elementContaining("Offline Ontology Data", in: app).tap()
        let schemaImportButton = app.buttons["importOntologyButton_sdrf"]
        scrollDownUntilVisible(schemaImportButton, in: app)
        XCTAssertTrue(schemaImportButton.waitForExistence(timeout: 15))
        schemaImportButton.tap()
        XCTAssertTrue(
            waitForTextAppearing("Imported", in: app, timeout: 120),
            "The sdrf schema dataset should finish importing and show its \"Imported\" timestamp"
        )
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        tapToolbarButton("doneButton", label: "Done", in: app, timeout: 3)
        #endif

        tapTab("Jobs", in: app, timeout: 30)
        tapToolbarButton("newJobButton", label: "New Job", in: app, timeout: 10)
        let jobName = "Template Flow Job \(timestamp)"
        let jobNameField = app.textFields["newJobNameField"]
        XCTAssertTrue(jobNameField.waitForExistence(timeout: 5))
        jobNameField.tap()
        jobNameField.typeText(jobName)
        app.buttons["createJobButton"].tap()

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
            jobsBackButtonBeforeTemplates.tap()
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

        replaceText(in: schemaSearchField, with: "human")
        let humanRow = app.buttons["schemaRow_human"]
        XCTAssertTrue(humanRow.waitForExistence(timeout: 10), "human should be selectable since the sdrf dataset was just imported")
        humanRow.tap()

        app.buttons["createTemplateButton"].tap()

        #if os(macOS)
        closeWindow(matching: "table-template-manager", in: app)
        #else
        Thread.sleep(forTimeInterval: 1.0)
        dismissTableTemplateManagementSheet(in: app)
        if UIDevice.current.userInterfaceIdiom == .phone {
            findAndTapJobRow(named: jobName, in: app)
        }
        #endif

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 15))
        createFromTemplateButton.tap()

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app)
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
        XCTAssertTrue(addMetadataColumnButton.waitForExistence(timeout: 15), "The Metadata Table section should appear once created")

        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            let jobsBackButtonBeforeSecondTemplatesVisit = app.navigationBars.buttons["Jobs"]
            XCTAssertTrue(jobsBackButtonBeforeSecondTemplatesVisit.waitForExistence(timeout: 5), "Should be back on the job detail page with a Jobs back button before reaching list-level Table Templates management a second time")
            jobsBackButtonBeforeSecondTemplatesVisit.tap()
        }
        #endif
        tapToolbarButton("manageMetadataTableTemplatesButton", label: "Table Templates", in: app, timeout: 10)
        let managementSearchField = app.textFields.matching(identifier: "myTableTemplateSearchField").firstMatch
        XCTAssertTrue(managementSearchField.waitForExistence(timeout: 10))
        managementSearchField.tap()
        managementSearchField.typeText(tableTemplateName)

        let tableTemplateRow = app.buttons.matching(identifier: "myTableTemplateRow_\(tableTemplateName)").firstMatch
        XCTAssertTrue(tableTemplateRow.waitForExistence(timeout: 15), "The newly-created table template should appear in the management list")
        XCTAssertFalse(tableTemplateRow.label.contains("0 columns"), "Combining ms-proteomics + human should produce real columns, not an empty (Blank-equivalent) template: \(tableTemplateRow.label)")
        tableTemplateRow.tap()

        let editTemplateButton = app.buttons["editTableTemplateButton"]
        XCTAssertTrue(editTemplateButton.waitForExistence(timeout: 10), "The template preview should offer an Edit button")
        editTemplateButton.tap()

        let column1Name = "characteristics[flow test a]"
        let addTemplateColumnButton = app.buttons["addTemplateColumnButton"]
        scrollDownUntilVisible(addTemplateColumnButton, within: "templateColumnsForm", in: app, maxAttempts: 40)
        addTemplateColumnButton.tap()
        let addColumnNameField = app.textFields["addTemplateColumnNameField"]
        XCTAssertTrue(addColumnNameField.waitForExistence(timeout: 5))
        addColumnNameField.tap()
        addColumnNameField.typeText(column1Name)
        app.buttons["confirmAddTemplateColumnButton"].tap()
        XCTAssertTrue(app.buttons["templateColumnRow_\(column1Name)"].waitForExistence(timeout: 10), "The first added column should appear")

        let column2Name = "characteristics[flow test b]"
        scrollDownUntilVisible(addTemplateColumnButton, within: "templateColumnsForm", in: app, maxAttempts: 40)
        addTemplateColumnButton.tap()
        let addColumnNameField2 = app.textFields["addTemplateColumnNameField"]
        XCTAssertTrue(addColumnNameField2.waitForExistence(timeout: 5))
        addColumnNameField2.tap()
        addColumnNameField2.typeText(column2Name)
        app.buttons["confirmAddTemplateColumnButton"].tap()
        XCTAssertTrue(app.buttons["templateColumnRow_\(column2Name)"].waitForExistence(timeout: 10), "The second added column should appear")

        let templateNameField = app.textFields["tableTemplateNameField"]
        let selectModeButton = app.buttons["templateColumnSelectModeButton"]
        scrollUpUntilVisible(selectModeButton, orAtTop: templateNameField, within: "templateColumnsForm", in: app, maxAttempts: 15)
        selectModeButton.tap()
        let column1Row = app.buttons["templateColumnRow_\(column1Name)"]
        scrollDownUntilVisible(column1Row, within: "templateColumnsForm", in: app, maxAttempts: 40)
        column1Row.tap()
        let column2Row = app.buttons["templateColumnRow_\(column2Name)"]
        scrollDownUntilVisible(column2Row, within: "templateColumnsForm", in: app, maxAttempts: 40)
        column2Row.tap()
        let bulkStaffOnlyButton = app.buttons["templateColumnBulkStaffOnlyButton"]
        scrollUpUntilVisible(bulkStaffOnlyButton, orAtTop: templateNameField, within: "templateColumnsForm", in: app, maxAttempts: 15)
        bulkStaffOnlyButton.tap()
        XCTAssertFalse(app.alerts["Couldn't save template"].waitForExistence(timeout: 3), "Bulk staff-only update against a reachable backend shouldn't show an error")
        Thread.sleep(forTimeInterval: 3.0)

        scrollUpUntilVisible(selectModeButton, orAtTop: templateNameField, within: "templateColumnsForm", in: app, maxAttempts: 15)
        if selectModeButton.label == "Select" {
            selectModeButton.tap()
        }
        scrollDownUntilVisible(column1Row, within: "templateColumnsForm", in: app, maxAttempts: 40)
        column1Row.tap()
        scrollDownUntilVisible(column2Row, within: "templateColumnsForm", in: app, maxAttempts: 40)
        column2Row.tap()
        let bulkDeleteButton = app.buttons["templateColumnBulkDeleteButton"]
        scrollUpUntilVisible(bulkDeleteButton, orAtTop: templateNameField, within: "templateColumnsForm", in: app, maxAttempts: 15)
        bulkDeleteButton.tap()
        XCTAssertFalse(app.buttons["templateColumnRow_\(column1Name)"].waitForExistence(timeout: 5), "Bulk-deleted columns should no longer appear")
        scrollUpUntilVisible(selectModeButton, orAtTop: templateNameField, within: "templateColumnsForm", in: app, maxAttempts: 15)
        selectModeButton.tap()

        scrollDownUntilVisible(addTemplateColumnButton, within: "templateColumnsForm", in: app, maxAttempts: 40)
        addTemplateColumnButton.tap()
        let seedColumnNameField = app.textFields["addTemplateColumnNameField"]
        XCTAssertTrue(seedColumnNameField.waitForExistence(timeout: 5))
        seedColumnNameField.tap()
        seedColumnNameField.typeText("characteristics[flow seed col]")
        app.buttons["confirmAddTemplateColumnButton"].tap()
        XCTAssertTrue(app.buttons["templateColumnRow_characteristics[flow seed col]"].waitForExistence(timeout: 10))

        app.buttons["saveTableTemplateButton"].tap()
        #if os(macOS)
        closeWindow(matching: "table-template-manager", in: app)
        #else
        Thread.sleep(forTimeInterval: 1.0)
        dismissTableTemplateManagementSheet(in: app)
        if UIDevice.current.userInterfaceIdiom == .phone {
            findAndTapJobRow(named: jobName, in: app)
        }
        #endif
        let addMetadataColumnButtonAgain = app.buttons["addMetadataColumnButton"]
        scrollDownUntilVisible(addMetadataColumnButtonAgain, in: app)
        XCTAssertTrue(addMetadataColumnButtonAgain.waitForExistence(timeout: 10))
        addMetadataColumnButtonAgain.tap()
        app.buttons["manageColumnTemplatesButton"].tap()

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
        replaceText(in: columnTemplateNameField, with: columnTemplateName)
        columnTemplateNameField.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)

        let columnTemplateColumnNameField = app.textFields["columnTemplateColumnNameField"]
        replaceText(in: columnTemplateColumnNameField, with: "characteristics[flow column template]")
        columnTemplateColumnNameField.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)

        let tagsField = app.textFields["columnTemplateTagsField"]
        replaceText(in: tagsField, with: "flowtest, verify")
        tagsField.typeText("\n")
        Thread.sleep(forTimeInterval: 0.3)

        let defaultPositionField = app.textFields["columnTemplateDefaultPositionField"]
        replaceText(in: defaultPositionField, with: "2")

        app.buttons["saveColumnTemplateButton"].tap()

        let columnTemplateRow = app.buttons["myColumnTemplateRow_\(columnTemplateName)"]
        XCTAssertTrue(columnTemplateRow.waitForExistence(timeout: 15), "The newly-created column template should appear in the flat list")

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

        tapTab("Jobs", in: app, timeout: 30)
        findAndTapJobRow(named: jobName, in: app)

        let createFromTemplateButtonForGrid = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButtonForGrid, in: app)
        XCTAssertTrue(createFromTemplateButtonForGrid.waitForExistence(timeout: 15), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButtonForGrid.tap()

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app)
        let templateSearchFieldForGrid = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForGrid.waitForExistence(timeout: 10))
        templateSearchFieldForGrid.tap()
        templateSearchFieldForGrid.typeText(seed.templateName)

        let templateRowForGrid = app.buttons["metadataTemplateRow_\(seed.templateName)"]
        XCTAssertTrue(templateRowForGrid.waitForExistence(timeout: 15), "The template created via the API should appear once synced and filtered by search")
        templateRowForGrid.tap()

        let sampleCountFieldForGrid = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountFieldForGrid.waitForExistence(timeout: 5))
        sampleCountFieldForGrid.tap()
        sampleCountFieldForGrid.typeText("\(seed.sampleCount)")
        app.buttons["createMetadataTableButton"].tap()

        let openFullTableViewButton = app.buttons["openFullMetadataTableViewButton"]
        XCTAssertTrue(openFullTableViewButton.waitForExistence(timeout: 15))
        openFullTableViewButton.tap()

        tapSegment("List", within: "metadataTableViewModePicker", in: app)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", seed.column1Name)).firstMatch.waitForExistence(timeout: 10),
            "List mode should show the seeded columns"
        )

        tapSegment("Table", within: "metadataTableViewModePicker", in: app)
        let firstCell = app.buttons["metadataTableCell_\(seed.column1Name)_1"]
        XCTAssertTrue(firstCell.waitForExistence(timeout: 10), "Table mode should show a grid cell for sample 1")
        firstCell.tap()

        let valueField = firstExisting(app.textFields["metadataValueField"], app.textViews["metadataValueField"])
        XCTAssertTrue(valueField.waitForExistence(timeout: 5))
        valueField.tap()
        valueField.typeText("42.0")
        tapToolbarButton("saveMetadataValueButton", label: "Save", in: app)
        XCTAssertTrue(waitForTextAppearing("42.0", in: app, timeout: 15), "The edited cell value should appear once synced")

        tapSegment("List", within: "metadataTableViewModePicker", in: app)
        tapMenuItem("metadataTableColumnMenu_\(seed.column2Name)", item: "Autofill", in: app)

        let templateField = app.textFields["basicAutofillTemplateField"]
        XCTAssertTrue(templateField.waitForExistence(timeout: 5), "Basic mode should be selected by default")
        app.buttons["applyAutofillButton"].tap()
        XCTAssertTrue(app.alerts["Autofill Complete"].waitForExistence(timeout: 15), "Basic autofill against a reachable backend should report success")
        app.alerts["Autofill Complete"].buttons["OK"].tap()

        tapMenuItem("metadataTableColumnMenu_\(seed.column2Name)", item: "Autofill", in: app)
        tapSegment("Advanced", in: app)

        let templateSamplesField = app.textFields["advancedAutofillTemplateSamplesField"]
        XCTAssertTrue(templateSamplesField.waitForExistence(timeout: 5))
        templateSamplesField.tap()
        replaceText(in: templateSamplesField, with: "1")

        let targetCountField = app.textFields["advancedAutofillTargetSampleCountField"]
        targetCountField.tap()
        targetCountField.typeText("\(seed.sampleCount)")
        targetCountField.typeText("\n")
        Thread.sleep(forTimeInterval: 0.5)

        let addVariationButton = app.buttons["addAutofillVariationButton"]
        scrollDownUntilVisible(addVariationButton, in: app)
        Thread.sleep(forTimeInterval: 0.5)
        addVariationButton.tap()
        selectPickerOption("autofillVariationColumnPicker_0", option: seed.column1Name, in: app)
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
        XCTAssertTrue(app.alerts["Autofill Complete"].waitForExistence(timeout: 15), "Advanced autofill against a reachable backend should report success")
        app.alerts["Autofill Complete"].buttons["OK"].tap()
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
            jobsBackButton.tap()
        }
        #endif
        tapToolbarButton("metadataTablesBrowserButton", label: "Metadata Tables", in: app)

        let searchField = app.textFields["metadataTablesBrowserSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 10))
        searchField.tap()
        searchField.typeText(browserTableName)
        searchField.typeText("\n")

        let browserTableRow = app.buttons["metadataTableRow_\(browserTableName)"]
        XCTAssertTrue(browserTableRow.waitForExistence(timeout: 15), "The ccv-native standalone table should appear in the browser, unlike a job-created (ccm-owned) table")

        browserTableRow.swipeRight()
        let editSwipeAction = app.buttons["Edit"]
        XCTAssertTrue(editSwipeAction.waitForExistence(timeout: 5), "The row's leading Edit swipe action should appear")
        editSwipeAction.tap()

        let sampleCountField = app.textFields["metadataTableEditSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        replaceText(in: sampleCountField, with: "1")
        app.buttons["saveMetadataTableEditButton"].tap()

        XCTAssertTrue(app.alerts["Reduce Sample Count?"].waitForExistence(timeout: 10), "Reducing an already-populated sample count should ask for confirmation, not silently apply")
        app.buttons["confirmSampleCountReductionButton"].tap()
        XCTAssertFalse(app.alerts["Couldn't save table"].waitForExistence(timeout: 5), "Confirming the reduction should let the save go through")
    }

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
        XCTAssertTrue(waitForTextAppearing("Mix reagents", in: app, timeout: 10))

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

        app.buttons["bookingAnnotationInstrumentRow_Test Centrifuge"].tap()

        let bookingDescField = app.textFields["bookingAnnotationDescriptionField"]
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

        let timeKeeperID = try findTimeKeeperIDViaAPI(sessionID: seed.sessionID, stepID: seed.stepID, deviceToken: seed.deviceToken)
        try postJSON("time-keepers/\(timeKeeperID)/stop_timer/", body: [:], deviceToken: seed.deviceToken)

        let resumeButton = app.buttons["startStepTimerButton"].firstMatch
        XCTAssertTrue(resumeButton.waitForExistence(timeout: 15), "Stopping the timer from another \"device\" should push a live update back to this view with no local interaction")
    }

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

        findAndTapJobRow(named: jobName, in: app)

        let labGroupSearchFieldForPool = app.textFields["jobLabGroupSearchField"]
        XCTAssertTrue(labGroupSearchFieldForPool.waitForExistence(timeout: 10))
        labGroupSearchFieldForPool.tap()
        labGroupSearchFieldForPool.typeText("Test Lab Group")
        app.buttons["jobLabGroupRow_Test Lab Group"].tap()

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 15), "Creating a metadata table should become available once a lab group is assigned")
        createFromTemplateButton.tap()

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app)
        let templateSearchFieldForPool = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForPool.waitForExistence(timeout: 10))
        templateSearchFieldForPool.tap()
        templateSearchFieldForPool.typeText(templateName)

        let templateRow = app.buttons["metadataTemplateRow_\(templateName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 15), "The template created via the API should appear once synced and filtered by search")
        templateRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("5")

        app.buttons["createMetadataTableButton"].tap()

        let newPoolButton = app.buttons["newSamplePoolButton"]
        scrollDownUntilVisible(newPoolButton, in: app)
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

        tapTab("Inventory", in: app, timeout: 30)
        tapSegment("Instruments", in: app)

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

        let instrumentRow = waitForMatchAcrossTypes(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", instrumentName, instrumentName), in: app, timeout: 30)
        XCTAssertTrue(instrumentRow.exists, "The newly-created instrument should appear once synced")
        instrumentRow.tap()

        let addInstrumentMetadataButton = app.buttons["addMetadataColumnButton"]
        XCTAssertTrue(addInstrumentMetadataButton.waitForExistence(timeout: 15), "The Metadata section should appear once the instrument's auto-created metadata table syncs")
        addInstrumentMetadataButton.tap()

        let templateSearchField = app.textFields["addColumnSearchField"]
        XCTAssertTrue(templateSearchField.waitForExistence(timeout: 5))
        templateSearchField.tap()
        templateSearchField.typeText(templateName)

        let templateRow = app.buttons["addColumnGroupRow_\(columnName)"]
        XCTAssertTrue(templateRow.waitForExistence(timeout: 10), "The already-seeded \"salinity\" column template should appear in the search results")

        let instrumentFieldRow = app.buttons["metadataColumnRow_\(columnName)"]
        for _ in 0..<3 {
            guard templateRow.exists else { break }
            templateRow.tap()
            if instrumentFieldRow.waitForExistence(timeout: 5) { break }
        }
        XCTAssertTrue(instrumentFieldRow.waitForExistence(timeout: 15), "The newly-added metadata field should appear once synced")
        instrumentFieldRow.tap()

        let instrumentValueField = firstExisting(app.textFields["metadataValueField"], app.textViews["metadataValueField"])
        XCTAssertTrue(instrumentValueField.waitForExistence(timeout: 5))
        instrumentValueField.tap()
        instrumentValueField.typeText("42.5")
        tapToolbarButton("saveMetadataValueButton", label: "Save", in: app)

        XCTAssertTrue(waitForTextAppearing("42.5", in: app, timeout: 15), "The edited metadata value should appear once synced")

        tapTab("Inventory", in: app, timeout: 15)
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
        XCTAssertTrue(locationRow.waitForExistence(timeout: 15), "The newly-created location should appear once synced")
        locationRow.tap()

        tapMenuItem("storageAddMenu", item: "Add Reagent", in: app)
        let reagentName = "Live Metadata Reagent \(timestamp)"
        let reagentNameField = app.textFields["newStoredReagentNameField"]
        XCTAssertTrue(reagentNameField.waitForExistence(timeout: 5))
        reagentNameField.tap()
        reagentNameField.typeText(reagentName)
        selectPickerOption("newStoredReagentUnitPicker", option: "g", in: app)
        let reagentQuantityField = app.textFields["newStoredReagentQuantityField"]
        reagentQuantityField.tap()
        reagentQuantityField.typeText("100")
        app.buttons["saveStoredReagentButton"].tap()

        let reagentSearchField = app.textFields["reagentSearchField"]
        XCTAssertTrue(reagentSearchField.waitForExistence(timeout: 10))
        reagentSearchField.tap()
        reagentSearchField.typeText(reagentName)

        let reagentRow = app.buttons["storedReagentRow_\(reagentName)"]
        XCTAssertTrue(reagentRow.waitForExistence(timeout: 15), "The newly-added reagent should appear once synced")
        reagentRow.tap()

        let addReagentMetadataButton = app.buttons["addMetadataColumnButton"]
        XCTAssertTrue(addReagentMetadataButton.waitForExistence(timeout: 15), "The Metadata section should appear once the reagent's auto-created metadata table syncs")
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
        XCTAssertTrue(reagentFieldRow.waitForExistence(timeout: 15), "The newly-added metadata field should appear on the stored reagent once synced")
    }

    @MainActor
    func testMetadataTemplatePickerTiersAndTableEditor() throws {
        let seed = try seedTemplatePickerTierData()

        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-reset-state"]
        app.launch()
        signIn(app)

        tapTab("Jobs", in: app, timeout: 30)

        findAndTapJobRow(named: seed.jobName, in: app)

        let createFromTemplateButton = app.buttons["createMetadataFromTemplateButton"]
        scrollDownUntilVisible(createFromTemplateButton, in: app)
        XCTAssertTrue(createFromTemplateButton.waitForExistence(timeout: 15))
        createFromTemplateButton.tap()

        let templateSearchFieldForTiers = app.textFields["templateSearchField"]
        XCTAssertTrue(templateSearchFieldForTiers.waitForExistence(timeout: 10))

        selectPickerOption("templateCategoryFilterPicker", option: "Personal", in: app)
        templateSearchFieldForTiers.tap()
        templateSearchFieldForTiers.typeText(seed.personalTemplateName)
        let personalRow = app.buttons["metadataTemplateRow_\(seed.personalTemplateName)"]
        XCTAssertTrue(personalRow.waitForExistence(timeout: 10), "The personal template should be listed under the Personal category")

        replaceText(in: templateSearchFieldForTiers, with: seed.jobGroupTemplateName)
        selectPickerOption("templateCategoryFilterPicker", option: "Job's Lab Group", in: app)
        XCTAssertTrue(app.buttons["metadataTemplateRow_\(seed.jobGroupTemplateName)"].waitForExistence(timeout: 10), "The job's own lab-group template should be listed under Job's Lab Group")

        replaceText(in: templateSearchFieldForTiers, with: seed.otherGroupTemplateName)
        selectPickerOption("templateCategoryFilterPicker", option: "Shared With Me", in: app)
        XCTAssertTrue(app.buttons["metadataTemplateRow_\(seed.otherGroupTemplateName)"].waitForExistence(timeout: 10), "The other lab group's template should be listed under Shared With Me")

        selectPickerOption("templateCategoryFilterPicker", option: "All", in: app)
        replaceText(in: templateSearchFieldForTiers, with: seed.personalTemplateName)
        XCTAssertTrue(personalRow.waitForExistence(timeout: 10))
        personalRow.tap()

        let sampleCountField = app.textFields["metadataSampleCountField"]
        XCTAssertTrue(sampleCountField.waitForExistence(timeout: 5))
        sampleCountField.tap()
        sampleCountField.typeText("5")

        app.buttons["createMetadataTableButton"].tap()

        let firstColumnRow = app.buttons["metadataColumnRow_\(seed.firstColumnName)"]
        XCTAssertTrue(firstColumnRow.waitForExistence(timeout: 15), "The metadata table's first column should render")

        let firstGridCell = app.buttons["metadataCell_\(seed.firstColumnName)_1"]
        XCTAssertTrue(firstGridCell.waitForExistence(timeout: 10), "The per-sample grid should render a cell for sample 1")

    }

    @MainActor
    private func signIn(_ app: XCUIApplication) {
        let serverURLField = app.textFields["serverURLField"]
        XCTAssertTrue(serverURLField.waitForExistence(timeout: 5))
        serverURLField.tap()
        replaceText(in: serverURLField, with: "http://127.0.0.1:8002/api/v1/")

        let usernameField = app.textFields["usernameField"]
        usernameField.tap()
        usernameField.typeText("testuser")

        let passwordField = app.secureTextFields["passwordField"]
        passwordField.tap()
        passwordField.typeText("testuser123")

        app.buttons["signInButton"].tap()
    }

    @MainActor
    private func selectPickerOption(_ identifier: String, option: String, in app: XCUIApplication) {
        let picker = firstExisting(app.popUpButtons[identifier], app.buttons[identifier], app.otherElements[identifier])
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Picker \"\(identifier)\" not found")
        picker.tap()

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

    private func scrollDownUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxAttempts: Int = 15) {
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxAttempts {
            app.swipeUp(velocity: .fast)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func scrollDownUntilVisible(_ element: XCUIElement, within containerIdentifier: String, in app: XCUIApplication, maxAttempts: Int = 15) {
        func container() -> XCUIElement {
            firstExisting(app.collectionViews[containerIdentifier], app.tables[containerIdentifier], app.otherElements[containerIdentifier], app.scrollViews[containerIdentifier])
        }
        var attempts = 0
        while !(element.exists && element.isHittable), attempts < maxAttempts {
            container().swipeUp(velocity: .fast)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.3)
        }
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
        var attempts = 0
        while !element.exists, attempts < maxAttempts {
            container().swipeDown(velocity: .fast)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func scrollUpUntilVisible(_ element: XCUIElement, orAtTop topAnchor: XCUIElement, within containerIdentifier: String, in app: XCUIApplication, maxAttempts: Int = 15) {
        func container() -> XCUIElement {
            firstExisting(app.collectionViews[containerIdentifier], app.tables[containerIdentifier], app.otherElements[containerIdentifier], app.scrollViews[containerIdentifier])
        }
        var attempts = 0
        while !element.exists, !topAnchor.exists, attempts < maxAttempts {
            container().swipeDown(velocity: .fast)
            attempts += 1
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func findAndTapJobRow(named jobName: String, in app: XCUIApplication, timeout: TimeInterval = 30) {
        let searchField = app.textFields["jobSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: timeout))
        searchField.tap()
        replaceText(in: searchField, with: jobName)

        let jobRow = waitForMatchAcrossTypes(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", jobName, jobName), in: app, timeout: timeout)
        XCTAssertTrue(jobRow.exists, "The job \"\(jobName)\" should appear once filtered by name")
        jobRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func closeWindow(matching identifierSubstring: String, in app: XCUIApplication, timeout: TimeInterval = 10) {
        #if os(macOS)
        let window = app.windows.matching(NSPredicate(format: "identifier CONTAINS %@", identifierSubstring)).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: timeout), "Expected a window matching \"\(identifierSubstring)\" to close")
        let closeButton = window.buttons["_XCUI:CloseWindow"]
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
        }
        let deadline = Date().addingTimeInterval(timeout)
        while window.exists, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.3)
        }
        if window.exists {
            app.typeKey("w", modifierFlags: .command)
            let fallbackDeadline = Date().addingTimeInterval(5)
            while window.exists, Date() < fallbackDeadline {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        XCTAssertFalse(window.exists, "Window matching \"\(identifierSubstring)\" should have closed")
        #endif
    }

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

    private func tapSegment(_ label: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let segment = firstExisting(app.radioButtons[label], app.buttons[label])
        XCTAssertTrue(segment.waitForExistence(timeout: timeout), "\"\(label)\" segment not found")
        segment.tap()
    }

    private func tapSegment(_ label: String, within pickerIdentifier: String, in app: XCUIApplication, timeout: TimeInterval = 5) {
        let picker = firstExisting(app.segmentedControls[pickerIdentifier], app.otherElements[pickerIdentifier])
        XCTAssertTrue(picker.waitForExistence(timeout: timeout), "\"\(pickerIdentifier)\" segmented control not found")
        let segment = firstExisting(picker.radioButtons[label], picker.buttons[label])
        XCTAssertTrue(segment.waitForExistence(timeout: timeout), "\"\(label)\" segment not found within \"\(pickerIdentifier)\"")
        segment.tap()
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

    private func replaceText(in field: XCUIElement, with newText: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        for _ in 0..<3 {
            field.typeKey("a", modifierFlags: .command)
            field.typeKey("v", modifierFlags: .command)
            if field.value as? String == newText { return }
            field.tap()
        }
        XCTAssertEqual(field.value as? String, newText, "Failed to replace field text after multiple attempts")
        #else
        field.tap()
        for _ in 0..<3 {
            if field.value as? String == newText { return }
            field.typeKey("a", modifierFlags: .command)
            field.typeText(newText)
            if field.value as? String == newText { return }
            field.tap()
        }
        XCTAssertEqual(field.value as? String, newText, "Failed to replace field text after multiple attempts")
        #endif
    }

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

    private func dismissTableTemplateManagementSheet(in app: XCUIApplication, maxAttempts: Int = 3) {
        let backToTemplatesButton = app.buttons["Templates"]
        if backToTemplatesButton.waitForExistence(timeout: 3) {
            backToTemplatesButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        let stillOpenMarker = app.buttons["newMetadataTableTemplateButton"]
        for _ in 0..<maxAttempts {
            tapToolbarButton("doneButton", label: "Done", in: app, timeout: 3)
            Thread.sleep(forTimeInterval: 0.5)
            if !stillOpenMarker.exists {
                return
            }
        }
        XCTFail("Table Template Management sheet did not dismiss after \(maxAttempts) attempts at \"doneButton\"")
    }

    private func elementContaining(_ substring: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        let staticText = app.staticTexts.matching(predicate).firstMatch
        let button = app.buttons.matching(predicate).firstMatch
        return staticText.exists ? staticText : button
    }

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

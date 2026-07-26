import CupcakeModels
import CupcakeNetworking
import CupcakeOntology
import CupcakeSync
import SwiftData
import SwiftUI

enum UnimodMapping {
    private static let knownPositions = ["Anywhere", "Protein N-term", "Protein C-term", "Any N-term", "Any C-term"]
    private static let classificationToModificationType: [String: String] = [
        "Post-translational": "Variable",
        "Chemical derivatization": "Fixed",
        "Artefact": "Variable",
        "Pre-translational": "Fixed",
        "Multiple": "Variable",
        "Other": "Variable",
    ]

    static func position(from unimodPosition: String) -> String {
        knownPositions.contains(unimodPosition) ? unimodPosition : "Anywhere"
    }

    static func modificationType(from classification: String) -> String? {
        classificationToModificationType[classification]
    }
}

struct MetadataCellEditTarget: Identifiable {
    let column: CachedMetadataColumn
    let sampleIndex: Int?
    var id: String { "\(column.serverID)_\(sampleIndex.map(String.init) ?? "default")" }
}

struct MetadataValueEditWindowID: Codable, Hashable {
    let columnServerID: Int64
    let sampleIndex: Int?
    let projectServerID: Int64?
}

struct MetadataValueEditWindowContent: View {
    let windowID: MetadataValueEditWindowID?
    let ontologyStore: ModelContainer

    @Query private var columns: [CachedMetadataColumn]

    private var column: CachedMetadataColumn? {
        guard let windowID else { return nil }
        return columns.first { $0.serverID == windowID.columnServerID }
    }

    var body: some View {
        if let windowID, let column {
            MetadataValueEditSheet(column: column, sampleIndex: windowID.sampleIndex, projectServerID: windowID.projectServerID, ontologyStore: ontologyStore)
        } else {
            ContentUnavailableView("Column Not Found", systemImage: "questionmark.square.dashed")
        }
    }
}

struct MetadataValueEditSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Query private var labGroups: [CachedLabGroup]

    let column: CachedMetadataColumn
    let sampleIndex: Int?
    let projectServerID: Int64?
    let ontologyStore: ModelContainer

    @State private var value: String
    @State private var suggestions: [OntologySuggestionDTO] = []
    @State private var matchType: OntologyMatchType = .contains
    @State private var searchTask: Task<Void, Never>?
    @State private var personalFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var labGroupFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var globalFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var selectedFavouriteScope: FavouriteScope = .personal
    @State private var favouriteSearchText = ""
    @State private var favouriteDisplayNameOverride = ""
    @State private var projectHistoryValues: [String] = []
    @State private var keyValueFields: [String: String] = [:]
    @State private var ageYears = ""
    @State private var ageMonths = ""
    @State private var ageDays = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingFavouritesManagementSheet = false
    @State private var offlineOntologyType: String?
    @State private var offlineCustomFilters: [String: [String: String]]?
    @State private var availableSpecifications: [(key: String, spec: [String: String])] = []

    private let specialSyntaxType: SDRFSpecialSyntaxType?

    init(column: CachedMetadataColumn, sampleIndex: Int? = nil, projectServerID: Int64?, ontologyStore: ModelContainer) {
        self.column = column
        self.sampleIndex = sampleIndex
        self.projectServerID = projectServerID
        self.ontologyStore = ontologyStore
        let initialValue: String
        if let sampleIndex {
            let modifierValue = column.modifiers.first { SampleIndexTextParser.parse($0.samples).contains(sampleIndex) }?.value
            initialValue = modifierValue ?? column.value ?? ""
        } else {
            initialValue = column.value ?? ""
        }
        _value = State(initialValue: initialValue)
        let syntaxType = SDRFSyntaxDetector.detect(columnName: column.name, columnType: column.type)
        specialSyntaxType = syntaxType
        switch syntaxType {
        case .modification:
            _keyValueFields = State(initialValue: SDRFKeyValueSyntax.parse(initialValue, allowedKeys: SDRFModificationKeys.order))
        case .cleavage:
            _keyValueFields = State(initialValue: SDRFKeyValueSyntax.parse(initialValue, allowedKeys: SDRFCleavageKeys.order))
        case .spikedCompound:
            _keyValueFields = State(initialValue: SDRFKeyValueSyntax.parse(initialValue, allowedKeys: SDRFSpikedCompoundKeys.order))
        case .age:
            if let parsed = SDRFAgeSyntax.parse(initialValue) {
                _ageYears = State(initialValue: parsed.years)
                _ageMonths = State(initialValue: parsed.months)
                _ageDays = State(initialValue: parsed.days)
            }
        case nil:
            break
        }
    }

    private var resolvedOntologyType: String? {
        column.ontologyType ?? offlineOntologyType
    }

    private var hasOntologyType: Bool {
        resolvedOntologyType != nil && !column.readonly && (specialSyntaxType == nil || specialSyntaxType == .modification)
    }

    private var firstLabGroupServerID: Int64? {
        labGroups.first?.serverID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(column.displayName ?? column.name) {
                    switch specialSyntaxType {
                    case .modification:
                        SDRFKeyValueInputView(fieldSpecs: SDRFModificationFieldSpecs.all, fields: $keyValueFields) { key, newValue in
                            if key == "NT" {
                                scheduleSearch(text: newValue)
                            }
                        }
                    case .cleavage:
                        SDRFKeyValueInputView(fieldSpecs: SDRFCleavageFieldSpecs.all, fields: $keyValueFields)
                    case .spikedCompound:
                        SDRFKeyValueInputView(fieldSpecs: SDRFSpikedCompoundFieldSpecs.all, fields: $keyValueFields)
                    case .age:
                        SDRFAgeInputView(years: $ageYears, months: $ageMonths, days: $ageDays)
                    case nil:
                        TextField("Value", text: $value)
                            .accessibilityIdentifier("metadataValueField")
                            .onChange(of: value) {
                                scheduleSearch(text: value)
                            }
                        if hasOntologyType {
                            Picker("Match", selection: $matchType) {
                                ForEach(OntologyMatchType.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("metadataValueMatchTypePicker")
                            .onChange(of: matchType) {
                                scheduleSearch(text: value)
                            }
                        }
                        HStack {
                            Button("Not Applicable") { value = "not applicable" }
                                .accessibilityIdentifier("metadataValueNotApplicableButton")
                            Spacer()
                            Button("Not Available") { value = "not available" }
                                .accessibilityIdentifier("metadataValueNotAvailableButton")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
                if hasOntologyType, !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions) { suggestion in
                            Button {
                                selectSuggestion(suggestion)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(suggestion.displayName)
                                    if let description = suggestion.description, !description.isEmpty, description != suggestion.displayName {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("ontologySuggestionRow_\(suggestion.displayName)")
                        }
                    }
                }
                if specialSyntaxType == .modification, !availableSpecifications.isEmpty {
                    Section("Specifications") {
                        ForEach(availableSpecifications, id: \.key) { entry in
                            Button {
                                applySpecification(entry.spec)
                            } label: {
                                Text(specificationSummary(entry.spec))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("specificationRow_\(entry.key)")
                        }
                    }
                }
                if !column.readonly {
                    Section("Favourites") {
                        Picker("Category", selection: $selectedFavouriteScope) {
                            ForEach(FavouriteScope.allCases, id: \.self) { scope in
                                Text(scope.label).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("favouriteScopePicker")
                        .onChange(of: selectedFavouriteScope) { favouriteSearchText = "" }
                        if favourites(for: selectedFavouriteScope).count > 5 {
                            TextField("Filter", text: $favouriteSearchText)
                                .accessibilityIdentifier("favouriteSearchField")
                        }
                        favouritesList(for: selectedFavouriteScope)
                    }
                    Button("Manage My Favourites…") {
                        if PlatformWindowPreference.prefersSeparateWindow {
                            PlatformWindowPreference.openOrFocusWindow(id: "favourites-manager", using: openWindow)
                        } else {
                            isShowingFavouritesManagementSheet = true
                        }
                    }
                    .accessibilityIdentifier("manageFavouritesButton")
                }
                if !projectHistoryValues.isEmpty {
                    Section("Project History") {
                        ForEach(projectHistoryValues, id: \.self) { historyValue in
                            Button {
                                value = historyValue
                            } label: {
                                Text(historyValue)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(sampleIndex.map { "Edit Value, Sample \($0)" } ?? "Edit Value")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { closeEditor() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || column.readonly)
                    .accessibilityIdentifier("saveMetadataValueButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .alert("Couldn't save value", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            loadOfflineOntologyConfig()
            await loadFavourites()
            await loadProjectHistory()
        }
        .sheet(isPresented: $isShowingFavouritesManagementSheet, onDismiss: {
            Task { await loadFavourites() }
        }) {
            NavigationStack {
                FavouritesManagementSheet()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { isShowingFavouritesManagementSheet = false }
                        }
                    }
            }
            .frame(minWidth: 380, minHeight: 440)
        }
    }

    private func loadOfflineOntologyConfig() {
        guard column.ontologyType == nil, specialSyntaxType == nil || specialSyntaxType == .modification else { return }
        let context = ModelContext(ontologyStore)
        let columnName = column.name
        guard let template = try? context.fetch(
            FetchDescriptor<CachedColumnTemplate>(predicate: #Predicate { $0.columnName == columnName })
        ).first, let ontologyType = template.ontologyType else { return }

        offlineOntologyType = ontologyType
        if let filtersJSON = template.customOntologyFilters, let data = filtersJSON.data(using: .utf8) {
            offlineCustomFilters = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        }
    }

    private func favourites(for scope: FavouriteScope) -> [FavouriteMetadataOptionDTO] {
        switch scope {
        case .personal: personalFavourites
        case .labGroup: labGroupFavourites
        case .global: globalFavourites
        }
    }

    @ViewBuilder
    private func favouritesList(for scope: FavouriteScope) -> some View {
        let allItems = favourites(for: scope)
        let items = favouriteSearchText.isEmpty
            ? allItems
            : allItems.filter { ($0.displayValue ?? $0.value ?? "").localizedCaseInsensitiveContains(favouriteSearchText) }
        if allItems.isEmpty {
            Text("None yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if items.isEmpty {
            Text("No matches for \"\(favouriteSearchText)\"")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(items) { favourite in
                Button {
                    value = favourite.displayValue ?? favourite.value ?? ""
                } label: {
                    Text(favourite.displayValue ?? favourite.value ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        TextField("Display Name (optional)", text: $favouriteDisplayNameOverride)
            .font(.caption)
            .accessibilityIdentifier("favouriteDisplayNameField")
        Button("Add Current Value to \(scope.label)") {
            Task { await addToFavourites(scope: scope) }
        }
        .font(.caption)
        .disabled(scope == .labGroup && firstLabGroupServerID == nil)
        .accessibilityIdentifier("addFavourite_\(scope.label)")
    }

    private enum FavouriteScope: CaseIterable, Hashable {
        case personal
        case labGroup
        case global

        var label: String {
            switch self {
            case .personal: "Personal"
            case .labGroup: "Lab Group"
            case .global: "Global"
            }
        }
    }

    private func loadFavourites() async {
        let services = appSession.makeSyncServices()
        let columnName = column.name
        let userID = appSession.currentUserID
        let labGroupID = firstLabGroupServerID

        async let personal: [FavouriteMetadataOptionDTO] = fetchOrEmpty {
            guard let userID else { return [] }
            return try await services.favouriteMetadataOptionSync.fetchPersonalFavourites(columnName: columnName, userID: userID)
        }
        async let labGroup: [FavouriteMetadataOptionDTO] = fetchOrEmpty {
            guard let labGroupID else { return [] }
            return try await services.favouriteMetadataOptionSync.fetchLabGroupFavourites(columnName: columnName, labGroupID: labGroupID)
        }
        async let global: [FavouriteMetadataOptionDTO] = fetchOrEmpty {
            try await services.favouriteMetadataOptionSync.fetchGlobalFavourites(columnName: columnName)
        }

        personalFavourites = await personal
        labGroupFavourites = await labGroup
        globalFavourites = await global
    }

    private func fetchOrEmpty(_ body: () async throws -> [FavouriteMetadataOptionDTO]) async -> [FavouriteMetadataOptionDTO] {
        (try? await body()) ?? []
    }

    private func loadProjectHistory() async {
        guard let projectServerID else { return }
        let services = appSession.makeSyncServices()
        projectHistoryValues = (try? await services.instrumentJobSync.fetchProjectColumnValues(projectServerID: projectServerID, columnName: column.name)) ?? []
    }

    private func addToFavourites(scope: FavouriteScope) async {
        guard !value.isEmpty else { return }
        let displayName = favouriteDisplayNameOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = displayName.isEmpty ? nil : displayName
        let request: CreateFavouriteMetadataOptionRequest
        switch scope {
        case .personal:
            guard let userID = appSession.currentUserID else { return }
            request = CreateFavouriteMetadataOptionRequest(name: column.name, type: column.type, value: value, displayValue: displayValue, user: userID)
        case .labGroup:
            guard let labGroupID = firstLabGroupServerID else { return }
            request = CreateFavouriteMetadataOptionRequest(name: column.name, type: column.type, value: value, displayValue: displayValue, labGroup: labGroupID)
        case .global:
            request = CreateFavouriteMetadataOptionRequest(name: column.name, type: column.type, value: value, displayValue: displayValue, isGlobal: true)
        }
        do {
            let services = appSession.makeSyncServices()
            try await services.favouriteMetadataOptionSync.createFavourite(request)
            favouriteDisplayNameOverride = ""
            await loadFavourites()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func selectSuggestion(_ suggestion: OntologySuggestionDTO) {
        guard specialSyntaxType == .modification else {
            value = suggestion.displayName
            suggestions = []
            return
        }
        let fullData = suggestion.fullData
        keyValueFields["NT"] = fullData?.name ?? suggestion.displayName
        if let accession = fullData?.accession, !accession.isEmpty {
            keyValueFields["AC"] = accession
        }
        if let composition = fullData?.deltaComposition, !composition.isEmpty {
            keyValueFields["CF"] = composition
        }
        if let monoMass = fullData?.deltaMonoMass, !monoMass.isEmpty {
            keyValueFields["MM"] = monoMass
        }
        availableSpecifications = (fullData?.specifications ?? [:])
            .filter { $0.value["hidden"] != "1" }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, spec: $0.value) }
        suggestions = []
    }

    private func specificationSummary(_ spec: [String: String]) -> String {
        var parts: [String] = []
        if let site = spec["site"], !site.isEmpty { parts.append("Site: \(site)") }
        if let position = spec["position"], !position.isEmpty { parts.append("Position: \(position)") }
        if let classification = spec["classification"], !classification.isEmpty { parts.append("Class: \(classification)") }
        return parts.isEmpty ? "Specification" : parts.joined(separator: " | ")
    }

    private func applySpecification(_ spec: [String: String]) {
        if let site = spec["site"], !site.isEmpty {
            keyValueFields["TA"] = site
        }
        if let position = spec["position"], !position.isEmpty {
            keyValueFields["PP"] = UnimodMapping.position(from: position)
        }
        if let classification = spec["classification"], let modificationType = UnimodMapping.modificationType(from: classification) {
            keyValueFields["MT"] = modificationType
        }
    }

    private func scheduleSearch(text: String) {
        searchTask?.cancel()
        guard hasOntologyType else { return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let services = appSession.makeSyncServices()
                let results: [OntologySuggestionDTO]
                if column.ontologyType != nil {
                    results = try await services.metadataColumnSync.fetchOntologySuggestions(columnServerID: column.serverID, search: text, matchType: matchType)
                } else if let offlineOntologyType {
                    results = try await services.metadataColumnSync.fetchOntologySuggestions(
                        ontologyType: offlineOntologyType,
                        customFilters: offlineCustomFilters,
                        search: text,
                        match: matchType.rawValue
                    )
                } else {
                    results = []
                }
                guard !Task.isCancelled else { return }
                suggestions = results
            } catch {
            }
        }
    }

    private var valueToSave: String {
        switch specialSyntaxType {
        case .modification:
            return SDRFKeyValueSyntax.format(keyValueFields, keyOrder: SDRFModificationKeys.order)
        case .cleavage:
            return SDRFKeyValueSyntax.format(keyValueFields, keyOrder: SDRFCleavageKeys.order)
        case .spikedCompound:
            return SDRFKeyValueSyntax.format(keyValueFields, keyOrder: SDRFSpikedCompoundKeys.order)
        case .age:
            return SDRFAgeSyntax.format(years: ageYears, months: ageMonths, days: ageDays)
        case nil:
            return value
        }
    }

    private func closeEditor() {
        if PlatformWindowPreference.prefersSeparateWindow {
            dismissWindow()
        } else {
            dismiss()
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            let dto: MetadataColumnDTO
            if let sampleIndex {
                dto = try await services.metadataColumnSync.updateColumnValue(
                    columnServerID: column.serverID,
                    value: valueToSave,
                    sampleIndices: [sampleIndex],
                    valueType: .sampleSpecific
                )
            } else {
                dto = try await services.metadataColumnSync.updateColumnValue(columnServerID: column.serverID, value: valueToSave)
            }
            column.value = dto.value
            column.notApplicable = dto.notApplicable
            column.notAvailable = dto.notAvailable
            column.modifiers = dto.modifiers.map { MetadataColumnModifier(samples: $0.samples, value: $0.value) }
            try? modelContext.save()
            closeEditor()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

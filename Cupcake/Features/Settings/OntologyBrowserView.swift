import CupcakeModels
import CupcakeOntology
import CupcakeSync
import SwiftData
import SwiftUI

struct OntologyBrowserView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case offline, online
        var id: String { rawValue }
        var label: String { self == .offline ? "Offline" : "Online" }
    }

    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext

    @State private var mode: Mode
    @State private var matchType: OntologyMatchType = .contains
    @State private var searchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var resultBuckets: [String: [OntologyBrowserResult]] = [:]
    @State private var selectedResult: OntologyBrowserResult?
    @State private var isShowingDatabaseFilter = false
    @State private var importStates: [String: OntologyImportStateSnapshot] = [:]
    @State private var isSearching = false
    @AppStorage("ontologyBrowserEnabledOffline") private var enabledOfflineStorage = ""
    @AppStorage("ontologyBrowserEnabledOnline") private var enabledOnlineStorage = ""

    init() {
        _mode = State(initialValue: .offline)
    }

    private var enabledTypeKeys: Binding<Set<String>> {
        switch mode {
        case .offline:
            Binding(
                get: { decodeSet(enabledOfflineStorage, fallback: importedTypeKeys) },
                set: { enabledOfflineStorage = encodeSet($0) }
            )
        case .online:
            Binding(
                get: { decodeSet(enabledOnlineStorage, fallback: Set(OntologyRegistry.termTypeKeys)) },
                set: { enabledOnlineStorage = encodeSet($0) }
            )
        }
    }

    private var importedTypeKeys: Set<String> {
        Set(importStates.filter { $0.value.importedAt != nil && $0.value.isEnabled }.keys)
    }

    private func decodeSet(_ raw: String, fallback: @autoclosure () -> Set<String>) -> Set<String> {
        raw.isEmpty ? fallback() : Set(raw.split(separator: ",").map(String.init))
    }

    private func encodeSet(_ set: Set<String>) -> String {
        set.sorted().joined(separator: ",")
    }

    private var sortedBucketKeys: [String] {
        resultBuckets.keys.sorted { (OntologyRegistry.displayNames[$0] ?? $0) < (OntologyRegistry.displayNames[$1] ?? $1) }
    }

    private var hasResults: Bool {
        resultBuckets.values.contains { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search ontology terms", text: $searchText)
                .accessibilityIdentifier("ontologyBrowserSearchField")
                .padding(.horizontal, 12)
                .padding(.top, 8)
            Picker("Match", selection: $matchType) {
                ForEach(OntologyMatchType.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .accessibilityIdentifier("ontologyBrowserMatchTypePicker")
            ExplorerList(
                isEmpty: searchText.count < 2 || !hasResults,
                emptyTitle: searchText.count < 2 ? "Search Ontology Terms" : "No Results",
                emptySystemImage: "magnifyingglass",
                emptyMessage: searchText.count < 2
                    ? "Type at least 2 characters to search across enabled databases."
                    : "No matches in the currently enabled databases."
            ) {
                ForEach(sortedBucketKeys, id: \.self) { typeKey in
                    if let results = resultBuckets[typeKey], !results.isEmpty {
                        Section("\(OntologyRegistry.displayNames[typeKey] ?? typeKey) (\(results.count))") {
                            ForEach(results) { result in
                                Button {
                                    selectedResult = result
                                } label: {
                                    OntologyResultRow(result: result)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("ontologyResultRow_\(result.id)")
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in scheduleSearch(newValue) }
        .onChange(of: mode) { _, _ in scheduleSearch(searchText) }
        .onChange(of: matchType) { _, _ in scheduleSearch(searchText) }
        .navigationTitle("Ontology Browser")
        .toolbar {
            ToolbarItem {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("ontologyBrowserModePicker")
            }
            ToolbarItem {
                Button {
                    isShowingDatabaseFilter = true
                } label: {
                    Label("Databases", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("ontologyBrowserDatabasesButton")
            }
        }
        .sheet(item: $selectedResult) { result in
            NavigationStack {
                OntologyResultDetailView(result: result)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { selectedResult = nil }
                        }
                    }
            }
            .frame(minWidth: 360, minHeight: 420)
        }
        .sheet(isPresented: $isShowingDatabaseFilter) {
            OntologyDatabaseFilterSheet(
                mode: mode == .offline ? .offline : .online,
                enabledTypeKeys: enabledTypeKeys,
                importStates: importStates
            )
        }
        .task { await loadImportStates() }
    }

    private func loadImportStates() async {
        let service = OntologyImportService(modelContainer: modelContext.container)
        for typeKey in OntologyRegistry.termTypeKeys {
            importStates[typeKey] = try? await service.importState(typeKey: typeKey)
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        guard text.count >= 2 else {
            resultBuckets = [:]
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            let typeKeys = enabledTypeKeys.wrappedValue
            switch mode {
            case .offline:
                let service = OfflineOntologySearchService(modelContainer: modelContext.container)
                if let results = try? await service.search(text: text, enabledTypeKeys: typeKeys, matchType: matchType) {
                    guard !Task.isCancelled else { return }
                    resultBuckets = results
                }
            case .online:
                let results = await appSession.makeSyncServices().ontologySearchSync.search(text: text, enabledTypeKeys: typeKeys, matchType: matchType)
                guard !Task.isCancelled else { return }
                resultBuckets = results
            }
        }
    }
}

private struct OntologyDatabaseFilterSheet: View {
    enum FilterMode { case offline, online }

    let mode: FilterMode
    @Binding var enabledTypeKeys: Set<String>
    let importStates: [String: OntologyImportStateSnapshot]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(OntologyRegistry.termTypeKeys, id: \.self) { typeKey in
                    let isImported = importStates[typeKey]?.importedAt != nil && importStates[typeKey]?.isEnabled == true
                    let canSelect = mode == .online || isImported
                    Toggle(isOn: Binding(
                        get: { enabledTypeKeys.contains(typeKey) },
                        set: { isOn in
                            if isOn { enabledTypeKeys.insert(typeKey) } else { enabledTypeKeys.remove(typeKey) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(OntologyRegistry.displayNames[typeKey] ?? typeKey)
                            if mode == .offline, !isImported {
                                Text("Not imported. Enable in Offline Ontology Data")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!canSelect)
                    .accessibilityIdentifier("ontologyDatabaseToggle_\(typeKey)")
                }
            }
            .navigationTitle("Databases")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}

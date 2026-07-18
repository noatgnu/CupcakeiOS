import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct MetadataColumnAutofillSheet: View {
    let column: MetadataColumnDTO
    let metadataTableServerID: Int64
    let sampleCount: Int
    let allColumns: [MetadataColumnDTO]
    let onCompleted: () async -> Void

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case basic = "Basic"
        case advanced = "Advanced"
        var id: String { rawValue }
    }

    private enum BasicFillMode: String, CaseIterable, Identifiable {
        case template = "Template"
        case range = "Range"
        var id: String { rawValue }
    }

    private struct VariationRow: Identifiable {
        let id = UUID()
        var columnID: Int64?
        var type = "range"
        var startText = "1"
        var endText = "10"
        var stepText = "1"
        var valuesText = ""
        var patternText = "{i}"
        var countText = "10"
    }

    @State private var mode: Mode = .basic
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var resultMessage: String?
    @State private var isShowingResult = false

    @State private var basicFillMode: BasicFillMode = .template
    @State private var templateText = "run {sample_index}"
    @State private var rangeStartText = "1"
    @State private var rangeIncrementText = "1"
    @State private var selectedSampleIndices: Set<Int> = []
    @State private var currentPage = 1
    private let pageSize = 10

    @State private var templateSamplesText = "1"
    @State private var targetSampleCountText = ""
    @State private var fillStrategy: AutofillFillStrategy = .cartesianProduct
    @State private var variations: [VariationRow] = []

    private var canApplyBasic: Bool {
        guard !selectedSampleIndices.isEmpty else { return false }
        switch basicFillMode {
        case .template: return !templateText.isEmpty
        case .range: return Int(rangeStartText) != nil
        }
    }

    private var parsedTemplateSamples: [Int] {
        templateSamplesText
            .split(separator: ",")
            .flatMap { part -> [Int] in
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("-") {
                    let bounds = trimmed.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    guard bounds.count == 2, bounds[0] <= bounds[1] else { return [] }
                    return Array(bounds[0]...bounds[1])
                }
                return Int(trimmed).map { [$0] } ?? []
            }
    }

    private var canApplyAdvanced: Bool {
        guard let targetSampleCount = Int(targetSampleCountText), targetSampleCount >= 1, targetSampleCount <= sampleCount else { return false }
        return !parsedTemplateSamples.isEmpty && !variations.isEmpty && variations.allSatisfy { $0.columnID != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                #if !os(macOS)
                Section {
                    Text(column.displayName ?? column.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                #endif
                Section {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { modeOption in
                            Text(modeOption.rawValue).tag(modeOption)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("autofillModePicker")
                }
                if mode == .basic {
                    basicContent
                } else {
                    advancedContent
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Autofill")
            #if os(macOS)
            .navigationSubtitle(column.displayName ?? column.name)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task { await apply() }
                    }
                    .disabled(isSaving || (mode == .basic ? !canApplyBasic : !canApplyAdvanced))
                    .accessibilityIdentifier("applyAutofillButton")
                }
            }
        }
        .frame(minWidth: 380, minHeight: 560)
        .alert("Couldn't autofill", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Autofill Complete", isPresented: $isShowingResult) {
            Button("OK") { dismiss() }
        } message: {
            Text(resultMessage ?? "")
        }
        .task {
            selectedSampleIndices = Set(sampleCount > 0 ? Array(1...sampleCount) : [])
        }
    }

    @ViewBuilder
    private var basicContent: some View {
        Section("Fill Mode") {
            Picker("Fill Mode", selection: $basicFillMode) {
                ForEach(BasicFillMode.allCases) { fillModeOption in
                    Text(fillModeOption.rawValue).tag(fillModeOption)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("basicAutofillFillModePicker")
            if basicFillMode == .template {
                TextField("Template (use {sample_index})", text: $templateText)
                    .accessibilityIdentifier("basicAutofillTemplateField")
                Text("Also supports {index} and {n} as aliases for {sample_index}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Start Value", text: $rangeStartText)
                    .accessibilityIdentifier("basicAutofillRangeStartField")
                TextField("Increment", text: $rangeIncrementText)
                    .accessibilityIdentifier("basicAutofillRangeIncrementField")
            }
        }
        Section("Samples") {
            HStack {
                Button("Select All") { selectedSampleIndices = Set(1...max(sampleCount, 1)) }
                    .accessibilityIdentifier("basicAutofillSelectAllButton")
                Button("Clear") { selectedSampleIndices = [] }
                Spacer()
                Text("\(selectedSampleIndices.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(pagedSampleIndices, id: \.self) { sampleIndex in
                Button {
                    if selectedSampleIndices.contains(sampleIndex) {
                        selectedSampleIndices.remove(sampleIndex)
                    } else {
                        selectedSampleIndices.insert(sampleIndex)
                    }
                } label: {
                    HStack {
                        Text("Sample \(sampleIndex)")
                        Spacer()
                        if selectedSampleIndices.contains(sampleIndex) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                        if let preview = previewValue(for: sampleIndex) {
                            Text(preview).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("basicAutofillSampleRow_\(sampleIndex)")
            }
            if totalPages > 1 {
                HStack {
                    Button("Previous") { currentPage = max(1, currentPage - 1) }
                        .disabled(currentPage <= 1)
                    Spacer()
                    Text("Page \(currentPage) of \(totalPages)").font(.caption)
                    Spacer()
                    Button("Next") { currentPage = min(totalPages, currentPage + 1) }
                        .disabled(currentPage >= totalPages)
                        .accessibilityIdentifier("basicAutofillNextPageButton")
                }
            }
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(sampleCount) / Double(pageSize))))
    }

    private var pagedSampleIndices: [Int] {
        guard sampleCount > 0 else { return [] }
        let start = (currentPage - 1) * pageSize + 1
        let end = min(start + pageSize - 1, sampleCount)
        guard start <= end else { return [] }
        return Array(start...end)
    }

    private func previewValue(for sampleIndex: Int) -> String? {
        guard selectedSampleIndices.contains(sampleIndex) else { return nil }
        switch basicFillMode {
        case .template:
            guard !templateText.isEmpty else { return nil }
            return templateText
                .replacingOccurrences(of: "{sample_index}", with: String(sampleIndex))
                .replacingOccurrences(of: "{index}", with: String(sampleIndex))
                .replacingOccurrences(of: "{n}", with: String(sampleIndex))
        case .range:
            guard let start = Int(rangeStartText) else { return nil }
            let increment = Int(rangeIncrementText) ?? 1
            let sortedSelected = selectedSampleIndices.sorted()
            guard let position = sortedSelected.firstIndex(of: sampleIndex) else { return nil }
            return String(start + position * increment)
        }
    }

    @ViewBuilder
    private var advancedContent: some View {
        Section("Template Samples") {
            TextField("e.g. 1 or 1-2", text: $templateSamplesText)
                .accessibilityIdentifier("advancedAutofillTemplateSamplesField")
            TextField("Target Sample Count", text: $targetSampleCountText)
                .accessibilityIdentifier("advancedAutofillTargetSampleCountField")
            Text("Must be at most \(sampleCount) — this table's own sample count.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Fill Strategy", selection: $fillStrategy) {
                ForEach(AutofillFillStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.displayName).tag(strategy)
                }
            }
            .accessibilityIdentifier("advancedAutofillFillStrategyPicker")
        }
        Section("Variations") {
            ForEach(variations.indices, id: \.self) { index in
                variationRow($variations[index], index: index)
            }
            .onDelete { offsets in variations.remove(atOffsets: offsets) }
            Button {
                variations.append(VariationRow())
            } label: {
                Label("Add Variation", systemImage: "plus")
            }
            .accessibilityIdentifier("addAutofillVariationButton")
        }
    }

    @ViewBuilder
    private func variationRow(_ variation: Binding<VariationRow>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Column", selection: variation.columnID) {
                Text("Choose\u{2026}").tag(Int64?.none)
                ForEach(allColumns, id: \.id) { candidate in
                    Text(candidate.displayName ?? candidate.name).tag(Optional(candidate.id))
                }
            }
            .accessibilityIdentifier("autofillVariationColumnPicker_\(index)")
            Picker("Type", selection: variation.type) {
                Text("Range").tag("range")
                Text("List").tag("list")
                Text("Pattern").tag("pattern")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("autofillVariationTypePicker_\(index)")
            switch variation.wrappedValue.type {
            case "range":
                HStack {
                    TextField("Start", text: variation.startText)
                        .accessibilityIdentifier("autofillVariationStartField_\(index)")
                    TextField("End", text: variation.endText)
                        .accessibilityIdentifier("autofillVariationEndField_\(index)")
                    TextField("Step", text: variation.stepText)
                        .accessibilityIdentifier("autofillVariationStepField_\(index)")
                }
            case "list":
                TextField("Comma-separated values", text: variation.valuesText)
                    .accessibilityIdentifier("autofillVariationValuesField_\(index)")
            default:
                HStack {
                    TextField("Pattern (use {i})", text: variation.patternText)
                        .accessibilityIdentifier("autofillVariationPatternField_\(index)")
                    TextField("Count", text: variation.countText)
                        .accessibilityIdentifier("autofillVariationCountField_\(index)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func apply() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            switch mode {
            case .basic:
                let indices = selectedSampleIndices.sorted()
                let updates: [BulkUpdateSampleValueEntry]
                switch basicFillMode {
                case .template:
                    updates = indices.map { index in
                        BulkUpdateSampleValueEntry(
                            sampleIndex: index,
                            value: templateText
                                .replacingOccurrences(of: "{sample_index}", with: String(index))
                                .replacingOccurrences(of: "{index}", with: String(index))
                                .replacingOccurrences(of: "{n}", with: String(index))
                        )
                    }
                case .range:
                    let start = Int(rangeStartText) ?? 0
                    let increment = Int(rangeIncrementText) ?? 1
                    updates = indices.enumerated().map { position, index in
                        BulkUpdateSampleValueEntry(sampleIndex: index, value: String(start + position * increment))
                    }
                }
                let response = try await services.metadataColumnSync.bulkUpdateSampleValues(columnServerID: column.id, updates: updates)
                resultMessage = response.failedCount == 0
                    ? "Auto-filled \(response.updatedCount) sample(s)."
                    : "Auto-filled \(response.updatedCount) sample(s), \(response.failedCount) failed."
                await onCompleted()
                isShowingResult = true
            case .advanced:
                guard let targetSampleCount = Int(targetSampleCountText) else { return }
                let specs: [AutofillVariationSpec] = variations.compactMap { variation in
                    guard let columnID = variation.columnID else { return nil }
                    switch variation.type {
                    case "range":
                        guard let start = Int(variation.startText), let end = Int(variation.endText) else { return nil }
                        return .range(columnId: columnID, start: start, end: end, step: Int(variation.stepText) ?? 1)
                    case "list":
                        let values = variation.valuesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        guard !values.isEmpty else { return nil }
                        return .list(columnId: columnID, values: values)
                    default:
                        return .pattern(columnId: columnID, pattern: variation.patternText, count: Int(variation.countText) ?? 1)
                    }
                }
                let request = AdvancedAutofillRequest(
                    templateSamples: parsedTemplateSamples,
                    targetSampleCount: targetSampleCount,
                    variations: specs,
                    fillStrategy: fillStrategy
                )
                let response = try await services.metadataTableSync.advancedAutofill(tableServerID: metadataTableServerID, request: request)
                resultMessage = "Modified \(response.samplesModified ?? 0) sample(s) across \(response.columnsModified ?? 0) column(s)."
                await onCompleted()
                isShowingResult = true
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

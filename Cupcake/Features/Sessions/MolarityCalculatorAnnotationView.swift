import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

/// Solves concentration/volume/molecular-weight/mass/dilution problems, with a reagent-typeahead molecular-weight autofill.
struct MolarityCalculatorAnnotationView: View {
    let onSave: (Data) -> Void
    let onCancel: () -> Void

    @Environment(AppSession.self) private var appSession

    private enum Mode: String, CaseIterable, Identifiable {
        case dynamic
        case massFromVolumeAndConcentration
        case volumeFromMassAndConcentration
        case concentrationFromMassAndVolume
        case volumeFromStockVolumeAndConcentration

        var id: String { rawValue }

        var label: String {
            switch self {
            case .dynamic: return "Solve for missing value"
            case .massFromVolumeAndConcentration: return "Mass from volume + concentration"
            case .volumeFromMassAndConcentration: return "Volume from mass + concentration"
            case .concentrationFromMassAndVolume: return "Concentration from mass + volume"
            case .volumeFromStockVolumeAndConcentration: return "Dilution (stock → target)"
            }
        }
    }

    private static let massUnits: [(unit: String, baseConversion: Double)] = [
        ("ng", 1), ("μg", 1_000), ("mg", 1_000_000), ("g", 1_000_000_000), ("kg", 1_000_000_000_000),
    ]
    private static let volumeUnits: [(unit: String, baseConversion: Double)] = [
        ("nL", 1), ("μL", 1_000), ("mL", 1_000_000), ("L", 1_000_000_000),
    ]
    private static let molarityUnits: [(unit: String, baseConversion: Double)] = [
        ("nM", 1), ("μM", 1_000), ("mM", 1_000_000), ("M", 1_000_000_000),
    ]

    @State private var mode: Mode = .dynamic
    @State private var concentration: Double?
    @State private var concentrationUnit = "mM"
    @State private var volume: Double?
    @State private var volumeUnit = "mL"
    @State private var molecularWeight: Double?
    @State private var weight: Double?
    @State private var weightUnit = "mg"
    @State private var stockConcentration: Double?
    @State private var stockConcentrationUnit = "mM"
    @State private var targetConcentration: Double?
    @State private var targetConcentrationUnit = "mM"
    @State private var stockVolume: Double?
    @State private var stockVolumeUnit = "mL"

    @State private var history: [MolarityHistoryEntry] = []
    @State private var errorMessage: String?
    @State private var isShowingError = false

    @State private var reagentSearchText = ""
    @State private var reagentSuggestions: [StoredReagentDTO] = []
    @State private var isSearchingReagents = false

    private var showsMolecularWeightLookup: Bool {
        mode != .volumeFromStockVolumeAndConcentration
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Calculation") {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("molarityModePicker")
                }
                modeFields
                if showsMolecularWeightLookup {
                    reagentLookupSection
                }
                Section {
                    Button("Calculate", action: calculate)
                        .accessibilityIdentifier("calculateMolarityButton")
                    Button("Clear Form", role: .destructive) { clearForm() }
                }
                if !history.isEmpty {
                    Section("History (\(history.count))") {
                        ForEach(history.reversed()) { entry in
                            Text(Self.formatExpression(entry))
                                .font(.caption)
                                .opacity(entry.scratched == true ? 0.5 : 1)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        history.removeAll { $0.id == entry.id }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Molarity Calculator")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(history.isEmpty)
                        .accessibilityIdentifier("saveMolarityButton")
                }
            }
            .alert("Calculator error", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 380, minHeight: 520)
    }

    @ViewBuilder
    private var modeFields: some View {
        switch mode {
        case .dynamic:
            Section("Fill any 3 of 4 — the 4th is calculated") {
                numberField("Concentration", value: $concentration, unit: $concentrationUnit, units: Self.molarityUnits, identifier: "molarityConcentrationField")
                numberField("Volume", value: $volume, unit: $volumeUnit, units: Self.volumeUnits, identifier: "molarityVolumeField")
                numberField("Molecular Weight (g/mol)", value: $molecularWeight, identifier: "molarityMolecularWeightField")
                numberField("Weight", value: $weight, unit: $weightUnit, units: Self.massUnits, identifier: "molarityWeightField")
            }
        case .massFromVolumeAndConcentration:
            Section("Inputs") {
                numberField("Concentration", value: $concentration, unit: $concentrationUnit, units: Self.molarityUnits, identifier: "molarityConcentrationField")
                numberField("Volume", value: $volume, unit: $volumeUnit, units: Self.volumeUnits, identifier: "molarityVolumeField")
                numberField("Molecular Weight (g/mol)", value: $molecularWeight, identifier: "molarityMolecularWeightField")
                unitPicker("Result Unit", selection: $weightUnit, units: Self.massUnits)
            }
        case .volumeFromMassAndConcentration:
            Section("Inputs") {
                numberField("Weight", value: $weight, unit: $weightUnit, units: Self.massUnits, identifier: "molarityWeightField")
                numberField("Concentration", value: $concentration, unit: $concentrationUnit, units: Self.molarityUnits, identifier: "molarityConcentrationField")
                numberField("Molecular Weight (g/mol)", value: $molecularWeight, identifier: "molarityMolecularWeightField")
                unitPicker("Result Unit", selection: $volumeUnit, units: Self.volumeUnits)
            }
        case .concentrationFromMassAndVolume:
            Section("Inputs") {
                numberField("Weight", value: $weight, unit: $weightUnit, units: Self.massUnits, identifier: "molarityWeightField")
                numberField("Volume", value: $volume, unit: $volumeUnit, units: Self.volumeUnits, identifier: "molarityVolumeField")
                numberField("Molecular Weight (g/mol)", value: $molecularWeight, identifier: "molarityMolecularWeightField")
                unitPicker("Result Unit", selection: $concentrationUnit, units: Self.molarityUnits)
            }
        case .volumeFromStockVolumeAndConcentration:
            Section("Inputs") {
                numberField("Stock Concentration", value: $stockConcentration, unit: $stockConcentrationUnit, units: Self.molarityUnits, identifier: "molarityStockConcentrationField")
                numberField("Target Concentration", value: $targetConcentration, unit: $targetConcentrationUnit, units: Self.molarityUnits, identifier: "molarityTargetConcentrationField")
                numberField("Stock Volume", value: $stockVolume, unit: $stockVolumeUnit, units: Self.volumeUnits, identifier: "molarityStockVolumeField")
                unitPicker("Result Unit", selection: $volumeUnit, units: Self.volumeUnits)
            }
        }
    }

    /// Debounced search against reagents with a known molecular weight, autofilling the field on tap.
    private var reagentLookupSection: some View {
        Section("Look Up Molecular Weight") {
            TextField("Search reagents…", text: $reagentSearchText)
                .accessibilityIdentifier("molarityReagentSearchField")
            if isSearchingReagents {
                ProgressView()
            } else {
                ForEach(reagentSuggestions, id: \.id) { reagent in
                    Button {
                        selectReagent(reagent)
                    } label: {
                        if let mw = reagent.molecularWeight.flatMap(Double.init) {
                            Text("\(reagent.reagentName ?? "Unknown") (\(String(format: "%.2f", mw)) g/mol)")
                        }
                    }
                }
            }
        }
        .task(id: reagentSearchText) {
            guard !reagentSearchText.isEmpty else {
                reagentSuggestions = []
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            isSearchingReagents = true
            defer { isSearchingReagents = false }
            reagentSuggestions = (try? await appSession.makeSyncServices().inventorySync.searchStoredReagentsWithMolecularWeight(search: reagentSearchText)) ?? []
        }
    }

    private func selectReagent(_ reagent: StoredReagentDTO) {
        guard let mw = reagent.molecularWeight.flatMap(Double.init) else { return }
        molecularWeight = mw
        reagentSearchText = ""
        reagentSuggestions = []
    }

    private func numberField(_ label: String, value: Binding<Double?>, unit: Binding<String>? = nil, units: [(unit: String, baseConversion: Double)] = [], identifier: String? = nil) -> some View {
        NumberField(label: label, value: value, unit: unit, units: units, identifier: identifier)
    }

    private func unitPicker(_ label: String?, selection: Binding<String>, units: [(unit: String, baseConversion: Double)]) -> some View {
        Picker(label ?? "", selection: selection) {
            ForEach(units, id: \.unit) { entry in
                Text(entry.unit).tag(entry.unit)
            }
        }
    }

    // MARK: - Unit conversion

    private static func convert(_ value: Double, from: String, to: String, table: [(unit: String, baseConversion: Double)]) -> Double {
        guard let fromFactor = table.first(where: { $0.unit == from })?.baseConversion,
              let toFactor = table.first(where: { $0.unit == to })?.baseConversion else { return value }
        return value * fromFactor / toFactor
    }

    private func clearForm() {
        concentration = nil
        volume = nil
        molecularWeight = nil
        weight = nil
        stockConcentration = nil
        targetConcentration = nil
        stockVolume = nil
    }

    private func showError(_ message: String) {
        errorMessage = message
        isShowingError = true
    }

    private func calculate() {
        switch mode {
        case .dynamic: calculateDynamic()
        case .massFromVolumeAndConcentration: calculateMassFromVolumeAndConcentration()
        case .volumeFromMassAndConcentration: calculateVolumeFromMassAndConcentration()
        case .concentrationFromMassAndVolume: calculateConcentrationFromMassAndVolume()
        case .volumeFromStockVolumeAndConcentration: calculateVolumeFromStockVolumeAndConcentration()
        }
    }

    private func calculateDynamic() {
        let filledCount = [concentration, volume, molecularWeight, weight].compactMap { $0 }.count
        guard filledCount >= 3 else { showError("Please fill at least 3 values to calculate the 4th"); return }

        let calculateField: String
        if concentration == nil { calculateField = "concentration" }
        else if volume == nil { calculateField = "volume" }
        else if molecularWeight == nil { calculateField = "molecularWeight" }
        else if weight == nil { calculateField = "weight" }
        else { showError("All fields are filled. Please clear one field to calculate"); return }

        let concentrationInM = concentration.map { Self.convert($0, from: concentrationUnit, to: "M", table: Self.molarityUnits) } ?? 0
        let volumeInL = volume.map { Self.convert($0, from: volumeUnit, to: "L", table: Self.volumeUnits) } ?? 0
        let weightInG = weight.map { Self.convert($0, from: weightUnit, to: "g", table: Self.massUnits) } ?? 0
        let mw = molecularWeight ?? 0

        var result = 0.0
        switch calculateField {
        case "weight":
            result = Self.convert(concentrationInM * volumeInL * mw, from: "g", to: weightUnit, table: Self.massUnits)
            weight = result
        case "volume":
            result = Self.convert(weightInG / (concentrationInM * mw), from: "L", to: volumeUnit, table: Self.volumeUnits)
            volume = result
        case "concentration":
            result = Self.convert(weightInG / (volumeInL * mw), from: "M", to: concentrationUnit, table: Self.molarityUnits)
            concentration = result
        case "molecularWeight":
            result = weightInG / (concentrationInM * volumeInL)
            molecularWeight = result
        default: return
        }
        guard result.isFinite else { showError("Calculation error"); return }

        history.append(MolarityHistoryEntry(
            data: [
                "concentration": concentration.map(MolarityDataValue.number) ?? .null,
                "concentrationUnit": .string(concentrationUnit),
                "volume": volume.map(MolarityDataValue.number) ?? .null,
                "volumeUnit": .string(volumeUnit),
                "molecularWeight": molecularWeight.map(MolarityDataValue.number) ?? .null,
                "weight": weight.map(MolarityDataValue.number) ?? .null,
                "weightUnit": .string(weightUnit),
            ],
            operationType: "dynamic",
            result: result,
            calculatedField: calculateField
        ))
    }

    private func calculateMassFromVolumeAndConcentration() {
        guard let concentration, let volume, let molecularWeight else { showError("Please fill all required fields"); return }
        let concentrationInM = Self.convert(concentration, from: concentrationUnit, to: "M", table: Self.molarityUnits)
        let volumeInL = Self.convert(volume, from: volumeUnit, to: "L", table: Self.volumeUnits)
        let mass = concentrationInM * volumeInL * molecularWeight
        let finalWeight = Self.convert(mass, from: "g", to: weightUnit, table: Self.massUnits)
        guard finalWeight.isFinite else { showError("Calculation error"); return }

        history.append(MolarityHistoryEntry(
            data: [
                "concentration": .number(concentration), "concentrationUnit": .string(concentrationUnit),
                "volume": .number(volume), "volumeUnit": .string(volumeUnit),
                "molecularWeight": .number(molecularWeight), "weightUnit": .string(weightUnit),
            ],
            operationType: "massFromVolumeAndConcentration",
            result: finalWeight
        ))
    }

    private func calculateVolumeFromMassAndConcentration() {
        guard let weight, let concentration, let molecularWeight else { showError("Please fill all required fields"); return }
        let weightInG = Self.convert(weight, from: weightUnit, to: "g", table: Self.massUnits)
        let concentrationInM = Self.convert(concentration, from: concentrationUnit, to: "M", table: Self.molarityUnits)
        let volumeInL = weightInG / (concentrationInM * molecularWeight)
        let finalVolume = Self.convert(volumeInL, from: "L", to: volumeUnit, table: Self.volumeUnits)
        guard finalVolume.isFinite else { showError("Calculation error"); return }

        history.append(MolarityHistoryEntry(
            data: [
                "weight": .number(weight), "weightUnit": .string(weightUnit),
                "concentration": .number(concentration), "concentrationUnit": .string(concentrationUnit),
                "molecularWeight": .number(molecularWeight), "volumeUnit": .string(volumeUnit),
            ],
            operationType: "volumeFromMassAndConcentration",
            result: finalVolume
        ))
    }

    private func calculateConcentrationFromMassAndVolume() {
        guard let weight, let volume, let molecularWeight else { showError("Please fill all required fields"); return }
        let weightInG = Self.convert(weight, from: weightUnit, to: "g", table: Self.massUnits)
        let volumeInL = Self.convert(volume, from: volumeUnit, to: "L", table: Self.volumeUnits)
        let concentrationInM = weightInG / (volumeInL * molecularWeight)
        let finalConcentration = Self.convert(concentrationInM, from: "M", to: concentrationUnit, table: Self.molarityUnits)
        guard finalConcentration.isFinite else { showError("Calculation error"); return }

        history.append(MolarityHistoryEntry(
            data: [
                "weight": .number(weight), "weightUnit": .string(weightUnit),
                "volume": .number(volume), "volumeUnit": .string(volumeUnit),
                "molecularWeight": .number(molecularWeight), "concentrationUnit": .string(concentrationUnit),
            ],
            operationType: "concentrationFromMassAndVolume",
            result: finalConcentration
        ))
    }

    private func calculateVolumeFromStockVolumeAndConcentration() {
        guard let stockConcentration, let targetConcentration, let stockVolume else { showError("Please fill all required fields"); return }
        let stockConcInM = Self.convert(stockConcentration, from: stockConcentrationUnit, to: "M", table: Self.molarityUnits)
        let targetConcInM = Self.convert(targetConcentration, from: targetConcentrationUnit, to: "M", table: Self.molarityUnits)
        let stockVolumeInL = Self.convert(stockVolume, from: stockVolumeUnit, to: "L", table: Self.volumeUnits)
        let finalVolumeInL = (stockConcInM * stockVolumeInL) / targetConcInM
        let finalVolume = Self.convert(finalVolumeInL, from: "L", to: volumeUnit, table: Self.volumeUnits)
        guard finalVolume.isFinite else { showError("Calculation error"); return }

        history.append(MolarityHistoryEntry(
            data: [
                "stockConcentration": .number(stockConcentration), "stockConcentrationUnit": .string(stockConcentrationUnit),
                "targetConcentration": .number(targetConcentration), "targetConcentrationUnit": .string(targetConcentrationUnit),
                "stockVolume": .number(stockVolume), "stockVolumeUnit": .string(stockVolumeUnit),
                "volumeUnit": .string(volumeUnit),
            ],
            operationType: "volumeFromStockVolumeAndConcentration",
            result: finalVolume
        ))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(history) {
            onSave(data)
        }
    }

    /// Shows the full symbolic formula with every variable's actual value plugged in.
    static func formatExpression(_ entry: MolarityHistoryEntry) -> String {
        let resultText = String(format: "%.3f", entry.result)
        let unit = resultUnit(for: entry)

        func value(_ key: String) -> String { numberString(entry.data[key]) }
        func valueUnit(_ key: String) -> String { stringValue(entry.data[key]) }

        switch entry.operationType {
        case "massFromVolumeAndConcentration":
            return "Mass = Concentration × Volume × MW = \(value("concentration")) \(valueUnit("concentrationUnit")) × \(value("volume")) \(valueUnit("volumeUnit")) × \(value("molecularWeight")) g/mol = \(resultText) \(unit)"
        case "volumeFromMassAndConcentration":
            return "Volume = Mass / (Concentration × MW) = \(value("weight")) \(valueUnit("weightUnit")) / (\(value("concentration")) \(valueUnit("concentrationUnit")) × \(value("molecularWeight")) g/mol) = \(resultText) \(unit)"
        case "concentrationFromMassAndVolume":
            return "Concentration = Mass / (Volume × MW) = \(value("weight")) \(valueUnit("weightUnit")) / (\(value("volume")) \(valueUnit("volumeUnit")) × \(value("molecularWeight")) g/mol) = \(resultText) \(unit)"
        case "volumeFromStockVolumeAndConcentration":
            return "Volume = (Stock Conc. × Stock Volume) / Target Conc. = (\(value("stockConcentration")) \(valueUnit("stockConcentrationUnit")) × \(value("stockVolume")) \(valueUnit("stockVolumeUnit"))) / \(value("targetConcentration")) \(valueUnit("targetConcentrationUnit")) = \(resultText) \(unit)"
        case "dynamic":
            switch entry.calculatedField {
            case "weight":
                return "Weight = Concentration × Volume × MW = \(value("concentration")) \(valueUnit("concentrationUnit")) × \(value("volume")) \(valueUnit("volumeUnit")) × \(value("molecularWeight")) g/mol = \(resultText) \(unit)"
            case "volume":
                return "Volume = Weight / (Concentration × MW) = \(value("weight")) \(valueUnit("weightUnit")) / (\(value("concentration")) \(valueUnit("concentrationUnit")) × \(value("molecularWeight")) g/mol) = \(resultText) \(unit)"
            case "concentration":
                return "Concentration = Weight / (Volume × MW) = \(value("weight")) \(valueUnit("weightUnit")) / (\(value("volume")) \(valueUnit("volumeUnit")) × \(value("molecularWeight")) g/mol) = \(resultText) \(unit)"
            case "molecularWeight":
                return "MW = Weight / (Concentration × Volume) = \(value("weight")) \(valueUnit("weightUnit")) / (\(value("concentration")) \(valueUnit("concentrationUnit")) × \(value("volume")) \(valueUnit("volumeUnit"))) = \(resultText) g/mol"
            default:
                return "Result: \(resultText) \(unit)"
            }
        default:
            return "Result: \(resultText) \(unit)"
        }
    }

    private static func resultUnit(for entry: MolarityHistoryEntry) -> String {
        switch entry.operationType {
        case "massFromVolumeAndConcentration": return stringValue(entry.data["weightUnit"])
        case "volumeFromMassAndConcentration", "volumeFromStockVolumeAndConcentration": return stringValue(entry.data["volumeUnit"])
        case "concentrationFromMassAndVolume": return stringValue(entry.data["concentrationUnit"])
        case "dynamic":
            switch entry.calculatedField {
            case "weight": return stringValue(entry.data["weightUnit"])
            case "volume": return stringValue(entry.data["volumeUnit"])
            case "concentration": return stringValue(entry.data["concentrationUnit"])
            case "molecularWeight": return "g/mol"
            default: return ""
            }
        default: return ""
        }
    }

    private static func numberString(_ value: MolarityDataValue?) -> String {
        guard let value = value?.doubleValue else { return "—" }
        return String(format: "%.3f", value)
    }

    private static func stringValue(_ value: MolarityDataValue?) -> String {
        value?.stringValue ?? ""
    }
}

/// Plain string-bound numeric field, syncing its local text buffer from the `Double?` binding on appear/external change.
private struct NumberField: View {
    let label: String
    @Binding var value: Double?
    var unit: Binding<String>?
    var units: [(unit: String, baseConversion: Double)] = []
    var identifier: String?

    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Value", text: $text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .accessibilityIdentifier(identifier ?? "")
                .onAppear { text = Self.format(value) }
                .onChange(of: text) { _, newValue in value = Double(newValue) }
                .onChange(of: value) { _, newValue in
                    guard Double(text) != newValue else { return }
                    text = Self.format(newValue)
                }
            if let unit {
                Picker("", selection: unit) {
                    ForEach(units, id: \.unit) { entry in
                        Text(entry.unit).tag(entry.unit)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
            }
        }
    }

    private static func format(_ value: Double?) -> String {
        value.map { String($0) } ?? ""
    }
}

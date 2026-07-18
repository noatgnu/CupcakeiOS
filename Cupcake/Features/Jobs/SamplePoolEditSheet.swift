import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

enum SampleIndexTextParser {
    static func parse(_ text: String) -> [Int] {
        var indices = Set<Int>()
        for part in text.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("-") {
                let bounds = trimmed.split(separator: "-", maxSplits: 1)
                if bounds.count == 2, let lower = Int(bounds[0].trimmingCharacters(in: .whitespaces)),
                   let upper = Int(bounds[1].trimmingCharacters(in: .whitespaces)), lower <= upper {
                    indices.formUnion(lower...upper)
                }
            } else if let value = Int(trimmed) {
                indices.insert(value)
            }
        }
        return indices.sorted()
    }

    static func format(_ indices: [Int]) -> String {
        indices.sorted().map(String.init).joined(separator: ", ")
    }
}

struct SamplePoolEditSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let metadataTableServerID: Int64
    let sampleCount: Int
    let existingPool: CachedSamplePool?

    @State private var poolName: String
    @State private var poolDescription: String
    @State private var pooledOnlySamplesText: String
    @State private var pooledAndIndependentSamplesText: String
    @State private var isReference: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(metadataTableServerID: Int64, sampleCount: Int, existingPool: CachedSamplePool? = nil) {
        self.metadataTableServerID = metadataTableServerID
        self.sampleCount = sampleCount
        self.existingPool = existingPool
        _poolName = State(initialValue: existingPool?.poolName ?? "")
        _poolDescription = State(initialValue: existingPool?.poolDescription ?? "")
        _pooledOnlySamplesText = State(initialValue: SampleIndexTextParser.format(existingPool?.pooledOnlySamples ?? []))
        _pooledAndIndependentSamplesText = State(initialValue: SampleIndexTextParser.format(existingPool?.pooledAndIndependentSamples ?? []))
        _isReference = State(initialValue: existingPool?.isReference ?? false)
    }

    private var pooledOnlySamples: [Int] {
        SampleIndexTextParser.parse(pooledOnlySamplesText)
    }

    private var pooledAndIndependentSamples: [Int] {
        SampleIndexTextParser.parse(pooledAndIndependentSamplesText)
    }

    private var hasOverlap: Bool {
        !Set(pooledOnlySamples).isDisjoint(with: Set(pooledAndIndependentSamples))
    }

    private var hasOutOfRangeIndex: Bool {
        (pooledOnlySamples + pooledAndIndependentSamples).contains { $0 < 1 || $0 > sampleCount }
    }

    private var canSave: Bool {
        !poolName.isEmpty && !hasOverlap && !hasOutOfRangeIndex
            && !(pooledOnlySamples.isEmpty && pooledAndIndependentSamples.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pool Name", text: $poolName)
                        .accessibilityIdentifier("samplePoolNameField")
                    TextField("Description", text: $poolDescription, axis: .vertical)
                        .accessibilityIdentifier("samplePoolDescriptionField")
                    Toggle("Reference Pool", isOn: $isReference)
                        .accessibilityIdentifier("samplePoolIsReferenceToggle")
                } footer: {
                    Text("Samples 1–\(sampleCount) are available on this table.")
                }
                Section {
                    TextField("e.g. 1-3, 5", text: $pooledOnlySamplesText)
                        .accessibilityIdentifier("samplePoolOnlySamplesField")
                } header: {
                    Text("Pooled Only Samples")
                } footer: {
                    Text("Samples that exist only as part of this pool, not independently.")
                }
                Section {
                    TextField("e.g. 6, 7", text: $pooledAndIndependentSamplesText)
                        .accessibilityIdentifier("samplePoolIndependentSamplesField")
                } header: {
                    Text("Pooled and Independent Samples")
                } footer: {
                    Text("Samples that are also included independently, outside this pool.")
                }
                if hasOverlap {
                    Text("A sample can't be in both lists.")
                        .foregroundStyle(.red)
                }
                if hasOutOfRangeIndex {
                    Text("Every sample index must be between 1 and \(sampleCount).")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existingPool == nil ? "New Sample Pool" : "Edit Sample Pool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || !canSave)
                    .accessibilityIdentifier("saveSamplePoolButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 480)
        .alert("Couldn't save sample pool", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            if let existingPool {
                try await services.samplePoolSync.update(
                    serverID: existingPool.serverID,
                    poolName: poolName,
                    poolDescription: poolDescription.isEmpty ? nil : poolDescription,
                    pooledOnlySamples: pooledOnlySamples,
                    pooledAndIndependentSamples: pooledAndIndependentSamples,
                    isReference: isReference
                )
            } else {
                try await services.samplePoolSync.create(
                    metadataTableServerID: metadataTableServerID,
                    poolName: poolName,
                    poolDescription: poolDescription.isEmpty ? nil : poolDescription,
                    pooledOnlySamples: pooledOnlySamples,
                    pooledAndIndependentSamples: pooledAndIndependentSamples,
                    isReference: isReference
                )
            }
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

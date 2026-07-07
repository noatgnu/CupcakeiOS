import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// This user's own complexity/duration rating (0-10 each) for a protocol. Online-only.
struct RateProtocolSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query private var ratings: [CachedProtocolRating]

    let protocolServerID: Int64

    @State private var complexityRating: Double = 0
    @State private var durationRating: Double = 0
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var existingRating: CachedProtocolRating? {
        ratings.first(where: { $0.protocolServerID == protocolServerID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Complexity: \(Int(complexityRating))")
                        Slider(value: $complexityRating, in: 0...10, step: 1)
                            .accessibilityIdentifier("complexityRatingSlider")
                    }
                    VStack(alignment: .leading) {
                        Text("Duration Accuracy: \(Int(durationRating))")
                        Slider(value: $durationRating, in: 0...10, step: 1)
                            .accessibilityIdentifier("durationRatingSlider")
                    }
                } footer: {
                    Text("0 = not at all, 10 = extremely.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Rate Protocol")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("saveRatingButton")
                }
            }
        }
        .frame(minWidth: 340, minHeight: 260)
        .onAppear {
            if let existingRating {
                complexityRating = Double(existingRating.complexityRating)
                durationRating = Double(existingRating.durationRating)
            }
        }
        .alert("Couldn't save rating", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let userID = appSession.currentUserID else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appSession.makeSyncServices().protocolRatingSync.rate(
                protocolServerID: protocolServerID,
                userID: userID,
                complexityRating: Int(complexityRating),
                durationRating: Int(durationRating)
            )
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

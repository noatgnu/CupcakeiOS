import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct BookInstrumentForJobSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CachedInstrument.createdAt, order: .reverse) private var instruments: [CachedInstrument]

    let jobClientID: UUID
    let jobServerID: Int64

    @State private var selectedInstrumentServerID: Int64?
    @State private var instrumentSearchText = ""
    @State private var startTime = Date()
    @State private var isInProgress = true
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var usageDescription = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var canSave: Bool {
        selectedInstrumentServerID != nil && !usageDescription.isEmpty && (isInProgress || endTime > startTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instrument") {
                    SearchableSelectionList(
                        items: instruments,
                        searchPlaceholder: "Search instruments",
                        searchFieldIdentifier: "jobBookingInstrumentSearchField",
                        searchText: $instrumentSearchText,
                        matches: { $0.instrumentName.localizedCaseInsensitiveContains($1) },
                        isSelected: { $0.serverID == selectedInstrumentServerID },
                        rowIdentifier: { "jobBookingInstrumentRow_\($0.instrumentName)" },
                        onSelect: { selectedInstrumentServerID = $0.serverID }
                    ) { instrument in
                        Text(instrument.instrumentName)
                    }
                }
                ExistingBookingsSection(instrumentServerID: selectedInstrumentServerID)
                Section {
                    DatePicker("Start Time", selection: $startTime)
                        .accessibilityIdentifier("jobBookingStartTimePicker")
                    Toggle("In Progress (no end time yet)", isOn: $isInProgress)
                        .accessibilityIdentifier("jobBookingInProgressToggle")
                    if !isInProgress {
                        DatePicker("End Time", selection: $endTime)
                            .accessibilityIdentifier("jobBookingEndTimePicker")
                    }
                    TextField("Description", text: $usageDescription, axis: .vertical)
                        .accessibilityIdentifier("jobBookingDescriptionField")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Book Instrument")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveJobBookingButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 420)
        .alert("Couldn't book instrument", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        guard let selectedInstrumentServerID, let instrumentName = instruments.first(where: { $0.serverID == selectedInstrumentServerID })?.instrumentName else { return }
        isSaving = true
        defer { isSaving = false }

        let services = appSession.makeSyncServices()
        do {
            try await services.instrumentJobAnnotationSync.createBookingAnnotation(
                jobServerID: jobServerID,
                jobClientID: jobClientID,
                instrumentServerID: selectedInstrumentServerID,
                instrumentName: instrumentName,
                timeStarted: Self.iso8601.string(from: startTime),
                timeEnded: isInProgress ? nil : Self.iso8601.string(from: endTime),
                usageDescription: usageDescription
            )
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private static let iso8601 = ISO8601DateFormatter()
}

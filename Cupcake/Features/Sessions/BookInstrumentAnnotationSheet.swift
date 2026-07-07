import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Step-scoped instrument booking annotation (instrument picker, start/end time, description). Online-only.
struct BookInstrumentAnnotationSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CachedInstrument.instrumentName) private var instruments: [CachedInstrument]

    let sessionServerID: Int64
    let sessionClientID: UUID
    let stepServerID: Int64
    let stepClientID: UUID

    @State private var selectedInstrumentServerID: Int64?
    @State private var startTime = Date().addingTimeInterval(3600)
    @State private var endTime = Date().addingTimeInterval(3600 * 3)
    @State private var usageDescription = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var bookableInstruments: [CachedInstrument] {
        instruments.filter { $0.acceptsBookings }
    }

    private var canSave: Bool {
        selectedInstrumentServerID != nil && endTime > startTime
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Instrument") {
                    Picker("Instrument", selection: $selectedInstrumentServerID) {
                        Text("None").tag(Int64?.none)
                        ForEach(bookableInstruments) { instrument in
                            Text(instrument.instrumentName).tag(Optional(instrument.serverID))
                        }
                    }
                    .accessibilityIdentifier("bookingAnnotationInstrumentPicker")
                }
                ExistingBookingsSection(instrumentServerID: selectedInstrumentServerID)
                Section {
                    DatePicker("Start Time", selection: $startTime)
                        .accessibilityIdentifier("bookingAnnotationStartTimePicker")
                    DatePicker("End Time", selection: $endTime)
                        .accessibilityIdentifier("bookingAnnotationEndTimePicker")
                    TextField("Description", text: $usageDescription, axis: .vertical)
                        .accessibilityIdentifier("bookingAnnotationDescriptionField")
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
                    .accessibilityIdentifier("saveBookingAnnotationButton")
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
        guard let selectedInstrumentServerID,
              let instrumentName = instruments.first(where: { $0.serverID == selectedInstrumentServerID })?.instrumentName else { return }
        isSaving = true
        defer { isSaving = false }

        let services = appSession.makeSyncServices()
        do {
            try await services.stepAnnotationSync.createBookingAnnotation(
                sessionServerID: sessionServerID,
                sessionClientID: sessionClientID,
                stepServerID: stepServerID,
                stepClientID: stepClientID,
                instrumentServerID: selectedInstrumentServerID,
                instrumentName: instrumentName,
                timeStarted: Self.iso8601.string(from: startTime),
                timeEnded: Self.iso8601.string(from: endTime),
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

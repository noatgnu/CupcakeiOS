import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Field set and layout verified against the reference web app's `instrument-usage-modal.ts`:
/// two separate date-time pickers (start required, end optional — "leave empty if in
/// progress"), a description field, and a maintenance checkbox. The instrument itself is fixed
/// context, not a form field, matching `@Input() instrument` there. `approved` is deliberately
/// never sent or defaulted to `true` by this app — see `CreateInstrumentUsageRequest`'s doc
/// comment.
///
/// Always created locally first, then synced immediately when signed in — a genuine
/// unreachability failure queues it in the outbox, same pattern as every other create flow.
struct BookInstrumentSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let instrumentServerID: Int64
    let instrumentName: String

    @State private var startTime = Date()
    @State private var isInProgress = true
    @State private var endTime = Date().addingTimeInterval(3600)
    @State private var usageDescription = ""
    @State private var maintenance = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var canSave: Bool {
        !usageDescription.isEmpty && (isInProgress || endTime > startTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start Time", selection: $startTime)
                        .accessibilityIdentifier("bookingStartTimePicker")
                    Toggle("In Progress (no end time yet)", isOn: $isInProgress)
                        .accessibilityIdentifier("bookingInProgressToggle")
                    if !isInProgress {
                        DatePicker("End Time", selection: $endTime)
                            .accessibilityIdentifier("bookingEndTimePicker")
                    }
                    TextField("Description", text: $usageDescription, axis: .vertical)
                        .accessibilityIdentifier("bookingDescriptionField")
                    Toggle("Maintenance", isOn: $maintenance)
                        .accessibilityIdentifier("bookingMaintenanceToggle")
                } footer: {
                    Text("Booking \(instrumentName).")
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
                    .accessibilityIdentifier("saveBookingButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 400)
        .alert("Couldn't book instrument", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let usage = CachedInstrumentUsage(
            instrumentServerID: instrumentServerID,
            instrumentName: instrumentName,
            timeStarted: Self.iso8601.string(from: startTime),
            timeEnded: isInProgress ? nil : Self.iso8601.string(from: endTime),
            usageDescription: usageDescription,
            approved: false,
            maintenance: maintenance
        )
        modelContext.insert(usage)
        try? modelContext.save()

        guard appSession.isAuthenticated else {
            dismiss()
            return
        }

        let clientID = usage.clientID
        let services = appSession.makeSyncServices()
        do {
            try await services.instrumentSync.syncLocallyCreatedInstrumentUsage(clientID: clientID)
            dismiss()
        } catch let error as APIError {
            if case .transport = error {
                try? await services.outboxSync.enqueueCreateInstrumentUsage(clientID: clientID)
                dismiss()
            } else {
                errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
                isShowingError = true
            }
        } catch {
            errorMessage = "Saved locally, but couldn't sync: \(error.localizedDescription)"
            isShowingError = true
        }
    }

    private static let iso8601 = ISO8601DateFormatter()
}

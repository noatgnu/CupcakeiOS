import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct InstrumentDetailView: View {
    let instrumentServerID: Int64
    let ontologyStore: ModelContainer

    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Query private var instruments: [CachedInstrument]
    @Query private var usages: [CachedInstrumentUsage]
    @Query private var maintenanceLogs: [CachedMaintenanceLog]
    @State private var isShowingBookingSheet = false
    @State private var isShowingMaintenanceSheet = false
    @State private var isShowingEditSheet = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var editingMetadataColumn: CachedMetadataColumn?
    @State private var isShowingAddMetadataColumnSheet = false

    private var instrument: CachedInstrument? {
        instruments.first(where: { $0.serverID == instrumentServerID })
    }

    private var bookings: [CachedInstrumentUsage] {
        usages
            .filter { $0.instrumentServerID == instrumentServerID }
            .sorted { ($0.timeStarted ?? "") > ($1.timeStarted ?? "") }
    }

    private var logs: [CachedMaintenanceLog] {
        maintenanceLogs
            .filter { $0.instrumentServerID == instrumentServerID }
            .sorted { ($0.maintenanceDate ?? "") > ($1.maintenanceDate ?? "") }
    }

    private func timeRangeText(_ booking: CachedInstrumentUsage) -> String {
        let start = HumanReadableTime.formatAbsolute(booking.timeStarted) ?? "…"
        let end = booking.timeEnded.flatMap(HumanReadableTime.formatAbsolute) ?? "In Progress"
        return "\(start) – \(end)"
    }

    var body: some View {
        List {
            if let instrument {
                Section("Info") {
                    if let description = instrument.instrumentDescription {
                        Text(description)
                    }
                    if instrument.maintenanceOverdue {
                        Label("Maintenance overdue", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            Section("Bookings") {
                if bookings.isEmpty {
                    Text("No bookings yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bookings) { booking in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(booking.usageDescription)
                            HStack(spacing: 4) {
                                Text(timeRangeText(booking))
                                if booking.maintenance {
                                    Text("· Maintenance")
                                }
                                Text(booking.approved ? "· Approved" : "· Pending")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            MetadataFieldsSection(
                metadataTableServerID: instrument?.metadataTableServerID,
                ontologyStore: ontologyStore,
                onColumnsChanged: { await refreshMetadataTable() },
                editingColumn: $editingMetadataColumn,
                isShowingAddColumnSheet: $isShowingAddMetadataColumnSheet
            )
            Section("Maintenance") {
                if logs.isEmpty {
                    Text("No maintenance logged yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.maintenanceDescription?.isEmpty == false ? log.maintenanceDescription! : log.maintenanceType.capitalized)
                            HStack(spacing: 4) {
                                Text(HumanReadableTime.formatAbsolute(log.maintenanceDate) ?? "No date")
                                Text("· \(log.status.replacingOccurrences(of: "_", with: " ").capitalized)")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            if log.status != "completed" {
                                Button("Complete") {
                                    Task { await markComplete(log) }
                                }
                                .tint(.green)
                                .accessibilityIdentifier("completeMaintenanceLogButton")
                            }
                        }
                        .contextMenu {
                            if log.status != "completed" {
                                Button("Complete") {
                                    Task { await markComplete(log) }
                                }
                                .accessibilityIdentifier("completeMaintenanceLogMenuButton")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(instrument?.instrumentName ?? "Instrument")
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingBookingSheet = true
                } label: {
                    Label("Book", systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("bookInstrumentButton")
            }
            ToolbarItem {
                Button {
                    isShowingMaintenanceSheet = true
                } label: {
                    Label("Log Maintenance", systemImage: "wrench.and.screwdriver")
                }
                .accessibilityIdentifier("logMaintenanceButton")
            }
            ToolbarItem {
                Menu {
                    Button {
                        isShowingEditSheet = true
                    } label: {
                        Label("Edit Instrument", systemImage: "pencil")
                    }
                    .accessibilityIdentifier("editInstrumentButton")
                    if let instrument {
                        Button {
                            Task { await toggleEnabled(instrument) }
                        } label: {
                            Label(instrument.enabled ? "Disable" : "Enable", systemImage: instrument.enabled ? "xmark.circle" : "checkmark.circle")
                        }
                        .accessibilityIdentifier("toggleInstrumentEnabledButton")
                    }
                    Button(role: .destructive) {
                        Task { await deleteInstrument() }
                    } label: {
                        Label("Delete Instrument", systemImage: "trash")
                    }
                    .accessibilityIdentifier("deleteInstrumentButton")
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(isDeleting)
            }
        }
        .sheet(isPresented: $isShowingBookingSheet) {
            BookInstrumentSheet(instrumentServerID: instrumentServerID, instrumentName: instrument?.instrumentName ?? "Instrument")
        }
        .sheet(isPresented: $isShowingMaintenanceSheet) {
            LogMaintenanceSheet(instrumentServerID: instrumentServerID, instrumentName: instrument?.instrumentName ?? "Instrument")
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let instrument {
                EditInstrumentSheet(existingInstrument: instrument)
            }
        }
        .sheet(item: $editingMetadataColumn) { column in
            MetadataValueEditSheet(column: column, projectServerID: nil, ontologyStore: ontologyStore)
        }
        .sheet(isPresented: $isShowingAddMetadataColumnSheet) {
            if let tableServerID = instrument?.metadataTableServerID {
                AddMetadataColumnSheet(tableServerID: tableServerID, ontologyStore: ontologyStore) {
                    await refreshMetadataTable()
                }
            }
        }
        .alert("Couldn't update instrument", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            try? await appSession.makeSyncServices().maintenanceLogSync.refetch(instrumentServerID: instrumentServerID)
            await refreshMetadataTable()
        }
    }

    private func refreshMetadataTable() async {
        guard let tableServerID = instrument?.metadataTableServerID else { return }
        try? await appSession.makeSyncServices().instrumentSync.refreshMetadataTable(instrumentServerID: instrumentServerID, metadataTableServerID: tableServerID)
    }

    private func markComplete(_ log: CachedMaintenanceLog) async {
        try? await appSession.makeSyncServices().maintenanceLogSync.updateStatus(serverID: log.serverID, status: "completed")
    }

    private func toggleEnabled(_ instrument: CachedInstrument) async {
        do {
            try await appSession.makeSyncServices().instrumentSync.updateInstrument(
                serverID: instrument.serverID,
                instrumentName: instrument.instrumentName,
                instrumentDescription: instrument.instrumentDescription,
                enabled: !instrument.enabled,
                acceptsBookings: instrument.acceptsBookings,
                allowOverlappingBookings: instrument.allowOverlappingBookings
            )
            instrument.enabled.toggle()
            try? modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func deleteInstrument() async {
        guard let instrument else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await appSession.makeSyncServices().instrumentSync.deleteInstrument(serverID: instrument.serverID)
            modelContext.delete(instrument)
            try? modelContext.save()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

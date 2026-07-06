import CupcakeModels
import SwiftData
import SwiftUI

/// Matches the reference web app's per-instrument "Bookings" tab (`instruments.ts:672-698`,
/// `instruments.html:806-887`): time started/ended (or "In Progress" if not yet ended),
/// description, and a status showing "Maintenance" when the booking is a maintenance block,
/// plus Approved/Pending from `approved`. `maintenanceOverdue` is surfaced here (not in the
/// list row), matching the reference app's own instrument-detail placement.
struct InstrumentDetailView: View {
    let instrumentServerID: Int64

    @Query private var instruments: [CachedInstrument]
    @Query private var usages: [CachedInstrumentUsage]
    @State private var isShowingBookingSheet = false

    private var instrument: CachedInstrument? {
        instruments.first(where: { $0.serverID == instrumentServerID })
    }

    private var bookings: [CachedInstrumentUsage] {
        usages
            .filter { $0.instrumentServerID == instrumentServerID }
            .sorted { ($0.timeStarted ?? "") > ($1.timeStarted ?? "") }
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
        }
        .sheet(isPresented: $isShowingBookingSheet) {
            BookInstrumentSheet(instrumentServerID: instrumentServerID, instrumentName: instrument?.instrumentName ?? "Instrument")
        }
    }
}

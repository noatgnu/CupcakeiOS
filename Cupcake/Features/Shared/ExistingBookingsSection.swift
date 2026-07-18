import CupcakeModels
import SwiftData
import SwiftUI

struct ExistingBookingsSection: View {
    let instrumentServerID: Int64?

    @Query private var allUsages: [CachedInstrumentUsage]

    private var bookings: [CachedInstrumentUsage] {
        guard let instrumentServerID else { return [] }
        return allUsages
            .filter { $0.instrumentServerID == instrumentServerID }
            .sorted { ($0.timeStarted ?? "") < ($1.timeStarted ?? "") }
    }

    var body: some View {
        Section("Existing Bookings") {
            if instrumentServerID == nil {
                Text("Select an instrument to see its existing bookings.")
                    .foregroundStyle(.secondary)
            } else if bookings.isEmpty {
                Text("No existing bookings for this instrument.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bookings) { booking in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(HumanReadableTime.formatRange(start: booking.timeStarted, end: booking.timeEnded))
                        Text(booking.usageDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("existingBookingRow_\(booking.serverID.map(String.init) ?? booking.clientID.uuidString)")
                }
            }
        }
    }
}

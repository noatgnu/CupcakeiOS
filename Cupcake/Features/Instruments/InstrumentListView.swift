import CupcakeModels
import SwiftData
import SwiftUI

/// Field set and layout verified against the reference web app's `instruments.ts`/`.html`: a
/// flat list (no lab-group grouping — instrument access there is ACL-based, not lab-group-based)
/// showing name, truncated description, and Enabled/Disabled + Accepts Bookings badges.
/// `maintenanceOverdue` deliberately isn't shown here — the reference app only surfaces it in the
/// instrument's own detail/maintenance section (`instruments.html:580,596`), not the list row.
struct InstrumentListView: View {
    @Query(sort: \CachedInstrument.instrumentName) private var instruments: [CachedInstrument]

    var body: some View {
        NavigationStack {
            Group {
                if instruments.isEmpty {
                    ContentUnavailableView(
                        "No Instruments",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Instruments synced from the server will appear here.")
                    )
                } else {
                    List(instruments, id: \.serverID) { instrument in
                        NavigationLink(value: instrument.serverID) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(instrument.instrumentName)
                                if let description = instrument.instrumentDescription {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                HStack(spacing: 6) {
                                    badge(instrument.enabled ? "Enabled" : "Disabled", color: instrument.enabled ? .green : .gray)
                                    if instrument.acceptsBookings {
                                        badge("Accepts Bookings", color: .blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Instruments")
            .navigationDestination(for: Int64.self) { serverID in
                InstrumentDetailView(instrumentServerID: serverID)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

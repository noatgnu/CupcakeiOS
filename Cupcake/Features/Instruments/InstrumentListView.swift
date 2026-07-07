import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

/// Flat two-panel list of instruments (sidebar) with the selected instrument's detail on the right.
struct InstrumentListView<SectionPicker: View>: View {
    @ViewBuilder let sectionPicker: () -> SectionPicker

    @Environment(AppSession.self) private var appSession
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CachedInstrument.instrumentName) private var instruments: [CachedInstrument]
    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "Instruments")]
    @State private var selectedInstrumentServerID: Int64?
    @State private var isShowingNewInstrumentSheet = false
    @State private var editInstrumentTarget: CachedInstrument?
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var searchText = ""

    private var filteredInstruments: [CachedInstrument] {
        instruments.filter { searchText.isEmpty || $0.instrumentName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack) {
            SelectableExplorerList(
                selection: $selectedInstrumentServerID,
                isEmpty: filteredInstruments.isEmpty,
                emptyTitle: "No Instruments",
                emptySystemImage: "wrench.and.screwdriver",
                emptyMessage: instruments.isEmpty ? "Instruments synced from the server will appear here." : "No instruments match your search."
            ) {
                ForEach(filteredInstruments, id: \.serverID) { instrument in
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
                    .tag(instrument.serverID)
                    .contextMenu {
                        Button {
                            editInstrumentTarget = instrument
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task { await deleteInstrument(instrument) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewInstrumentSheet = true
                    } label: {
                        Label("New Instrument", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newInstrumentButton")
                }
            }
        } detail: {
            if let selectedInstrumentServerID {
                InstrumentDetailView(instrumentServerID: selectedInstrumentServerID)
            } else {
                ExplorerList(
                    isEmpty: true,
                    emptyTitle: "No Instrument Selected",
                    emptySystemImage: "wrench.and.screwdriver",
                    emptyMessage: "Select an instrument to see its details."
                ) { EmptyView() }
            }
        } sidebarHeader: {
            VStack(spacing: 8) {
                TextField("Search instruments", text: $searchText)
                    .accessibilityIdentifier("instrumentSearchField")
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                sectionPicker()
            }
        }
        .onChange(of: selectedInstrumentServerID) { _, newValue in
            guard let newValue, let instrument = instruments.first(where: { $0.serverID == newValue }) else {
                pathStack = [pathStack[0]]
                return
            }
            pathStack = [pathStack[0], BreadcrumbSegment(id: instrument.serverID, name: instrument.instrumentName)]
        }
        .onChange(of: pathStack) { _, newValue in
            if newValue.count == 1 {
                selectedInstrumentServerID = nil
            }
        }
        .sheet(isPresented: $isShowingNewInstrumentSheet) {
            EditInstrumentSheet()
        }
        .sheet(item: $editInstrumentTarget) { instrument in
            EditInstrumentSheet(existingInstrument: instrument)
        }
        .alert("Couldn't delete instrument", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deleteInstrument(_ instrument: CachedInstrument) async {
        do {
            try await appSession.makeSyncServices().instrumentSync.deleteInstrument(serverID: instrument.serverID)
            modelContext.delete(instrument)
            try? modelContext.save()
            if selectedInstrumentServerID == instrument.serverID {
                selectedInstrumentServerID = nil
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
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

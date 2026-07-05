import CupcakeModels
import SwiftData
import SwiftUI

/// Shows a stored reagent's stock and its full add/reserve action history — `currentQuantity`
/// is a server-computed sum of these actions (§4), never edited directly.
struct StoredReagentDetailView: View {
    let storedReagentClientID: UUID

    @Query private var storedReagents: [CachedStoredReagent]
    @Query private var actions: [CachedReagentAction]

    @State private var isShowingRecordActionSheet = false

    private var storedReagent: CachedStoredReagent? {
        storedReagents.first(where: { $0.clientID == storedReagentClientID })
    }

    private var actionsHere: [CachedReagentAction] {
        actions
            .filter { $0.storedReagentClientID == storedReagentClientID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if let storedReagent {
                Section("Stock") {
                    let unit = storedReagent.reagentUnit ?? ""
                    LabeledContent("Quantity", value: "\(storedReagent.quantity.formatted()) \(unit)")
                    LabeledContent("Current Quantity", value: "\(storedReagent.currentQuantity.formatted()) \(unit)")
                    if let barcode = storedReagent.barcode {
                        LabeledContent("Barcode", value: barcode)
                    }
                    if let expirationDate = storedReagent.expirationDate {
                        LabeledContent("Expires", value: expirationDate)
                    }
                }
            }
            Section("History") {
                if actionsHere.isEmpty {
                    Text("No actions recorded yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(actionsHere) { action in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(action.actionType == "add" ? "Add" : "Reserve") \(action.quantity.formatted()) \(storedReagent?.reagentUnit ?? "")")
                            if let notes = action.notes {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(storedReagent?.reagentName ?? "Reagent")
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingRecordActionSheet = true
                } label: {
                    Label("Record Action", systemImage: "plus")
                }
                .accessibilityIdentifier("recordActionButton")
            }
        }
        .sheet(isPresented: $isShowingRecordActionSheet) {
            if let storedReagent {
                RecordReagentActionSheet(storedReagent: storedReagent)
            }
        }
    }
}

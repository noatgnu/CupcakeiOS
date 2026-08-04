import CupcakeModels
import SwiftUI

struct InsertReagentTokenView: View {
    let stepReagents: [(stepReagent: CachedStepReagent, reagent: CachedReagent)]
    let onInsert: (String) -> Void
    let onAttachNewReagent: (() -> Void)?

    var body: some View {
        NavigationStack {
            List {
                if stepReagents.isEmpty {
                    Text("No reagents attached to this step yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(stepReagents, id: \.stepReagent.clientID) { entry in
                    Section(entry.reagent.name) {
                        if let id = entry.stepReagent.serverID {
                            propertyButton(title: "Name", token: "%\(id).name%")
                            propertyButton(title: "Quantity", token: "%\(id).quantity%")
                            if entry.stepReagent.scalable {
                                propertyButton(title: "Scaled Quantity", token: "%\(id).scaled_quantity%")
                            }
                            propertyButton(title: "Unit", token: "%\(id).unit%")
                        } else {
                            Text("Syncing… available once this reagent finishes syncing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let onAttachNewReagent {
                    Section {
                        Button {
                            onAttachNewReagent()
                        } label: {
                            Label("Attach New Reagent…", systemImage: "plus")
                        }
                        .accessibilityIdentifier("attachNewReagentFromEditorButton")
                    }
                }
            }
            .navigationTitle("Insert Reagent")
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 360)
        #endif
    }

    private func propertyButton(title: String, token: String) -> some View {
        Button {
            onInsert(token)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(token)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("reagentTokenOption_\(title)")
    }
}

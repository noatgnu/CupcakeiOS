import SwiftData
import SwiftUI

struct InventoryView: View {
    let ontologyStore: ModelContainer

    private enum Section: String, CaseIterable {
        case storage = "Storage"
        case instruments = "Instruments"
    }

    @State private var selection: Section = .storage

    var body: some View {
        switch selection {
        case .storage:
            StorageListView(ontologyStore: ontologyStore, sectionPicker: { sectionPicker })
        case .instruments:
            InstrumentListView(ontologyStore: ontologyStore, sectionPicker: { sectionPicker })
        }
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $selection) {
            ForEach(Section.allCases, id: \.self) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .accessibilityIdentifier("inventorySectionPicker")
    }
}

import SwiftUI

/// Merges what used to be two separate tabs (Storage, Instruments) into one, to keep the total
/// tab count at 4 — avoiding iOS's "More" overflow entirely, which showed a genuine double
/// back-button bug for any tab landing there that does its own internal push navigation (list ->
/// detail). Each side keeps its own independent `NavigationStack` (not merged into one shared
/// stack) specifically to avoid a `navigationDestination(for: Int64.self)` collision between
/// `StorageListView`'s recursive drill-down and `InstrumentListView`'s instrument detail — this
/// segmented switch just swaps which one is currently visible, the same way each TabView tab
/// already keeps its own independent stack.
struct InventoryView: View {
    private enum Section: String, CaseIterable {
        case storage = "Storage"
        case instruments = "Instruments"
    }

    @State private var selection: Section = .storage

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selection) {
                ForEach(Section.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .accessibilityIdentifier("inventorySectionPicker")

            switch selection {
            case .storage:
                NavigationStack {
                    StorageListView(parentServerID: nil)
                }
            case .instruments:
                InstrumentListView()
            }
        }
    }
}

import SwiftUI

struct SearchableSelectionList<Item: Identifiable, RowLabel: View>: View {
    let items: [Item]
    let searchPlaceholder: String
    let searchFieldIdentifier: String
    @Binding var searchText: String
    let matches: (Item, String) -> Bool
    let isSelected: (Item) -> Bool
    let rowIdentifier: (Item) -> String
    let onSelect: (Item) -> Void
    @ViewBuilder let rowLabel: (Item) -> RowLabel

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter { matches($0, searchText) }
    }

    var body: some View {
        if items.count > 5 {
            TextField(searchPlaceholder, text: $searchText)
                .accessibilityIdentifier(searchFieldIdentifier)
        }
        if items.isEmpty {
            Text("None available.")
                .foregroundStyle(.secondary)
        } else if filteredItems.isEmpty {
            Text("No matches for \"\(searchText)\".")
                .foregroundStyle(.secondary)
        } else {
            ForEach(filteredItems) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack {
                        rowLabel(item)
                        Spacer()
                        if isSelected(item) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(rowIdentifier(item))
            }
        }
    }
}

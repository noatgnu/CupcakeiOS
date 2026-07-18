import SwiftUI

struct ExplorerList<EmptyContent: View, RowContent: View>: View {
    let isEmpty: Bool
    var accessibilityIdentifier: String?
    @ViewBuilder let emptyContent: () -> EmptyContent
    @ViewBuilder let rows: () -> RowContent

    init(
        isEmpty: Bool,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder emptyContent: @escaping () -> EmptyContent,
        @ViewBuilder rows: @escaping () -> RowContent
    ) {
        self.isEmpty = isEmpty
        self.accessibilityIdentifier = accessibilityIdentifier
        self.emptyContent = emptyContent
        self.rows = rows
    }

    init(
        isEmpty: Bool,
        emptyTitle: String,
        emptySystemImage: String,
        emptyMessage: String,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder rows: @escaping () -> RowContent
    ) where EmptyContent == ContentUnavailableView<Label<Text, Image>, Text?, EmptyView> {
        self.isEmpty = isEmpty
        self.accessibilityIdentifier = accessibilityIdentifier
        self.emptyContent = {
            ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyMessage))
        }
        self.rows = rows
    }

    var body: some View {
        List {
            if isEmpty {
                emptyContent()
                    .listRowSeparator(.hidden)
                    .frame(maxWidth: .infinity)
            } else {
                rows()
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .contentMargins(.top, 12, for: .scrollContent)
    }
}

struct SelectableExplorerList<SelectionValue: Hashable, EmptyContent: View, RowContent: View>: View {
    let selection: Binding<SelectionValue?>
    let isEmpty: Bool
    @ViewBuilder let emptyContent: () -> EmptyContent
    @ViewBuilder let rows: () -> RowContent

    init(
        selection: Binding<SelectionValue?>,
        isEmpty: Bool,
        emptyTitle: String,
        emptySystemImage: String,
        emptyMessage: String,
        @ViewBuilder rows: @escaping () -> RowContent
    ) where EmptyContent == ContentUnavailableView<Label<Text, Image>, Text?, EmptyView> {
        self.selection = selection
        self.isEmpty = isEmpty
        self.emptyContent = {
            ContentUnavailableView(emptyTitle, systemImage: emptySystemImage, description: Text(emptyMessage))
        }
        self.rows = rows
    }

    var body: some View {
        List(selection: selection) {
            if isEmpty {
                emptyContent()
                    .listRowSeparator(.hidden)
                    .frame(maxWidth: .infinity)
            } else {
                rows()
            }
        }
        .contentMargins(.top, 12, for: .scrollContent)
    }
}

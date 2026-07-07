import SwiftUI

/// A plain two-panel `NavigationSplitView` of settings sections. No breadcrumb — there's no drill-down hierarchy here.
struct SettingsView: View {
    private enum Section: Hashable {
        case appearance, offlineOntologyData
    }

    // `nil` by default so compact width shows the sidebar first, matching standard iOS Settings.
    @State private var selectedSection: Section?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow

    /// The close button lives inside this view itself, since a `.toolbar` at the call site can't reach both columns.
    private func close() {
        if PlatformWindowPreference.prefersSeparateWindow {
            dismissWindow()
        } else {
            dismiss()
        }
    }

    #if os(macOS)
    private var closeToolbarItem: some ToolbarContent { ToolbarItemGroup {} }
    #else
    @ToolbarContentBuilder
    private var closeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done", action: close)
        }
    }
    #endif

    var body: some View {
        NavigationSplitView {
            SelectableExplorerList(
                selection: $selectedSection,
                isEmpty: false,
                emptyTitle: "",
                emptySystemImage: "",
                emptyMessage: ""
            ) {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                    .tag(Section.appearance)
                Label("Offline Ontology Data", systemImage: "arrow.down.circle")
                    .tag(Section.offlineOntologyData)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .navigationTitle("Settings")
            .toolbar { closeToolbarItem }
        } detail: {
            NavigationStack {
                switch selectedSection {
                case .appearance:
                    AppearanceSettingsView()
                case .offlineOntologyData:
                    OfflineOntologyDataView()
                case nil:
                    ExplorerList(
                        isEmpty: true,
                        emptyTitle: "No Section Selected",
                        emptySystemImage: "gearshape",
                        emptyMessage: "Select a settings section to see its options."
                    ) { EmptyView() }
                }
            }
            .navigationTitle("Settings")
            .toolbar { closeToolbarItem }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

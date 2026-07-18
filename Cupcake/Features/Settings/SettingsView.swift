import SwiftUI

struct SettingsView: View {
    private enum Section: Hashable {
        case appearance, metadata, offlineOntologyData
    }

    @State private var selectedSection: Section?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow

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
                Label("Metadata", systemImage: "tablecells")
                    .tag(Section.metadata)
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
                case .metadata:
                    MetadataSettingsView()
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

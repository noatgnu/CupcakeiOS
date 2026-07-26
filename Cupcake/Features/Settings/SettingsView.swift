import SwiftUI

struct SettingsView: View {
    private enum Section: Hashable {
        case appearance, account, deviceTokens, connection, metadata, offlineOntologyData, ontologyBrowser, transcription
    }

    @Environment(AppSession.self) private var appSession
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
                if appSession.isAuthenticated {
                    Label("Account", systemImage: "person.crop.circle")
                        .tag(Section.account)
                    Label("API Tokens", systemImage: "key")
                        .tag(Section.deviceTokens)
                }
                Label("Connection", systemImage: "wifi.slash")
                    .tag(Section.connection)
                Label("Metadata", systemImage: "tablecells")
                    .tag(Section.metadata)
                Label("Offline Ontology Data", systemImage: "arrow.down.circle")
                    .tag(Section.offlineOntologyData)
                Label("Ontology Browser", systemImage: "magnifyingglass")
                    .tag(Section.ontologyBrowser)
                Label("Transcription", systemImage: "waveform")
                    .tag(Section.transcription)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .navigationTitle("Settings")
            #if os(macOS)
            .toolbar(removing: .title)
            #endif
            .toolbar { closeToolbarItem }
        } detail: {
            NavigationStack {
                switch selectedSection {
                case .appearance:
                    AppearanceSettingsView()
                case .account:
                    AccountSettingsView()
                case .deviceTokens:
                    DeviceTokensView()
                case .connection:
                    ConnectionSettingsView()
                case .metadata:
                    MetadataSettingsView()
                case .offlineOntologyData:
                    OfflineOntologyDataView()
                case .ontologyBrowser:
                    OntologyBrowserView()
                case .transcription:
                    TranscriptionSettingsView()
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
            #if os(macOS)
            .toolbar(removing: .title)
            #endif
            .toolbar { closeToolbarItem }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

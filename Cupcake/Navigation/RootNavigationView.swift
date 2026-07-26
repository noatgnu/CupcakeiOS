
import SwiftData
import SwiftUI

struct RootNavigationView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.openWindow) private var openWindow
    let ontologyStore: ModelContainer

    private enum Tab: CaseIterable {
        case protocols, sessions, jobs, inventory

        var label: String {
            switch self {
            case .protocols: "Protocols"
            case .sessions: "Sessions"
            case .jobs: "Jobs"
            case .inventory: "Inventory"
            }
        }

        var systemImage: String {
            switch self {
            case .protocols: "list.bullet.clipboard"
            case .sessions: "clock"
            case .jobs: "list.clipboard"
            case .inventory: "shippingbox"
            }
        }
    }

    @State private var selectedTab: Tab = .protocols
    @State private var isShowingSettings = false

    var body: some View {
        Group {
            if appSession.canUseApp {
                ZStack {
                    switch selectedTab {
                    case .protocols:
                        ProtocolListView()
                    case .sessions:
                        SessionListView()
                    case .jobs:
                        JobListView(ontologyStore: ontologyStore)
                    case .inventory:
                        InventoryView(ontologyStore: ontologyStore)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !appSession.isShowingPushedDetail {
                        floatingTabSelector
                            .padding(.bottom, 16)
                    }
                }
                .overlay(alignment: .top) {
                    if let progress = appSession.syncProgress {
                        SyncProgressBanner(progress: progress)
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.default, value: appSession.syncProgress)
                .task {
                    try? await appSession.syncAll()
                }
                #if !os(macOS)
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView()
                        .modelContainer(ontologyStore)
                        .frame(minWidth: 400, minHeight: 500)
                }
                #endif
            } else {
                NavigationStack {
                    LoginView()
                }
            }
        }
        .alert(
            "Import Local Notebook?",
            isPresented: Binding(
                get: { appSession.pendingLocalImportCount != nil },
                set: { if !$0 { appSession.dismissLocalImportPrompt() } }
            )
        ) {
            Button("Not Now", role: .cancel) { appSession.dismissLocalImportPrompt() }
            Button("Import") {
                Task { await appSession.importLocalNotebook() }
            }
            .accessibilityIdentifier("importLocalNotebookButton")
        } message: {
            Text("You have \(appSession.pendingLocalImportCount ?? 0) item(s) created while offline. Import them to this server now?")
        }
        .onChange(of: appSession.pendingDeepLink) { _, newValue in
            if newValue != nil {
                selectedTab = .sessions
            }
        }
    }

    private var floatingTabSelector: some View {
        HStack(spacing: 10) {
            ForEach(Tab.allCases, id: \.self) { tab in
                capsuleButton(systemImage: tab.systemImage, label: tab.label, isSelected: selectedTab == tab) {
                    selectedTab = tab
                }
            }
            #if !os(macOS)
            Divider()
                .frame(height: 24)
            capsuleButton(systemImage: "gearshape", label: "Settings", accessibilityIdentifier: "settingsButton", isSelected: false) {
                if PlatformWindowPreference.prefersSeparateWindow {
                    PlatformWindowPreference.openOrFocusWindow(id: "settings", using: openWindow)
                } else {
                    isShowingSettings = true
                }
            }
            if appSession.isAuthenticated {
                Menu {
                    Button("Switch Instance…") {
                        appSession.leaveActiveInstance()
                    }
                    .accessibilityIdentifier("switchInstanceButton")
                    Button("Sign Out", role: .destructive) {
                        Task { await appSession.signOut() }
                    }
                    .accessibilityIdentifier("signOutButton")
                } label: {
                    capsuleIcon(systemImage: "person.crop.circle", isSelected: false)
                }
                .accessibilityIdentifier("accountMenu")
                .help("Account")
            }
            #endif
        }
    }

    private func capsuleButton(systemImage: String, label: String, accessibilityIdentifier: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            capsuleIcon(systemImage: systemImage, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityIdentifier ?? label)
    }

    private func capsuleIcon(systemImage: String, isSelected: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .frame(width: 44, height: 44)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .background(
                Circle().fill(isSelected ? Color.accentColor.opacity(0.15) : .clear)
            )
            .background(
                Circle().fill(.regularMaterial)
            )
            .overlay(
                Circle().strokeBorder(.separator, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

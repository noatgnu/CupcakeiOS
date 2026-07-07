import SwiftUI

/// A two-panel explorer layout (sidebar + detail) with a breadcrumb bar.
struct TwoPanelExplorerView<SidebarHeader: View, Sidebar: View, Detail: View>: View {
    @Binding var pathStack: [BreadcrumbSegment]
    /// True for flat selection lists, where compact width pushes a dedicated detail page instead of stacking.
    let pushesDetailOnCompact: Bool
    let sidebarHeader: () -> SidebarHeader
    let sidebar: () -> Sidebar
    let detail: () -> Detail

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var navigationPath = NavigationPath()

    init(
        pathStack: Binding<[BreadcrumbSegment]>,
        pushesDetailOnCompact: Bool = false,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping () -> Detail,
        @ViewBuilder sidebarHeader: @escaping () -> SidebarHeader = { EmptyView() }
    ) {
        self._pathStack = pathStack
        self.pushesDetailOnCompact = pushesDetailOnCompact
        self.sidebar = sidebar
        self.detail = detail
        self.sidebarHeader = sidebarHeader
    }

    var body: some View {
        if horizontalSizeClass == .compact {
            compactBody
        } else {
            regularBody
        }
    }

    private var regularBody: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                sectionTitle
                sidebarHeader()
                sidebar()
            }
            .toolbar(removing: .title)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            NavigationStack {
                detail()
                    // Suppresses the native title, which would duplicate the breadcrumb bar's last segment.
                    .toolbar(removing: .title)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            BreadcrumbBar(segments: pathStack, onGoBack: goBack, onSelect: goToSegment)
                        }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Sidebar header showing this panel's fixed name. iOS/iPadOS only — macOS shows it via the breadcrumb bar.
    @ViewBuilder
    private var sectionTitle: some View {
        #if os(macOS)
        EmptyView()
        #else
        Text(pathStack.first?.name ?? "")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, -16)
            .padding(.bottom, 4)
        #endif
    }

    private var compactBody: some View {
        NavigationStack(path: $navigationPath) {
            compactSidebarPage
                .navigationDestination(for: BreadcrumbSegment.self) { _ in
                    if pushesDetailOnCompact {
                        detail()
                    } else {
                        compactPage
                    }
                }
        }
        .onAppear { syncNavigationPath() }
        .onChange(of: pathStack) { syncNavigationPath() }
    }

    private func syncNavigationPath() {
        var path = NavigationPath()
        for segment in pathStack.dropFirst() {
            path.append(segment)
        }
        navigationPath = path
    }

    /// The root compact page: sidebar only when pushing detail separately, else sidebar+detail stacked.
    private var compactSidebarPage: some View {
        VStack(spacing: 0) {
            sectionTitle
            sidebarHeader()
            sidebar()
            if !pushesDetailOnCompact {
                Divider()
                detail()
            }
        }
        .toolbar(removing: .title)
    }

    private var compactPage: some View {
        VStack(spacing: 0) {
            sectionTitle
            sidebarHeader()
            sidebar()
            Divider()
            detail()
        }
        .toolbar(removing: .title)
    }

    private func goBack() {
        guard pathStack.count > 1 else { return }
        pathStack.removeLast()
    }

    private func goToSegment(_ index: Int) {
        guard index < pathStack.count else { return }
        pathStack = Array(pathStack.prefix(index + 1))
    }
}

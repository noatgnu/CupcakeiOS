import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct FavouritesManagementSheet: View {
    @Environment(AppSession.self) private var appSession
    @Query private var labGroups: [CachedLabGroup]

    @State private var personalFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var labGroupFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var globalFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var personalPage = 0
    @State private var labGroupPage = 0
    @State private var globalPage = 0
    private let pageSize = 20

    var body: some View {
        Form {
            favouritesSection("Personal", favourites: personalFavourites, page: $personalPage)
            favouritesSection("Lab Group", favourites: labGroupFavourites, page: $labGroupPage, showLabGroupName: true)
            favouritesSection("Global", favourites: globalFavourites, page: $globalPage)
            if !isLoading && personalFavourites.isEmpty && labGroupFavourites.isEmpty && globalFavourites.isEmpty {
                Text("No favourites yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("My Favourites")
        .alert("Couldn't update favourites", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadAll()
        }
    }

    @ViewBuilder
    private func favouritesSection(_ title: String, favourites: [FavouriteMetadataOptionDTO], page: Binding<Int>, showLabGroupName: Bool = false) -> some View {
        if !favourites.isEmpty {
            let totalPages = max(1, Int(ceil(Double(favourites.count) / Double(pageSize))))
            let start = page.wrappedValue * pageSize
            let paged = start < favourites.count ? Array(favourites[start..<min(start + pageSize, favourites.count)]) : []
            Section("\(title) (\(favourites.count))") {
                ForEach(paged) { favourite in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favourite.displayValue ?? favourite.value ?? "")
                        Text(showLabGroupName ? "\(favourite.name) · \(favourite.labGroupName ?? "")" : favourite.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("favouriteRow_\(favourite.id)")
                }
                .onDelete { offsets in
                    Task { await deleteFavourites(paged, at: offsets) }
                }
                if totalPages > 1 {
                    HStack {
                        Button("Previous") { page.wrappedValue -= 1 }
                            .disabled(page.wrappedValue == 0)
                        Spacer()
                        Text("Page \(page.wrappedValue + 1) of \(totalPages)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Next") { page.wrappedValue += 1 }
                            .disabled(page.wrappedValue >= totalPages - 1)
                    }
                }
            }
        }
    }

    private func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        let services = appSession.makeSyncServices()
        let userID = appSession.currentUserID

        async let personal: [FavouriteMetadataOptionDTO] = fetchOrEmpty {
            guard let userID else { return [] }
            return try await services.favouriteMetadataOptionSync.fetchPersonalFavourites(userID: userID, limit: 100)
        }
        async let labGroup: [FavouriteMetadataOptionDTO] = fetchOrEmpty {
            var all: [FavouriteMetadataOptionDTO] = []
            for labGroup in labGroups {
                all += try await services.favouriteMetadataOptionSync.fetchLabGroupFavourites(labGroupID: labGroup.serverID, limit: 100)
            }
            return all
        }
        async let global: [FavouriteMetadataOptionDTO] = fetchOrEmpty {
            try await services.favouriteMetadataOptionSync.fetchGlobalFavourites(limit: 100)
        }

        personalFavourites = await personal
        labGroupFavourites = await labGroup
        globalFavourites = await global
    }

    private func fetchOrEmpty(_ body: () async throws -> [FavouriteMetadataOptionDTO]) async -> [FavouriteMetadataOptionDTO] {
        (try? await body()) ?? []
    }

    private func deleteFavourites(_ favourites: [FavouriteMetadataOptionDTO], at offsets: IndexSet) async {
        let toDelete = offsets.map { favourites[$0] }
        do {
            let services = appSession.makeSyncServices()
            for favourite in toDelete {
                try await services.favouriteMetadataOptionSync.deleteFavourite(id: favourite.id)
            }
            await loadAll()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

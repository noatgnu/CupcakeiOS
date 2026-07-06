import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct FavouritesManagementSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    @Query private var labGroups: [CachedLabGroup]

    @State private var personalFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var labGroupFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var globalFavourites: [FavouriteMetadataOptionDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Form {
                favouritesSection("Personal", favourites: personalFavourites)
                favouritesSection("Lab Group", favourites: labGroupFavourites, showLabGroupName: true)
                favouritesSection("Global", favourites: globalFavourites)
                if !isLoading && personalFavourites.isEmpty && labGroupFavourites.isEmpty && globalFavourites.isEmpty {
                    Text("No favourites yet.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("My Favourites")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 440)
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
    private func favouritesSection(_ title: String, favourites: [FavouriteMetadataOptionDTO], showLabGroupName: Bool = false) -> some View {
        if !favourites.isEmpty {
            Section(title) {
                ForEach(favourites) { favourite in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(favourite.displayValue ?? favourite.value ?? "")
                        Text(showLabGroupName ? "\(favourite.name) · \(favourite.labGroupName ?? "")" : favourite.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("favouriteRow_\(favourite.id)")
                }
                .onDelete { offsets in
                    Task { await deleteFavourites(favourites, at: offsets) }
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

import Testing

@testable import CupcakeAuth

@Suite("KeychainStore", .serialized)
struct KeychainStoreTests {
    @Test("round-trips a saved token")
    func roundTrips() throws {
        let store = KeychainStore(service: "com.erymonite.cupcake.tests", account: "round-trip")
        defer { store.delete() }

        try store.save("device-token-value")
        #expect(store.load() == "device-token-value")
    }

    @Test("overwrites a previously saved token")
    func overwrites() throws {
        let store = KeychainStore(service: "com.erymonite.cupcake.tests", account: "overwrite")
        defer { store.delete() }

        try store.save("first-value")
        try store.save("second-value")
        #expect(store.load() == "second-value")
    }

    @Test("returns nil after delete")
    func deletesToken() throws {
        let store = KeychainStore(service: "com.erymonite.cupcake.tests", account: "delete")

        try store.save("to-be-deleted")
        store.delete()
        #expect(store.load() == nil)
    }
}

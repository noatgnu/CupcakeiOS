import Foundation

public struct KnownInstance: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var label: String
    public var baseURLString: String
    public var lastUsername: String?
    public var lastSignedInAt: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        baseURLString: String,
        lastUsername: String? = nil,
        lastSignedInAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.baseURLString = baseURLString
        self.lastUsername = lastUsername
        self.lastSignedInAt = lastSignedInAt
    }

    public var storeFileName: String {
        "CupcakeStore-\(id.uuidString).store"
    }

    public var keychainAccount: String {
        id.uuidString
    }
}

public enum KnownInstanceRegistry {
    private static let defaultsKey = "cupcake.knownInstances"

    public static func allInstances(defaults: UserDefaults = .standard) -> [KnownInstance] {
        guard let data = defaults.data(forKey: defaultsKey),
              let instances = try? JSONDecoder().decode([KnownInstance].self, from: data) else {
            return []
        }
        return instances
    }

    public static func add(_ instance: KnownInstance, defaults: UserDefaults = .standard) {
        var instances = allInstances(defaults: defaults)
        instances.append(instance)
        save(instances, defaults: defaults)
    }

    public static func update(_ instance: KnownInstance, defaults: UserDefaults = .standard) {
        var instances = allInstances(defaults: defaults)
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[index] = instance
        save(instances, defaults: defaults)
    }

    public static func remove(id: UUID, defaults: UserDefaults = .standard) {
        var instances = allInstances(defaults: defaults)
        instances.removeAll { $0.id == id }
        save(instances, defaults: defaults)
    }

    public static func removeAll(defaults: UserDefaults = .standard) {
        save([], defaults: defaults)
    }

    private static func save(_ instances: [KnownInstance], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

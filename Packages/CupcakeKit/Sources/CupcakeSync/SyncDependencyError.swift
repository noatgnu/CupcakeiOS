/// Thrown when a create-locally-then-sync operation depends on a parent's `serverID` that doesn't exist yet. Retried like a connectivity failure.
public enum SyncDependencyError: Error {
    case parentNotSynced
}

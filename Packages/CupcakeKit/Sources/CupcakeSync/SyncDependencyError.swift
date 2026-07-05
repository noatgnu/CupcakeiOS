/// Thrown by any `sync*` method when its create-locally-then-sync operation depends on a parent
/// record's `serverID` that doesn't exist yet (e.g. a session's protocol, a section's protocol,
/// a step's section) — an ordering issue, not a real failure: the parent's own outbox entry
/// just hasn't replayed yet. `OutboxService.replayPending()` retries these the same way it
/// retries `APIError.transport`, rather than marking them `.failed`.
public enum SyncDependencyError: Error {
    case parentNotSynced
}

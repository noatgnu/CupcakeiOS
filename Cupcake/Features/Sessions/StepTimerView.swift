import CupcakeModels
import CupcakeSync
import SwiftData
import SwiftUI

struct StepTimerView: View {
    let sessionServerID: Int64
    let sessionClientID: UUID
    let step: CachedProtocolStep
    let onTimeKeeperChanged: () async -> Void

    @Environment(AppSession.self) private var appSession
    @Query private var timeKeepers: [CachedTimeKeeper]
    @State private var isBusy = false

    private var timeKeeper: CachedTimeKeeper? {
        timeKeepers.first(where: { $0.sessionClientID == sessionClientID && $0.stepClientID == step.clientID })
    }

    var body: some View {
        if let stepDuration = step.stepDuration {
            HStack {
                Image(systemName: "timer")
                if let timeKeeper, timeKeeper.started {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(Self.format(Self.remainingSeconds(for: timeKeeper)))
                            .font(.body.monospacedDigit())
                    }
                    .accessibilityIdentifier("stepTimerRemaining")
                } else {
                    Text(Self.format(timeKeeper?.currentDuration ?? stepDuration))
                        .font(.body.monospacedDigit())
                        .accessibilityIdentifier("stepTimerRemaining")
                }
                Spacer()
                if timeKeeper?.started == true {
                    Button("Stop") { Task { await stop() } }
                        .accessibilityIdentifier("stopStepTimerButton")
                } else {
                    Button(timeKeeper == nil ? "Start Timer" : "Resume") { Task { await start(stepDuration: stepDuration) } }
                        .accessibilityIdentifier("startStepTimerButton")
                }
                if timeKeeper != nil {
                    Button("Reset") { Task { await reset() } }
                        .accessibilityIdentifier("resetStepTimerButton")
                }
            }
            .disabled(isBusy)
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }

    private static func remainingSeconds(for timeKeeper: CachedTimeKeeper) -> Int {
        guard timeKeeper.started, let startTimeString = timeKeeper.startTime else {
            return timeKeeper.currentDuration
        }
        let startDate = Date.parsedISO8601(startTimeString)
        let elapsed = Int(Date().timeIntervalSince(startDate))
        return max(0, timeKeeper.currentDuration - elapsed)
    }

    private static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func start(stepDuration: Int) async {
        guard let stepServerID = step.serverID else { return }
        isBusy = true
        defer { isBusy = false }
        let services = appSession.makeSyncServices()
        do {
            if let existing = timeKeeper {
                try await services.timeKeeperSync.startTimer(serverID: existing.serverID)
            } else {
                let serverID = try await services.timeKeeperSync.create(
                    sessionServerID: sessionServerID,
                    sessionClientID: sessionClientID,
                    stepServerID: stepServerID,
                    stepClientID: step.clientID,
                    durationSeconds: stepDuration
                )
                try await services.timeKeeperSync.startTimer(serverID: serverID)
            }
            await onTimeKeeperChanged()
        } catch {}
    }

    private func stop() async {
        guard let timeKeeper else { return }
        isBusy = true
        defer { isBusy = false }
        _ = try? await appSession.makeSyncServices().timeKeeperSync.stopTimer(serverID: timeKeeper.serverID)
        await onTimeKeeperChanged()
    }

    private func reset() async {
        guard let timeKeeper else { return }
        isBusy = true
        defer { isBusy = false }
        _ = try? await appSession.makeSyncServices().timeKeeperSync.resetTimer(serverID: timeKeeper.serverID)
        await onTimeKeeperChanged()
    }
}

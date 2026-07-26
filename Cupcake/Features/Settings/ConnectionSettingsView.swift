import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(AppSession.self) private var appSession

    var body: some View {
        Form {
            Section("Connection") {
                Toggle(
                    "Work Offline",
                    isOn: Binding(
                        get: { appSession.isForceOffline },
                        set: { newValue in Task { await appSession.setForceOffline(newValue) } }
                    )
                )
                .accessibilityIdentifier("forceOfflineToggle")
            }
            Section {
                Text(
                    appSession.isForceOffline
                        ? "Cupcake will not attempt any network requests. Content you create or edit queues locally and syncs automatically once you turn this off."
                        : "Turn this on to deliberately work offline, even with a live connection available. Anything you create while offline queues and syncs once you turn it back off."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Connection")
    }
}

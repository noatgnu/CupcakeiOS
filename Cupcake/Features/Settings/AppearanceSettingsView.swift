import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("appAppearance") private var appearanceRawValue: String = AppAppearance.system.rawValue

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("appearancePicker")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}

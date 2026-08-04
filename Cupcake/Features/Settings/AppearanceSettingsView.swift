import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(AppSession.self) private var appSession
    @AppStorage("appAppearance") private var appearanceRawValue: String = AppAppearance.system.rawValue
    @AppStorage("stepDetailUseCustomFontSize") private var useCustomStepFontSize = false
    @AppStorage("stepDetailFontSize") private var stepFontSize: Double = Double(HTMLText.defaultBodyPointSize)

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    private var isOverridingForInstance: Bool {
        appSession.appearanceOverride != nil
    }

    private var instanceOverride: Binding<AppAppearance> {
        Binding(
            get: { appSession.appearanceOverride ?? AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appSession.setAppearanceOverride($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("appearancePicker")
            } header: {
                Text("Appearance")
            } footer: {
                if appSession.activeInstance != nil {
                    Text("This is the default used everywhere unless overridden for this instance below.")
                }
            }

            if appSession.activeInstance != nil {
                Section("This Instance") {
                    Toggle(
                        "Override for This Instance",
                        isOn: Binding(
                            get: { isOverridingForInstance },
                            set: { isOn in appSession.setAppearanceOverride(isOn ? (appSession.appearanceOverride ?? AppAppearance(rawValue: appearanceRawValue) ?? .system) : nil) }
                        )
                    )
                    .accessibilityIdentifier("appearanceOverrideToggle")
                    if isOverridingForInstance {
                        Picker("Appearance Override", selection: instanceOverride) {
                            ForEach(AppAppearance.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("appearanceOverridePicker")
                    }
                }
            }

            Section("Step Text Size") {
                Toggle("Use Fixed Text Size", isOn: $useCustomStepFontSize)
                    .accessibilityIdentifier("useCustomStepFontSizeToggle")
                if useCustomStepFontSize {
                    Slider(value: $stepFontSize, in: 12...28, step: 1) {
                        Text("Text Size")
                    } minimumValueLabel: {
                        Text("A").font(.caption)
                    } maximumValueLabel: {
                        Text("A").font(.title3)
                    }
                    .accessibilityIdentifier("stepFontSizeSlider")
                    Text("Using a 200 µL pipette tip, remove one colony and transfer it into 300 mL broth.")
                        .font(.system(size: stepFontSize))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
    }
}
